import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

/// Thin wrapper around Firebase Auth (email/password, Google, Apple),
/// notifying listeners on every state change so `go_router`'s
/// `refreshListenable` can re-run its redirect logic (see app/router.dart).
class AuthService extends ChangeNotifier {
  /// True once Firebase itself has been initialized (main.dart's
  /// Firebase.initializeApp is best-effort — this stays false if that
  /// failed, e.g. no connectivity on first launch). Every ambient/passive
  /// read below is guarded by this: `FirebaseAuth.instance` throws
  /// `[core/no-app] No Firebase App has been created` when it hasn't, and
  /// [currentUser] in particular is read on *every* go_router redirect
  /// (app/router.dart) starting at launch — completely outside main.dart's
  /// own try/catch around Firebase init. Without this guard, an app that's
  /// documented to "still run fully offline" if Firebase fails would instead
  /// crash on its very first navigation. Sign-in methods below deliberately
  /// stay unguarded — a user actively tapping "sign in" while Firebase is
  /// unavailable should see a real error, not silently do nothing.
  static bool get _available => Firebase.apps.isNotEmpty;

  static FirebaseAuth get _auth => FirebaseAuth.instance;

  User? get currentUser => _available ? _auth.currentUser : null;
  bool get emailVerified =>
      _available ? (_auth.currentUser?.emailVerified ?? false) : false;
  Stream<User?> get authStateChanges =>
      _available ? _auth.authStateChanges() : Stream<User?>.value(null);

  // ── Email / Password ───────────────────────────────────────────────

  /// Signs in with email/password. Rethrows [FirebaseAuthException] for the
  /// caller to map to a localized message via [codeToKey].
  Future<void> signInWithEmail(String email, String password) async {
    try {
      await _auth.signInWithEmailAndPassword(
          email: email.trim(), password: password);
      notifyListeners();
    } on FirebaseAuthException {
      rethrow;
    }
  }

  /// Creates a new email/password account and fires off (but doesn't await)
  /// the verification email.
  Future<void> registerWithEmail(String email, String password) async {
    try {
      await _auth.createUserWithEmailAndPassword(
          email: email.trim(), password: password);
      // Always send — whether it blocks access is controlled by
      // kEnforceEmailVerification in feature_flags.dart.
      _auth.currentUser?.sendEmailVerification().ignore();
      notifyListeners();
    } on FirebaseAuthException {
      rethrow;
    }
  }

  /// Sends a "reset your password" email via Firebase.
  Future<void> sendPasswordReset(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
    } on FirebaseAuthException {
      rethrow;
    }
  }

  // ── Google ─────────────────────────────────────────────────────────

  /// Runs the native Google sign-in flow, then exchanges its token for a
  /// Firebase credential. No-ops if the user cancels the picker.
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

  /// Runs Sign In with Apple, then exchanges its identity token for a
  /// Firebase credential.
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

  // ── Email verification ─────────────────────────────────────────────

  Future<void> sendVerificationEmail() =>
      _auth.currentUser?.sendEmailVerification() ?? Future.value();

  /// Re-fetches the user profile from Firebase so emailVerified reflects
  /// the latest server state, then notifies listeners (triggers router refresh).
  Future<void> reloadUser() async {
    await _auth.currentUser?.reload();
    notifyListeners();
  }

  // ── Sign out / Delete ──────────────────────────────────────────────

  /// Signs out of both Google (if used) and Firebase.
  Future<void> signOut() async {
    await GoogleSignIn().signOut();
    await _auth.signOut();
    notifyListeners();
  }

  /// Deletes the Firebase Auth account itself. Callers are responsible for
  /// deleting the user's Firestore/Storage data first — see
  /// `LogbookService.deleteUserAndAllLogbooks`.
  Future<void> deleteAccount() async {
    try {
      await _auth.currentUser?.delete();
      notifyListeners();
    } on FirebaseAuthException {
      rethrow;
    }
  }

  // ── Error mapping ──────────────────────────────────────────────────

  /// Maps a Firebase Auth error [code] to a localization key, so screens can
  /// show a translated message instead of Firebase's raw English string.
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
      case 'too-many-requests':
        return 'authErrorTooManyRequests';
      case 'user-disabled':
        return 'authErrorUserDisabled';
      default:
        return 'authErrorGeneric';
    }
  }
}
