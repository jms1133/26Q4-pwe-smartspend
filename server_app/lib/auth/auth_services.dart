import 'package:server_app/auth/auth_config.dart';
import 'package:server_app/auth/password_hasher.dart';
import 'package:server_app/auth/rate_limiter.dart';
import 'package:server_app/auth/token_service.dart';

/// The auth building blocks the request pipeline needs, created once at
/// startup and shared by all requests (like the DB pool).
class AuthServices {
  final TokenService tokens;
  final PasswordHasher passwords;

  /// Failed logins per (client IP, username).
  final RateLimiter loginLimiter;

  /// Registration attempts per client IP.
  final RateLimiter registerLimiter;

  static const loginMaxFailures = 5;
  static const loginWindow = Duration(minutes: 15);
  static const registerMaxAttempts = 10;
  static const registerWindow = Duration(hours: 1);

  AuthServices({
    required this.tokens,
    required this.passwords,
    RateLimiter? loginLimiter,
    RateLimiter? registerLimiter,
    DateTime Function()? now,
  }) : loginLimiter =
           loginLimiter ??
           RateLimiter(
             maxAttempts: loginMaxFailures,
             window: loginWindow,
             now: now,
           ),
       registerLimiter =
           registerLimiter ??
           RateLimiter(
             maxAttempts: registerMaxAttempts,
             window: registerWindow,
             now: now,
           );

  static Future<AuthServices> fromConfig(AuthConfig config) async {
    return AuthServices(
      tokens: TokenService(config.jwtSecret),
      passwords: await PasswordHasher.create(config.bcryptCost),
    );
  }
}
