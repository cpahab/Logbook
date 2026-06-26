import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Runs one-time Firestore data migrations for the signed-in user.
///
/// Each migration is idempotent and gated by a flag stored in
/// `users/{uid}.completedMigrations.{migrationId}`. Once the flag is set the
/// migration is never attempted again, even if the document scan returns
/// nothing to change.
///
/// Call [runAll] once per login session, after Firestore connectivity is
/// confirmed (i.e. from within _initFirestore in main.dart).
class MigrationService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Future<void> runAll(String uid) async {
    try {
      await _stripParticipantsList(uid);
    } catch (e) {
      // Migrations are best-effort. A failure here is non-fatal; it will
      // retry on the next launch (flag is only set after success).
      if (kDebugMode) debugPrint('MigrationService: error during migration: $e');
    }
  }

  // ── Migration: strip retired `participantsList` field from all entries ──────
  //
  // `participantsList` (Hive field index 13) was retired in favour of the
  // `crew:` sentinel in timeline entries. Writing stopped, but old Firestore
  // documents still carry the stale key. This migration removes it from all
  // entry documents across every logbook the user belongs to.
  //
  // Migration ID: stripParticipantsList
  Future<void> _stripParticipantsList(String uid) async {
    const migrationId = 'stripParticipantsList';
    final userRef = _db.collection('users').doc(uid);

    // Check whether this migration has already run for this user.
    final userDoc = await userRef.get();
    final completed =
        (userDoc.data()?['completedMigrations'] as Map<String, dynamic>?)?[migrationId] as bool? ?? false;
    if (completed) return;

    final logbookIds = List<String>.from(
        userDoc.data()?['logbooks'] as List? ?? []);

    for (final logbookId in logbookIds) {
      final entriesRef = _db
          .collection('logbooks')
          .doc(logbookId)
          .collection('entries');

      // Query only documents that still carry the stale field.
      final snap = await entriesRef
          .where('participantsList', isNull: false)
          .get();

      if (snap.docs.isEmpty) continue;

      // Firestore batch limit is 500 writes; chunk to stay within it.
      const chunkSize = 400;
      for (var i = 0; i < snap.docs.length; i += chunkSize) {
        final batch = _db.batch();
        final chunk = snap.docs.skip(i).take(chunkSize);
        for (final doc in chunk) {
          batch.update(doc.reference, {'participantsList': FieldValue.delete()});
        }
        await batch.commit();
      }

      if (kDebugMode) {
        debugPrint(
            'MigrationService [$migrationId]: removed participantsList from '
            '${snap.docs.length} entries in logbook $logbookId');
      }
    }

    // Mark migration complete so it never runs again.
    await userRef.set(
      {'completedMigrations': {migrationId: true}},
      SetOptions(merge: true),
    );
  }
}
