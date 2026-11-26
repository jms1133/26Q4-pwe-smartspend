import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:openapi/api.dart';

import '../services/api_errors.dart';
import '../services/token_store.dart';

const invalidCredentialsMessage = 'Invalid username or password.';
const usernameTakenMessage = 'Username is already taken.';
const sessionExpiredMessage = 'Session expired, please log in again.';
const accountCreatedMessage = 'Account created, please log in.';

enum RegisterResult {
  /// Registered and logged in.
  loggedIn,

  /// Registered, but the automatic login afterwards failed.
  accountCreated,

  failed,
}

/// Holds the login session. Widgets that `watch` it (the AuthGate, the
/// dashboard's AppBar) rebuild only when [notifyListeners] is called, so
/// every state change below ends with it.
class AuthProvider extends ChangeNotifier {
  AuthProvider(this._api, this._store, {DateTime Function()? now})
      : _now = now ?? DateTime.now;

  final DefaultApi _api;
  final TokenStore _store;
  final DateTime Function() _now;

  /// Called synchronously when a session ends (logout, 401) or is replaced,
  /// before listeners are notified. `main.dart` uses it to clear the
  /// expense data, so no screen can show the previous user's data.
  VoidCallback? onSessionEnded;

  String? _token;
  DateTime? _expiresAt;
  String? _username;
  bool _isBusy = false;
  bool _isRestoring = true;
  String? _error;
  String? _notice;

  String? get token => _token;
  DateTime? get expiresAt => _expiresAt;
  String? get username => _username;
  bool get isBusy => _isBusy;

  /// True until [restore] has finished; the gate shows a spinner meanwhile,
  /// so the login screen doesn't flash on a reload with a stored session.
  bool get isRestoring => _isRestoring;

  /// Why the last login or register failed.
  String? get error => _error;

  /// Information for the login screen that is not an error of the last
  /// action ("Session expired", "Account created").
  String? get notice => _notice;

  bool get isAuthenticated {
    final expiresAt = _expiresAt;
    return _token != null && expiresAt != null && expiresAt.isAfter(_now());
  }

  /// Loads a stored session at app start. An expired one is deleted.
  Future<void> restore() async {
    try {
      final stored = await _store.read();
      if (stored != null && stored.expiresAt.isAfter(_now())) {
        _token = stored.token;
        _expiresAt = stored.expiresAt;
        _username = stored.username;
      } else if (stored != null) {
        await _store.clear();
      }
    } catch (e) {
      debugPrint('Could not restore the session: $e');
    } finally {
      _isRestoring = false;
      notifyListeners();
    }
  }

  Future<bool> login(String username, String password) async {
    _startAction();
    final ok = await _login(username, password);
    _isBusy = false;
    notifyListeners();
    return ok;
  }

  /// Registers, then logs in with the same credentials, so the user doesn't
  /// fill in a second form.
  Future<RegisterResult> register(String username, String password) async {
    _startAction();
    var result = RegisterResult.failed;
    try {
      final response = await _api.registerWithHttpInfo(
        Credentials(username: username, password: password),
      );
      if (response.statusCode >= 400) {
        _error = response.statusCode == 409
            ? usernameTakenMessage
            : _commonError(response.statusCode, response.headers,
                response.body, 'Registration failed');
      } else if (await _login(username, password)) {
        result = RegisterResult.loggedIn;
      } else {
        _error = null;
        _notice = accountCreatedMessage;
        result = RegisterResult.accountCreated;
      }
    } catch (e) {
      _error = describeApiError(e, 'Registration failed');
    }
    _isBusy = false;
    notifyListeners();
    return result;
  }

  /// Ends the session. Idempotent: several parallel 401s produce one state
  /// change, one notification and one message. State is cleared before the
  /// first `await`, so a second call already sees no token.
  Future<void> logout({bool sessionExpired = false}) async {
    if (_token == null) return;
    _token = null;
    _expiresAt = null;
    _username = null;
    _error = null;
    _notice = sessionExpired ? sessionExpiredMessage : null;
    onSessionEnded?.call();
    notifyListeners();
    try {
      await _store.clear();
    } catch (e) {
      debugPrint('Could not clear the stored session: $e');
    }
  }

  void _startAction() {
    _isBusy = true;
    _error = null;
    _notice = null;
    notifyListeners();
  }

  /// Shared by [login] and [register]. Sets [_error] on failure and does not
  /// notify; the callers do that once at the end.
  Future<bool> _login(String username, String password) async {
    try {
      final response = await _api.loginWithHttpInfo(
        Credentials(username: username, password: password),
      );
      if (response.statusCode >= 400) {
        // A 401 here means wrong credentials, never an expired session.
        _error = response.statusCode == 401
            ? invalidCredentialsMessage
            : _commonError(response.statusCode, response.headers,
                response.body, 'Login failed');
        return false;
      }
      final token = AuthToken.fromJson(jsonDecode(response.body));
      if (token == null) {
        _error = 'Login failed: unexpected response.';
        return false;
      }
      if (_token != null) onSessionEnded?.call();
      _token = token.token;
      _expiresAt = token.expiresAt;
      _username = username.trim().toLowerCase();
      await _saveSession();
      return true;
    } catch (e) {
      _error = describeApiError(e, 'Login failed');
      return false;
    }
  }

  Future<void> _saveSession() async {
    try {
      await _store.write(StoredSession(
        token: _token!,
        expiresAt: _expiresAt!,
        username: _username!,
      ));
    } catch (e) {
      // The session still works until the next reload.
      debugPrint('Could not store the session: $e');
    }
  }

  String _commonError(
    int status,
    Map<String, String> headers,
    String body,
    String action,
  ) {
    if (status == 429) return tooManyAttemptsMessage(headers['retry-after']);
    if (status == 400 && body.trim().isNotEmpty) return body.trim();
    return '$action (HTTP $status).';
  }
}

/// `Retry-After` is in seconds; shown rounded up to whole minutes.
String tooManyAttemptsMessage(String? retryAfter) {
  final seconds = int.tryParse(retryAfter?.trim() ?? '');
  if (seconds == null || seconds <= 0) {
    return 'Too many attempts. Try again later.';
  }
  final minutes = (seconds / 60).ceil();
  return 'Too many attempts. Try again in $minutes min.';
}
