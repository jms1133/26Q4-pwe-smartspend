import 'dart:convert';
import 'dart:io';

import 'package:postgres/postgres.dart';
import 'package:shelf/shelf.dart';
import 'package:openapi/api.dart';
import 'package:server_app/auth/auth_middleware.dart';
import 'package:server_app/handlers/category_handlers.dart';
import 'package:server_app/services/ai_service.dart';

/// Select list of every expense query, in one place so all of them stay in
/// sync with [_rowToExpense]. Expects the expense row as `e` and its category
/// as `c`: the table stores `category_id`, the API returns the name.
const _expenseColumns =
    'e.id, e.title, c.name AS category, e.subcategory, '
    'e.description, e.amount, e.timestamp';

/// Joins the category name onto the expense rows named `e`.
const _joinCategory = 'JOIN categories c ON c.id = e.category_id';

/// Converts a single PostgreSQL [ResultRow] into the generated [Expense] model.
///
/// This is the "map-to-object" bridge: `toColumnMap()` turns the row into a
/// `Map<String, dynamic>` keyed by column name, and we lift that into the
/// strongly-typed class that the OpenAPI generator wrote for us in
/// /openapi/lib/model/expense.dart. TIMESTAMPTZ arrives as a UTC `DateTime`.
/// NUMERIC arrives as a `String` (e.g. "12.50"): the postgres package does
/// not convert it to `double` itself, because that could lose digits. The
/// API's `amount` is a JSON number (`double`), so we parse it here. With at
/// most 12 significant digits this is lossless in the sense that the double
/// prints back as the same 2-decimal value.
Expense _rowToExpense(ResultRow row) {
  final map = row.toColumnMap();
  return Expense(
    id: map['id'] as int,
    title: map['title'] as String,
    category: map['category'] as String,
    subcategory: map['subcategory'] as String?,
    description: map['description'] as String?,
    amount: double.parse(map['amount'] as String),
    timestamp: map['timestamp'] as DateTime,
  );
}

/// Returns the request body as an [ExpenseInput], or null if it is not a
/// JSON object with all required keys.
///
/// The explicit key check matters: the generated `fromJson` only checks
/// required keys inside an `assert()`, which is stripped in production builds.
ExpenseInput? _parseExpenseInput(Object? json) {
  if (json is! Map ||
      !ExpenseInput.requiredKeys.every(
        (key) => json.containsKey(key) && json[key] != null,
      )) {
    return null;
  }
  return ExpenseInput.fromJson(json);
}

/// Largest absolute value `NUMERIC(12, 2)` can store is 9,999,999,999.99.
const _amountLimit = 1e10;

/// Converts the API's `double` amount into the exact decimal string that is
/// sent as a NUMERIC parameter, or returns null if it doesn't fit the column.
///
/// `toStringAsFixed(2)` rounds to cents and never produces exponent notation
/// (`1e-7`) for values below the limit, which the postgres package's NUMERIC
/// encoder would reject. Checking here turns an out-of-range amount into a
/// 400 instead of a database overflow error (500).
String? _amountToNumeric(double amount) {
  if (!amount.isFinite) return null;
  final fixed = amount.toStringAsFixed(2);
  if (double.parse(fixed).abs() >= _amountLimit) return null;
  return fixed;
}

/// Every query below filters by the user id from the request context, set
/// by the auth middleware from the verified token. Another user's expense
/// therefore looks exactly like a nonexistent one (404).
Future<Response> listExpensesHandler(Request request, Session db) async {
  final rows = await db.execute(
    Sql.named('''
      SELECT $_expenseColumns FROM expenses e $_joinCategory
      WHERE e.user_id = @userId
      ORDER BY e.timestamp DESC, e.id DESC
    '''),
    parameters: {'userId': userIdOf(request)},
  );
  final expenses = rows.map(_rowToExpense).toList();

  return Response.ok(
    jsonEncode(expenses.map((e) => e.toJson()).toList()),
    headers: {'Content-Type': 'application/json'},
  );
}

