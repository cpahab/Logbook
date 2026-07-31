// Regression coverage for the wiki finding "The documented Firebase-failure
// offline fallback is fragile because AuthService still eagerly depends on
// FirebaseAuth.instance": main.dart documents that any Firebase.initializeApp
// failure should leave the app in offline (Hive-only) mode rather than
// crashing, but app/router.dart reads AuthService.currentUser on *every*
// go_router redirect starting at launch, completely outside main.dart's own
// try/catch around Firebase init — so an unguarded FirebaseAuth.instance
// access there would violate that promise on the very first navigation.
//
// A plain flutter_test environment never calls Firebase.initializeApp(), so
// it *is* "Firebase failed/never initialized" — exactly the scenario this
// fix targets. No mocking needed: if AuthService still ate eagerly touched
// FirebaseAuth.instance here, these would throw the framework's own
// "[core/no-app] No Firebase App has been created" error instead of the
// graceful values asserted below.

import 'package:flutter_test/flutter_test.dart';
import 'package:logbook/features/auth/data/auth_repository.dart';

void main() {
  test('currentUser is null when Firebase was never initialized (not a thrown '
      '"no Firebase App" error)', () {
    expect(AuthService().currentUser, isNull);
  });

  test('emailVerified is false when Firebase was never initialized', () {
    expect(AuthService().emailVerified, isFalse);
  });

  test('authStateChanges emits a single null instead of throwing on subscribe',
      () async {
    final events = await AuthService().authStateChanges.toList();
    expect(events, [null]);
  });
}
