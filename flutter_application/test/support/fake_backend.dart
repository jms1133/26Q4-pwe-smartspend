import 'dart:async';
import 'dart:convert';

import 'package:flutter_application_1/services/token_store.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// In-memory stand-in for the shelf server, plugged into the generated
/// client via `ApiClient.client`. It answers like the real backend (status
/// codes, plain-text errors, `Retry-After`), so the tests run the real
/// [DefaultApi], the bearer header and the error mapping.
class FakeBackend {
  FakeBackend({DateTime Function()? now}) : _now = now ?? DateTime.now;

  final DateTime Function() _now;

  /// username -> password
  final Map<String, String> users = {};
  final Map<String, List<Map<String, dynamic>>> _expenses = {};
  final Map<String, String> _tokens = {};
  int _nextToken = 1;
  int _nextExpenseId = 1;

  /// Every request the client sent, in order.
  final List<http.Request> requests = [];

  /// When set, `/auth/login` answers 429 with this `Retry-After` value.
  String? rateLimitRetryAfter;

  /// When true, `/auth/login` answers 500 (register still works).
  bool failLogin = false;

  /// When true, every request fails before reaching the "server".
  bool unreachable = false;

  /// Lifetime of issued tokens.
  Duration tokenLifetime = const Duration(hours: 1);

  /// When set, `GET /expenses` waits for this before answering.
  Completer<void>? holdListExpenses;

  late final http.Client client = MockClient(_handle);

  /// Invalidates every issued token, like a server restart with a new
  /// `JWT_SECRET`, so the next protected request gets 401.
  void revokeAllTokens() => _tokens.clear();

  void addExpense(String username, String title, double amount) {
    _expenses.putIfAbsent(username, () => []).add({
      'id': _nextExpenseId++,
      'title': title,
      'category': 'food',
      'amount': amount,
      'description': null,
      'subcategory': null,
      'timestamp': DateTime.utc(2026, 11, 1).toIso8601String(),
    });
  }

  Future<http.Response> _handle(http.Request request) async {
    requests.add(request);
    if (unreachable) {
      throw http.ClientException('Connection refused', request.url);
    }
    final path = request.url.path;
    if (path == '/auth/register') return _register(request);
    if (path == '/auth/login') return _login(request);

    final username = _tokens[_bearer(request)];
    if (username == null) {
      return http.Response(
        'Missing or invalid token.',
        401,
        headers: {'www-authenticate': 'Bearer'},
      );
    }
    if (path == '/expenses' && request.method == 'GET') {
      final hold = holdListExpenses;
      if (hold != null) await hold.future;
      return _json(_expenses[username] ?? const []);
    }
    if (path == '/categories' && request.method == 'GET') {
      return _json(const []);
    }
    return http.Response('Not found', 404);
  }

  http.Response _register(http.Request request) {
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    final username = body['username'] as String;
    if (users.containsKey(username)) {
      return http.Response('Username is already taken.', 409);
    }
    users[username] = body['password'] as String;
    return _json({'id': users.length, 'username': username}, status: 201);
  }

  http.Response _login(http.Request request) {
    final retryAfter = rateLimitRetryAfter;
    if (retryAfter != null) {
      return http.Response(
        'Too many attempts. Try again later.',
        429,
        headers: {'retry-after': retryAfter},
      );
    }
    if (failLogin) return http.Response('Internal Server Error', 500);
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    final username = body['username'] as String;
    if (users[username] != body['password']) {
      return http.Response('Invalid username or password.', 401);
    }
    final token = 'token-$username-${_nextToken++}';
    _tokens[token] = username;
    return _json({
      'token': token,
      'expiresAt': _now().add(tokenLifetime).toUtc().toIso8601String(),
    });
  }

  String? _bearer(http.Request request) {
    final header = request.headers['authorization'];
    if (header == null || !header.startsWith('Bearer ')) return null;
    return header.substring('Bearer '.length);
  }

  http.Response _json(Object body, {int status = 200}) => http.Response(
        jsonEncode(body),
        status,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
}

/// [TokenStore] that keeps the session in a field.
class MemoryTokenStore implements TokenStore {
  MemoryTokenStore([this.session]);

  StoredSession? session;
  int clearCalls = 0;

  @override
  Future<StoredSession?> read() async => session;

  @override
  Future<void> write(StoredSession session) async => this.session = session;

  @override
  Future<void> clear() async {
    clearCalls++;
    session = null;
  }
}
