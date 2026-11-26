import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import 'login_screen.dart';

/// Decides what `MaterialApp.home` shows. `context.watch` subscribes to the
/// [AuthProvider], so this widget rebuilds on every `notifyListeners()`:
/// after `restore()`, login and logout. [signedIn] builds the screen for a
/// logged-in user; it is a parameter so this file doesn't import the
/// dashboard (which lives in `main.dart`).
class AuthGate extends StatelessWidget {
  const AuthGate({super.key, required this.signedIn});

  final WidgetBuilder signedIn;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    if (auth.isRestoring) {
      return const Scaffold(
        key: Key('auth-restoring'),
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (!auth.isAuthenticated) return const LoginScreen();
    // Keyed by user, so a different user gets a fresh dashboard State
    // (and with it a fresh initState load).
    return KeyedSubtree(
      key: ValueKey('session-${auth.username}'),
      child: Builder(builder: signedIn),
    );
  }
}
