import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:openapi/api.dart';

/// Converts a single SQLite [Row] into the generated [Expense] model.
///
/// This is the "map-to-object" bridge: sqlite3 gives us a row that behaves
/// like a `Map<String, dynamic>` (you can do `row['title']`), and we lift
/// that into the strongly-typed class that the OpenAPI generator wrote for
/// us in /openapi/lib/model/expense.dart.
Expense _rowToExpense(Row row) {
  return Expense(
    id: row['id'] as int,
    title: row['title'] as String,
    category: ExpenseCategoryEnum.fromJson(row['category'] as String)!,
    subcategory: row['subcategory'] as String?,
    description: row['description'] as String?,
    amount: row['amount'] as double,
    timestamp: DateTime.parse(row['timestamp'] as String),
  );
}

Response listExpensesHandler(Request request, Database db) {
  final rows = db.select('SELECT * FROM expenses ORDER BY timestamp DESC');
  final expenses = rows.map(_rowToExpense).toList();

  return Response.ok(
    jsonEncode(expenses.map((e) => e.toJson()).toList()),
    headers: {'Content-Type': 'application/json'},
  );
}

Future<Response> createExpenseHandler(Request request, Database db) async {
  try {
    final payload = await request.readAsString();
    final json = jsonDecode(payload);

    if (json is! Map ||
        !ExpenseInput.requiredKeys.every(
          (key) => json.containsKey(key) && json[key] != null,
        )) {
      return Response.badRequest(body: 'Invalid expense payload.');
    }

    final input = ExpenseInput.fromJson(json);
    if (input == null) {
      return Response.badRequest(body: 'Invalid expense payload.');
    }

    final timestamp = DateTime.now().toUtc().toIso8601String();

    db.execute(
      '''
      INSERT INTO expenses (title, category, subcategory, description, amount, timestamp)
      VALUES (?, ?, ?, ?, ?, ?)
      ''',
      [
        input.title,
        input.category.value,
        input.subcategory,
        input.description,
        input.amount,
        timestamp,
      ],
    );

    final newId = db.lastInsertRowId;
    final row = db.select('SELECT * FROM expenses WHERE id = ?', [newId]).first;
    final expense = _rowToExpense(row);

    return Response(
      201,
      body: jsonEncode(expense.toJson()),
      headers: {'Content-Type': 'application/json'},
    );
  } catch (e) {
    print('Error in createExpenseHandler: $e');
    return Response.internalServerError(body: 'Failed to create expense.');
  }
}

Future<Response> updateExpenseHandler(
  Request request,
  Database db,
  String idParam,
) async {
  try {
    final id = int.tryParse(idParam);
    if (id == null) {
      return Response.badRequest(body: 'Invalid expense id.');
    }

    final existing = db.select('SELECT id FROM expenses WHERE id = ?', [id]);
    if (existing.isEmpty) {
      return Response.notFound('Expense not found.');
    }

    final payload = await request.readAsString();
    final json = jsonDecode(payload);

    if (json is! Map ||
        !ExpenseInput.requiredKeys.every(
          (key) => json.containsKey(key) && json[key] != null,
        )) {
      return Response.badRequest(body: 'Invalid expense payload.');
    }

    final input = ExpenseInput.fromJson(json);
    if (input == null) {
      return Response.badRequest(body: 'Invalid expense payload.');
    }

    db.execute(
      '''
      UPDATE expenses
      SET title = ?, category = ?, subcategory = ?, description = ?, amount = ?
      WHERE id = ?
      ''',
      [
        input.title,
        input.category.value,
        input.subcategory,
        input.description,
        input.amount,
        id,
      ],
    );

    final row = db.select('SELECT * FROM expenses WHERE id = ?', [id]).first;
    final expense = _rowToExpense(row);

    return Response.ok(
      jsonEncode(expense.toJson()),
      headers: {'Content-Type': 'application/json'},
    );
  } catch (e) {
    print('Error in updateExpenseHandler: $e');
    return Response.internalServerError(body: 'Failed to update expense.');
  }
}

Response deleteExpenseHandler(Request request, Database db, String idParam) {
  final id = int.tryParse(idParam);
  if (id == null) {
    return Response.badRequest(body: 'Invalid expense id.');
  }

  final existing = db.select('SELECT id FROM expenses WHERE id = ?', [id]);
  if (existing.isEmpty) {
    return Response.notFound('Expense not found.');
  }

  db.execute('DELETE FROM expenses WHERE id = ?', [id]);
  return Response(204);
}
