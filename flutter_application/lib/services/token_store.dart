import 'package:shared_preferences/shared_preferences.dart';

/// A login session as persisted on the device.
class StoredSession {
  const StoredSession({
    required this.token,
    required this.expiresAt,
    required this.username,
  });

  final String token;
  final DateTime expiresAt;
  final String username;
}

/// Where the session survives a page reload. An interface so tests can use
/// an in-memory version and Android can later use `flutter_secure_storage`.
abstract interface class TokenStore {
  Future<StoredSession?> read();
  Future<void> write(StoredSession session);
  Future<void> clear();
}

/// [TokenStore] backed by `shared_preferences`, which is the browser's
/// `localStorage` on web. Any script running on the page can read it, so a
/// cross-site-scripting bug would expose the token; the server limits that
/// risk by issuing tokens that expire after one hour.
class SharedPreferencesTokenStore implements TokenStore {
  SharedPreferencesTokenStore([SharedPreferencesAsync? prefs])
      : _prefs = prefs ?? SharedPreferencesAsync();

  final SharedPreferencesAsync _prefs;

  static const tokenKey = 'auth.token';
  static const expiresAtKey = 'auth.expiresAt';
  static const usernameKey = 'auth.username';

  @override
  Future<StoredSession?> read() async {
    final token = await _prefs.getString(tokenKey);
    final expiresAt = await _prefs.getString(expiresAtKey);
    final username = await _prefs.getString(usernameKey);
    final parsedExpiry = expiresAt == null ? null : DateTime.tryParse(expiresAt);
    if (token == null ||
        token.isEmpty ||
        parsedExpiry == null ||
        username == null) {
      return null;
    }
    return StoredSession(
      token: token,
      expiresAt: parsedExpiry,
      username: username,
    );
  }

  @override
  Future<void> write(StoredSession session) async {
    await _prefs.setString(tokenKey, session.token);
    await _prefs.setString(
      expiresAtKey,
      session.expiresAt.toUtc().toIso8601String(),
    );
    await _prefs.setString(usernameKey, session.username);
  }

  @override
  Future<void> clear() async {
    await _prefs.remove(tokenKey);
    await _prefs.remove(expiresAtKey);
    await _prefs.remove(usernameKey);
  }
}
