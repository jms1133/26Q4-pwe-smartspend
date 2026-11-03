import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart';
import 'package:test/test.dart';

void main() {
  final port = '8082';
  final host = 'http://localhost:$port';
  late Process p;

  setUp(() async {
    p = await Process.start(
      'dart',
      ['run', 'bin/server.dart'],
      // DB_PATH=':memory:' gives each test run a fresh, isolated SQLite
      // database that lives only in RAM and disappears when the process
      // is killed — so tests never touch or pollute smart_spend.db.
      environment: {'PORT': port, 'DB_PATH': ':memory:'},
    );
    // Wait for server to start and print to stdout.
    await p.stdout.first;
  });

  tearDown(() => p.kill());

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
  });
}
