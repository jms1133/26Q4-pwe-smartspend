/// In-memory sliding-window rate limiter: at most [maxAttempts] attempts
/// per key within [window].
///
/// Callers check with [retryAfter] and, if allowed, [record] the attempt
/// *before* doing the slow work (bcrypt). Recording only after the work
/// would let a burst of parallel requests all pass the check before the
/// first one is counted.
///
/// State lives in this process only: it resets on restart and isn't shared
/// between server instances. Enough for one server; several instances would
/// need a shared store such as PostgreSQL or Redis.
class RateLimiter {
  final int maxAttempts;
  final Duration window;
  final DateTime Function() _now;

  /// Attempt times per key, oldest first.
  final _attempts = <String, List<DateTime>>{};

  RateLimiter({
    required this.maxAttempts,
    required this.window,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  /// Null if another attempt for [key] is allowed now, otherwise the time
  /// until the oldest counted attempt leaves the window.
  ///
  /// Also prunes expired attempts of all keys, so keys that stop sending
  /// requests don't stay in memory forever.
  Duration? retryAfter(String key) {
    final now = _now();
    _prune(now);

    final attempts = _attempts[key];
    if (attempts == null || attempts.length < maxAttempts) return null;
    final oldestCounted = attempts[attempts.length - maxAttempts];
    return oldestCounted.add(window).difference(now);
  }

  void record(String key) => (_attempts[key] ??= []).add(_now());

  /// Forgets all attempts for [key], e.g. after a successful login.
  void reset(String key) => _attempts.remove(key);

  /// Number of keys currently held in memory.
  int get trackedKeys => _attempts.length;

  void _prune(DateTime now) {
    final cutoff = now.subtract(window);
    _attempts.removeWhere((_, attempts) {
      attempts.removeWhere((time) => !time.isAfter(cutoff));
      return attempts.isEmpty;
    });
  }
}

/// Value for the `Retry-After` header: whole seconds, rounded up, at least 1.
int retryAfterSeconds(Duration wait) {
  final seconds = (wait.inMilliseconds / 1000).ceil();
  return seconds < 1 ? 1 : seconds;
}
