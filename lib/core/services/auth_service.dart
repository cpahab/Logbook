import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

class AuthService {
  static final _auth = FirebaseAuth.instance;

  static Stream<User?> get authStateChanges => _auth.authStateChanges();
  static User? get currentUser => _auth.currentUser;

  // ── Email / Password ───────────────────────────────────────────────

  static Future<UserCredential> signInWithEmail(
      String email, String password) =>
      _auth.signInWithEmailAndPassword(email: email.trim(), password: password);

  static Future<UserCredential> registerWithEmail(
      String email, String password) =>
      _auth.createUserWithEmailAndPassword(
          email: email.trim(), password: password);

  static Future<void> sendPasswordResetEmail(String email) =>
      _auth.sendPasswordResetEmail(email: email.trim());

  // ── Google ─────────────────────────────────────────────────────────

  static Future<UserCredential?> signInWithGoogle() async {
    final googleUser = await GoogleSignIn().signIn();
    if (googleUser == null) return null; // user cancelled
    final googleAuth = await googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );
    return _auth.signInWithCredential(credential);
  }

  // ── Apple ──────────────────────────────────────────────────────────

  static bool get isAppleAvailable =>
      Platform.isIOS || Platform.isMacOS;

  static Future<UserCredential?> signInWithApple() async {
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
    return _auth.signInWithCredential(oauthCredential);
  }

  // ── Sign out ───────────────────────────────────────────────────────

  static Future<void> signOut() async {
    await GoogleSignIn().signOut();
    await _auth.signOut();
  }

  // ── Error messages ─────────────────────────────────────────────────

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
