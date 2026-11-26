import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../services/credential_rules.dart';

/// Login and registration in one form; the toggle switches the mode.
/// After a successful login the AuthGate replaces this screen with the
/// dashboard, so nothing here navigates.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _registerMode = false;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final auth = context.read<AuthProvider>();
    final username = normalizeUsername(_usernameController.text);
    final password = _passwordController.text;

    if (!_registerMode) {
      await auth.login(username, password);
      return;
    }
    final result = await auth.register(username, password);
    if (!mounted) return;
    if (result == RegisterResult.accountCreated) {
      setState(() {
        _registerMode = false;
        _confirmController.clear();
      });
    }
  }

  void _toggleMode() {
    setState(() {
      _registerMode = !_registerMode;
      _confirmController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Smart Spend')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Form(
              key: _formKey,
              child: AutofillGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      _registerMode ? 'Create account' : 'Log in',
                      style: theme.textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 16),
                    if (auth.notice != null)
                      _Banner(
                        key: const Key('auth-notice'),
                        text: auth.notice!,
                        color: theme.colorScheme.secondaryContainer,
                      ),
                    if (auth.error != null)
                      _Banner(
                        key: const Key('auth-error'),
                        text: auth.error!,
                        color: theme.colorScheme.errorContainer,
                      ),
                    TextFormField(
                      key: const Key('username-field'),
                      controller: _usernameController,
                      decoration: const InputDecoration(
                        labelText: 'Username',
                        border: OutlineInputBorder(),
                      ),
                      autofillHints: const [AutofillHints.username],
                      textInputAction: TextInputAction.next,
                      validator: validateUsername,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      key: const Key('password-field'),
                      controller: _passwordController,
                      decoration: const InputDecoration(
                        labelText: 'Password',
                        border: OutlineInputBorder(),
                      ),
                      obscureText: true,
                      autofillHints: [
                        _registerMode
                            ? AutofillHints.newPassword
                            : AutofillHints.password,
                      ],
                      textInputAction: _registerMode
                          ? TextInputAction.next
                          : TextInputAction.done,
                      onFieldSubmitted: (_) =>
                          _registerMode || auth.isBusy ? null : _submit(),
                      validator: validatePassword,
                    ),
                    if (_registerMode) ...[
                      const SizedBox(height: 16),
                      TextFormField(
                        key: const Key('confirm-field'),
                        controller: _confirmController,
                        decoration: const InputDecoration(
                          labelText: 'Confirm password',
                          border: OutlineInputBorder(),
                        ),
                        obscureText: true,
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => auth.isBusy ? null : _submit(),
                        validator: (value) => value == _passwordController.text
                            ? null
                            : 'Passwords do not match',
                      ),
                    ],
                    const SizedBox(height: 24),
                    FilledButton(
                      key: const Key('submit-button'),
                      onPressed: auth.isBusy ? null : _submit,
                      child: auth.isBusy
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(_registerMode ? 'Create account' : 'Log in'),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      key: const Key('mode-toggle'),
                      onPressed: auth.isBusy ? null : _toggleMode,
                      child: Text(
                        _registerMode
                            ? 'Already have an account? Log in'
                            : 'No account yet? Create one',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({super.key, required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text),
    );
  }
}
