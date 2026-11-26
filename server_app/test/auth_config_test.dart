import 'package:server_app/auth/auth_config.dart';
import 'package:server_app/auth/password_hasher.dart';
import 'package:test/test.dart';

const _secret = 'a-secret-that-is-at-least-32-bytes-long';

AuthConfig _fromEnv(Map<String, String> env) => AuthConfig.fromEnvironment(
  environment: env,
  envFilePath: 'test/does-not-exist.env',
);

void main() {
  group('AuthConfig.fromEnvironment', () {
    test('reads JWT_SECRET and defaults BCRYPT_COST to 12', () {
      final config = _fromEnv({'JWT_SECRET': _secret});
      expect(config.jwtSecret, _secret);
      expect(config.bcryptCost, 12);
    });

    test('reads BCRYPT_COST', () {
      expect(
        _fromEnv({'JWT_SECRET': _secret, 'BCRYPT_COST': '4'}).bcryptCost,
        4,
      );
    });

    test('refuses a missing or empty JWT_SECRET', () {
      expect(() => _fromEnv({}), throwsStateError);
      expect(() => _fromEnv({'JWT_SECRET': ''}), throwsStateError);
    });

    test('refuses a JWT_SECRET shorter than 32 bytes', () {
      expect(() => _fromEnv({'JWT_SECRET': 'x' * 31}), throwsStateError);
      expect(_fromEnv({'JWT_SECRET': 'x' * 32}).jwtSecret, 'x' * 32);
    });

    test('refuses an invalid BCRYPT_COST', () {
      for (final cost in ['abc', '3', '32']) {
        expect(
          () => _fromEnv({'JWT_SECRET': _secret, 'BCRYPT_COST': cost}),
          throwsStateError,
          reason: cost,
        );
      }
    });
  });

  group('PasswordHasher', () {
    late PasswordHasher hasher;

    setUpAll(() async => hasher = await PasswordHasher.create(4));

    test('verifies the right password and rejects a wrong one', () async {
      final hash = await hasher.hash('correct horse battery');
      expect(hash, startsWith(r'$2a$04$'));
      expect(await hasher.verify('correct horse battery', hash), isTrue);
      expect(await hasher.verify('wrong horse battery', hash), isFalse);
    });

    test('salts every hash', () async {
      expect(
        await hasher.hash('same password'),
        isNot(await hasher.hash('same password')),
      );
    });

    test(
      'without a stored hash, checks against the dummy hash and fails',
      () async {
        final checkedHashes = <String>[];
        final spy = await PasswordHasher.create(
          4,
          check: (password, hash) {
            checkedHashes.add(hash);
            return checkPasswordInIsolate(password, hash);
          },
        );

        expect(await spy.verify('any password', null), isFalse);
        expect(checkedHashes, [spy.dummyHash]);
      },
    );
  });
}
