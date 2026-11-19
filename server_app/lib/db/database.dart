import 'dart:io';
import 'package:sqlite3/sqlite3.dart';

/// The category names seeded on first initialization. These used to be the
/// fixed `category` enum in `api.yaml`; they now live as data so the AI (or
/// user) can introduce new categories at runtime. Seeding preserves the
/// original set so existing expenses and the form dropdown still have them.
const List<String> seedCategories = [
  'food',
  'transport',
  'entertainment',
  'housing',
  'health',
  'insurance',
  'shopping',
  'subscriptions',
  'education',
];

/// Opens (and creates if needed) the SQLite database file, and ensures the
/// `expenses` and `categories` tables exist. The `categories` table is seeded
/// with [seedCategories] the first time it is created.
///
/// Note: sqlite3's Dart API is synchronous (no `Future`/`await` needed) —
/// unlike most Dart I/O, the native SQLite C library does the file access
/// in a blocking call under the hood. This is fine for a single-process
/// shelf server at this scale.
Database openExpenseDatabase({String path = 'smart_spend.db'}) {
  final dbFile = File(path);
  final db = sqlite3.open(dbFile.path);

  db.execute('''
    CREATE TABLE IF NOT EXISTS expenses (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      title TEXT NOT NULL,
      category TEXT NOT NULL,
      subcategory TEXT,
      description TEXT,
      amount REAL NOT NULL,
      timestamp TEXT NOT NULL
    )
  ''');

  // `name COLLATE NOCASE UNIQUE` makes the dedup case-insensitive at the DB
  // level: inserting "Food" when "food" exists is rejected, so find-or-create
  // (via INSERT OR IGNORE) converges on a single canonical row per concept.
  db.execute('''
    CREATE TABLE IF NOT EXISTS categories (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL COLLATE NOCASE UNIQUE
    )
  ''');

  final stmt = db.prepare('INSERT OR IGNORE INTO categories (name) VALUES (?)');
  for (final name in seedCategories) {
    stmt.execute([name]);
  }
  stmt.dispose();

  return db;
}
