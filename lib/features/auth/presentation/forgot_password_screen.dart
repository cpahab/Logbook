import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../app/theme/theme_extensions.dart';
import '../../../core/services/auth_service.dart';
import '../../../l10n/app_localizations.dart';
import '../../../l10n/l10n_extension.dart';
import 'auth_widgets.dart';

/// Password-reset request screen: collects an email, sends a reset link via
/// Firebase, then swaps to a confirmation view. Reachable from the login
/// screen's "forgot password?" link.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _loading = false;
  bool _sent = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  /// Validates the form and sends the reset email; on success shows the
  /// confirmation view instead of the form.
  Future<void> _send() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _loading = true);
    try {
      await context.read<AuthService>().sendPasswordReset(_emailCtrl.text);
      if (mounted) setState(() => _sent = true);
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        final l10n = context.l10n;
        final msg = switch (AuthService.codeToKey(e.code)) {
          'authErrorInvalidEmail' => l10n.authErrorInvalidEmail,
          'authErrorUserNotFound' => l10n.authErrorUserNotFound,
          'authErrorNetworkFailed' => l10n.authErrorNetworkFailed,
          _ => l10n.authErrorGeneric,
        };
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(msg)));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        scrolledUnderElevation: 0,
        leading: BackButton(color: cs.primary),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: _sent ? _buildConfirmation(cs, l10n) : _buildForm(cs, l10n),
        ),
      ),
    );
  }

  /// The email-entry form, shown before a reset email has been sent.
  Widget _buildForm(ColorScheme cs, AppLocalizations l10n) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.authForgotPasswordTitle,
            style: Theme.of(context).textTheme.headlineMedium!.copyWith(
              fontWeight: FontWeight.w600, color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.authForgotPasswordDesc,
            style: Theme.of(context).textTheme.bodyMedium!.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 32),

          AuthField(
            controller: _emailCtrl,
            label: l10n.authEmailLabel,
            hint: l10n.authEmailHint,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _send(),
            validator: (v) {
              if (v == null || v.trim().isEmpty) return l10n.authErrorInvalidEmail;
              return null;
            },
          ),
          const SizedBox(height: 20),

          SizedBox(
            width: double.infinity,
            height: 50,
            child: FilledButton(
              onPressed: _loading ? null : _send,
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              child: _loading
                  ? SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: cs.onPrimary))
                  : Text(l10n.authSendResetEmail,
                      style: Theme.of(context).textTheme.fieldValueCompact),
            ),
          ),
        ],
      ),
    );
  }

  /// "Check your email" view, shown after the reset email is sent.
  Widget _buildConfirmation(ColorScheme cs, AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.mark_email_read_outlined, size: 48, color: cs.primary),
        const SizedBox(height: 20),
        Text(
          l10n.authResetEmailSent,
          style: Theme.of(context).textTheme.titleLarge!.copyWith(
              fontWeight: FontWeight.w600, color: cs.onSurface),
        ),
        const SizedBox(height: 24),
        TextButton.icon(
          onPressed: () => context.pop(),
          icon: Icon(Icons.arrow_back, size: 18, color: cs.primary),
          label: Text(l10n.authBackToSignIn,
              style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                  color: cs.primary,
                  fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }
}
