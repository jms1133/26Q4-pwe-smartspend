import 'dart:convert';
import 'dart:io';

import 'package:server_app/db/db_config.dart';

/// Secrets and tuning for authentication, resolved like [DbConfig]:
/// process environment first, then the repo-root `.env`, then defaults.
class AuthConfig {
  /// HMAC key for signing JWTs (HS256).
  final String jwtSecret;

  /// bcrypt cost factor (log2 of the number of rounds).
  final int bcryptCost;

  /// HS256 keys shorter than the 256-bit hash output weaken the signature.
  static const minSecretBytes = 32;

  /// bcrypt's valid range; the package throws outside of it.
  static const minBcryptCost = 4;
  static const maxBcryptCost = 31;

  /// About 0.2-0.3 s per hash on a laptop: slow for an attacker, still fine
  /// for one login.
  static const defaultBcryptCost = 12;

  AuthConfig({required this.jwtSecret, this.bcryptCost = defaultBcryptCost}) {
    if (utf8.encode(jwtSecret).length < minSecretBytes) {
      throw StateError(
        'JWT_SECRET must be at least $minSecretBytes bytes long.',
      );
    }
    if (bcryptCost < minBcryptCost || bcryptCost > maxBcryptCost) {
      throw StateError(
        'BCRYPT_COST must be between $minBcryptCost and $maxBcryptCost, '
        'got $bcryptCost.',
      );
    }
  }

  /// Throws a [StateError] if `JWT_SECRET` is missing or too short, so the
  /// server refuses to start instead of signing tokens with a weak key.
  factory AuthConfig.fromEnvironment({
    Map<String, String>? environment,
    String envFilePath = '../.env',
  }) {
    final values = <String, String>{
      ...readEnvFile(envFilePath),
      ...(environment ?? Platform.environment),
    };

    final secret = values['JWT_SECRET'];
    if (secret == null || secret.isEmpty) {
      throw StateError(
        'JWT_SECRET is not set. Add it to the repo-root .env (see '
        '.env.example), e.g. generated with: openssl rand -base64 48',
      );
    }

    final costValue = values['BCRYPT_COST'];
    final cost = costValue == null
        ? defaultBcryptCost
        : int.tryParse(costValue);
    if (cost == null) {
      throw StateError('BCRYPT_COST must be an integer, got "$costValue".');
    }

    return AuthConfig(jwtSecret: secret, bcryptCost: cost);
  }
}
