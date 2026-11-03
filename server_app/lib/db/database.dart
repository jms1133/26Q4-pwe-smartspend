import 'dart:io';
import 'package:sqlite3/sqlite3.dart';

/// Opens (and creates if needed) the SQLite database file, and ensures
/// the `expenses` table exists.
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

  return db;
}
