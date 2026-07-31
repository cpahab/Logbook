import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../app/route_names.dart';
import '../../../app/theme/theme_extensions.dart';
import '../data/auth_repository.dart';
import '../../../core/services/local_logbook_service.dart';
import '../../../l10n/l10n_extension.dart';
import '../../settings/domain/theme_provider.dart';
import 'auth_widgets.dart';

/// Email/password + Google/Apple sign-in screen. The router's redirect logic
/// (app/router.dart) sends unauthenticated users here first.
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

  /// Maps a Firebase Auth exception to a localized message via
  /// [AuthService.codeToKey].
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

  /// Shows [message] in a snackbar, guarding against a disposed widget.
  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  /// Validates the form, then signs in with the entered email/password.
  Future<void> _signIn() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _loading = true);
    try {
      await context
          .read<AuthService>()
          .signInWithEmail(_emailCtrl.text, _passwordCtrl.text);
    } on FirebaseAuthException catch (e) {
      _showError(_localizedError(e));
    } catch (e) {
      if (kDebugMode) debugPrint('sign-in error: $e');
      if (mounted) _showError(context.l10n.authErrorGeneric);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Runs the Google sign-in flow and reports any failure via a snackbar.
  Future<void> _signInGoogle() async {
    setState(() => _loading = true);
    final auth = context.read<AuthService>();
    final genericError = context.l10n.authErrorGeneric;
    try {
      await auth.signInWithGoogle();
    } on FirebaseAuthException catch (e) {
      _showError(_localizedError(e));
    } catch (e) {
      if (kDebugMode) debugPrint('sign-in error: $e');
      _showError(genericError);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Enters local mode: all data stays on this device, no account needed.
  /// The router picks up the flag change and stops forcing the auth screen,
  /// but doesn't auto-navigate away from it, so this still has to push home
  /// itself.
  ///
  /// A device's first-ever local logbook is the reserved empty-string
  /// sentinel (see `LocalLogbookService`), which needs no Hive box
  /// renaming — the base boxes `repo`/`emergencyRepo`/`themeProvider` already
  /// have open (from `main.dart`'s boot, before local mode was chosen) are
  /// already exactly the right ones, so only the registry entry and the
  /// active-id pointer need to be created; nothing needs switching.
  Future<void> _continueOffline() async {
    final themeProvider = context.read<ThemeProvider>();
    final localLogbookService = context.read<LocalLogbookService>();

    final logbooks = await localLogbookService.listLogbooks();
    if (logbooks.isEmpty) {
      await localLogbookService.createLogbookWithId('', 'My Logbook');
      await themeProvider.adoptActiveLocalLogbookId('');
    }
    // else: a returning local-mode user already has an active logbook set —
    // nothing to do here.

    themeProvider.enableLocalMode();
    if (mounted) context.goNamed(AppRoute.home);
  }

  /// Runs the Apple sign-in flow and reports any failure via a snackbar.
  Future<void> _signInApple() async {
    setState(() => _loading = true);
    final auth = context.read<AuthService>();
    final genericError = context.l10n.authErrorGeneric;
    try {
      await auth.signInWithApple();
    } on FirebaseAuthException catch (e) {
      _showError(_localizedError(e));
    } catch (e) {
      if (kDebugMode) debugPrint('sign-in error: $e');
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
                // -- Anchor icon + title/subtitle header --
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

                // -- Password field (with visibility toggle) --
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
                // -- end password field --

                // -- Forgot-password link --
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => context.pushNamed(AppRoute.forgotPassword),
                    child: Text(l10n.authForgotPasswordLink,
                        style: Theme.of(context).textTheme.bodySmall!.copyWith(
                            color: cs.primary)),
                  ),
                ),

                // -- Sign-in button (shows a spinner while _loading) --
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
                            style: Theme.of(context).textTheme.fieldValueCompact
                                .copyWith(color: cs.onPrimary)),
                  ),
                ),
                const SizedBox(height: 24),
                // -- end sign-in button --

                // -- Social sign-in (Google/Apple, platform-gated) --
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
                // -- end social sign-in --

                const SizedBox(height: 22),

                // -- "No account? Register" row --
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

                const SizedBox(height: 4),

                // -- "Continue without an account" escape hatch: kept
                // low-emphasis so it doesn't compete with the primary
                // sign-in/register paths above. --
                Center(
                  child: TextButton(
                    onPressed: _continueOffline,
                    child: Text(l10n.authContinueOffline,
                        style: Theme.of(context).textTheme.bodySmall!.copyWith(
                            color: cs.onSurfaceVariant)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
