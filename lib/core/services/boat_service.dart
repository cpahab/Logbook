import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

/// Manages boat identity and membership.
///
/// Firestore layout:
///   users/{uid}                    { activeBoatId, boats: [] }
///   boats/{boatId}                 { name, ownerUid, shareCode, createdAt }
///   boats/{boatId}/members/{uid}   { role: 'owner'|'guest', joinedAt }
class BoatService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ── Create ─────────────────────────────────────────────────────────────────

  /// Creates a new logbook boat for [uid] with the given [name].
  /// Returns the new boatId.
  Future<String> createBoat(String uid, String name) async {
    final boatRef = _db.collection('boats').doc();
    final boatId = boatRef.id;
    final shareCode = _generateShareCode();

    await boatRef.set({
      'name': name,
      'ownerUid': uid,
      'shareCode': shareCode,
      'createdAt': FieldValue.serverTimestamp(),
    });

    final batch = _db.batch();
    batch.set(
      boatRef.collection('members').doc(uid),
      {'role': 'owner', 'joinedAt': FieldValue.serverTimestamp()},
    );
    batch.set(
      _db.collection('users').doc(uid),
      {
        'activeBoatId': boatId,
        'boats': FieldValue.arrayUnion([boatId]),
      },
      SetOptions(merge: true),
    );
    await batch.commit();

    return boatId;
  }

  // ── Read ───────────────────────────────────────────────────────────────────

  /// Returns the active boatId for [uid], or null if no profile exists.
  Future<String?> getActiveBoatId(String uid) async {
    final doc = await _db.collection('users').doc(uid).get();
    return doc.data()?['activeBoatId'] as String?;
  }

  /// Returns the list of boats accessible to [uid] with metadata.
  /// Each map contains: boatId, name, role, shareCode.
  Future<List<Map<String, dynamic>>> listBoats(String uid) async {
    final userDoc = await _db.collection('users').doc(uid).get();
    final boatIds = List<String>.from(
        userDoc.data()?['boats'] as List? ?? []);

    final result = <Map<String, dynamic>>[];
    for (final boatId in boatIds) {
      final boatDoc = await _db.collection('boats').doc(boatId).get();
      if (!boatDoc.exists) continue;
      final data = boatDoc.data()!;

      final memberDoc = await _db
          .collection('boats')
          .doc(boatId)
          .collection('members')
          .doc(uid)
          .get();
      final role = memberDoc.data()?['role'] as String? ?? 'guest';

      result.add({
        'boatId': boatId,
        'name': data['name'] as String? ?? '',
        'role': role,
        'shareCode': data['shareCode'] as String? ?? '',
      });
    }
    return result;
  }

  // ── Update ─────────────────────────────────────────────────────────────────

  /// Sets [boatId] as the active logbook for [uid].
  Future<void> setActiveBoat(String uid, String boatId) =>
      _db.collection('users').doc(uid).set(
            {'activeBoatId': boatId},
            SetOptions(merge: true),
          );

  // ── Share code lookup ──────────────────────────────────────────────────────

  /// Finds a boat by its [shareCode]. Returns the boatId or null.
  Future<String?> findByShareCode(String shareCode) async {
    final snap = await _db
        .collection('boats')
        .where('shareCode', isEqualTo: shareCode)
        .limit(1)
        .get();
    return snap.docs.isEmpty ? null : snap.docs.first.id;
  }

  // ── Join / Remove ──────────────────────────────────────────────────────────

  /// Adds [uid] to [boatId] as a guest and sets it as their active boat.
  Future<void> joinBoat(String boatId, String uid) async {
    final batch = _db.batch();
    batch.set(
      _db.collection('boats').doc(boatId).collection('members').doc(uid),
      {'role': 'guest', 'joinedAt': FieldValue.serverTimestamp()},
    );
    batch.set(
      _db.collection('users').doc(uid),
      {
        'activeBoatId': boatId,
        'boats': FieldValue.arrayUnion([boatId]),
      },
      SetOptions(merge: true),
    );
    await batch.commit();
  }

  /// Removes [uid] from [boatId]. Updates activeBoatId if this was the active boat.
  Future<void> removeMember(String boatId, String uid) async {
    await _db
        .collection('boats')
        .doc(boatId)
        .collection('members')
        .doc(uid)
        .delete();

    final userDoc = await _db.collection('users').doc(uid).get();
    final data = userDoc.data();
    final remaining = List<String>.from(data?['boats'] as List? ?? [])
      ..remove(boatId);

    final Map<String, dynamic> update = {
      'boats': FieldValue.arrayRemove([boatId]),
    };
    if (data?['activeBoatId'] == boatId) {
      update['activeBoatId'] = remaining.isNotEmpty ? remaining.first : null;
    }

    await _db.collection('users').doc(uid).set(
          update,
          SetOptions(merge: true),
        );
  }

  // ── Code generation ────────────────────────────────────────────────────────

  static String _generateShareCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rand = Random.secure();
    return List.generate(8, (_) => chars[rand.nextInt(chars.length)]).join();
  }

  // ── Name lookup ───────────────────────────────────────────────────────────

  Future<String?> getBoatName(String boatId) async {
    final doc = await _db.collection('boats').doc(boatId).get();
    return doc.data()?['name'] as String?;
  }

  // ── Rename / regenerate ────────────────────────────────────────────────────

  Future<void> renameBoat(String boatId, String name) =>
      _db.collection('boats').doc(boatId).update({'name': name});

  Future<String> regenerateShareCode(String boatId) async {
    final code = _generateShareCode();
    await _db.collection('boats').doc(boatId).update({'shareCode': code});
    return code;
  }

  // ── Delete ─────────────────────────────────────────────────────────────────

  Future<void> deleteBoat(String boatId, String ownerUid) async {
    final boatRef = _db.collection('boats').doc(boatId);

    // Delete all entries (may be large — chunked).
    await _deleteCollectionInChunks(boatRef.collection('entries'));

    // Delete known meta documents.
    for (final id in ['settings', 'contacts', 'ui', 'crew_roster']) {
      try {
        await boatRef.collection('meta').doc(id).delete();
      } catch (_) {}
    }

    // Delete all members + the boat doc itself.
    final membersSnap = await boatRef.collection('members').get();
    final batch = _db.batch();
    for (final doc in membersSnap.docs) {
      batch.delete(doc.reference);
    }
    batch.delete(boatRef);
    await batch.commit();

    // Remove from owner's boat list.
    final userDoc = await _db.collection('users').doc(ownerUid).get();
    final data = userDoc.data();
    final remaining =
        List<String>.from(data?['boats'] as List? ?? [])..remove(boatId);
    final Map<String, dynamic> update = {
      'boats': FieldValue.arrayRemove([boatId]),
    };
    if (data?['activeBoatId'] == boatId) {
      update['activeBoatId'] = remaining.isNotEmpty ? remaining.first : null;
    }
    await _db
        .collection('users')
        .doc(ownerUid)
        .set(update, SetOptions(merge: true));
  }

  /// Deletes every Firestore document and user data associated with [uid].
  /// Owned boats are fully wiped; guest-only boats remove the member entry.
  /// Does NOT delete the Firebase Auth account — call that separately.
  Future<void> deleteUserAndAllBoats(String uid) async {
    final userDoc = await _db.collection('users').doc(uid).get();
    final boatIds =
        List<String>.from(userDoc.data()?['boats'] as List? ?? []);

    for (final boatId in boatIds) {
      try {
        final memberDoc = await _db
            .collection('boats')
            .doc(boatId)
            .collection('members')
            .doc(uid)
            .get();
        final role = memberDoc.data()?['role'] as String?;
        if (role == 'owner') {
          await deleteBoat(boatId, uid);
        } else {
          // Guest: just remove self from the boat.
          await _db
              .collection('boats')
              .doc(boatId)
              .collection('members')
              .doc(uid)
              .delete();
        }
      } catch (_) {}
    }

    // Delete the user profile document.
    try {
      await _db.collection('users').doc(uid).delete();
    } catch (_) {}
  }

  /// Deletes all documents in [col] in chunks to stay within Firestore's
  /// 500-write-per-batch limit.
  Future<void> _deleteCollectionInChunks(
      CollectionReference<Map<String, dynamic>> col) async {
    const chunkSize = 400;
    while (true) {
      final snap = await col.limit(chunkSize).get();
      if (snap.docs.isEmpty) break;
      final batch = _db.batch();
      for (final doc in snap.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
      if (snap.docs.length < chunkSize) break;
    }
  }

  // ── Member queries ─────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> listMembers(String boatId) async {
    final snap = await _db
        .collection('boats')
        .doc(boatId)
        .collection('members')
        .get();
    return snap.docs.map((d) => {...d.data(), 'uid': d.id}).toList();
  }

  Future<bool> isMember(String boatId, String uid) async {
    final doc = await _db
        .collection('boats')
        .doc(boatId)
        .collection('members')
        .doc(uid)
        .get();
    return doc.exists;
  }

  // ── Backward-compatible aliases (used by settings screen) ─────────────────

  /// Alias for [findByShareCode] — queries shareCode field.
  Future<String?> findBoatByInviteCode(String code) => findByShareCode(code);

  /// Alias for [getActiveBoatId].
  Future<String?> getBoatIdForUser(String uid) => getActiveBoatId(uid);
}
