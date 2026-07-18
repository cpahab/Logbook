import 'package:flutter/material.dart';

import '../../../app/theme/theme_extensions.dart';
import 'package:provider/provider.dart';

import '../../../core/services/auth_service.dart';
import '../../../l10n/l10n_extension.dart';

/// Blocking screen shown to signed-in users with an unverified email, when
/// `kEnforceEmailVerification` (core/config/feature_flags.dart) is on.
/// Offers "I've verified, check again" and "resend email" actions.
class VerifyEmailScreen extends StatefulWidget {
  const VerifyEmailScreen({super.key});

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  bool _resending = false;
  bool _checking = false;

  /// Re-sends the Firebase verification email.
  Future<void> _resend() async {
    setState(() => _resending = true);
    try {
      await context.read<AuthService>().sendVerificationEmail();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.authVerifyEmailSent)),
        );
      }
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  Future<void> _checkVerified() async {
    setState(() => _checking = true);
    try {
      // Reload fetches the latest profile from Firebase. If verified,
      // AuthService.notifyListeners() triggers the router redirect to '/'.
      await context.read<AuthService>().reloadUser();
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final email = context.read<AuthService>().currentUser?.email ?? '';
    final busy = _resending || _checking;

    return Scaffold(
      backgroundColor: cs.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(Icons.mark_email_unread_outlined,
                  size: 64, color: cs.primary),
              const SizedBox(height: 28),
              Text(
                l10n.authVerifyEmailTitle,
                style: Theme.of(context).textTheme.headlineMedium!.copyWith(
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                l10n.authVerifyEmailBody(email),
                style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                    color: cs.onSurfaceVariant, height: 1.5),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 40),
              FilledButton(
                onPressed: busy ? null : _checkVerified,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                child: _checking
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: cs.onPrimary))
                    : Text(l10n.authVerifyEmailCheck,
                        style: Theme.of(context).textTheme.fieldValueCompact
                            .copyWith(color: cs.onPrimary)),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: busy ? null : _resend,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                child: _resending
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: cs.primary))
                    : Text(l10n.authVerifyEmailResend,
                        style: Theme.of(context).textTheme.bodyMedium),
              ),
              const SizedBox(height: 24),
              TextButton(
                onPressed: busy ? null : context.read<AuthService>().signOut,
                child: Text(
                  context.l10n.authSignOut,
                  style: Theme.of(context).textTheme.bodySmall!.copyWith(
                      color: cs.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
