import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/services/auth_service.dart';
import '../../../l10n/l10n_extension.dart';
import 'auth_widgets.dart';

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
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() { _loading = true; _error = null; });
    try {
      await AuthService.registerWithEmail(_emailCtrl.text, _passwordCtrl.text);
      if (mounted) context.go('/');
    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() => _error = _msg(e.code));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _signInGoogle() async {
    setState(() { _loading = true; _error = null; });
    try {
      final result = await AuthService.signInWithGoogle();
      if (result != null && mounted) context.go('/');
    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() => _error = _msg(e.code));
    } catch (_) {
      if (mounted) setState(() => _error = context.l10n.authErrorGeneric);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _msg(String code) {
    final l10n = context.l10n;
    switch (AuthService.codeToKey(code)) {
      case 'authErrorInvalidEmail': return l10n.authErrorInvalidEmail;
      case 'authErrorEmailInUse': return l10n.authErrorEmailInUse;
      case 'authErrorWeakPassword': return l10n.authErrorWeakPassword;
      case 'authErrorNetworkFailed': return l10n.authErrorNetworkFailed;
      default: return l10n.authErrorGeneric;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: cs.surface,
        elevation: 0,
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
                Text(
                  l10n.authRegisterTitle,
                  style: GoogleFonts.newsreader(
                    fontSize: 28, fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  l10n.authRegisterSubtitle,
                  style: GoogleFonts.inter(
                      fontSize: 14, color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 32),

                AuthField(
                  controller: _emailCtrl,
                  label: l10n.authEmailLabel,
                  hint: l10n.authEmailHint,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return l10n.authErrorInvalidEmail;
                    return null;
                  },
                ),
                const SizedBox(height: 12),

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

                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!,
                      style: GoogleFonts.inter(fontSize: 13, color: cs.error)),
                ],
                const SizedBox(height: 20),

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
                            style: GoogleFonts.inter(
                                fontSize: 15, fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(height: 24),

                AuthOrDivider(label: l10n.authOrDivider),
                const SizedBox(height: 16),

                AuthSocialButton(
                  onPressed: _loading ? null : _signInGoogle,
                  label: l10n.authSignInWithGoogle,
                  icon: const GoogleLogo(),
                ),
                const SizedBox(height: 32),

                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(l10n.authAlreadyHaveAccount,
                        style: GoogleFonts.inter(
                            fontSize: 14, color: cs.onSurfaceVariant)),
                    TextButton(
                      onPressed: () => context.pop(),
                      child: Text(l10n.authSignInLink,
                          style: GoogleFonts.inter(
                              fontSize: 14, fontWeight: FontWeight.w600,
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
