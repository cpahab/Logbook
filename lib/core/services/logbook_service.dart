import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

/// Manages logbook identity and membership.
///
/// Firestore layout:
///   users/{uid}                        { activeLogbookId, logbooks: [] }
///   logbooks/{logbookId}               { name, ownerUid, shareCode, createdAt }
///   logbooks/{logbookId}/members/{uid} { role: 'owner'|'guest', joinedAt }
class LogbookService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ── Create ─────────────────────────────────────────────────────────────────

  /// Creates a new logbook for [uid] with the given [name].
  /// Returns the new logbookId.
  Future<String> createLogbook(String uid, String name) async {
    final logbookRef = _db.collection('logbooks').doc();
    final logbookId = logbookRef.id;
    final shareCode = _generateShareCode();

    await logbookRef.set({
      'name': name,
      'ownerUid': uid,
      'shareCode': shareCode,
      'createdAt': FieldValue.serverTimestamp(),
    });

    final batch = _db.batch();
    batch.set(
      _db.collection('shareCodes').doc(shareCode),
      {'logbookId': logbookId},
    );
    batch.set(
      logbookRef.collection('members').doc(uid),
      {'role': 'owner', 'joinedAt': FieldValue.serverTimestamp()},
    );
    batch.set(
      _db.collection('users').doc(uid),
      {
        'activeLogbookId': logbookId,
        'logbooks': FieldValue.arrayUnion([logbookId]),
      },
      SetOptions(merge: true),
    );
    await batch.commit();

    return logbookId;
  }

  // ── Read ───────────────────────────────────────────────────────────────────

  /// Returns the active logbookId for [uid], or null if no profile exists.
  Future<String?> getActiveLogbookId(String uid) async {
    final doc = await _db.collection('users').doc(uid).get();
    return doc.data()?['activeLogbookId'] as String?;
  }

  /// Returns the list of logbooks accessible to [uid] with metadata.
  /// Each map contains: logbookId, name, role, shareCode.
  Future<List<Map<String, dynamic>>> listLogbooks(String uid) async {
    final userDoc = await _db.collection('users').doc(uid).get();
    final logbookIds = List<String>.from(
        userDoc.data()?['logbooks'] as List? ?? []);

    final result = <Map<String, dynamic>>[];
    for (final logbookId in logbookIds) {
      final logbookDoc =
          await _db.collection('logbooks').doc(logbookId).get();
      if (!logbookDoc.exists) continue;
      final data = logbookDoc.data()!;

      final memberDoc = await _db
          .collection('logbooks')
          .doc(logbookId)
          .collection('members')
          .doc(uid)
          .get();
      final role = memberDoc.data()?['role'] as String? ?? 'guest';

      result.add({
        'logbookId': logbookId,
        'name': data['name'] as String? ?? '',
        'role': role,
        'shareCode': data['shareCode'] as String? ?? '',
      });
    }
    return result;
  }

  // ── Update ─────────────────────────────────────────────────────────────────

  /// Sets [logbookId] as the active logbook for [uid].
  Future<void> setActiveLogbook(String uid, String logbookId) =>
      _db.collection('users').doc(uid).set(
            {'activeLogbookId': logbookId},
            SetOptions(merge: true),
          );

  // ── Share code lookup ──────────────────────────────────────────────────────

  /// Finds a logbook by its [shareCode]. Returns the logbookId or null.
  Future<String?> findByShareCode(String shareCode) async {
    final doc = await _db.collection('shareCodes').doc(shareCode).get();
    return doc.data()?['logbookId'] as String?;
  }

  // ── Join / Remove ──────────────────────────────────────────────────────────

  /// Adds [uid] to [logbookId] as a guest and sets it as their active logbook.
  Future<void> joinLogbook(String logbookId, String uid) async {
    final batch = _db.batch();
    batch.set(
      _db
          .collection('logbooks')
          .doc(logbookId)
          .collection('members')
          .doc(uid),
      {'role': 'guest', 'joinedAt': FieldValue.serverTimestamp()},
    );
    batch.set(
      _db.collection('users').doc(uid),
      {
        'activeLogbookId': logbookId,
        'logbooks': FieldValue.arrayUnion([logbookId]),
      },
      SetOptions(merge: true),
    );
    await batch.commit();
  }

  /// Removes [uid] from [logbookId]. Updates activeLogbookId if needed.
  Future<void> removeMember(String logbookId, String uid) async {
    await _db
        .collection('logbooks')
        .doc(logbookId)
        .collection('members')
        .doc(uid)
        .delete();

    final userDoc = await _db.collection('users').doc(uid).get();
    final data = userDoc.data();
    final remaining =
        List<String>.from(data?['logbooks'] as List? ?? [])
          ..remove(logbookId);

    final Map<String, dynamic> update = {
      'logbooks': FieldValue.arrayRemove([logbookId]),
    };
    if (data?['activeLogbookId'] == logbookId) {
      update['activeLogbookId'] =
          remaining.isNotEmpty ? remaining.first : null;
    }

    await _db
        .collection('users')
        .doc(uid)
        .set(update, SetOptions(merge: true));
  }

  // ── Code generation ────────────────────────────────────────────────────────

  static String _generateShareCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rand = Random.secure();
    return List.generate(8, (_) => chars[rand.nextInt(chars.length)]).join();
  }

  // ── Name lookup ───────────────────────────────────────────────────────────

  Future<String?> getLogbookName(String logbookId) async {
    final doc = await _db.collection('logbooks').doc(logbookId).get();
    return doc.data()?['name'] as String?;
  }

  // ── Rename / regenerate ────────────────────────────────────────────────────

  Future<void> renameLogbook(String logbookId, String name) =>
      _db.collection('logbooks').doc(logbookId).update({'name': name});

  Future<String> regenerateShareCode(String logbookId) async {
    final logbookDoc =
        await _db.collection('logbooks').doc(logbookId).get();
    final oldCode = logbookDoc.data()?['shareCode'] as String?;

    final newCode = _generateShareCode();
    final batch = _db.batch();
    batch.update(
        _db.collection('logbooks').doc(logbookId), {'shareCode': newCode});
    batch.set(
        _db.collection('shareCodes').doc(newCode), {'logbookId': logbookId});
    if (oldCode != null) {
      batch.delete(_db.collection('shareCodes').doc(oldCode));
    }
    await batch.commit();
    return newCode;
  }

  // ── Delete ─────────────────────────────────────────────────────────────────

  Future<void> deleteLogbook(String logbookId, String ownerUid) async {
    final logbookRef = _db.collection('logbooks').doc(logbookId);

    // Clean up the shareCode lookup entry.
    final logbookDoc = await logbookRef.get();
    final shareCode = logbookDoc.data()?['shareCode'] as String?;
    if (shareCode != null) {
      await _db.collection('shareCodes').doc(shareCode).delete();
    }

    // Delete all entries (may be large — chunked).
    await _deleteCollectionInChunks(logbookRef.collection('entries'));

    // Delete known meta documents.
    for (final id in ['settings', 'contacts', 'ui', 'crew_roster']) {
      try {
        await logbookRef.collection('meta').doc(id).delete();
      } catch (_) {}
    }

    // Delete all members + the logbook doc itself.
    final membersSnap = await logbookRef.collection('members').get();
    final batch = _db.batch();
    for (final doc in membersSnap.docs) {
      batch.delete(doc.reference);
    }
    batch.delete(logbookRef);
    await batch.commit();

    // Remove from owner's logbook list.
    final userDoc = await _db.collection('users').doc(ownerUid).get();
    final data = userDoc.data();
    final remaining =
        List<String>.from(data?['logbooks'] as List? ?? [])
          ..remove(logbookId);
    final Map<String, dynamic> update = {
      'logbooks': FieldValue.arrayRemove([logbookId]),
    };
    if (data?['activeLogbookId'] == logbookId) {
      update['activeLogbookId'] =
          remaining.isNotEmpty ? remaining.first : null;
    }
    await _db
        .collection('users')
        .doc(ownerUid)
        .set(update, SetOptions(merge: true));
  }

  /// Deletes every Firestore document and user data associated with [uid].
  /// Owned logbooks are fully wiped; guest-only logbooks remove the member entry.
  /// Does NOT delete the Firebase Auth account — call that separately.
  Future<void> deleteUserAndAllLogbooks(String uid) async {
    final userDoc = await _db.collection('users').doc(uid).get();
    final logbookIds =
        List<String>.from(userDoc.data()?['logbooks'] as List? ?? []);

    for (final logbookId in logbookIds) {
      try {
        final memberDoc = await _db
            .collection('logbooks')
            .doc(logbookId)
            .collection('members')
            .doc(uid)
            .get();
        final role = memberDoc.data()?['role'] as String?;
        if (role == 'owner') {
          await deleteLogbook(logbookId, uid);
        } else {
          await _db
              .collection('logbooks')
              .doc(logbookId)
              .collection('members')
              .doc(uid)
              .delete();
        }
      } catch (_) {}
    }

    try {
      await _db.collection('users').doc(uid).delete();
    } catch (_) {}
  }

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

  Future<List<Map<String, dynamic>>> listMembers(String logbookId) async {
    final snap = await _db
        .collection('logbooks')
        .doc(logbookId)
        .collection('members')
        .get();
    return snap.docs.map((d) => {...d.data(), 'uid': d.id}).toList();
  }

  Future<bool> isMember(String logbookId, String uid) async {
    final doc = await _db
        .collection('logbooks')
        .doc(logbookId)
        .collection('members')
        .doc(uid)
        .get();
    return doc.exists;
  }
}
