import 'dart:isolate';

import 'package:bcrypt/bcrypt.dart';

/// Signature of the function that compares a password with a bcrypt hash.
/// Injectable so tests can observe which hash a login was checked against.
typedef PasswordCheck = Future<bool> Function(String password, String hash);

/// Hashes and verifies passwords with bcrypt.
///
/// The `bcrypt` package is synchronous and CPU-bound: one hash at cost 12
/// keeps the CPU busy for a few hundred milliseconds. shelf handles every
/// request on the server's single isolate, and `await` only frees that
/// isolate while waiting for I/O, not during a computation. Hashing inline
/// would therefore freeze all other requests for that time. `Isolate.run`
/// executes the computation on a separate isolate (own thread, own memory)
/// and returns a Future, so the main isolate keeps serving requests.
class PasswordHasher {
  final int cost;

  /// Hash of a fixed throwaway password with the same [cost]. A login for an
  /// unknown username is checked against it, so it takes as long as a login
  /// with a wrong password and the response time doesn't reveal which
  /// usernames exist.
  final String dummyHash;

  final PasswordCheck _check;

  PasswordHasher._(this.cost, this.dummyHash, this._check);

  /// Computes [dummyHash] once; call at startup.
  static Future<PasswordHasher> create(
    int cost, {
    PasswordCheck check = checkPasswordInIsolate,
  }) async {
    final dummyHash = await hashPasswordInIsolate(
      'dummy password for unknown usernames',
      cost,
    );
    return PasswordHasher._(cost, dummyHash, check);
  }

  Future<String> hash(String password) => hashPasswordInIsolate(password, cost);

  /// Returns true only if [storedHash] is not null and matches [password].
  /// With no stored hash (unknown username) it still does the full bcrypt
  /// work against [dummyHash] and then returns false.
  Future<bool> verify(String password, String? storedHash) async {
    final matches = await _check(password, storedHash ?? dummyHash);
    return storedHash != null && matches;
  }
}

// Top-level functions on purpose: the closure passed to Isolate.run is
// copied to the new isolate, so it must only capture plain values (two
// strings, an int), never an object holding sockets such as the DB pool.

Future<String> hashPasswordInIsolate(String password, int cost) =>
    Isolate.run(() => BCrypt.hashpw(password, BCrypt.gensalt(logRounds: cost)));

Future<bool> checkPasswordInIsolate(String password, String hash) =>
    Isolate.run(() => BCrypt.checkpw(password, hash));
