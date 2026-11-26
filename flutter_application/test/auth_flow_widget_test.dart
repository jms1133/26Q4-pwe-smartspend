import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_application_1/app_services.dart';
import 'package:flutter_application_1/main.dart';
import 'package:flutter_application_1/providers/auth_provider.dart';
import 'package:flutter_application_1/services/token_store.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_backend.dart';

/// Store whose [read] waits for [gate], to observe the app before restore()
/// has finished.
class _SlowStore extends MemoryTokenStore {
  final gate = Completer<void>();

  @override
  Future<StoredSession?> read() async {
    await gate.future;
    return super.read();
  }
}

void main() {
  late FakeBackend backend;

  setUp(() {
    backend = FakeBackend()..users['alice'] = 'correct-horse';
    backend.addExpense('alice', 'Cinema tickets', 15);
  });

  /// Same wiring as `main()`, with the fake backend plugged in.
  Future<AppServices> startApp(
    WidgetTester tester, {
    TokenStore? store,
    bool settle = true,
  }) async {
    final services = AppServices.create(
      basePath: 'http://test',
      store: store ?? MemoryTokenStore(),
    );
    services.apiClient.client = backend.client;
    unawaited(services.auth.restore());
    await tester.pumpWidget(SmartSpendApp(services: services));
    if (settle) await tester.pumpAndSettle();
    return services;
  }

  Future<void> logIn(WidgetTester tester, String user, String password) async {
    await tester.enterText(find.byKey(const Key('username-field')), user);
    await tester.enterText(find.byKey(const Key('password-field')), password);
    await tester.tap(find.byKey(const Key('submit-button')));
    await tester.pumpAndSettle();
  }

  testWidgets('gate shows a spinner, not the login form, while restoring',
      (tester) async {
    final store = _SlowStore();
    await startApp(tester, store: store, settle: false);
    await tester.pump();

    expect(find.byKey(const Key('auth-restoring')), findsOneWidget);
    expect(find.byKey(const Key('username-field')), findsNothing);

    store.gate.complete();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('auth-restoring')), findsNothing);
    expect(find.byKey(const Key('username-field')), findsOneWidget);
  });

  testWidgets('logged out: login screen is shown', (tester) async {
    await startApp(tester);

    expect(find.text('Log in'), findsWidgets);
    expect(find.byKey(const Key('logout-button')), findsNothing);
  });

  testWidgets('restored session: dashboard with username and expenses',
      (tester) async {
    backend.users['alice'] = 'correct-horse';
    // Log in once outside the UI so the fake backend knows the token.
    final seed = AppServices.create(
      basePath: 'http://test',
      store: MemoryTokenStore(),
    );
    seed.apiClient.client = backend.client;
    await tester.runAsync(() => seed.auth.login('alice', 'correct-horse'));
    final store = MemoryTokenStore(StoredSession(
      token: seed.auth.token!,
      expiresAt: seed.auth.expiresAt!,
      username: 'alice',
    ));

    await startApp(tester, store: store);

    expect(find.byKey(const Key('appbar-username')), findsOneWidget);
    expect(find.text('alice'), findsOneWidget);
    expect(find.text('Cinema tickets'), findsOneWidget);
  });

  testWidgets('form validation blocks bad input without a request',
      (tester) async {
    await startApp(tester);

    await tester.enterText(find.byKey(const Key('username-field')), 'a!');
    await tester.enterText(find.byKey(const Key('password-field')), 'short');
    await tester.tap(find.byKey(const Key('submit-button')));
    await tester.pumpAndSettle();

    expect(find.text('3–32 characters: a–z, 0–9, ".", "_" or "-"'),
        findsOneWidget);
    expect(find.text('At least 8 characters'), findsOneWidget);
    expect(backend.requests, isEmpty);
  });

  testWidgets('register mode: mismatching confirmation is rejected',
      (tester) async {
    await startApp(tester);

    await tester.tap(find.byKey(const Key('mode-toggle')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('username-field')), 'bob');
    await tester.enterText(
        find.byKey(const Key('password-field')), 'battery-staple');
    await tester.enterText(
        find.byKey(const Key('confirm-field')), 'battery-stapel');
    await tester.tap(find.byKey(const Key('submit-button')));
    await tester.pumpAndSettle();

    expect(find.text('Passwords do not match'), findsOneWidget);
    expect(backend.requests, isEmpty);
  });

  testWidgets('wrong password shows the error banner', (tester) async {
    await startApp(tester);

    await logIn(tester, 'alice', 'wrong-password');

    expect(find.byKey(const Key('auth-error')), findsOneWidget);
    expect(find.text(invalidCredentialsMessage), findsOneWidget);
    expect(find.byKey(const Key('logout-button')), findsNothing);
  });

  testWidgets('successful login switches to the dashboard and loads data',
      (tester) async {
    await startApp(tester);

    await logIn(tester, '  Alice ', 'correct-horse');

    expect(find.byKey(const Key('logout-button')), findsOneWidget);
    expect(find.text('alice'), findsOneWidget);
    expect(find.text('Cinema tickets'), findsOneWidget);
  });

  testWidgets('logout returns to the login screen without a notice',
      (tester) async {
    await startApp(tester);
    await logIn(tester, 'alice', 'correct-horse');

    await tester.tap(find.byKey(const Key('logout-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('username-field')), findsOneWidget);
    expect(find.byKey(const Key('auth-notice')), findsNothing);
  });

  testWidgets('401 on a pushed screen returns to login with expired notice',
      (tester) async {
    final services = await startApp(tester);
    await logIn(tester, 'alice', 'correct-horse');
    await tester.tap(find.byTooltip('Analytics'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Analytics'), findsNothing);

    backend.revokeAllTokens();
    unawaited(services.expenses.loadExpenses());
    await tester.pumpAndSettle();

    expect(services.auth.isAuthenticated, isFalse);
    expect(find.byKey(const Key('username-field')), findsOneWidget);
    expect(find.byKey(const Key('auth-notice')), findsOneWidget);
    expect(find.text(sessionExpiredMessage), findsOneWidget);
    expect(find.text('Cinema tickets'), findsNothing);
  });
}
