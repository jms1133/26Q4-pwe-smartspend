import 'dart:convert';

import 'package:server_app/db/default_categories.dart';
import 'package:test/test.dart';

import 'support/test_server.dart';

void main() {
  late TestServer server;

  /// Sends alice's token on every request. Auth itself is tested in
  /// auth_test.dart, cross-user access in isolation_test.dart.
  late ApiClient alice;

  setUp(() async {
    // Each test gets its own throwaway PostgreSQL database and an in-process
    // server (see test/support/test_server.dart).
    server = TestServer();
    await server.start();
    alice = await server.signUp('alice');
  });

  tearDown(() => server.stop());

  test('Root', () async {
    final response = await server.client().get('/');
    expect(response.statusCode, 200);
    expect(response.body, 'Hello, World!\n');
  });

  test('404', () async {
    final response = await alice.get('/foobar');
    expect(response.statusCode, 404);
  });

  group('Expenses CRUD', () {
    test('listExpenses returns an empty array on a fresh database', () async {
      final response = await alice.get('/expenses');
      expect(response.statusCode, 200);
      expect(jsonDecode(response.body), isEmpty);
    });

    test('createExpense persists and returns the new expense', () async {
      final response = await alice.postJson('/expenses', {
        'title': 'Hundehaftpflichtversicherung',
        'category': 'insurance',
        'amount': 12.5,
        'subcategory': 'pets',
      });

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
      final response = await alice.postJson('/expenses', {
        'category': 'food',
        'amount': 5.0,
      });
      expect(response.statusCode, 400);
    });

    test('listExpenses reflects previously created expenses', () async {
      await alice.postJson('/expenses', {
        'title': 'Cinema',
        'category': 'entertainment',
        'amount': 15.0,
      });

      final response = await alice.get('/expenses');
      expect(response.statusCode, 200);
      final body = jsonDecode(response.body) as List;
      expect(body.length, 1);
      expect(body.first['title'], 'Cinema');
      expect(body.first['category'], 'entertainment');
    });

    test('updateExpense modifies an existing expense', () async {
      final created = await alice.postJson('/expenses', {
        'title': 'Groceries',
        'category': 'food',
        'amount': 20.0,
      });
      final id = jsonDecode(created.body)['id'];

      final response = await alice.putJson('/expenses/$id', {
        'title': 'Groceries (corrected)',
        'category': 'shopping',
        'amount': 25.5,
      });

      expect(response.statusCode, 200);
      final body = jsonDecode(response.body);
      expect(body['title'], 'Groceries (corrected)');
      expect(body['category'], 'shopping');
      expect(body['amount'], 25.5);
    });

    test('updateExpense on unknown id returns 404', () async {
      final response = await alice.putJson('/expenses/999999', {
        'title': 'Ghost',
        'category': 'other',
        'amount': 1.0,
      });
      expect(response.statusCode, 404);
    });

    test('deleteExpense removes an existing expense', () async {
      final created = await alice.postJson('/expenses', {
        'title': 'Temporary',
        'category': 'other',
        'amount': 3.0,
      });
      final id = jsonDecode(created.body)['id'];

      final deleteResponse = await alice.delete('/expenses/$id');
      expect(deleteResponse.statusCode, 204);

      final listResponse = await alice.get('/expenses');
      expect(jsonDecode(listResponse.body), isEmpty);
    });

    test('deleteExpense on unknown id returns 404', () async {
      final response = await alice.delete('/expenses/999999');
      expect(response.statusCode, 404);
    });

    test(
      'createExpense reuses an existing category case-insensitively',
      () async {
        final response = await alice.postJson('/expenses', {
          'title': 'Bakery',
          'category': '  FOOD ',
          'amount': 4.2,
        });

        expect(response.statusCode, 201);
        expect(jsonDecode(response.body)['category'], 'food');
      },
    );

    test('timestamp is a UTC ISO-8601 date-time', () async {
      final response = await alice.postJson('/expenses', {
        'title': 'Bus',
        'category': 'transport',
        'amount': 3.0,
      });

      final timestamp = DateTime.parse(
        jsonDecode(response.body)['timestamp'] as String,
      );
      expect(timestamp.isUtc, isTrue);
      expect(
        DateTime.now().toUtc().difference(timestamp).inMinutes.abs(),
        lessThan(5),
      );
    });
  });

  group('Amount (NUMERIC(12, 2))', () {
    Future<double> sumOfStoredAmounts() async {
      final list = await alice.get('/expenses');
      return (jsonDecode(list.body) as List)
          .map((e) => (e['amount'] as num).toDouble())
          .fold<double>(0, (a, b) => a + b);
    }

    test('stores cents exactly', () async {
      for (final amount in [0.1, 0.2]) {
        await alice.postJson('/expenses', {
          'title': 'Gum',
          'category': 'food',
          'amount': amount,
        });
      }
      final created = await alice.postJson('/expenses', {
        'title': 'Exact',
        'category': 'food',
        'amount': 1234567890.12,
      });

      expect(jsonDecode(created.body)['amount'], 1234567890.12);
      expect(await sumOfStoredAmounts(), closeTo(1234567890.42, 1e-6));
    });

    test('rounds more than two decimals to cents', () async {
      final response = await alice.postJson('/expenses', {
        'title': 'Fuel',
        'category': 'transport',
        'amount': 1.239,
      });
      expect(response.statusCode, 201);
      expect(jsonDecode(response.body)['amount'], 1.24);
    });

    test('accepts an integer JSON number', () async {
      final response = await alice.postJson('/expenses', {
        'title': 'Rent',
        'category': 'housing',
        'amount': 800,
      });
      expect(response.statusCode, 201);
      expect(jsonDecode(response.body)['amount'], 800);
    });

    test(
      'rejects an amount that does not fit NUMERIC(12, 2) with 400',
      () async {
        final create = await alice.postJson('/expenses', {
          'title': 'Yacht',
          'category': 'shopping',
          'amount': 1e10,
        });
        expect(create.statusCode, 400);

        final ok = await alice.postJson('/expenses', {
          'title': 'Car',
          'category': 'transport',
          'amount': 9999999999.99,
        });
        expect(ok.statusCode, 201);

        final id = jsonDecode(ok.body)['id'];
        final update = await alice.putJson('/expenses/$id', {
          'title': 'Car',
          'category': 'transport',
          'amount': -1e12,
        });
        expect(update.statusCode, 400);
      },
    );
  });

  group('Categories', () {
    Future<List<String>> categoryNames() async {
      final response = await alice.get('/categories');
      expect(response.statusCode, 200);
      return (jsonDecode(response.body) as List)
          .map((c) => c['name'] as String)
          .toList();
    }

    test('a new user starts with exactly the default categories', () async {
      final names = await categoryNames();
      expect(names, unorderedEquals(defaultCategoryNames));
      expect(names, isNot(contains('other')));
      expect(names, orderedEquals([...names]..sort()));
    });

    test('createCategory creates a new category with 201', () async {
      final response = await alice.postJson('/categories', {
        'name': 'Gambling',
      });

      expect(response.statusCode, 201);
      final body = jsonDecode(response.body);
      expect(body['id'], isA<int>());
      expect(body['name'], 'Gambling');
    });

    test(
      'createCategory returns the existing row case-insensitively',
      () async {
        final first = await alice.postJson('/categories', {'name': 'Pets'});
        final second = await alice.postJson('/categories', {'name': '  pETS '});

        expect(second.statusCode, 200);
        expect(jsonDecode(second.body), jsonDecode(first.body));

        final pets = (await categoryNames()).where(
          (n) => n.toLowerCase() == 'pets',
        );
        expect(pets.length, 1);
      },
    );

    test('concurrent creates of the same new name yield one row', () async {
      final responses = await Future.wait([
        for (final name in ['Crypto', 'crypto', 'CRYPTO', ' Crypto ', 'cRyPtO'])
          alice.postJson('/categories', {'name': name}),
      ]);

      final statuses = responses.map((r) => r.statusCode).toList();
      expect(statuses.where((s) => s == 201).length, 1);
      expect(statuses.where((s) => s == 200).length, 4);
      final ids = responses.map((r) => jsonDecode(r.body)['id']).toSet();
      expect(ids.length, 1);

      final crypto = (await categoryNames()).where(
        (n) => n.toLowerCase() == 'crypto',
      );
      expect(crypto.length, 1);
    });

    test('createCategory with a blank name returns 400', () async {
      final response = await alice.postJson('/categories', {'name': '   '});
      expect(response.statusCode, 400);
    });
  });
}
