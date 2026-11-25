import 'dart:math';

import 'package:postgres/postgres.dart';
import 'package:server_app/db/db_config.dart';

/// Creates and drops throwaway PostgreSQL databases for tests.
///
/// Uses the same settings as the server (env / repo-root `.env`), but
/// connects to the `postgres` maintenance database to run
/// `CREATE/DROP DATABASE`, which can't run inside the database being dropped.
class TestDatabases {
  TestDatabases() : baseConfig = DbConfig.fromEnvironment();

  final DbConfig baseConfig;

  /// Creates a database with a unique name and returns that name.
  ///
  /// The random suffix keeps parallel test runs (e.g. several agents sharing
  /// one Compose `db`) apart. The name only contains `[a-z0-9_]`, so
  /// interpolating it into DDL is safe.
  Future<String> create() async {
    final suffix = '${DateTime.now().microsecondsSinceEpoch}_'
        '${Random().nextInt(1 << 32)}';
    final name = 'smart_spend_test_$suffix';
    await _runAdmin('CREATE DATABASE $name');
    return name;
  }

  /// Drops [name]. `WITH (FORCE)` (PostgreSQL 13+) terminates connections
  /// a killed server's pool may still hold open.
  Future<void> drop(String name) =>
      _runAdmin('DROP DATABASE IF EXISTS $name WITH (FORCE)');

  Future<void> _runAdmin(String sql) async {
    final conn = await Connection.open(
      baseConfig.withDatabase('postgres').endpoint,
      settings: const ConnectionSettings(sslMode: DbConfig.sslMode),
    );
    try {
      await conn.execute(sql);
    } finally {
      await conn.close();
    }
  }
}
