import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// One-time setup that runs on every authenticated launch.
///
/// Firestore layout created/maintained here:
///   users/{uid}              — profile: { logbookId, email, createdAt }
///   logbooks/{logbookId}        — logbook root: { members:[uid,...], ownerId, createdAt }
///
/// [logbookId] is always the app's logbook code (ThemeProvider.installationId).
/// For a first-time sign-in this matches the local code; for a subsequent
/// sign-in on a different device it reads the stored logbookId from the user's
/// profile and returns it so the caller can reconcile services.
class BootstrapService {
  static final _db = FirebaseFirestore.instance;

  /// Returns the canonical logbookId for [uid].
  ///
  /// If the user profile does not exist it is created with [fallbackLogbookId]
  /// as the logbookId. The boat document is likewise created/updated so the uid
  /// is present in its `members` array.
  static Future<String> ensureUserAndLogbook({
    required String uid,
    required String email,
    required String fallbackLogbookId,
  }) async {
    final userRef = _db.collection('users').doc(uid);
    late DocumentSnapshot<Map<String, dynamic>> userSnap;
    try {
      userSnap = await userRef
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 10));
    } catch (_) {
      userSnap = await userRef.get(const GetOptions(source: Source.cache));
    }

    if (userSnap.exists) {
      // Profile already exists — trust the stored logbookId.
      final logbookId = (userSnap.data()?['logbookId'] as String?) ?? fallbackLogbookId;
      // Ensure the uid is in the boat's members list (idempotent).
      await _ensureLogbookMember(logbookId: logbookId, uid: uid);
      return logbookId;
    }

    // First authenticated launch from this account: use the local code as logbookId.
    final logbookId = fallbackLogbookId;
    final batch = _db.batch();

    batch.set(userRef, {
      'logbookId': logbookId,
      'email': email,
      'createdAt': FieldValue.serverTimestamp(),
    });

    final boatRef = _db.collection('logbooks').doc(logbookId);
    late DocumentSnapshot<Map<String, dynamic>> boatSnap;
    try {
      boatSnap = await boatRef
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 10));
    } catch (_) {
      boatSnap = await boatRef.get(const GetOptions(source: Source.cache));
    }

    if (boatSnap.exists) {
      // Boat already exists (e.g. created by another device). Join as member.
      batch.update(boatRef, {
        'members': FieldValue.arrayUnion([uid]),
      });
    } else {
      batch.set(boatRef, {
        'members': [uid],
        'ownerId': uid,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }

    await batch.commit().timeout(const Duration(seconds: 10));
    return logbookId;
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  static Future<void> _ensureLogbookMember({
    required String logbookId,
    required String uid,
  }) async {
    final boatRef = _db.collection('logbooks').doc(logbookId);
    late DocumentSnapshot<Map<String, dynamic>> boatSnap;
    try {
      boatSnap = await boatRef
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 10));
    } catch (_) {
      boatSnap = await boatRef.get(const GetOptions(source: Source.cache));
    }

    if (!boatSnap.exists) {
      // Boat doc missing — recreate defensively.
      await boatRef.set({
        'members': [uid],
        'ownerId': uid,
        'createdAt': FieldValue.serverTimestamp(),
      });
      return;
    }

    final members = (boatSnap.data()?['members'] as List?)?.cast<String>() ?? [];
    if (!members.contains(uid)) {
      await boatRef.update({
        'members': FieldValue.arrayUnion([uid]),
      }).timeout(const Duration(seconds: 10));
    }
  }

  // ── Current user helpers ─────────────────────────────────────────────────────

  /// Convenience: runs [ensureUserAndLogbook] for the currently signed-in user.
  /// Returns null if no user is signed in.
  static Future<String?> bootstrapCurrentLogbook(String fallbackLogbookId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    return ensureUserAndLogbook(
      uid: user.uid,
      email: user.email ?? '',
      fallbackLogbookId: fallbackLogbookId,
    );
  }
}
