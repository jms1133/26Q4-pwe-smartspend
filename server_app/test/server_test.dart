import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart';
import 'package:test/test.dart';

import 'support/test_database.dart';

void main() {
  late Process p;
  late String host;
  late String testDatabase;

  final databases = TestDatabases();

  setUp(() async {
    // Each test gets its own throwaway PostgreSQL database, replacing the
    // old SQLite ':memory:'. The server applies the migrations to it on
    // startup, so every test also exercises the migration runner.
    testDatabase = await databases.create();

    // PORT=0 lets the OS pick a free port, so parallel test runs never
    // collide on a fixed 8082. The server prints the port it actually bound
    // to; we parse it from that startup line below. POSTGRES_DB overrides
    // the database from .env; everything else (host, port, credentials) is
    // inherited.
    p = await Process.start(
      'dart',
      ['run', 'bin/server.dart'],
      environment: {'PORT': '0', 'POSTGRES_DB': testDatabase},
    );

    // Keep draining stdout with listen() (not just .first) so the child's
    // output buffer can't fill up and block the server. Parse only the PORT
    // from the "Server running on http://host:port" line, then build our own
    // URL. We connect to 127.0.0.1 (not localhost): on macOS localhost can
    // resolve to ::1 first, but the server binds IPv4 only (anyIPv4).
    final boundPort = Completer<String>();
    p.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      final match =
          RegExp(r'Server running on http://\S+:(\d+)').firstMatch(line);
      if (match != null && !boundPort.isCompleted) {
        boundPort.complete(match.group(1));
      }
    });
    p.stderr.transform(utf8.decoder).listen(stderr.write);

    final port = await boundPort.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () =>
          throw StateError('Server did not report a bound port within 30s'),
    );
    host = 'http://127.0.0.1:$port';
  });

  tearDown(() async {
    p.kill();
    await p.exitCode;
    await databases.drop(testDatabase);
  });

  Future<Response> postJson(String path, Object body) => post(
        Uri.parse('$host$path'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );

  test('Root', () async {
    final response = await get(Uri.parse('$host/'));
    expect(response.statusCode, 200);
    expect(response.body, 'Hello, World!\n');
  });

  test('Echo', () async {
    final response = await get(Uri.parse('$host/echo/hello'));
    expect(response.statusCode, 200);
    expect(response.body, 'hello\n');
  });

  test('404', () async {
    final response = await get(Uri.parse('$host/foobar'));
    expect(response.statusCode, 404);
  });

  group('Expenses CRUD', () {
    test('listExpenses returns an empty array on a fresh database', () async {
      final response = await get(Uri.parse('$host/expenses'));
      expect(response.statusCode, 200);
      expect(jsonDecode(response.body), isEmpty);
    });

    test('createExpense persists and returns the new expense', () async {
      final response = await post(
        Uri.parse('$host/expenses'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'title': 'Hundehaftpflichtversicherung',
          'category': 'insurance',
          'amount': 12.5,
          'subcategory': 'pets',
        }),
      );

      expect(response.statusCode, 201);
      final body = jsonDecode(response.body);
      expect(body['id'], isA<int>());
      expect(body['title'], 'Hundehaftpflichtversicherung');
      expect(body['category'], 'insurance');
      expect(body['amount'], 12.5);
      expect(body['subcategory'], 'pets');
      expect(body['timestamp'], isNotNull);
    });

    test('createExpense without required field returns 400', () async {
      final response = await post(
        Uri.parse('$host/expenses'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'category': 'food', 'amount': 5.0}),
      );

      expect(response.statusCode, 400);
    });

    test('listExpenses reflects previously created expenses', () async {
      await post(
        Uri.parse('$host/expenses'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'title': 'Cinema',
          'category': 'entertainment',
          'amount': 15.0,
        }),
      );

      final response = await get(Uri.parse('$host/expenses'));
      expect(response.statusCode, 200);
      final body = jsonDecode(response.body) as List;
      expect(body.length, 1);
      expect(body.first['title'], 'Cinema');
    });

    test('updateExpense modifies an existing expense', () async {
      final created = await post(
        Uri.parse('$host/expenses'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'title': 'Groceries',
          'category': 'food',
          'amount': 20.0,
        }),
      );
      final id = jsonDecode(created.body)['id'];

      final response = await put(
        Uri.parse('$host/expenses/$id'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'title': 'Groceries (corrected)',
          'category': 'food',
          'amount': 25.5,
        }),
      );

      expect(response.statusCode, 200);
      final body = jsonDecode(response.body);
      expect(body['title'], 'Groceries (corrected)');
      expect(body['amount'], 25.5);
    });

    test('updateExpense on unknown id returns 404', () async {
      final response = await put(
        Uri.parse('$host/expenses/999999'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'title': 'Ghost',
          'category': 'other',
          'amount': 1.0,
        }),
      );

      expect(response.statusCode, 404);
    });

    test('deleteExpense removes an existing expense', () async {
      final created = await post(
        Uri.parse('$host/expenses'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'title': 'Temporary',
          'category': 'other',
          'amount': 3.0,
        }),
      );
      final id = jsonDecode(created.body)['id'];

      final deleteResponse = await delete(Uri.parse('$host/expenses/$id'));
      expect(deleteResponse.statusCode, 204);

      final listResponse = await get(Uri.parse('$host/expenses'));
      expect(jsonDecode(listResponse.body), isEmpty);
    });

    test('deleteExpense on unknown id returns 404', () async {
      final response = await delete(Uri.parse('$host/expenses/999999'));
      expect(response.statusCode, 404);
    });

    test('createExpense reuses an existing category case-insensitively',
        () async {
      final response = await post(
        Uri.parse('$host/expenses'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'title': 'Bakery',
          'category': '  FOOD ',
          'amount': 4.2,
        }),
      );

      expect(response.statusCode, 201);
      expect(jsonDecode(response.body)['category'], 'food');
    });

    test('timestamp is a UTC ISO-8601 date-time', () async {
      final response = await post(
        Uri.parse('$host/expenses'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'title': 'Bus',
          'category': 'transport',
          'amount': 3.0,
        }),
      );

      final timestamp =
          DateTime.parse(jsonDecode(response.body)['timestamp'] as String);
      expect(timestamp.isUtc, isTrue);
      expect(
        DateTime.now().toUtc().difference(timestamp).inMinutes.abs(),
        lessThan(5),
      );
    });
  });

  group('Amount (NUMERIC(12, 2))', () {
    Future<double> sumOfStoredAmounts() async {
      final list = await get(Uri.parse('$host/expenses'));
      return (jsonDecode(list.body) as List)
          .map((e) => (e['amount'] as num).toDouble())
          .fold<double>(0, (a, b) => a + b);
    }

    test('stores cents exactly', () async {
      for (final amount in [0.1, 0.2]) {
        await postJson('/expenses',
            {'title': 'Gum', 'category': 'food', 'amount': amount});
      }
      final created = await postJson('/expenses',
          {'title': 'Exact', 'category': 'food', 'amount': 1234567890.12});

      expect(jsonDecode(created.body)['amount'], 1234567890.12);
      expect(await sumOfStoredAmounts(), closeTo(1234567890.42, 1e-6));
    });

    test('rounds more than two decimals to cents', () async {
      final response = await postJson('/expenses',
          {'title': 'Fuel', 'category': 'transport', 'amount': 1.239});
      expect(response.statusCode, 201);
      expect(jsonDecode(response.body)['amount'], 1.24);
    });

    test('accepts an integer JSON number', () async {
      final response = await postJson('/expenses',
          {'title': 'Rent', 'category': 'housing', 'amount': 800});
      expect(response.statusCode, 201);
      expect(jsonDecode(response.body)['amount'], 800);
    });

    test('rejects an amount that does not fit NUMERIC(12, 2) with 400',
        () async {
      final create = await postJson('/expenses',
          {'title': 'Yacht', 'category': 'shopping', 'amount': 1e10});
      expect(create.statusCode, 400);

      final ok = await postJson('/expenses',
          {'title': 'Car', 'category': 'transport', 'amount': 9999999999.99});
      expect(ok.statusCode, 201);

      final id = jsonDecode(ok.body)['id'];
      final update = await put(
        Uri.parse('$host/expenses/$id'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(
            {'title': 'Car', 'category': 'transport', 'amount': -1e12}),
      );
      expect(update.statusCode, 400);
    });
  });

  group('Categories', () {
    test('listCategories returns the seeded categories', () async {
      final response = await get(Uri.parse('$host/categories'));
      expect(response.statusCode, 200);
      final names = (jsonDecode(response.body) as List)
          .map((c) => c['name'] as String)
          .toList();
      expect(names, contains('food'));
      expect(names, isNot(contains('other')));
      expect(names, orderedEquals([...names]..sort()));
    });

    test('createCategory creates a new category with 201', () async {
      final response = await post(
        Uri.parse('$host/categories'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'name': 'Gambling'}),
      );

      expect(response.statusCode, 201);
      final body = jsonDecode(response.body);
      expect(body['id'], isA<int>());
      expect(body['name'], 'Gambling');
    });

    test('createCategory returns the existing row case-insensitively',
        () async {
      final first = await post(
        Uri.parse('$host/categories'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'name': 'Pets'}),
      );
      final second = await post(
        Uri.parse('$host/categories'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'name': '  pETS '}),
      );

      expect(second.statusCode, 200);
      expect(jsonDecode(second.body), jsonDecode(first.body));

      final list = await get(Uri.parse('$host/categories'));
      final pets = (jsonDecode(list.body) as List)
          .where((c) => (c['name'] as String).toLowerCase() == 'pets');
      expect(pets.length, 1);
    });

    test('concurrent creates of the same new name yield one row', () async {
      final responses = await Future.wait([
        for (final name in ['Crypto', 'crypto', 'CRYPTO', ' Crypto ', 'cRyPtO'])
          postJson('/categories', {'name': name}),
      ]);

      final statuses = responses.map((r) => r.statusCode).toList();
      expect(statuses.where((s) => s == 201).length, 1);
      expect(statuses.where((s) => s == 200).length, 4);
      final ids = responses.map((r) => jsonDecode(r.body)['id']).toSet();
      expect(ids.length, 1);

      final list = await get(Uri.parse('$host/categories'));
      final crypto = (jsonDecode(list.body) as List)
          .where((c) => (c['name'] as String).toLowerCase() == 'crypto');
      expect(crypto.length, 1);
    });

    test('createCategory with a blank name returns 400', () async {
      final response = await post(
        Uri.parse('$host/categories'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'name': '   '}),
      );
      expect(response.statusCode, 400);
    });
  });
}
