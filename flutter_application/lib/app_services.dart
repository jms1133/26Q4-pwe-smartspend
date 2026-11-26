import 'package:flutter/widgets.dart';
import 'package:openapi/api.dart';

import 'providers/auth_provider.dart';
import 'providers/expense_provider.dart';
import 'services/api_client_factory.dart';
import 'services/token_store.dart';

/// The objects the app shares, wired together once. `main()` uses it with
/// the real server and `localStorage`; widget tests use it with a fake API
/// and an in-memory store, so both run the same wiring.
class AppServices {
  AppServices._(this.apiClient, this.auth, this.expenses, this.navigatorKey);

  /// Tests replace `apiClient.client` with a fake HTTP client, so the real
  /// [DefaultApi] and bearer header are exercised. [now] lets tests control
  /// token expiry.
  factory AppServices.create({
    required String basePath,
    required TokenStore store,
    DateTime Function()? now,
  }) {
    // The ApiClient needs the AuthProvider's token and the AuthProvider needs
    // the API for login, so the getter closes over a variable that is
    // assigned right after. It is only called when a request is sent.
    late final AuthProvider auth;
    final apiClient = createApiClient(
      basePath: basePath,
      token: () => auth.token,
    );
    final defaultApi = DefaultApi(apiClient);
    auth = AuthProvider(defaultApi, store, now: now);
    final expenses = ExpenseProvider(
      defaultApi,
      onUnauthorized: () => auth.logout(sessionExpired: true),
    );
    final navigatorKey = GlobalKey<NavigatorState>();
    auth.onSessionEnded = () {
      expenses.clear();
      // The gate swaps only the bottom route; a form or the analytics screen
      // pushed on top would otherwise stay visible after logout.
      navigatorKey.currentState?.popUntil((route) => route.isFirst);
    };
    return AppServices._(apiClient, auth, expenses, navigatorKey);
  }

  final ApiClient apiClient;
  final AuthProvider auth;
  final ExpenseProvider expenses;
  final GlobalKey<NavigatorState> navigatorKey;
}
