import 'dart:io';

import 'package:postgres/postgres.dart';

/// PostgreSQL connection settings for the server.
///
/// Values are resolved with this precedence (highest first):
///   1. Process environment variables (e.g. set by Docker Compose or CI).
///   2. The repo-root `.env` file (the same file Docker Compose reads), so
///      local `dart run` / `dart test` work without exporting variables.
///   3. Defaults that match `docker-compose.yml`.
///
/// The variable names are the ones in `.env.example`, so the server and the
/// `db` container always agree on database, user and password.
class DbConfig {
  final String host;
  final int port;
  final String database;
  final String username;
  final String password;

  const DbConfig({
    required this.host,
    required this.port,
    required this.database,
    required this.username,
    required this.password,
  });

  /// Builds the config from [environment] (defaults to the process
  /// environment) layered over the `.env` file at [envFilePath].
  ///
  /// Throws a [StateError] if no password is configured: there is
  /// deliberately no default, mirroring `POSTGRES_PASSWORD` in Compose.
  factory DbConfig.fromEnvironment({
    Map<String, String>? environment,
    String envFilePath = '../.env',
  }) {
    final values = <String, String>{
      ...readEnvFile(envFilePath),
      ...(environment ?? Platform.environment),
    };

    final password = values['POSTGRES_PASSWORD'];
    if (password == null || password.isEmpty) {
      throw StateError(
        'POSTGRES_PASSWORD is not set. Copy .env.example to .env in the repo '
        'root and set a password, or export POSTGRES_PASSWORD.',
      );
    }

    final portValue = values['DB_PORT'] ?? '5432';
    final port = int.tryParse(portValue);
    if (port == null) {
      throw StateError('DB_PORT must be an integer, got "$portValue".');
    }

    return DbConfig(
      // Compose publishes the port on 127.0.0.1 only. localhost still works:
      // it resolves to both 127.0.0.1 and ::1, and the socket connect tries
      // each address (checked on macOS against the Compose container).
      host: values['DB_HOST'] ?? 'localhost',
      port: port,
      database: values['POSTGRES_DB'] ?? 'smart_spend',
      username: values['POSTGRES_USER'] ?? 'smart_spend',
      password: password,
    );
  }

  /// Returns a copy pointing at another database on the same server. Tests
  /// use this to reach the `postgres` maintenance database.
  DbConfig withDatabase(String database) => DbConfig(
        host: host,
        port: port,
        database: database,
        username: username,
        password: password,
      );

  Endpoint get endpoint => Endpoint(
        host: host,
        port: port,
        database: database,
        username: username,
        password: password,
      );

  /// TLS is off because the database is only reachable on 127.0.0.1 or the
  /// internal Compose network. The postgres package defaults to
  /// `SslMode.require`, which the stock `postgres:16` image does not support.
  static const SslMode sslMode = SslMode.disable;
}

/// Parses a `.env` file into a map. Missing files yield an empty map.
///
/// Supports `KEY=VALUE` lines, blank lines, `#` comments and values wrapped
/// in single or double quotes. This is the subset Docker Compose uses for
/// `.env.example`; it does not expand `${VAR}` references.
Map<String, String> readEnvFile(String path) {
  final file = File(path);
  if (!file.existsSync()) return {};
  return parseEnvLines(file.readAsLinesSync());
}

/// Line-level parser behind [readEnvFile], split out so it can be tested
/// without touching the file system.
Map<String, String> parseEnvLines(Iterable<String> lines) {
  final result = <String, String>{};
  for (final rawLine in lines) {
    final line = rawLine.trim();
    if (line.isEmpty || line.startsWith('#')) continue;

    final separator = line.indexOf('=');
    if (separator <= 0) continue;

    final key = line.substring(0, separator).trim();
    var value = line.substring(separator + 1).trim();
    final isQuoted = value.length >= 2 &&
        ((value.startsWith('"') && value.endsWith('"')) ||
            (value.startsWith("'") && value.endsWith("'")));
    if (isQuoted) {
      value = value.substring(1, value.length - 1);
    }
    result[key] = value;
  }
  return result;
}
