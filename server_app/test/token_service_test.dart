import 'dart:convert';

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:server_app/auth/token_service.dart';
import 'package:test/test.dart';

const _secret = 'unit-test-secret-with-at-least-32-bytes';

String _b64(Map<String, Object?> json) =>
    base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');

void main() {
  var now = DateTime.utc(2026, 11, 26, 12);
  late TokenService tokens;

  setUp(() {
    now = DateTime.utc(2026, 11, 26, 12);
    tokens = TokenService(_secret, now: () => now);
  });

  Map<String, Object?> payloadOf(String token) => jsonDecode(
    utf8.decode(base64Url.decode(base64Url.normalize(token.split('.')[1]))),
  ) as Map<String, Object?>;

  test('issued token verifies and carries sub, iat and exp', () {
    final (:token, :expiresAt) = tokens.issue(42);

    expect(tokens.verify(token), 42);
    expect(expiresAt, now.add(const Duration(hours: 1)));
    expect(payloadOf(token), {
      'sub': '42',
      'iat': now.millisecondsSinceEpoch ~/ 1000,
      'exp': expiresAt.millisecondsSinceEpoch ~/ 1000,
    });
  });

  test('rejects an expired token (injected clock)', () {
    final (:token, expiresAt: _) = tokens.issue(1);

    now = now.add(const Duration(minutes: 59));
    expect(tokens.verify(token), 1);

    now = now.add(const Duration(minutes: 1));
    expect(tokens.verify(token), isNull);
  });

  test('rejects a token signed with another algorithm (HS512)', () {
    final token = JWT({'sub': '1', 'exp': 4102444800})
        .sign(SecretKey(_secret), algorithm: JWTAlgorithm.HS512);
    expect(tokens.verify(token), isNull);
  });

  test('rejects alg "none"', () {
    final header = _b64({'alg': 'none', 'typ': 'JWT'});
    final payload = _b64({'sub': '1', 'exp': 4102444800});
    expect(tokens.verify('$header.$payload.'), isNull);
  });

  test('rejects a token signed with a wrong secret', () {
    final other = TokenService(
      'another-secret-with-at-least-32-bytes!',
      now: () => now,
    );
    final (:token, expiresAt: _) = other.issue(1);
    expect(tokens.verify(token), isNull);
  });

  test('rejects an altered payload', () {
    final (:token, expiresAt: _) = tokens.issue(1);
    final parts = token.split('.');
    final forged = {...payloadOf(token), 'sub': '2'};
    expect(tokens.verify('${parts[0]}.${_b64(forged)}.${parts[2]}'), isNull);
  });

  test('rejects a header without typ JWT', () {
    final token = JWT(
      {'sub': '1', 'exp': 4102444800},
      header: {'typ': 'at+jwt'},
    ).sign(SecretKey(_secret));
    expect(tokens.verify(token), isNull);
  });

  test('rejects garbage', () {
    for (final token in ['', 'abc', 'a.b.c', '...', 'x.${_b64({})}.y']) {
      expect(tokens.verify(token), isNull, reason: token);
    }
  });

  test(
    'rejects a validly signed token without exp or with a non-numeric sub',
    () {
      final noExp = JWT({'sub': '1'}).sign(SecretKey(_secret));
      final badSub = JWT({'sub': 'alice', 'exp': 4102444800})
          .sign(SecretKey(_secret));
      expect(tokens.verify(noExp), isNull);
      expect(tokens.verify(badSub), isNull);
    },
  );
}
