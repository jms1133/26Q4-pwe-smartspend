import 'package:postgres/postgres.dart';
import 'package:server_app/db/db_config.dart';
import 'package:server_app/db/migrations.dart';

/// Opens a connection pool to PostgreSQL and brings the schema up to date by
/// applying the numbered SQL files in [migrationsDir] (see migrations.dart).
///
/// Unlike the old synchronous sqlite3 API, every database call now goes over
/// the network, so it returns a `Future` and must be `await`ed. The handlers
/// receive the pool as a [Session]: each `execute` borrows a free connection,
/// runs the statement and gives the connection back, so concurrent requests
/// don't block each other.
Future<Pool> openExpenseDatabase(
  DbConfig config, {
  String migrationsDir = 'migrations',
}) async {
  // Read the files before connecting, so a broken migrations directory fails
  // without any network round trip.
  final migrations = loadMigrations(migrationsDir);

  final pool = Pool.withEndpoints(
    [config.endpoint],
    settings: const PoolSettings(
      maxConnectionCount: 10,
      sslMode: DbConfig.sslMode,
    ),
  );
  try {
    final applied = await applyMigrations(pool, migrations);
    if (applied.isNotEmpty) {
      print('Applied database migrations: ${applied.join(', ')}');
    }
  } catch (_) {
    await pool.close();
    rethrow;
  }
  return pool;
}
