import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// One-time setup that runs on every authenticated launch.
///
/// Firestore layout created/maintained here:
///   users/{uid}              — profile: { boatId, email, createdAt }
///   boats/{boatId}           — boat root: { members:[uid,...], ownerId, createdAt }
///
/// [boatId] is always the app's logbook code (ThemeProvider.installationId).
/// For a first-time sign-in this matches the local code; for a subsequent
/// sign-in on a different device it reads the stored boatId from the user's
/// profile and returns it so the caller can reconcile services.
class BootstrapService {
  static final _db = FirebaseFirestore.instance;

  /// Returns the canonical boatId for [uid].
  ///
  /// If the user profile does not exist it is created with [fallbackBoatId]
  /// as the boatId. The boat document is likewise created/updated so the uid
  /// is present in its `members` array.
  static Future<String> ensureUserAndBoat({
    required String uid,
    required String email,
    required String fallbackBoatId,
  }) async {
    final userRef = _db.collection('users').doc(uid);
    final userSnap = await userRef.get(const GetOptions(source: Source.server))
        .timeout(const Duration(seconds: 10));

    if (userSnap.exists) {
      // Profile already exists — trust the stored boatId.
      final boatId = (userSnap.data()?['boatId'] as String?) ?? fallbackBoatId;
      // Ensure the uid is in the boat's members list (idempotent).
      await _ensureBoatMember(boatId: boatId, uid: uid);
      return boatId;
    }

    // First authenticated launch from this account: use the local code as boatId.
    final boatId = fallbackBoatId;
    final batch = _db.batch();

    batch.set(userRef, {
      'boatId': boatId,
      'email': email,
      'createdAt': FieldValue.serverTimestamp(),
    });

    final boatRef = _db.collection('boats').doc(boatId);
    final boatSnap = await boatRef
        .get(const GetOptions(source: Source.server))
        .timeout(const Duration(seconds: 10));

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
    return boatId;
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  static Future<void> _ensureBoatMember({
    required String boatId,
    required String uid,
  }) async {
    final boatRef = _db.collection('boats').doc(boatId);
    final boatSnap = await boatRef
        .get(const GetOptions(source: Source.server))
        .timeout(const Duration(seconds: 10));

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

  /// Convenience: runs [ensureUserAndBoat] for the currently signed-in user.
  /// Returns null if no user is signed in.
  static Future<String?> bootstrapCurrentUser(String fallbackBoatId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    return ensureUserAndBoat(
      uid: user.uid,
      email: user.email ?? '',
      fallbackBoatId: fallbackBoatId,
    );
  }
}
