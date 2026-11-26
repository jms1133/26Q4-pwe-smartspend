import 'dart:async';

import 'package:flutter_application_1/app_services.dart';
import 'package:flutter_application_1/providers/auth_provider.dart';
import 'package:flutter_application_1/services/api_errors.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_backend.dart';

void main() {
  // onSessionEnded reads navigatorKey.currentState, which needs the
  // widgets binding (runApp creates it in the app).
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeBackend backend;
  late AppServices services;

  setUp(() {
    backend = FakeBackend()
      ..users['alice'] = 'alice-password'
      ..users['bob'] = 'bob-password'
      ..addExpense('alice', 'Alice coffee', 3.5)
      ..addExpense('bob', 'Bob lunch', 12);
    services = AppServices.create(
      basePath: 'http://test',
      store: MemoryTokenStore(),
    );
    services.apiClient.client = backend.client;
  });

  test('a 401 calls onUnauthorized: session ends with the expired notice',
      () async {
    await services.auth.login('alice', 'alice-password');
    backend.revokeAllTokens();

    await services.expenses.loadExpenses();

    expect(services.auth.isAuthenticated, isFalse);
    expect(services.auth.notice, sessionExpiredMessage);
    expect(services.expenses.error, isNull);
    expect(services.expenses.expenses, isEmpty);
  });

  test('clear() empties lists and error and notifies', () async {
    await services.auth.login('alice', 'alice-password');
    await services.expenses.loadExpenses();
    expect(services.expenses.expenses, hasLength(1));
    var notified = 0;
    services.expenses.addListener(() => notified++);

    services.expenses.clear();

    expect(services.expenses.expenses, isEmpty);
    expect(services.expenses.categories, isEmpty);
    expect(services.expenses.error, isNull);
    expect(services.expenses.isLoading, isFalse);
    expect(notified, 1);
  });

  test("a response started as alice is dropped after bob logs in", () async {
    await services.auth.login('alice', 'alice-password');
    backend.holdListExpenses = Completer<void>();
    final aliceLoad = services.expenses.loadExpenses();
    await pumpEventQueue();

    await services.auth.logout();
    await services.auth.login('bob', 'bob-password');
    backend.holdListExpenses!.complete();
    await aliceLoad;

    expect(services.expenses.expenses, isEmpty);

    backend.holdListExpenses = null;
    await services.expenses.loadExpenses();
    expect(
      services.expenses.expenses.map((e) => e.title),
      ['Bob lunch'],
    );
  });

  test('network error shows "Server not reachable" and keeps the session',
      () async {
    await services.auth.login('alice', 'alice-password');
    backend.unreachable = true;

    await services.expenses.loadExpenses();

    expect(
      services.expenses.error,
      serverNotReachableMessage,
    );
    expect(services.auth.isAuthenticated, isTrue);
  });
}
