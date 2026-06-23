import 'package:cloud_firestore/cloud_firestore.dart';

/// Manages boat identity and membership in the new data model.
///
/// Firestore layout:
///   boats/{boatId}             — root: { ownerId, inviteCode, createdAt }
///   boats/{boatId}/members/{uid} — { role, joinedAt }
///   users/{uid}                — profile: { boatId, role }
class BoatService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Returns the canonical boatId for [uid].
  ///
  /// If users/{uid} already has a boatId stored, that value is returned
  /// immediately. Otherwise a new boat is created with [inviteCode] as its
  /// human-readable code, the calling user is added as owner, and the new
  /// boatId (a Firestore auto-generated UUID) is returned.
  Future<String> resolveBoatId(String uid, String inviteCode) async {
    final profileDoc = await _db.collection('users').doc(uid).get();
    final existing = profileDoc.data();
    if (existing != null && existing['boatId'] is String) {
      return existing['boatId'] as String;
    }

    // New boat: use an auto-generated Firestore document ID.
    final boatRef = _db.collection('boats').doc();
    final boatId = boatRef.id;

    // Step 1: Create the boat root document so the members rule can verify
    // ownerId in step 2 (security rules evaluate committed state).
    await boatRef.set({
      'ownerId': uid,
      'inviteCode': inviteCode,
      'createdAt': FieldValue.serverTimestamp(),
    });

    // Step 2: Add the creator as owner-member and write the user profile.
    final batch = _db.batch();
    batch.set(
      boatRef.collection('members').doc(uid),
      {'role': 'owner', 'joinedAt': FieldValue.serverTimestamp()},
    );
    batch.set(
      _db.collection('users').doc(uid),
      {'boatId': boatId, 'role': 'owner'},
    );
    await batch.commit();

    return boatId;
  }

  /// Returns the boatId stored in users/{uid}, or null if no profile exists.
  Future<String?> getBoatIdForUser(String uid) async {
    final doc = await _db.collection('users').doc(uid).get();
    return doc.data()?['boatId'] as String?;
  }

  /// Adds [uid] to [boatId] as a member with [role] and overwrites
  /// their users/{uid} profile with the new boatId and role.
  Future<void> addMemberToBoat(
      String boatId, String uid, String role) async {
    final batch = _db.batch();
    batch.set(
      _db.collection('boats').doc(boatId).collection('members').doc(uid),
      {'role': role, 'joinedAt': FieldValue.serverTimestamp()},
    );
    batch.set(
      _db.collection('users').doc(uid),
      {'boatId': boatId, 'role': role},
    );
    await batch.commit();
  }
}
