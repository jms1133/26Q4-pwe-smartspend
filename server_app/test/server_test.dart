import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart';
import 'package:postgres/postgres.dart';
import 'package:server_app/db/database.dart';
import 'package:server_app/server.dart';
import 'package:server_app/services/ai_service.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:test/test.dart';

import 'support/test_database.dart';

void main() {
  late HttpServer server;
  late Pool pool;
  late String host;
  late String testDatabase;

  final databases = TestDatabases();

  setUp(() async {
    // Each test gets its own throwaway PostgreSQL database. Opening the pool
    // applies the migrations to it, like the real server does on startup.
    testDatabase = await databases.create();
    pool = await openExpenseDatabase(
        databases.baseConfig.withDatabase(testDatabase));

    // The server runs inside the test process (not as a `dart run`
    // subprocess), so coverage sees the handler code. shelf_io.serve returns
    // once the socket is bound: no startup line to wait for. Port 0 lets the
    // OS pick a free port, so parallel runs never collide.
    //
    // The secrets path doesn't exist, so the AI service has no key unless
    // OPENAI_API_KEY is set in the environment (it isn't locally or in CI).
    // No test here calls /classify or /chat.
    final aiService = AiService(secretsPath: 'test/no-secrets.json');
    server = await shelf_io.serve(
      buildHandler(pool, aiService),
      InternetAddress.loopbackIPv4,
      0,
    );
    host = 'http://127.0.0.1:${server.port}';
  });

  tearDown(() async {
    // Order matters: stop accepting requests, release the pool's
    // connections, then drop the database they pointed at.
    await server.close(force: true);
    await pool.close();
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
