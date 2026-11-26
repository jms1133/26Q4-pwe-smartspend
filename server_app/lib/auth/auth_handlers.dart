import 'dart:convert';
import 'dart:io';

import 'package:postgres/postgres.dart';
import 'package:server_app/auth/auth_services.dart';
import 'package:server_app/auth/rate_limiter.dart';
import 'package:server_app/db/default_categories.dart';
import 'package:shelf/shelf.dart';

final _usernamePattern = RegExp(r'^[a-z0-9._-]{3,32}$');

const _minPasswordBytes = 8;

/// bcrypt only uses the first 72 bytes of a password and silently ignores
/// the rest, so longer passwords are rejected instead of being truncated.
const _maxPasswordBytes = 72;

/// Validated, normalized credentials from a request body.
typedef _Credentials = ({String username, String password});

/// `POST /auth/register`: creates a user and copies the default categories
/// for them. 201 `User`, 400 invalid input, 409 username taken, 429 too many
/// attempts from this IP.
Future<Response> registerHandler(
  Request request,
  Pool db,
  AuthServices auth,
) async {
  try {
    // Every attempt counts, valid or not: the limit exists because a 409
    // reveals that a username is taken.
    final ipKey = _clientIp(request);
    final wait = auth.registerLimiter.retryAfter(ipKey);
    if (wait != null) return _tooManyRequests(wait);
    auth.registerLimiter.record(ipKey);

    final parsed = _parseCredentials(await request.readAsString());
    if (parsed.error != null) return Response.badRequest(body: parsed.error);
    final credentials = parsed.credentials!;

    final passwordHash = await auth.passwords.hash(credentials.password);

    final int userId;
    try {
      // One transaction: a user without categories (or categories without
      // a user) can never be committed.
      userId = await db.runTx((tx) async {
        final rows = await tx.execute(
          Sql.named('''
            INSERT INTO users (username, password_hash)
            VALUES (@username, @hash)
            RETURNING id
          '''),
          parameters: {'username': credentials.username, 'hash': passwordHash},
        );
        final id = rows.first[0] as int;
        await tx.execute(
          Sql.named('''
            INSERT INTO categories (user_id, name)
            SELECT @userId, unnest(@names)
          '''),
          parameters: {
            'userId': id,
            'names': TypedValue(Type.textArray, defaultCategoryNames),
          },
        );
        return id;
      });
    } on UniqueViolationException catch (e) {
      // Checking the database's unique index instead of a SELECT first: two
      // simultaneous registrations of the same name can't both pass.
      if (e.constraintName != 'users_username_lower_key') rethrow;
      return Response(409, body: 'Username is already taken.');
    }

    return Response(
      201,
      body: jsonEncode({'id': userId, 'username': credentials.username}),
      headers: {'Content-Type': 'application/json'},
    );
  } catch (e) {
    print('Error in registerHandler: $e');
    return Response.internalServerError(body: 'Failed to register.');
  }
}

/// `POST /auth/login`: 200 `AuthToken`, 400 invalid input, 401 wrong
/// username or password (deliberately the same response for both), 429
/// after too many failures for this IP and username.
Future<Response> loginHandler(
  Request request,
  Session db,
  AuthServices auth,
) async {
  try {
    final parsed = _parseCredentials(await request.readAsString());
    if (parsed.error != null) return Response.badRequest(body: parsed.error);
    final credentials = parsed.credentials!;

    final limitKey = '${_clientIp(request)}|${credentials.username}';
    final wait = auth.loginLimiter.retryAfter(limitKey);
    if (wait != null) return _tooManyRequests(wait);
    // Counted before the bcrypt check, so parallel requests can't all slip
    // through; reset below if the login succeeds.
    auth.loginLimiter.record(limitKey);

    final rows = await db.execute(
      Sql.named(
        'SELECT id, password_hash FROM users '
        'WHERE lower(username) = @username',
      ),
      parameters: {'username': credentials.username},
    );
    final user = rows.isEmpty ? null : rows.first.toColumnMap();

    // For an unknown username, verify runs bcrypt against a dummy hash, so
    // both failure cases take the same time and give the same 401.
    final valid = await auth.passwords.verify(
      credentials.password,
      user?['password_hash'] as String?,
    );
    if (user == null || !valid) {
      return Response.unauthorized('Invalid username or password.');
    }

    auth.loginLimiter.reset(limitKey);
    final (:token, :expiresAt) = auth.tokens.issue(user['id'] as int);
    return Response.ok(
      jsonEncode({'token': token, 'expiresAt': expiresAt.toIso8601String()}),
      headers: {'Content-Type': 'application/json'},
    );
  } catch (e) {
    print('Error in loginHandler: $e');
    return Response.internalServerError(body: 'Failed to log in.');
  }
}

/// Parses and validates a `Credentials` body. The username is trimmed and
/// lowercased before validation, so "  Alice " and "alice" are one account.
({_Credentials? credentials, String? error}) _parseCredentials(String body) {
  final Object? json;
  try {
    json = jsonDecode(body);
  } on FormatException {
    return (credentials: null, error: 'Body must be JSON.');
  }
  if (json is! Map ||
      json['username'] is! String ||
      json['password'] is! String) {
    return (
      credentials: null,
      error: 'Fields "username" and "password" are required.',
    );
  }

  final username = (json['username'] as String).trim().toLowerCase();
  if (!_usernamePattern.hasMatch(username)) {
    return (
      credentials: null,
      error: 'Username must be 3-32 characters: a-z, 0-9, ".", "_" or "-".',
    );
  }

  final password = json['password'] as String;
  final passwordBytes = utf8.encode(password).length;
  if (passwordBytes < _minPasswordBytes || passwordBytes > _maxPasswordBytes) {
    return (
      credentials: null,
      error:
          'Password must be $_minPasswordBytes-$_maxPasswordBytes bytes '
          'long (UTF-8).',
    );
  }

  return (credentials: (username: username, password: password), error: null);
}

/// The TCP peer address. shelf_io puts the connection info into the request
/// context. Behind a reverse proxy this would be the proxy's address; the
/// app has none, so `X-Forwarded-For` is deliberately not trusted.
String _clientIp(Request request) {
  final info = request.context['shelf.io.connection_info'];
  return info is HttpConnectionInfo ? info.remoteAddress.address : 'unknown';
}

Response _tooManyRequests(Duration wait) => Response(
  429,
  body: 'Too many attempts. Try again later.',
  headers: {'Retry-After': '${retryAfterSeconds(wait)}'},
);
