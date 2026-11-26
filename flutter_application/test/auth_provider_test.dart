import 'package:flutter_application_1/app_services.dart';
import 'package:flutter_application_1/providers/auth_provider.dart';
import 'package:flutter_application_1/services/api_errors.dart';
import 'package:flutter_application_1/services/token_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'support/fake_backend.dart';

void main() {
  // onSessionEnded reads navigatorKey.currentState, which needs the
  // widgets binding (runApp creates it in the app).
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime.utc(2026, 11, 26, 12);

  late FakeBackend backend;
  late MemoryTokenStore store;
  late AppServices services;
  late AuthProvider auth;

  AppServices build({StoredSession? stored}) {
    store = MemoryTokenStore(stored);
    final s = AppServices.create(
      basePath: 'http://test',
      store: store,
      now: () => now,
    );
    s.apiClient.client = backend.client;
    return s;
  }

  setUp(() {
    backend = FakeBackend(now: () => now);
    backend.users['alice'] = 'correct-horse';
    services = build();
    auth = services.auth;
  });

  group('login', () {
    test('success stores token, expiry and username', () async {
      final ok = await auth.login('alice', 'correct-horse');

      expect(ok, isTrue);
      expect(auth.isAuthenticated, isTrue);
      expect(auth.username, 'alice');
      expect(auth.error, isNull);
      expect(store.session?.token, auth.token);
      expect(store.session?.expiresAt, now.add(const Duration(hours: 1)));
      expect(store.session?.username, 'alice');
    });

    test('wrong password shows invalid credentials, not session expired',
        () async {
      final ok = await auth.login('alice', 'wrong-password');

      expect(ok, isFalse);
      expect(auth.isAuthenticated, isFalse);
      expect(auth.error, invalidCredentialsMessage);
      expect(auth.notice, isNull);
      expect(store.session, isNull);
    });

    test('429 shows the Retry-After wait rounded up to minutes', () async {
      backend.rateLimitRetryAfter = '61';

      await auth.login('alice', 'correct-horse');

      expect(auth.error, 'Too many attempts. Try again in 2 min.');
    });

    test('network error shows "Server not reachable"', () async {
      backend.unreachable = true;

      final ok = await auth.login('alice', 'correct-horse');

      expect(ok, isFalse);
      expect(auth.error, serverNotReachableMessage);
    });

    test('isBusy is true while the request runs and notifies twice', () async {
      final busyStates = <bool>[];
      auth.addListener(() => busyStates.add(auth.isBusy));

      await auth.login('alice', 'correct-horse');

      expect(busyStates, [true, false]);
    });
  });

  group('register', () {
    test('creates the account and logs in', () async {
      final result = await auth.register('bob', 'battery-staple');

      expect(result, RegisterResult.loggedIn);
      expect(backend.users['bob'], 'battery-staple');
      expect(auth.isAuthenticated, isTrue);
      expect(auth.username, 'bob');
    });

    test('taken username shows the 409 message', () async {
      final result = await auth.register('alice', 'whatever-123');

      expect(result, RegisterResult.failed);
      expect(auth.error, usernameTakenMessage);
      expect(auth.isAuthenticated, isFalse);
    });

    test('created but login fails: notice "Account created", no error',
        () async {
      backend.failLogin = true;

      final result = await auth.register('bob', 'battery-staple');

      expect(result, RegisterResult.accountCreated);
      expect(backend.users, contains('bob'));
      expect(auth.isAuthenticated, isFalse);
      expect(auth.error, isNull);
      expect(auth.notice, accountCreatedMessage);
    });
  });

  group('logout', () {
    test('clears state, store and the expense data', () async {
      backend.addExpense('alice', 'Coffee', 3.5);
      await auth.login('alice', 'correct-horse');
      await services.expenses.loadExpenses();
      expect(services.expenses.expenses, hasLength(1));

      await auth.logout();

      expect(services.expenses.expenses, isEmpty);
      expect(auth.isAuthenticated, isFalse);
      expect(auth.token, isNull);
      expect(auth.username, isNull);
      expect(auth.notice, isNull);
      expect(store.session, isNull);
    });

    test('parallel calls (several 401s) notify once and set one message',
        () async {
      await auth.login('alice', 'correct-horse');
      var notified = 0;
      auth.addListener(() => notified++);

      await Future.wait([
        auth.logout(sessionExpired: true),
        auth.logout(sessionExpired: true),
        auth.logout(sessionExpired: true),
      ]);

      expect(notified, 1);
      expect(store.clearCalls, 1);
      expect(auth.notice, sessionExpiredMessage);
    });
  });

  group('restore', () {
    test('loads a valid stored session', () async {
      services = build(
        stored: StoredSession(
          token: 'stored-token',
          expiresAt: now.add(const Duration(minutes: 30)),
          username: 'alice',
        ),
      );
      auth = services.auth;
      expect(auth.isRestoring, isTrue);

      await auth.restore();

      expect(auth.isRestoring, isFalse);
      expect(auth.isAuthenticated, isTrue);
      expect(auth.token, 'stored-token');
      expect(auth.username, 'alice');
    });

    test('drops an expired stored session', () async {
      services = build(
        stored: StoredSession(
          token: 'old-token',
          expiresAt: now.subtract(const Duration(minutes: 1)),
          username: 'alice',
        ),
      );
      auth = services.auth;

      await auth.restore();

      expect(auth.isRestoring, isFalse);
      expect(auth.isAuthenticated, isFalse);
      expect(store.session, isNull);
    });
  });

  group('bearer header', () {
    test('sent with the current token, omitted when logged out', () async {
      await services.expenses.loadExpenses();
      expect(backend.requests.last.headers['authorization'], isNull);

      await auth.login('alice', 'correct-horse');
      await services.expenses.loadExpenses();
      expect(
        backend.requests.last.headers['authorization'],
        'Bearer ${auth.token}',
      );
    });

    test('the session is no longer valid once expiresAt has passed', () async {
      var clock = now;
      final s = AppServices.create(
        basePath: 'http://test',
        store: MemoryTokenStore(),
        now: () => clock,
      );
      s.apiClient.client = backend.client;
      await s.auth.login('alice', 'correct-horse');
      expect(s.auth.isAuthenticated, isTrue);

      clock = now.add(const Duration(hours: 1, seconds: 1));

      expect(s.auth.isAuthenticated, isFalse);
    });
  });

  group('tooManyAttemptsMessage', () {
    test('falls back without a usable Retry-After', () {
      expect(tooManyAttemptsMessage(null), 'Too many attempts. Try again later.');
      expect(tooManyAttemptsMessage('soon'),
          'Too many attempts. Try again later.');
      expect(tooManyAttemptsMessage('900'),
          'Too many attempts. Try again in 15 min.');
    });
  });

  group('SharedPreferencesTokenStore', () {
    setUp(() {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
    });

    test('write, read and clear round-trip', () async {
      final prefsStore = SharedPreferencesTokenStore();
      final session = StoredSession(
        token: 'abc',
        expiresAt: DateTime.utc(2026, 11, 26, 13),
        username: 'alice',
      );

      await prefsStore.write(session);
      final read = await prefsStore.read();
      expect(read?.token, 'abc');
      expect(read?.expiresAt, session.expiresAt);
      expect(read?.username, 'alice');

      await prefsStore.clear();
      expect(await prefsStore.read(), isNull);
    });

    test('read returns null for an unparseable expiry', () async {
      final prefs = SharedPreferencesAsync();
      await prefs.setString(SharedPreferencesTokenStore.tokenKey, 'abc');
      await prefs.setString(SharedPreferencesTokenStore.expiresAtKey, 'x');
      await prefs.setString(SharedPreferencesTokenStore.usernameKey, 'alice');

      expect(await SharedPreferencesTokenStore(prefs).read(), isNull);
    });
  });
}
