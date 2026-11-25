import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart';
import 'package:test/test.dart';

void main() {
  late Process p;
  late String host;

  setUp(() async {
    // PORT=0 lets the OS pick a free port, so parallel test runs (e.g.
    // multiple agents) never collide on a fixed 8082. The server prints the
    // port it actually bound to; we parse it from that startup line below.
    //
    // DB_PATH=':memory:' gives each test run a fresh, isolated SQLite
    // database that lives only in RAM and disappears when the process
    // is killed — so tests never touch or pollute smart_spend.db.
    p = await Process.start(
      'dart',
      ['run', 'bin/server.dart'],
      environment: {'PORT': '0', 'DB_PATH': ':memory:'},
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
          throw StateError('Server did not report a bound port within 15s'),
    );
    host = 'http://127.0.0.1:$port';
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
