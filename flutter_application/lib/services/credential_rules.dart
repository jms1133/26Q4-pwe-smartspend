import 'dart:convert';

/// Client-side copies of the server's credential rules, for early feedback
/// only. The server validates again and is the authority.

final _usernamePattern = RegExp(r'^[a-z0-9._-]{3,32}$');

/// The server stores usernames trimmed and lowercased.
String normalizeUsername(String input) => input.trim().toLowerCase();

String? validateUsername(String? input) {
  final username = normalizeUsername(input ?? '');
  if (username.isEmpty) return 'Username is required';
  if (!_usernamePattern.hasMatch(username)) {
    return '3–32 characters: a–z, 0–9, ".", "_" or "-"';
  }
  return null;
}

/// bcrypt ignores everything after 72 bytes, so the limit is in UTF-8 bytes,
/// not characters ("ü" counts as 2).
String? validatePassword(String? input) {
  final password = input ?? '';
  if (password.isEmpty) return 'Password is required';
  final bytes = utf8.encode(password).length;
  if (bytes < 8) return 'At least 8 characters';
  if (bytes > 72) return 'At most 72 bytes';
  return null;
}
