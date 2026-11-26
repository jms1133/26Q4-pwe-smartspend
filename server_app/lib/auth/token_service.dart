import 'dart:convert';

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';

/// Issues and verifies HS256 JSON Web Tokens with the claims `sub` (user id
/// as a string), `iat` and `exp`.
///
/// Expiry is checked here against the injected [now], not by the library:
/// `dart_jsonwebtoken` reads the time through `package:clock`, which works
/// via zones, and tests would otherwise need to wrap the server in a fake
/// clock zone. With an injected function the tests just pass a different
/// clock.
class TokenService {
  final SecretKey _key;
  final DateTime Function() _now;
  final Duration validity;

  TokenService(
    String secret, {
    DateTime Function()? now,
    this.validity = const Duration(hours: 1),
  }) : _key = SecretKey(secret),
       _now = now ?? DateTime.now;

  /// Returns a signed token for [userId] and the moment it expires.
  ({String token, DateTime expiresAt}) issue(int userId) {
    final issuedAt = _now().toUtc();
    final expiresAt = issuedAt.add(validity);
    final token = JWT({
      'sub': '$userId',
      'iat': _secondsSinceEpoch(issuedAt),
      'exp': _secondsSinceEpoch(expiresAt),
    }).sign(_key, algorithm: JWTAlgorithm.HS256, noIssueAt: true);
    return (token: token, expiresAt: expiresAt);
  }

  /// Returns the user id from a valid token, or null if the token is
  /// malformed, not HS256, wrongly signed, altered or expired.
  int? verify(String token) {
    // The library takes the algorithm from the token's own header. Checking
    // it first means a token can't pick a weaker algorithm (e.g. "none")
    // than the one this server signs with.
    final header = _decodeHeader(token);
    if (header == null || header['alg'] != 'HS256' || header['typ'] != 'JWT') {
      return null;
    }

    final Object? payload;
    try {
      payload = JWT
          .verify(token, _key, checkExpiresIn: false, checkNotBefore: false)
          .payload;
    } on Exception {
      return null;
    }

    if (payload is! Map) return null;
    final exp = payload['exp'];
    final sub = payload['sub'];
    if (exp is! int || sub is! String) return null;

    final expiresAt = DateTime.fromMillisecondsSinceEpoch(
      exp * 1000,
      isUtc: true,
    );
    if (!_now().isBefore(expiresAt)) return null;

    return int.tryParse(sub);
  }

  static Map<String, Object?>? _decodeHeader(String token) {
    final parts = token.split('.');
    if (parts.length != 3) return null;
    try {
      final decoded = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[0]))),
      );
      return decoded is Map<String, Object?> ? decoded : null;
    } on FormatException {
      return null;
    }
  }

  static int _secondsSinceEpoch(DateTime time) =>
      time.millisecondsSinceEpoch ~/ 1000;
}
