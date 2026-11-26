import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:postgres/postgres.dart';
import 'package:server_app/auth/auth_services.dart';
import 'package:server_app/auth/password_hasher.dart';
import 'package:server_app/auth/rate_limiter.dart';
import 'package:server_app/auth/token_service.dart';
import 'package:server_app/db/database.dart';
import 'package:server_app/server.dart';
import 'package:server_app/services/ai_service.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

import 'test_database.dart';

/// Test-only signing key. Not a secret: it only ever signs tokens for
/// throwaway test databases.
const testJwtSecret = 'test-only-jwt-secret-not-used-anywhere-else';

/// bcrypt's minimum cost: about 1 ms per hash instead of a few hundred.
const testBcryptCost = 4;

const testPassword = 'correct horse battery';

/// Auth services with test settings. Pass small limits or a fake clock to
/// test rate limiting and expiry.
Future<AuthServices> testAuthServices({
  DateTime Function()? now,
  PasswordCheck check = checkPasswordInIsolate,
  int? loginMaxFailures,
  int? registerMaxAttempts,
}) async {
  return AuthServices(
    tokens: TokenService(testJwtSecret, now: now),
    passwords: await PasswordHasher.create(testBcryptCost, check: check),
    now: now,
    loginLimiter: loginMaxFailures == null
        ? null
        : RateLimiter(
            maxAttempts: loginMaxFailures,
            window: AuthServices.loginWindow,
            now: now,
          ),
    registerLimiter: registerMaxAttempts == null
        ? null
        : RateLimiter(
            maxAttempts: registerMaxAttempts,
            window: AuthServices.registerWindow,
            now: now,
          ),
  );
}

/// The full request pipeline (logging, CORS, auth, router) served inside the
/// test process on a fresh database, as in Step 6.
class TestServer {
  final _databases = TestDatabases();
  late final String database;
  late final Pool pool;
  late final HttpServer _server;
  late final AuthServices auth;

  String get host => 'http://127.0.0.1:${_server.port}';

  Future<void> start({AuthServices? auth}) async {
    database = await _databases.create();
    pool = await openExpenseDatabase(
      _databases.baseConfig.withDatabase(database),
    );
    this.auth = auth ?? await testAuthServices();

    // The secrets path doesn't exist, so the AI service has no key unless
    // OPENAI_API_KEY is set in the environment (it isn't locally or in CI).
    // No test calls /classify or /chat.
    final aiService = AiService(secretsPath: 'test/no-secrets.json');
    _server = await shelf_io.serve(
      buildHandler(pool, aiService, this.auth),
      InternetAddress.loopbackIPv4,
      0,
    );
  }

  /// Stop accepting requests, release the pool's connections, then drop the
  /// database they pointed at.
  Future<void> stop() async {
    await _server.close(force: true);
    await pool.close();
    await _databases.drop(database);
  }

  Future<http.Response> register(
    String username, [
    String password = testPassword,
  ]) => client().postJson('/auth/register', {
    'username': username,
    'password': password,
  });

  Future<http.Response> login(
    String username, [
    String password = testPassword,
  ]) => client().postJson('/auth/login', {
    'username': username,
    'password': password,
  });

  /// Registers [username] and returns a client that sends their token.
  Future<ApiClient> signUp(String username) async {
    final registered = await register(username);
    if (registered.statusCode != 201) {
      throw StateError('register $username: ${registered.statusCode}');
    }
    final loggedIn = await login(username);
    final token = jsonDecode(loggedIn.body)['token'] as String;
    return client(token);
  }

  ApiClient client([String? token]) => ApiClient(host, token);
}

/// Thin wrapper around `package:http` that sends JSON and, if set, the
/// bearer token on every request.
class ApiClient {
  final String host;
  final String? token;

  ApiClient(this.host, this.token);

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    if (token != null) 'Authorization': 'Bearer $token',
  };

  Uri _uri(String path) => Uri.parse('$host$path');

  Future<http.Response> get(String path) =>
      http.get(_uri(path), headers: _headers);

  Future<http.Response> postJson(String path, Object body) =>
      http.post(_uri(path), headers: _headers, body: jsonEncode(body));

  Future<http.Response> putJson(String path, Object body) =>
      http.put(_uri(path), headers: _headers, body: jsonEncode(body));

  Future<http.Response> delete(String path) =>
      http.delete(_uri(path), headers: _headers);
}
