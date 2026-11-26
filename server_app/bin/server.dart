import 'dart:io';

import 'package:server_app/db/database.dart';
import 'package:server_app/db/db_config.dart';
import 'package:server_app/server.dart';
import 'package:server_app/services/ai_service.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

void main(List<String> args) async {
  // Use any available host or container IP (usually `0.0.0.0`).
  final ip = InternetAddress.anyIPv4;

  // Open one connection pool at startup and share it across all requests.
  // Connection settings come from the env / repo-root .env (see DbConfig),
  // the same values Docker Compose uses for the `db` container.
  final db = await openExpenseDatabase(DbConfig.fromEnvironment());
  final handler = buildHandler(db, AiService());

  // For running in containers, we respect the PORT environment variable.
  final port = int.parse(Platform.environment['PORT'] ?? '8082');

  final server = await shelf_io.serve(handler, ip, port);
  print('Server running on http://${server.address.host}:${server.port}');
}
