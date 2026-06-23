import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

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
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() { _loading = true; _error = null; });
    try {
      await AuthService.signInWithEmail(_emailCtrl.text, _passwordCtrl.text);
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

  Future<void> _signInApple() async {
    setState(() { _loading = true; _error = null; });
    try {
      final result = await AuthService.signInWithApple();
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
      case 'authErrorWrongPassword': return l10n.authErrorWrongPassword;
      case 'authErrorUserNotFound': return l10n.authErrorUserNotFound;
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
                  style: GoogleFonts.newsreader(
                    fontSize: 28, fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  l10n.authLoginSubtitle,
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
                    onPressed: () => context.push('/auth/forgot-password'),
                    child: Text(l10n.authForgotPasswordLink,
                        style: GoogleFonts.inter(
                            fontSize: 13, color: cs.primary)),
                  ),
                ),

                if (_error != null) ...[
                  const SizedBox(height: 4),
                  Text(_error!,
                      style: GoogleFonts.inter(fontSize: 13, color: cs.error)),
                  const SizedBox(height: 8),
                ],

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
                            style: GoogleFonts.inter(
                                fontSize: 15, fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(height: 24),

                AuthOrDivider(label: l10n.authOrDivider),
                const SizedBox(height: 16),

                if (!Platform.isMacOS)
                  AuthSocialButton(
                    onPressed: _loading ? null : _signInGoogle,
                    label: l10n.authSignInWithGoogle,
                    icon: const GoogleLogo(),
                  ),

                if (AuthService.isAppleAvailable && !Platform.isMacOS) ...[
                  const SizedBox(height: 10),
                  AuthSocialButton(
                    onPressed: _loading ? null : _signInApple,
                    label: l10n.authSignInWithApple,
                    icon: Icon(Icons.apple, size: 20, color: cs.onSurface),
                  ),
                ],
                const SizedBox(height: 32),

                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(l10n.authNoAccount,
                        style: GoogleFonts.inter(
                            fontSize: 14, color: cs.onSurfaceVariant)),
                    TextButton(
                      onPressed: () => context.push('/auth/register'),
                      child: Text(l10n.authRegisterLink,
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
