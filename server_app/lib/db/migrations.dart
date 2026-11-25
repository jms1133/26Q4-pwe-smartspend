import 'dart:io';

import 'package:postgres/postgres.dart';

/// One numbered SQL file from the migrations directory.
class Migration {
  final int version;
  final String name;
  final String sql;

  const Migration({
    required this.version,
    required this.name,
    required this.sql,
  });
}

/// `NNN_description.sql`, e.g. `001_initial_schema.sql`.
final _fileNamePattern = RegExp(r'^(\d+)_([a-z0-9_]+)\.sql$');

/// Arbitrary constant key for `pg_advisory_xact_lock`. All server instances
/// use the same key, so only one of them migrates at a time.
const _migrationLockKey = 862214001;

/// Reads all `*.sql` files in [directoryPath], sorted by version number.
///
/// Non-SQL files (e.g. a README) are ignored. A `.sql` file with a name that
/// doesn't match `NNN_description.sql`, or two files with the same version,
/// is a [StateError]: silently skipping a mistyped file would leave the
/// schema incomplete without anyone noticing.
List<Migration> loadMigrations(String directoryPath) {
  final directory = Directory(directoryPath);
  if (!directory.existsSync()) {
    throw StateError(
      'Migrations directory not found: ${directory.absolute.path}',
    );
  }

  final fileNamesByVersion = <int, String>{};
  final migrations = <Migration>[];
  for (final file in directory.listSync().whereType<File>()) {
    final fileName = file.uri.pathSegments.last;
    if (!fileName.endsWith('.sql')) continue;

    final match = _fileNamePattern.firstMatch(fileName);
    if (match == null) {
      throw StateError(
        'Invalid migration file name "$fileName". '
        'Expected NNN_description.sql (lowercase letters, digits, underscores).',
      );
    }

    final version = int.parse(match.group(1)!);
    final previous = fileNamesByVersion[version];
    if (previous != null) {
      throw StateError(
        'Duplicate migration version $version: "$previous" and "$fileName".',
      );
    }
    fileNamesByVersion[version] = fileName;
    migrations.add(Migration(
      version: version,
      name: match.group(2)!,
      sql: file.readAsStringSync(),
    ));
  }

  migrations.sort((a, b) => a.version.compareTo(b.version));
  return migrations;
}

/// Applies every migration whose version is not yet in `schema_version` and
/// returns the versions applied by this call (empty if already up to date).
///
/// Everything runs in a single transaction. PostgreSQL DDL is transactional,
/// so if any migration fails, all of this call's changes are rolled back,
/// including the `schema_version` rows. The advisory lock makes a second
/// server starting at the same time wait, and then see the work as done.
///
/// Rules for migration files: never edit a file once it has been applied
/// anywhere, add a new numbered file instead. Files must not contain
/// `BEGIN`/`COMMIT` or statements that cannot run inside a transaction
/// (e.g. `CREATE INDEX CONCURRENTLY`).
///
/// Throws a [StateError] if the database contains a version this code
/// doesn't know, i.e. the database is newer than the server.
Future<List<int>> applyMigrations(
  SessionExecutor db,
  List<Migration> migrations,
) {
  return db.runTx((tx) async {
    await tx.execute('SELECT pg_advisory_xact_lock($_migrationLockKey)');
    await tx.execute('''
      CREATE TABLE IF NOT EXISTS schema_version (
        version INTEGER PRIMARY KEY,
        name TEXT NOT NULL,
        applied_at TIMESTAMPTZ NOT NULL DEFAULT now()
      )
    ''');

    final rows = await tx.execute('SELECT version FROM schema_version');
    final appliedVersions = rows.map((row) => row[0] as int).toSet();

    final knownVersions = migrations.map((m) => m.version).toSet();
    final unknownVersions = appliedVersions.difference(knownVersions).toList()
      ..sort();
    if (unknownVersions.isNotEmpty) {
      throw StateError(
        'The database has migrations this server does not know: '
        '$unknownVersions. Is the server code out of date?',
      );
    }

    final newlyApplied = <int>[];
    for (final migration in migrations) {
      if (appliedVersions.contains(migration.version)) continue;

      // Simple query mode lets one file contain several statements; the
      // default extended mode accepts exactly one statement per call.
      await tx.execute(migration.sql, queryMode: QueryMode.simple);
      await tx.execute(
        Sql.named(
          'INSERT INTO schema_version (version, name) VALUES (@version, @name)',
        ),
        parameters: {'version': migration.version, 'name': migration.name},
      );
      newlyApplied.add(migration.version);
    }
    return newlyApplied;
  });
}
