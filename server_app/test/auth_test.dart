import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:server_app/auth/password_hasher.dart';
import 'package:server_app/auth/token_service.dart';
import 'package:test/test.dart';

import 'support/test_server.dart';

void main() {
  late TestServer server;

  tearDown(() => server.stop());

  Future<void> start({
    DateTime Function()? now,
    PasswordCheck check = checkPasswordInIsolate,
    int? loginMaxFailures,
    int? registerMaxAttempts,
  }) async {
    server = TestServer();
    await server.start(
      auth: await testAuthServices(
        now: now,
        check: check,
        loginMaxFailures: loginMaxFailures,
        registerMaxAttempts: registerMaxAttempts,
      ),
    );
  }

  group('POST /auth/register', () {
    setUp(() => start());

    test('creates a user and returns id and username with 201', () async {
      final response = await server.register('alice');
      expect(response.statusCode, 201);
      final body = jsonDecode(response.body);
      expect(body['id'], isA<int>());
      expect(body, {'id': body['id'], 'username': 'alice'});
    });

    test('stores a bcrypt hash, never the password', () async {
      await server.register('alice');
      final rows = await server.pool.execute(
        "SELECT password_hash FROM users WHERE username = 'alice'",
      );
      final hash = rows.first[0] as String;
      expect(hash, startsWith(r'$2a$'));
      expect(hash, isNot(contains(testPassword)));
    });

    test('trims and lowercases the username', () async {
      final response = await server.register('  Alice.B ');
      expect(response.statusCode, 201);
      expect(jsonDecode(response.body)['username'], 'alice.b');
    });

    test('a taken username returns 409, case-insensitively', () async {
      expect((await server.register('alice')).statusCode, 201);
      expect((await server.register('ALICE')).statusCode, 409);
    });

    test('concurrent registrations of one name create one user', () async {
      final responses = await Future.wait([
        for (var i = 0; i < 5; i++) server.register('alice'),
      ]);
      final statuses = responses.map((r) => r.statusCode).toList();
      expect(statuses.where((s) => s == 201).length, 1);
      expect(statuses.where((s) => s == 409).length, 4);
    });

    test('rejects invalid usernames with 400', () async {
      for (final username in ['al', 'a' * 33, 'alice!', 'al ice', 'ålice']) {
        final response = await server.register(username);
        expect(response.statusCode, 400, reason: username);
      }
      expect((await server.register('a.b_c-1')).statusCode, 201);
    });

    test('checks the password length in UTF-8 bytes (8-72)', () async {
      expect((await server.register('short', '1234567')).statusCode, 400);
      // 36 two-byte characters = 72 bytes: allowed; one more: 74 bytes.
      expect((await server.register('max', 'ä' * 36)).statusCode, 201);
      expect((await server.register('toolong', 'ä' * 37)).statusCode, 400);
      expect((await server.register('ascii73', 'a' * 73)).statusCode, 400);
    });

    test('rejects a malformed body with 400', () async {
      final client = server.client();
      for (final body in [
        'not json',
        '[]',
        '{"username": "alice"}',
        '{"username": 1, "password": "12345678"}',
      ]) {
        final response = await http.post(
          Uri.parse('${server.host}/auth/register'),
          headers: {'Content-Type': 'application/json'},
          body: body,
        );
        expect(response.statusCode, 400, reason: body);
      }
      expect(client.token, isNull);
    });
  });

  group('POST /auth/login', () {
    setUp(() => start());

    test('returns a token that opens protected routes', () async {
      await server.register('alice');
      final response = await server.login('ALICE');

      expect(response.statusCode, 200);
      final body = jsonDecode(response.body);
      final expiresAt = DateTime.parse(body['expiresAt'] as String);
      expect(
        expiresAt.difference(DateTime.now()).inMinutes,
        inInclusiveRange(58, 60),
      );

      final expenses = await server
          .client(body['token'] as String)
          .get('/expenses');
      expect(expenses.statusCode, 200);
    });

    test('wrong password and unknown username give the same 401', () async {
      await server.register('alice');

      final wrongPassword = await server.login('alice', 'wrong password');
      final unknownUser = await server.login('nobody');

      expect(wrongPassword.statusCode, 401);
      expect(unknownUser.statusCode, 401);
      expect(unknownUser.body, wrongPassword.body);
    });

    test('rejects invalid input with 400', () async {
      expect((await server.login('a')).statusCode, 400);
      expect((await server.login('alice', 'short')).statusCode, 400);
    });
  });

  test('unknown username is checked against the dummy hash (timing)', () async {
    final checkedHashes = <String>[];
    await start(
      check: (password, hash) {
        checkedHashes.add(hash);
        return checkPasswordInIsolate(password, hash);
      },
    );
    await server.register('alice');

    expect((await server.login('nobody')).statusCode, 401);
    expect(checkedHashes, [server.auth.passwords.dummyHash]);

    checkedHashes.clear();
    expect((await server.login('alice')).statusCode, 200);
    expect(checkedHashes.single, isNot(server.auth.passwords.dummyHash));
  });

  group('auth middleware', () {
    setUp(() => start());

    test(
      'protected routes without a token return 401 with WWW-Authenticate',
      () async {
        final anonymous = server.client();
        for (final response in [
          await anonymous.get('/expenses'),
          await anonymous.postJson('/expenses', {}),
          await anonymous.putJson('/expenses/1', {}),
          await anonymous.delete('/expenses/1'),
          await anonymous.get('/categories'),
          await anonymous.postJson('/categories', {'name': 'x'}),
          await anonymous.postJson('/classify', {'text': 'x'}),
          await anonymous.postJson('/chat', {'message': 'x'}),
        ]) {
          expect(response.statusCode, 401, reason: response.request?.url.path);
          expect(response.headers['www-authenticate'], 'Bearer');
        }
      },
    );

    test('a malformed Authorization header returns 401', () async {
      for (final header in ['Bearer', 'Bearer ', 'Basic YWxpY2U6eA==', 'x']) {
        final response = await http.get(
          Uri.parse('${server.host}/expenses'),
          headers: {'Authorization': header},
        );
        expect(response.statusCode, 401, reason: header);
      }
    });

    test('an invalid token returns 401', () async {
      final response = await server.client('not.a.token').get('/expenses');
      expect(response.statusCode, 401);
    });

    test('a token signed with another secret returns 401', () async {
      await server.register('alice');
      final foreign = TokenService('some-other-secret-that-is-32-bytes-long!')
          .issue(1);
      final response = await server.client(foreign.token).get('/expenses');
      expect(response.statusCode, 401);
    });

    test('the bearer scheme is case-insensitive', () async {
      final alice = await server.signUp('alice');
      final response = await http.get(
        Uri.parse('${server.host}/expenses'),
        headers: {'Authorization': 'bearer ${alice.token}'},
      );
      expect(response.statusCode, 200);
    });

    test('/ and /auth/* are public', () async {
      expect((await server.client().get('/')).statusCode, 200);
      expect((await server.register('alice')).statusCode, 201);
    });
  });

  test('an expired token returns 401', () async {
    var now = DateTime.now();
    await start(now: () => now);
    final alice = await server.signUp('alice');
    expect((await alice.get('/expenses')).statusCode, 200);

    now = now.add(const Duration(hours: 1));
    expect((await alice.get('/expenses')).statusCode, 401);
  });

  group('CORS', () {
    setUp(() => start());

    test(
      'preflight without a token is answered 200 and allows Authorization',
      () async {
        final request =
            http.Request('OPTIONS', Uri.parse('${server.host}/expenses'))
              ..headers.addAll({
                'Origin': 'http://localhost:5000',
                'Access-Control-Request-Method': 'GET',
                'Access-Control-Request-Headers': 'authorization',
              });
        final response = await http.Response.fromStream(await request.send());

        expect(response.statusCode, 200);
        final allowed = response.headers['access-control-allow-headers']!
            .split(',')
            .map((h) => h.trim().toLowerCase());
        expect(allowed, contains('authorization'));
        expect(response.headers['access-control-allow-origin'], '*');
      },
    );

    test('a 401 carries the CORS headers', () async {
      final response = await server.client().get('/expenses');
      expect(response.statusCode, 401);
      expect(response.headers['access-control-allow-origin'], '*');
      expect(
        response.headers['access-control-allow-headers'],
        contains('Authorization'),
      );
    });
  });

  group('rate limits', () {
    test('login: 429 with Retry-After after too many failures, '
        'reset on success', () async {
      var now = DateTime.now();
      await start(now: () => now, loginMaxFailures: 3);
      await server.register('alice');

      expect((await server.login('alice', 'wrong password')).statusCode, 401);
      expect((await server.login('alice', 'wrong password')).statusCode, 401);
      // A success before the limit resets the counter ...
      expect((await server.login('alice')).statusCode, 200);

      // ... so three more failures are allowed before the 429.
      for (var i = 0; i < 3; i++) {
        expect((await server.login('alice', 'wrong password')).statusCode, 401);
      }
      final blocked = await server.login('alice');
      expect(blocked.statusCode, 429);
      expect(blocked.headers['retry-after'], '900');

      // Another username from the same IP is not affected.
      await server.register('bob');
      expect((await server.login('bob')).statusCode, 200);

      // After the window the correct password works again.
      now = now.add(const Duration(minutes: 15));
      expect((await server.login('alice')).statusCode, 200);
    });

    test(
      'register: 429 with Retry-After after too many attempts per IP',
      () async {
        await start(registerMaxAttempts: 2);

        expect((await server.register('alice')).statusCode, 201);
        // Invalid and conflicting attempts count too.
        expect((await server.register('alice')).statusCode, 409);

        final blocked = await server.register('bob');
        expect(blocked.statusCode, 429);
        expect(
          int.parse(blocked.headers['retry-after']!),
          inInclusiveRange(3599, 3600),
        );
      },
    );
  });
}
