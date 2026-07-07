import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../app/route_names.dart';
import '../../../app/theme/theme_extensions.dart';
import '../../../core/services/auth_service.dart';
import '../../../l10n/l10n_extension.dart';
import 'auth_widgets.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _loading = false;
  bool _obscure = true;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  String _localizedError(FirebaseAuthException e) {
    final l10n = context.l10n;
    return switch (AuthService.codeToKey(e.code)) {
      'authErrorInvalidEmail' => l10n.authErrorInvalidEmail,
      'authErrorWrongPassword' => l10n.authErrorWrongPassword,
      'authErrorUserNotFound' => l10n.authErrorUserNotFound,
      'authErrorNetworkFailed' => l10n.authErrorNetworkFailed,
      _ => l10n.authErrorGeneric,
    };
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _signIn() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _loading = true);
    try {
      await context
          .read<AuthService>()
          .signInWithEmail(_emailCtrl.text, _passwordCtrl.text);
    } on FirebaseAuthException catch (e) {
      _showError(_localizedError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _signInGoogle() async {
    setState(() => _loading = true);
    final auth = context.read<AuthService>();
    final genericError = context.l10n.authErrorGeneric;
    try {
      await auth.signInWithGoogle();
    } on FirebaseAuthException catch (e) {
      _showError(_localizedError(e));
    } catch (e) {
      debugPrint('sign-in error: $e');
      _showError(genericError);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _signInApple() async {
    setState(() => _loading = true);
    final auth = context.read<AuthService>();
    final genericError = context.l10n.authErrorGeneric;
    try {
      await auth.signInWithApple();
    } on FirebaseAuthException catch (e) {
      _showError(_localizedError(e));
    } catch (e) {
      debugPrint('sign-in error: $e');
      _showError(genericError);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final platform = defaultTargetPlatform;
    final showGoogle = platform == TargetPlatform.iOS ||
        platform == TargetPlatform.android ||
        platform == TargetPlatform.macOS;
    final showApple = platform == TargetPlatform.iOS ||
        platform == TargetPlatform.macOS;

    return Scaffold(
      backgroundColor: cs.surface,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.anchor, size: 40, color: cs.primary),
                const SizedBox(height: 20),
                Text(
                  l10n.authLoginTitle,
                  style: Theme.of(context).textTheme.headlineMedium!.copyWith(
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  l10n.authLoginSubtitle,
                  style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                      color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 32),

                AuthField(
                  controller: _emailCtrl,
                  label: l10n.authEmailLabel,
                  hint: l10n.authEmailHint,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return l10n.authErrorInvalidEmail;
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),

                AuthField(
                  controller: _passwordCtrl,
                  label: l10n.authPasswordLabel,
                  hint: l10n.authPasswordHint,
                  obscureText: _obscure,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _signIn(),
                  validator: (v) {
                    if (v == null || v.isEmpty) return l10n.authErrorWrongPassword;
                    return null;
                  },
                  suffixIcon: IconButton(
                    icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility,
                        size: 20, color: cs.onSurfaceVariant),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),

                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => context.pushNamed(AppRoute.forgotPassword),
                    child: Text(l10n.authForgotPasswordLink,
                        style: Theme.of(context).textTheme.bodySmall!.copyWith(
                            color: cs.primary)),
                  ),
                ),

                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: FilledButton(
                    onPressed: _loading ? null : _signIn,
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    child: _loading
                        ? SizedBox(
                            width: 18, height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: cs.onPrimary))
                        : Text(l10n.authSignIn,
                            style: Theme.of(context).textTheme.fieldValueCompact),
                  ),
                ),
                const SizedBox(height: 24),

                if (showGoogle || showApple) ...[
                  AuthOrDivider(label: l10n.authOrDivider),
                  const SizedBox(height: 16),
                ],

                if (showGoogle) ...[
                  AuthSocialButton(
                    onPressed: _loading ? null : _signInGoogle,
                    label: l10n.authSignInWithGoogle,
                    icon: const GoogleLogo(),
                  ),
                  const SizedBox(height: 10),
                ],

                if (showApple) ...[
                  AuthSocialButton(
                    onPressed: _loading ? null : _signInApple,
                    label: l10n.authSignInWithApple,
                    icon: Icon(Icons.apple, size: 20, color: cs.onSurface),
                  ),
                  const SizedBox(height: 10),
                ],

                const SizedBox(height: 22),

                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(l10n.authNoAccount,
                        style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                            color: cs.onSurfaceVariant)),
                    TextButton(
                      onPressed: () => context.pushNamed(AppRoute.register),
                      child: Text(l10n.authRegisterLink,
                          style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                              fontWeight: FontWeight.w600,
                              color: cs.primary)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
