import 'dart:convert';

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'support/test_server.dart';

/// Two users on one server: neither can see, change or delete the other's
/// data, in both directions.
void main() {
  late TestServer server;
  late ApiClient alice;
  late ApiClient bob;

  setUp(() async {
    server = TestServer();
    await server.start();
    alice = await server.signUp('alice');
    bob = await server.signUp('bob');
  });

  tearDown(() => server.stop());

  Future<int> createExpense(ApiClient user, String title) async {
    final response = await user.postJson('/expenses', {
      'title': title,
      'category': 'food',
      'amount': 10.0,
    });
    expect(response.statusCode, 201);
    return jsonDecode(response.body)['id'] as int;
  }

  Future<List<String>> titles(ApiClient user) async {
    final response = await user.get('/expenses');
    return (jsonDecode(response.body) as List)
        .map((e) => e['title'] as String)
        .toList();
  }

  final directions = {
    'alice -> bob': () => (owner: bob, other: alice),
    'bob -> alice': () => (owner: alice, other: bob),
  };

  for (final MapEntry(key: direction, value: users) in directions.entries) {
    group(direction, () {
      test('list shows only the own expenses', () async {
        final (:owner, :other) = users();
        await createExpense(owner, 'Owner groceries');
        await createExpense(other, 'Other groceries');

        expect(await titles(owner), ['Owner groceries']);
        expect(await titles(other), ['Other groceries']);
      });

      test(
        "updating the other user's expense returns 404 and changes nothing",
        () async {
          final (:owner, :other) = users();
          final id = await createExpense(owner, 'Owner groceries');

          final response = await other.putJson('/expenses/$id', {
            'title': 'Hijacked',
            'category': 'food',
            'amount': 1.0,
          });

          expect(response.statusCode, 404);
          expect(await titles(owner), ['Owner groceries']);
        },
      );

      test(
        "deleting the other user's expense returns 404 and keeps it",
        () async {
          final (:owner, :other) = users();
          final id = await createExpense(owner, 'Owner groceries');

          expect((await other.delete('/expenses/$id')).statusCode, 404);
          expect(await titles(owner), ['Owner groceries']);
        },
      );

      test(
        "categories are per user: a new one doesn't appear for the other",
        () async {
          final (:owner, :other) = users();
          final created = await owner.postJson('/categories', {
            'name': 'Gambling',
          });
          expect(created.statusCode, 201);

          final names = (jsonDecode(
            (await other.get('/categories')).body,
          ) as List).map((c) => c['name']);
          expect(names, isNot(contains('Gambling')));

          // The same name is a separate row for the other user: 201, new id.
          final own = await other.postJson('/categories', {'name': 'gambling'});
          expect(own.statusCode, 201);
          expect(
            jsonDecode(own.body)['id'],
            isNot(jsonDecode(created.body)['id']),
          );
        },
      );
    });
  }

  test('both users get their own copy of the default categories', () async {
    final rows = await server.pool.execute(
      "SELECT count(*) FROM categories WHERE lower(name) = 'food'",
    );
    expect(rows.first[0], 2);
  });

  test("the composite foreign key rejects an expense pointing to another "
      "user's category", () async {
    final rows = await server.pool.execute('''
      SELECT
        (SELECT id FROM users WHERE username = 'alice'),
        (SELECT c.id FROM categories c JOIN users u ON u.id = c.user_id
          WHERE u.username = 'bob' AND c.name = 'food')
    ''');
    final aliceId = rows.first[0] as int;
    final bobsFood = rows.first[1] as int;

    await expectLater(
      server.pool.execute(
        Sql.named(
          'INSERT INTO expenses (user_id, category_id, title, amount) '
          'VALUES (@user, @category, @title, 1)',
        ),
        parameters: {'user': aliceId, 'category': bobsFood, 'title': 'x'},
      ),
      throwsA(
        isA<ForeignKeyViolationException>().having(
          (e) => e.constraintName,
          'constraintName',
          'expenses_user_category_fkey',
        ),
      ),
    );
  });
}
