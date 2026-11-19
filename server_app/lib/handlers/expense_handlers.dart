import 'dart:convert';
import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:openapi/api.dart';
import 'package:server_app/handlers/category_handlers.dart';
import 'package:server_app/services/ai_service.dart';

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
    category: row['category'] as String,
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

    // Find-or-create the category so a new one (from the AI or the user)
    // is registered. We store the canonical name from the categories table
    // so casing stays consistent across expenses.
    final category = findOrCreateCategory(db, input.category);
    final categoryName = category['name'] as String;

    final timestamp = DateTime.now().toUtc().toIso8601String();

    db.execute(
      '''
      INSERT INTO expenses (title, category, subcategory, description, amount, timestamp)
      VALUES (?, ?, ?, ?, ?, ?)
      ''',
      [
        input.title,
        categoryName,
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

    final category = findOrCreateCategory(db, input.category);
    final categoryName = category['name'] as String;

    db.execute(
      '''
      UPDATE expenses
      SET title = ?, category = ?, subcategory = ?, description = ?, amount = ?
      WHERE id = ?
      ''',
      [
        input.title,
        categoryName,
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

/// Parses raw natural-language expense text into a structured [ExpenseInput]
/// via the AI model. Returns the parsed input for the client to review before
/// saving it through the normal `POST /expenses` flow.
Future<Response> classifyHandler(
  Request request,
  AiService aiService,
  Database db,
) async {
  try {
    final payload = await request.readAsString();
    final json = jsonDecode(payload);

    if (json is! Map || json['text'] is! String) {
      return Response.badRequest(body: 'Missing required field "text".');
    }

    final text = (json['text'] as String).trim();
    if (text.isEmpty) {
      return Response.badRequest(body: 'Field "text" must not be empty.');
    }

    // Pass the current categories so the AI prefers an existing one over a
    // near-duplicate (synonym-sprawl mitigation).
    final categoryRows = db.select('SELECT name FROM categories');
    final knownCategories =
        categoryRows.map((r) => r['name'] as String).toList();

    String? rawResponse;
    final input = await aiService.classifyExpense(
      text,
      knownCategories: knownCategories,
      onRaw: (raw) => rawResponse = raw,
    );

    _logClassification(
      text: text,
      knownCategories: knownCategories,
      rawResponse: rawResponse,
      input: input,
    );

    return Response.ok(
      jsonEncode(input.toJson()),
      headers: {'Content-Type': 'application/json'},
    );
  } on AiServiceException catch (e) {
    print('Error in classifyHandler: $e');
    return Response.internalServerError(body: 'Failed to classify expense.');
  } catch (e) {
    print('Error in classifyHandler: $e');
    return Response.internalServerError(body: 'Failed to classify expense.');
  }
}

/// Research-only classification log (NOT a user/app feature, NOT persisted to
/// the database). Appends one JSON object per line to
/// docs/classification_log.jsonl so the AI's inputs and raw responses can be
/// reviewed for the Ausarbeitung/journal. Failures are swallowed: logging must
/// never affect the classify response. Override the path with the
/// CLASSIFICATION_LOG env var.
void _logClassification({
  required String text,
  required List<String> knownCategories,
  required String? rawResponse,
  required ExpenseInput input,
}) {
  try {
    final path = Platform.environment['CLASSIFICATION_LOG'] ??
        '../docs/classification_log.jsonl';
    final knownLower = knownCategories.map((c) => c.toLowerCase()).toSet();
    final wasNew = !knownLower.contains(input.category.toLowerCase());
    final record = <String, Object?>{
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'input_text': text,
      'known_categories': knownCategories,
      'raw_response': rawResponse,
      'parsed_title': input.title,
      'parsed_category': input.category,
      'parsed_subcategory': input.subcategory,
      'parsed_amount': input.amount,
      'was_new_category': wasNew,
    };
    File(path).writeAsStringSync(
      '${jsonEncode(record)}\n',
      mode: FileMode.append,
    );
  } catch (e) {
    print('Classification log write failed (non-fatal): $e');
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
