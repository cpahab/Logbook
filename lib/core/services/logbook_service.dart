import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'storage_service.dart';

/// Manages logbook identity and membership.
///
/// Firestore layout:
///   users/{uid}                        { activeLogbookId, logbooks: [] }
///   logbooks/{logbookId}               { name, ownerUid, shareCode, createdAt }
///   logbooks/{logbookId}/members/{uid} { role: 'owner'|'guest', joinedAt }
class LogbookService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ── Create ─────────────────────────────────────────────────────────────────

  /// Creates a new logbook for [uid] with the given [name]. Adds it to
  /// [uid]'s logbook list but deliberately does NOT set it as their active
  /// logbook — the caller must do that itself (via [setActiveLogbook]) only
  /// after confirming the local switch actually succeeded
  /// (HomeRepository.reattachAndSync can fail, e.g. right after creation
  /// before Storage's membership check has propagated). Otherwise the
  /// server would believe this new logbook is active while the app stays on
  /// the previous one locally — exactly the inconsistency that let stale
  /// data leak into a "new" logbook on a later reattach.
  /// [displayName]/[email] (from the caller's own auth profile) are stored on
  /// the member doc so the manage-guests list can show a name instead of a
  /// truncated uid — see [joinLogbook].
  /// Returns the new logbookId.
  Future<String> createLogbook(String uid, String name,
      {String? displayName, String? email}) async {
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
      {
        'logbookId': logbookId,
        // The join flow can read this lookup document before the caller is a
        // member, while the logbook document itself remains member-only.
        'name': name,
      },
    );
    batch.set(
      logbookRef.collection('members').doc(uid),
      {
        'role': 'owner',
        'joinedAt': FieldValue.serverTimestamp(),
        if (displayName != null && displayName.isNotEmpty) 'displayName': displayName,
        if (email != null && email.isNotEmpty) 'email': email,
      },
    );
    batch.set(
      _db.collection('users').doc(uid),
      {'logbooks': FieldValue.arrayUnion([logbookId])},
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
  ///
  /// Fetches each id independently (rather than one big `Future.wait` over
  /// every id) so a single stale id — one this uid was removed from by its
  /// owner, who has no permission to also clean up this uid's own
  /// `logbooks` array (see [removeMember]'s doc comment) — can't take the
  /// whole call down with a permission-denied. Any such stale ids found are
  /// dropped from [uid]'s own array afterward: this *is* something the
  /// current uid can write, unlike whoever removed them.
  Future<List<Map<String, dynamic>>> listLogbooks(String uid) async {
    final userDoc = await _db.collection('users').doc(uid).get();
    final logbookIds = List<String>.from(
        userDoc.data()?['logbooks'] as List? ?? []);

    if (logbookIds.isEmpty) return [];

    final fetched = await Future.wait(logbookIds.map((id) async {
      try {
        final logbookDoc = await _db.collection('logbooks').doc(id).get();
        final memberDoc = await _db
            .collection('logbooks')
            .doc(id)
            .collection('members')
            .doc(uid)
            .get();
        if (!logbookDoc.exists || !memberDoc.exists) return null;
        final data = logbookDoc.data()!;
        return {
          'logbookId': id,
          'name': data['name'] as String? ?? '',
          'role': memberDoc.data()?['role'] as String? ?? 'guest',
          'shareCode': data['shareCode'] as String? ?? '',
        };
      } catch (_) {
        return null;
      }
    }));

    final stale = [
      for (var i = 0; i < logbookIds.length; i++)
        if (fetched[i] == null) logbookIds[i]
    ];
    if (stale.isNotEmpty) {
      unawaited(_db.collection('users').doc(uid).set(
        {'logbooks': FieldValue.arrayRemove(stale)},
        SetOptions(merge: true),
      ).catchError((_) {}));
    }

    return fetched.whereType<Map<String, dynamic>>().toList();
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

  /// Returns the display name stored with [shareCode], or null for an older
  /// share-code document that predates name metadata.
  Future<String?> getLogbookNameByShareCode(String shareCode) async {
    final doc = await _db.collection('shareCodes').doc(shareCode).get();
    return doc.data()?['name'] as String?;
  }

  // ── Join / Remove ──────────────────────────────────────────────────────────

  /// Adds [uid] to [logbookId] as a guest. Deliberately does NOT set it as
  /// their active logbook — see [createLogbook]'s doc comment for why the
  /// caller must defer that (via [setActiveLogbook]) until after confirming
  /// the local switch succeeded.
  /// [displayName]/[email] (from the caller's own auth profile) are stored on
  /// the member doc so the owner's manage-guests list can show a name
  /// instead of a truncated uid.
  Future<void> joinLogbook(String logbookId, String uid,
      {String? displayName, String? email}) async {
    final batch = _db.batch();
    batch.set(
      _db
          .collection('logbooks')
          .doc(logbookId)
          .collection('members')
          .doc(uid),
      {
        'role': 'guest',
        'joinedAt': FieldValue.serverTimestamp(),
        if (displayName != null && displayName.isNotEmpty) 'displayName': displayName,
        if (email != null && email.isNotEmpty) 'email': email,
      },
    );
    batch.set(
      _db.collection('users').doc(uid),
      {'logbooks': FieldValue.arrayUnion([logbookId])},
      SetOptions(merge: true),
    );
    await batch.commit();
  }

  /// Removes [uid] from [logbookId]. Updates [uid]'s own `logbooks`
  /// array/activeLogbookId if needed — but only when [uid] is the caller
  /// themselves (leaving voluntarily): `users/{uid}` is only writable (and
  /// readable) by that same uid under the security rules, so when an owner
  /// removes a *different* member, this best-effort cleanup silently
  /// fails and the removed member's own profile keeps the stale
  /// logbookId. That's fine: [listLogbooks] self-heals it — the removed
  /// member's own client, which *can* write its own profile, drops any
  /// logbookId it's no longer actually a member of the next time it reads
  /// its list. The member-doc deletion above (the actually load-bearing
  /// effect) always succeeds regardless, since the owner does have
  /// permission for that.
  Future<void> removeMember(String logbookId, String uid) async {
    await _db
        .collection('logbooks')
        .doc(logbookId)
        .collection('members')
        .doc(uid)
        .delete();

    try {
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
    } catch (_) {}
  }

  // ── Code generation ────────────────────────────────────────────────────────

  static String _generateShareCode() {
    // Excludes I, O, 0, 1 — visually ambiguous when someone reads the code
    // aloud or types it in by hand.
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
    final name = logbookDoc.data()?['name'] as String? ?? '';

    final newCode = _generateShareCode();
    final batch = _db.batch();
    batch.update(
        _db.collection('logbooks').doc(logbookId), {'shareCode': newCode});
    batch.set(
        _db.collection('shareCodes').doc(newCode),
        {'logbookId': logbookId, 'name': name});
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

    // Delete known meta documents in a single batch so any failure surfaces
    // to the caller rather than being silently swallowed.
    final metaBatch = _db.batch();
    for (final id in ['settings', 'contacts', 'ui', 'crew_roster']) {
      metaBatch.delete(logbookRef.collection('meta').doc(id));
    }
    await metaBatch.commit();

    // Delete all members + the logbook doc itself.
    final membersSnap = await logbookRef.collection('members').get();
    final batch = _db.batch();
    for (final doc in membersSnap.docs) {
      batch.delete(doc.reference);
    }
    batch.delete(logbookRef);
    await batch.commit();

    // Delete all files in Storage (best-effort — orphaned files are not critical).
    try {
      await StorageService.deleteLogbookFolder(logbookId);
    } catch (_) {}

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
  ///
  /// Throws an [Exception] if any Firestore operation fails, so the caller can
  /// abort the Auth account deletion and inform the user.
  Future<void> deleteUserAndAllLogbooks(String uid) async {
    final userDoc = await _db.collection('users').doc(uid).get();
    final logbookIds =
        List<String>.from(userDoc.data()?['logbooks'] as List? ?? []);

    var failures = 0;
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
      } catch (_) {
        failures++;
      }
    }

    try {
      await _db.collection('users').doc(uid).delete();
    } catch (_) {
      failures++;
    }

    if (failures > 0) {
      throw Exception(
          '$failures Firestore document(s) could not be deleted.');
    }
  }

  Future<void> _deleteCollectionInChunks(
      CollectionReference<Map<String, dynamic>> col) async {
    const chunkSize = 400; // stays under Firestore's 500-write batch limit
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
