import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart';
import 'package:test/test.dart';

import 'support/test_database.dart';

/// The only subprocess test. `server_test.dart` serves the handler inside the
/// test process; this one checks what that skips: `bin/server.dart` reading
/// PORT/POSTGRES_DB from the environment, running the migrations at startup
/// and printing the bound port. Requires `dart` on PATH.
void main() {
  late Process process;
  late String testDatabase;

  final databases = TestDatabases();

  setUp(() async {
    testDatabase = await databases.create();
  });

  tearDown(() async {
    process.kill();
    await process.exitCode;
    await databases.drop(testDatabase);
  });

  test('bin/server.dart starts with PORT=0 and serves /expenses', () async {
    process = await Process.start(
      'dart',
      ['run', 'bin/server.dart'],
      environment: {'PORT': '0', 'POSTGRES_DB': testDatabase},
    );

    // Keep draining stdout with listen() so the child's output buffer can't
    // fill up and block it. Connect via 127.0.0.1: the server binds IPv4
    // only, and localhost can resolve to ::1 first on macOS.
    final boundPort = Completer<String>();
    process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      final match =
          RegExp(r'Server running on http://\S+:(\d+)').firstMatch(line);
      if (match != null && !boundPort.isCompleted) {
        boundPort.complete(match.group(1));
      }
    });
    process.stderr.transform(utf8.decoder).listen(stderr.write);

    final port = await boundPort.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () =>
          throw StateError('Server did not report a bound port within 30s'),
    );

    final response = await get(Uri.parse('http://127.0.0.1:$port/expenses'));
    expect(response.statusCode, 200);
    expect(jsonDecode(response.body), isEmpty);
  });
}