Future<Response> createExpenseHandler(Request request, Session db) async {
  try {
    final userId = userIdOf(request);
    final input = _parseExpenseInput(jsonDecode(await request.readAsString()));
    if (input == null) {
      return Response.badRequest(body: 'Invalid expense payload.');
    }
    final amount = _amountToNumeric(input.amount);
    if (amount == null) {
      return Response.badRequest(body: 'Field "amount" is out of range.');
    }

    // Find-or-create the category so a new one (from the AI or the user)
    // is registered for this user; the expense references it by id.
    final (:category, created: _) = await findOrCreateCategory(
      db,
      userId,
      input.category,
    );

    // `timestamp` is filled by the column DEFAULT now(). The CTE hands the
    // inserted row to the SELECT, which joins the category name, all in one
    // round trip.
    final rows = await db.execute(
      Sql.named('''
        WITH e AS (
          INSERT INTO expenses
            (user_id, category_id, title, subcategory, description, amount)
          VALUES
            (@userId, @categoryId, @title, @subcategory, @description, @amount)
          RETURNING *
        )
        SELECT $_expenseColumns FROM e $_joinCategory
      '''),
      parameters: {
        'userId': userId,
        'categoryId': category['id'],
        'title': input.title,
        'subcategory': input.subcategory,
        'description': input.description,
        'amount': TypedValue(Type.numeric, amount),
      },
    );
    final expense = _rowToExpense(rows.first);

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
  Session db,
  String idParam,
) async {
  try {
    final userId = userIdOf(request);
    final id = int.tryParse(idParam);
    if (id == null) {
      return Response.badRequest(body: 'Invalid expense id.');
    }

    final existing = await db.execute(
      Sql.named('SELECT 1 FROM expenses WHERE id = @id AND user_id = @userId'),
      parameters: {'id': id, 'userId': userId},
    );
    if (existing.isEmpty) {
      return Response.notFound('Expense not found.');
    }

    final input = _parseExpenseInput(jsonDecode(await request.readAsString()));
    if (input == null) {
      return Response.badRequest(body: 'Invalid expense payload.');
    }
    final amount = _amountToNumeric(input.amount);
    if (amount == null) {
      return Response.badRequest(body: 'Field "amount" is out of range.');
    }

    final (:category, created: _) = await findOrCreateCategory(
      db,
      userId,
      input.category,
    );

    final rows = await db.execute(
      Sql.named('''
        WITH e AS (
          UPDATE expenses
          SET title = @title, category_id = @categoryId,
              subcategory = @subcategory, description = @description,
              amount = @amount
          WHERE id = @id AND user_id = @userId
          RETURNING *
        )
        SELECT $_expenseColumns FROM e $_joinCategory
      '''),
      parameters: {
        'id': id,
        'userId': userId,
        'categoryId': category['id'],
        'title': input.title,
        'subcategory': input.subcategory,
        'description': input.description,
        'amount': TypedValue(Type.numeric, amount),
      },
    );
    // The row can vanish between the existence check and the UPDATE if a
    // concurrent DELETE wins; report that as 404 rather than crashing.
    if (rows.isEmpty) {
      return Response.notFound('Expense not found.');
    }
    final expense = _rowToExpense(rows.first);

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
  Session db,
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

    // Pass the user's own categories so the AI prefers an existing one over
    // a near-duplicate (synonym-sprawl mitigation). Other users' categories
    // stay private.
    final categoryRows = await db.execute(
      Sql.named(
        'SELECT name FROM categories WHERE user_id = @userId '
        'ORDER BY lower(name)',
      ),
      parameters: {'userId': userIdOf(request)},
    );
    final knownCategories = categoryRows.map((r) => r[0] as String).toList();

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
    final path =
        Platform.environment['CLASSIFICATION_LOG'] ??
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
      'parsed_description': input.description,
      'parsed_amount': input.amount,
      'was_new_category': wasNew,
    };
    File(path)
        .writeAsStringSync('${jsonEncode(record)}\n', mode: FileMode.append);
  } catch (e) {
    print('Classification log write failed (non-fatal): $e');
  }
}

Future<Response> deleteExpenseHandler(
  Request request,
  Session db,
  String idParam,
) async {
  final id = int.tryParse(idParam);
  if (id == null) {
    return Response.badRequest(body: 'Invalid expense id.');
  }

  // affectedRows replaces the separate existence check: one statement, and
  // no window for a concurrent delete between check and delete.
  final result = await db.execute(
    Sql.named('DELETE FROM expenses WHERE id = @id AND user_id = @userId'),
    parameters: {'id': id, 'userId': userIdOf(request)},
  );
  if (result.affectedRows == 0) {
    return Response.notFound('Expense not found.');
  }
  return Response(204);
}
