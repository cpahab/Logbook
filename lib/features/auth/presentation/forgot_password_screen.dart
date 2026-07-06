import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../../core/services/auth_service.dart';
import '../../../l10n/app_localizations.dart';
import '../../../l10n/l10n_extension.dart';
import 'auth_widgets.dart';

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

  Widget _buildForm(ColorScheme cs, AppLocalizations l10n) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.authForgotPasswordTitle,
            style: GoogleFonts.dmSans(
              fontSize: 28, fontWeight: FontWeight.w600, color: cs.onSurface,
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
                      style: GoogleFonts.dmSans(
                          fontSize: 15, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConfirmation(ColorScheme cs, AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.mark_email_read_outlined, size: 48, color: cs.primary),
        const SizedBox(height: 20),
        Text(
          l10n.authResetEmailSent,
          style: GoogleFonts.dmSans(
              fontSize: 22, fontWeight: FontWeight.w600, color: cs.onSurface),
        ),
        const SizedBox(height: 24),
        TextButton.icon(
          onPressed: () => context.pop(),
          icon: Icon(Icons.arrow_back, size: 18, color: cs.primary),
          label: Text(l10n.authBackToSignIn,
              style: GoogleFonts.dmSans(
                  fontSize: 14, color: cs.primary,
                  fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }
}
