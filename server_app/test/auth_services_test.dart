import 'package:server_app/auth/auth_config.dart';
import 'package:server_app/auth/auth_services.dart';
import 'package:server_app/auth/token_service.dart';
import 'package:test/test.dart';

const _secret = 'from-config-test-secret-with-32-bytes';

void main() {
  group('AuthServices.fromConfig', () {
    late AuthServices auth;

    setUpAll(() async {
      auth = await AuthServices.fromConfig(
        AuthConfig(jwtSecret: _secret, bcryptCost: 4),
      );
    });

    test('signs tokens with the configured secret', () {
      final (:token, expiresAt: _) = auth.tokens.issue(7);

      expect(auth.tokens.verify(token), 7);
      expect(TokenService(_secret).verify(token), 7);
      expect(
        TokenService('another-secret-that-is-also-32-bytes').verify(token),
        isNull,
      );
    });

    test('hashes passwords with the configured cost', () async {
      expect(auth.passwords.cost, 4);
      expect(auth.passwords.dummyHash, matches(r'^\$2[aby]\$04\$'));

      final hash = await auth.passwords.hash('correct horse');
      expect(hash, matches(r'^\$2[aby]\$04\$'));
      expect(await auth.passwords.verify('correct horse', hash), isTrue);
    });

    test('uses the default rate limits', () {
      expect(auth.loginLimiter.maxAttempts, AuthServices.loginMaxFailures);
      expect(auth.loginLimiter.maxAttempts, 5);
      expect(auth.loginLimiter.window, const Duration(minutes: 15));

      expect(
        auth.registerLimiter.maxAttempts,
        AuthServices.registerMaxAttempts,
      );
      expect(auth.registerLimiter.maxAttempts, 10);
      expect(auth.registerLimiter.window, const Duration(hours: 1));
    });
  });
}
