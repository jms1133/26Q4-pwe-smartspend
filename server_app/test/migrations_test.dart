import 'dart:io';

import 'package:postgres/postgres.dart';
import 'package:server_app/db/db_config.dart';
import 'package:server_app/db/migrations.dart';
import 'package:test/test.dart';

import 'support/test_database.dart';

void main() {
  group('loadMigrations', () {
    late Directory dir;

    setUp(() => dir = Directory.systemTemp.createTempSync('migrations_test_'));
    tearDown(() => dir.deleteSync(recursive: true));

    void write(String name, [String sql = 'SELECT 1;']) =>
        File('${dir.path}/$name').writeAsStringSync(sql);

    test('returns files sorted by version and ignores non-SQL files', () {
      write('010_later.sql');
      write('002_second.sql');
      write('001_first.sql', 'CREATE TABLE t ();');
      write('README.md', 'not a migration');

      final migrations = loadMigrations(dir.path);

      expect(migrations.map((m) => m.version), [1, 2, 10]);
      expect(migrations.map((m) => m.name), ['first', 'second', 'later']);
      expect(migrations.first.sql, 'CREATE TABLE t ();');
    });

    test('rejects a .sql file with an invalid name', () {
      write('001_first.sql');
      write('add_users.sql');
      expect(() => loadMigrations(dir.path), throwsStateError);
    });

    test('rejects two files with the same version', () {
      write('001_first.sql');
      write('1_also_first.sql');
      expect(() => loadMigrations(dir.path), throwsStateError);
    });

    test('rejects a missing directory', () {
      expect(
        () => loadMigrations('${dir.path}/does_not_exist'),
        throwsStateError,
      );
    });

    test('the repository migrations directory loads', () {
      final migrations = loadMigrations('migrations');
      expect(migrations.first.version, 1);
      expect(migrations.first.name, 'initial_schema');
    });
  });

  group('applyMigrations', () {
    final databases = TestDatabases();
    late String testDatabase;
    late Connection db;

    setUp(() async {
      testDatabase = await databases.create();
      db = await Connection.open(
        databases.baseConfig.withDatabase(testDatabase).endpoint,
        settings: const ConnectionSettings(sslMode: DbConfig.sslMode),
      );
    });

    tearDown(() async {
      await db.close();
      await databases.drop(testDatabase);
    });

    Future<List<int>> recordedVersions() async {
      final rows =
          await db.execute('SELECT version FROM schema_version ORDER BY 1');
      return rows.map((r) => r[0] as int).toList();
    }

    Future<bool> tableExists(String name) async {
      final rows = await db.execute(
        Sql.named('SELECT to_regclass(@name) IS NOT NULL'),
        parameters: {'name': name},
      );
      return rows.first[0] as bool;
    }

    const second = Migration(
      version: 2,
      name: 'add_notes',
      sql: 'CREATE TABLE notes (id INTEGER PRIMARY KEY);',
    );

    test('applies pending migrations once and records them', () async {
      final repo = loadMigrations('migrations');

      expect(await applyMigrations(db, repo), [1]);
      expect(await recordedVersions(), [1]);
      expect(await tableExists('expenses'), isTrue);

      final seeded = await db.execute('SELECT count(*) FROM categories');
      expect(seeded.first[0], 9);

      expect(await applyMigrations(db, repo), isEmpty);
      expect(await applyMigrations(db, [...repo, second]), [2]);
      expect(await recordedVersions(), [1, 2]);
      expect(await tableExists('notes'), isTrue);
    });

    test('rolls back everything when a migration fails', () async {
      const broken = Migration(
        version: 3,
        name: 'broken',
        sql: 'CREATE TABLE half_done (id INTEGER); SELECT * FROM missing;',
      );
      final repo = loadMigrations('migrations');

      await expectLater(
        applyMigrations(db, [...repo, second, broken]),
        throwsA(isA<ServerException>()),
      );

      // Nothing from this call survives, not even migration 1 or the
      // schema_version table it would have created.
      expect(await tableExists('schema_version'), isFalse);
      expect(await tableExists('expenses'), isFalse);
      expect(await tableExists('notes'), isFalse);
      expect(await tableExists('half_done'), isFalse);
    });

    test('refuses a database with a version the code does not know',
        () async {
      final repo = loadMigrations('migrations');
      await applyMigrations(db, [...repo, second]);

      expect(() => applyMigrations(db, repo), throwsStateError);
    });
  });
}
