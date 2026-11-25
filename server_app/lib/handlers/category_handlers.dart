import 'dart:convert';
import 'package:postgres/postgres.dart';
import 'package:shelf/shelf.dart';

/// Returns all categories ordered alphabetically (case-insensitive).
Future<Response> listCategoriesHandler(Request request, Session db) async {
  final rows = await db.execute(
    'SELECT id, name FROM categories ORDER BY lower(name) ASC',
  );
  final categories = rows.map(_rowToCategory).toList();

  return Response.ok(
    jsonEncode(categories),
    headers: {'Content-Type': 'application/json'},
  );
}

/// Find-or-create a category by name. Matching is case-insensitive (unique
/// index on `lower(name)`), so "Food" resolves to an existing "food" rather
/// than creating a duplicate. Returns 200 for an existing match and 201 when
/// a new row is created.
Future<Response> createCategoryHandler(Request request, Session db) async {
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

    final (:category, :created) = await findOrCreateCategory(db, name);
    return Response(
      created ? 201 : 200,
      body: jsonEncode(category),
      headers: {'Content-Type': 'application/json'},
    );
  } catch (e) {
    print('Error in createCategoryHandler: $e');
    return Response.internalServerError(body: 'Failed to create category.');
  }
}

/// Inserts [name] if it does not already exist (case-insensitive) and returns
/// the canonical category row plus whether it was newly created. Safe to call
/// on every expense save.
///
/// One statement, race-safe: the INSERT either creates the row or hits the
/// unique index on `lower(name)`. On conflict, `DO UPDATE` with a no-op
/// assignment (keeps the stored spelling) makes RETURNING yield the
/// *existing* row, which `DO NOTHING` would not. If two requests race on the
/// same new name, the second one waits for the first to commit and then
/// takes the conflict path, so both get the same id and only one row exists.
///
/// `xmax = 0` is true only for a freshly inserted row version; the no-op
/// update writes a new version with `xmax` set, so this tells "created"
/// from "already existed" without a second query.
Future<({Map<String, Object> category, bool created})> findOrCreateCategory(
  Session db,
  String name,
) async {
  final rows = await db.execute(
    Sql.named('''
      INSERT INTO categories (name) VALUES (@name)
      ON CONFLICT ((lower(name))) DO UPDATE SET name = categories.name
      RETURNING id, name, (xmax = 0) AS created
    '''),
    parameters: {'name': name.trim()},
  );
  final row = rows.first;
  return (
    category: _rowToCategory(row),
    created: row.toColumnMap()['created'] as bool,
  );
}

Map<String, Object> _rowToCategory(ResultRow row) {
  final map = row.toColumnMap();
  return {'id': map['id'] as int, 'name': map['name'] as String};
}
