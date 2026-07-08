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

/// Email/password account-creation screen, with optional Google sign-in as
/// a shortcut. Reachable from the login screen's "no account? register" link.
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _loading = false;
  bool _obscure = true;
  bool _obscureConfirm = true;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  /// Shows [message] in a snackbar, guarding against a disposed widget.
  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  /// Maps a Firebase Auth exception to a localized message.
  String _localizedError(FirebaseAuthException e) {
    final l10n = context.l10n;
    return switch (AuthService.codeToKey(e.code)) {
      'authErrorInvalidEmail' => l10n.authErrorInvalidEmail,
      'authErrorEmailInUse' => l10n.authErrorEmailInUse,
      'authErrorWeakPassword' => l10n.authErrorWeakPassword,
      'authErrorNetworkFailed' => l10n.authErrorNetworkFailed,
      _ => l10n.authErrorGeneric,
    };
  }

  /// Validates the form, creates the account, then navigates to home.
  Future<void> _register() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _loading = true);
    try {
      await context
          .read<AuthService>()
          .registerWithEmail(_emailCtrl.text, _passwordCtrl.text);
      if (mounted) context.goNamed(AppRoute.home);
    } on FirebaseAuthException catch (e) {
      _showError(_localizedError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Registers/signs in via Google and navigates to home on success.
  Future<void> _signInGoogle() async {
    setState(() => _loading = true);
    final auth = context.read<AuthService>();
    final genericError = context.l10n.authErrorGeneric;
    try {
      await auth.signInWithGoogle();
      if (mounted) context.goNamed(AppRoute.home);
    } on FirebaseAuthException catch (e) {
      _showError(_localizedError(e));
    } catch (_) {
      _showError(genericError);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final showGoogle = defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.macOS;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        scrolledUnderElevation: 0,
        leading: BackButton(color: cs.primary),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // -- Title/subtitle header --
                Text(
                  l10n.authRegisterTitle,
                  style: Theme.of(context).textTheme.headlineMedium!.copyWith(
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  l10n.authRegisterSubtitle,
                  style: Theme.of(context).textTheme.bodyMedium!.copyWith(color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 32),
                // -- end header --

                // -- Email field --
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
                // -- end email field --

                // -- Password field --
                AuthField(
                  controller: _passwordCtrl,
                  label: l10n.authPasswordLabel,
                  hint: l10n.authPasswordHint,
                  obscureText: _obscure,
                  textInputAction: TextInputAction.next,
                  validator: (v) {
                    if (v == null || v.length < 6) return l10n.authPasswordTooShort;
                    return null;
                  },
                  suffixIcon: IconButton(
                    icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility,
                        size: 20, color: cs.onSurfaceVariant),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
                const SizedBox(height: 12),
                // -- end password field --

                // -- Confirm-password field --
                AuthField(
                  controller: _confirmCtrl,
                  label: l10n.authConfirmPasswordLabel,
                  hint: l10n.authConfirmPasswordHint,
                  obscureText: _obscureConfirm,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _register(),
                  validator: (v) {
                    if (v != _passwordCtrl.text) return l10n.authPasswordMismatch;
                    return null;
                  },
                  suffixIcon: IconButton(
                    icon: Icon(_obscureConfirm ? Icons.visibility_off : Icons.visibility,
                        size: 20, color: cs.onSurfaceVariant),
                    onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                  ),
                ),
                const SizedBox(height: 20),
                // -- end confirm-password field --

                // -- Create-account button --
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: FilledButton(
                    onPressed: _loading ? null : _register,
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    child: _loading
                        ? SizedBox(
                            width: 18, height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: cs.onPrimary))
                        : Text(l10n.authCreateAccount,
                            style: Theme.of(context).textTheme.fieldValueCompact),
                  ),
                ),
                const SizedBox(height: 24),
                // -- end create-account button --

                // -- Google sign-in shortcut (iOS/Android/macOS only) --
                if (showGoogle) ...[
                  AuthOrDivider(label: l10n.authOrDivider),
                  const SizedBox(height: 16),
                  AuthSocialButton(
                    onPressed: _loading ? null : _signInGoogle,
                    label: l10n.authSignInWithGoogle,
                    icon: const GoogleLogo(),
                  ),
                  const SizedBox(height: 24),
                ],
                // -- end Google sign-in shortcut --

                // -- "Already have an account? Sign in" row --
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(l10n.authAlreadyHaveAccount,
                        style: Theme.of(context).textTheme.bodyMedium!.copyWith(color: cs.onSurfaceVariant)),
                    TextButton(
                      onPressed: () => context.pop(),
                      child: Text(l10n.authSignInLink,
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
