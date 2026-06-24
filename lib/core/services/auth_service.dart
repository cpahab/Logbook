import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

class AuthService extends ChangeNotifier {
  static final _auth = FirebaseAuth.instance;

  late final StreamSubscription<User?> _authSub;

  AuthService() {
    // Forward every Firebase Auth state change to GoRouter's refreshListenable.
    // This handles the case where currentUser is null at startup (Keychain not
    // yet loaded) but Firebase Auth resolves a valid session moments later.
    _authSub = _auth.authStateChanges().listen((_) => notifyListeners());
  }

  @override
  void dispose() {
    _authSub.cancel();
    super.dispose();
  }

  User? get currentUser => _auth.currentUser;
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // ── Email / Password ───────────────────────────────────────────────

  Future<void> signInWithEmail(String email, String password) async {
    try {
      await _auth.signInWithEmailAndPassword(
          email: email.trim(), password: password);
      notifyListeners();
    } on FirebaseAuthException {
      rethrow;
    }
  }

  Future<void> registerWithEmail(String email, String password) async {
    try {
      await _auth.createUserWithEmailAndPassword(
          email: email.trim(), password: password);
      notifyListeners();
    } on FirebaseAuthException {
      rethrow;
    }
  }

  Future<void> sendPasswordReset(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
    } on FirebaseAuthException {
      rethrow;
    }
  }

  // ── Google ─────────────────────────────────────────────────────────

  Future<void> signInWithGoogle() async {
    try {
      final googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) return; // user cancelled
      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      await _auth.signInWithCredential(credential);
      notifyListeners();
    } on FirebaseAuthException {
      rethrow;
    }
  }

  // ── Apple ──────────────────────────────────────────────────────────

  Future<void> signInWithApple() async {
    try {
      final appleCredential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
      );
      final oauthCredential = OAuthProvider('apple.com').credential(
        idToken: appleCredential.identityToken,
        accessToken: appleCredential.authorizationCode,
      );
      await _auth.signInWithCredential(oauthCredential);
      notifyListeners();
    } on FirebaseAuthException {
      rethrow;
    }
  }

  // ── Sign out / Delete ──────────────────────────────────────────────

  Future<void> signOut() async {
    await GoogleSignIn().signOut();
    await _auth.signOut();
    notifyListeners();
  }

  Future<void> deleteAccount() async {
    try {
      await _auth.currentUser?.delete();
      notifyListeners();
    } on FirebaseAuthException {
      rethrow;
    }
  }

  // ── Error mapping ──────────────────────────────────────────────────

  static String codeToKey(String code) {
    switch (code) {
      case 'invalid-email':
        return 'authErrorInvalidEmail';
      case 'wrong-password':
      case 'invalid-credential':
        return 'authErrorWrongPassword';
      case 'user-not-found':
        return 'authErrorUserNotFound';
      case 'email-already-in-use':
        return 'authErrorEmailInUse';
      case 'weak-password':
        return 'authErrorWeakPassword';
      case 'network-request-failed':
        return 'authErrorNetworkFailed';
      default:
        return 'authErrorGeneric';
    }
  }
}
