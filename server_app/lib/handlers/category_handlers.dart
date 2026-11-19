import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:sqlite3/sqlite3.dart';

/// Returns all categories ordered alphabetically (case-insensitive).
Response listCategoriesHandler(Request request, Database db) {
  final rows = db.select(
    'SELECT id, name FROM categories ORDER BY name COLLATE NOCASE ASC',
  );
  final categories = rows
      .map((row) => {'id': row['id'] as int, 'name': row['name'] as String})
      .toList();

  return Response.ok(
    jsonEncode(categories),
    headers: {'Content-Type': 'application/json'},
  );
}

/// Find-or-create a category by name. Matching is case-insensitive (the table
/// uses `COLLATE NOCASE UNIQUE`), so "Food" resolves to an existing "food"
/// rather than creating a duplicate. Returns 200 for an existing match and
/// 201 when a new row is created.
Future<Response> createCategoryHandler(Request request, Database db) async {
  return _findOrCreateResponse(request, db);
}

Future<Response> _findOrCreateResponse(Request request, Database db) async {
  try {
    final payload = await request.readAsString();
    final json = jsonDecode(payload);

    if (json is! Map || json['name'] is! String) {
      return Response.badRequest(body: 'Missing required field "name".');
    }

    final name = (json['name'] as String).trim();
    if (name.isEmpty) {
      return Response.badRequest(body: 'Field "name" must not be empty.');
    }

    final existing = findCategoryByName(db, name);
    if (existing != null) {
      return Response.ok(
        jsonEncode(existing),
        headers: {'Content-Type': 'application/json'},
      );
    }

    final created = findOrCreateCategory(db, name);
    return Response(
      201,
      body: jsonEncode(created),
      headers: {'Content-Type': 'application/json'},
    );
  } catch (e) {
    print('Error in createCategoryHandler: $e');
    return Response.internalServerError(body: 'Failed to create category.');
  }
}

/// Returns the existing category row for [name] (case-insensitive), or null.
Map<String, Object?>? findCategoryByName(Database db, String name) {
  final rows = db.select(
    'SELECT id, name FROM categories WHERE name = ? COLLATE NOCASE',
    [name.trim()],
  );
  if (rows.isEmpty) return null;
  final row = rows.first;
  return {'id': row['id'] as int, 'name': row['name'] as String};
}

/// Inserts [name] if it does not already exist (case-insensitive) and returns
/// the resulting category row. Safe to call on every expense save: the
/// `INSERT OR IGNORE` + `COLLATE NOCASE` constraint guarantees a single
/// canonical row per category concept.
Map<String, Object?> findOrCreateCategory(Database db, String name) {
  final trimmed = name.trim();
  db.execute(
    'INSERT OR IGNORE INTO categories (name) VALUES (?)',
    [trimmed],
  );
  return findCategoryByName(db, trimmed)!;
}
