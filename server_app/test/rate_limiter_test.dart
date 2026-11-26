import 'package:server_app/auth/rate_limiter.dart';
import 'package:test/test.dart';

void main() {
  var now = DateTime.utc(2026, 11, 26, 12);
  late RateLimiter limiter;

  setUp(() {
    now = DateTime.utc(2026, 11, 26, 12);
    limiter = RateLimiter(
      maxAttempts: 3,
      window: const Duration(minutes: 15),
      now: () => now,
    );
  });

  void attempt(String key, {int times = 1}) {
    for (var i = 0; i < times; i++) {
      limiter.record(key);
    }
  }

  test(
    'allows maxAttempts, then reports the wait until the oldest expires',
    () {
      attempt('k');
      now = now.add(const Duration(minutes: 5));
      attempt('k', times: 2);

      expect(limiter.retryAfter('k'), const Duration(minutes: 10));
    },
  );

  test('allows again once the oldest attempt leaves the window', () {
    attempt('k', times: 3);
    now = now.add(const Duration(minutes: 15));
    expect(limiter.retryAfter('k'), isNull);
  });

  test('keys are independent', () {
    attempt('a', times: 3);
    expect(limiter.retryAfter('a'), isNotNull);
    expect(limiter.retryAfter('b'), isNull);
  });

  test('reset forgets a key', () {
    attempt('k', times: 3);
    limiter.reset('k');
    expect(limiter.retryAfter('k'), isNull);
  });

  test('prunes expired entries of all keys on every check', () {
    for (var i = 0; i < 100; i++) {
      attempt('ip$i');
    }
    expect(limiter.trackedKeys, 100);

    now = now.add(const Duration(minutes: 16));
    limiter.retryAfter('someone else');
    expect(limiter.trackedKeys, 0);
  });

  test('retryAfterSeconds rounds up to whole seconds, minimum 1', () {
    expect(retryAfterSeconds(const Duration(milliseconds: 1)), 1);
    expect(retryAfterSeconds(Duration.zero), 1);
    expect(retryAfterSeconds(const Duration(seconds: 59, milliseconds: 1)), 60);
    expect(retryAfterSeconds(const Duration(minutes: 15)), 900);
  });
}
