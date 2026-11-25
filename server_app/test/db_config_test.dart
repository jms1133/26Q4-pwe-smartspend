import 'dart:io';

import 'package:server_app/db/db_config.dart';
import 'package:test/test.dart';

void main() {
  group('parseEnvLines', () {
    test('parses KEY=VALUE lines and skips comments and blanks', () {
      final values = parseEnvLines([
        '# comment',
        '',
        'POSTGRES_DB=smart_spend',
        '  DB_PORT = 5433  ',
      ]);
      expect(values, {'POSTGRES_DB': 'smart_spend', 'DB_PORT': '5433'});
    });

    test('strips matching single or double quotes', () {
      final values = parseEnvLines([
        'A="with spaces"',
        "B='single'",
        'C="unbalanced',
      ]);
      expect(values['A'], 'with spaces');
      expect(values['B'], 'single');
      expect(values['C'], '"unbalanced');
    });

    test('keeps "=" inside values and ignores lines without a key', () {
      final values = parseEnvLines(['PASSWORD=a=b=c', '=novalue', 'junk']);
      expect(values, {'PASSWORD': 'a=b=c'});
    });
  });

  group('DbConfig.fromEnvironment', () {
    const missingFile = '/nonexistent/.env';

    test('applies Compose-compatible defaults', () {
      final config = DbConfig.fromEnvironment(
        environment: {'POSTGRES_PASSWORD': 'secret'},
        envFilePath: missingFile,
      );
      expect(config.host, 'localhost');
      expect(config.port, 5432);
      expect(config.database, 'smart_spend');
      expect(config.username, 'smart_spend');
      expect(config.password, 'secret');
    });

    test('throws when no password is configured', () {
      expect(
        () => DbConfig.fromEnvironment(
          environment: {},
          envFilePath: missingFile,
        ),
        throwsStateError,
      );
    });

    test('throws on a non-numeric DB_PORT', () {
      expect(
        () => DbConfig.fromEnvironment(
          environment: {'POSTGRES_PASSWORD': 'x', 'DB_PORT': 'abc'},
          envFilePath: missingFile,
        ),
        throwsStateError,
      );
    });

    test('process environment overrides the .env file', () async {
      final dir = await Directory.systemTemp.createTemp('db_config_test');
      addTearDown(() => dir.delete(recursive: true));
      final envFile = File('${dir.path}/.env')
        ..writeAsStringSync(
          'POSTGRES_PASSWORD=from-file\nPOSTGRES_DB=file_db\nDB_PORT=5999\n',
        );

      final config = DbConfig.fromEnvironment(
        environment: {'POSTGRES_DB': 'env_db', 'DB_HOST': 'db'},
        envFilePath: envFile.path,
      );
      expect(config.password, 'from-file');
      expect(config.port, 5999);
      expect(config.database, 'env_db');
      expect(config.host, 'db');
    });

    test('withDatabase only changes the database name', () {
      final config = DbConfig.fromEnvironment(
        environment: {'POSTGRES_PASSWORD': 'secret', 'DB_PORT': '6000'},
        envFilePath: missingFile,
      ).withDatabase('postgres');
      expect(config.database, 'postgres');
      expect(config.port, 6000);
      expect(config.password, 'secret');
    });
  });
}
