// Regression coverage for durable offline deletion (see wiki/next steps.md,
// "Offline deletion is not durable"): entries/tracks used to be removed
// locally with a fire-and-forget, unretried cloud delete, so a failed or
// offline delete could resurrect on the next sync. Deletion is now a
// tombstone field write (deletedAt/trackDeletedAt) that travels through the
// same durable channels a normal edit already does, plus a pending-delete
// marker (retried on every attachFirestore/forceSync/reattachAndSync) for
// the case where there's no local entry left to carry the tombstone.
//
// No Firestore-mocking is used here — HomeRepository is exercised
// unattached (_firestore/_storage stay null), which is enough to verify:
//   (a) local removal + pending-delete bookkeeping happens correctly, and
//   (b) applyIncomingEntry's merge/tombstone-interpretation logic is correct,
// independent of the actual network calls.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:logbook/features/home/data/home_repository.dart';
import 'package:logbook/features/home/domain/crew_member.dart';
import 'package:logbook/features/home/domain/daily_track.dart';
import 'package:logbook/features/home/domain/day_entry.dart';
import 'package:logbook/features/home/domain/timeline_amendment.dart';
import 'package:logbook/features/home/domain/timeline_entry.dart';
import 'package:logbook/features/home/domain/track_point.dart';

import 'test_helpers/secure_storage_mock.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    mockSecureStorage();
    tempDir = await Directory.systemTemp.createTemp('entry_deletion_durability_test_');
    Hive.init(tempDir.path);
    if (!Hive.isAdapterRegistered(11)) Hive.registerAdapter(DayEntryAdapter());
    if (!Hive.isAdapterRegistered(2)) Hive.registerAdapter(TimelineEntryAdapter());
    if (!Hive.isAdapterRegistered(14)) Hive.registerAdapter(TimelineAmendmentAdapter());
    if (!Hive.isAdapterRegistered(3)) Hive.registerAdapter(DailyTrackAdapter());
    if (!Hive.isAdapterRegistered(4)) Hive.registerAdapter(TrackPointAdapter());
    if (!Hive.isAdapterRegistered(12)) Hive.registerAdapter(CrewMemberAdapter());
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  group('removeEntry (unattached — no Firestore/Storage)', () {
    test('removes the entry and track locally; nothing stays pending since '
        'there is no attached service to push to (matches local-mode users, '
        'who never attach one at all)', () async {
      final home = HomeRepository();
      await home.init();
      final date = DateTime(2024, 1, 1);
      home.addEntry(date);
      await home.replaceTrackPoints(date, [
        TrackPoint(lat: 1, lon: 1, time: date),
        TrackPoint(lat: 2, lon: 2, time: date),
      ]);

      await home.removeEntry(date);

      expect(home.getEntry(date), isNull);
      expect(home.dailyTracks.containsKey(date), isFalse);
      expect(home.pendingDeleteDatesForTesting, isNot(contains(date)));
    });
  });

  group('changeEntryDate (unattached)', () {
    test('moves the entry; nothing stays pending for either date since '
        'there is no attached service to push to', () async {
      final home = HomeRepository();
      await home.init();
      final oldDate = DateTime(2024, 1, 1);
      final newDate = DateTime(2024, 1, 2);
      home.addEntry(oldDate);

      final moved = await home.changeEntryDate(oldDate, newDate);

      expect(moved, isTrue);
      expect(home.getEntry(newDate), isNotNull);
      expect(home.getEntry(oldDate), isNull);
      expect(home.pendingDeleteDatesForTesting, isNot(contains(oldDate)));
      expect(home.pendingDeleteDatesForTesting, isNot(contains(newDate)));
    });
  });

  group('applyIncomingEntry', () {
    test('a tombstoned incoming entry (deletedAt set) removes the local entry', () async {
      final home = HomeRepository();
      await home.init();
      final date = DateTime(2024, 1, 1);
      home.addEntry(date);
      expect(home.getEntry(date), isNotNull);

      final incoming = DayEntry(date: date, deletedAt: DateTime.now());
      final changed = await home.applyIncomingEntry(incoming);

      expect(changed, isTrue);
      expect(home.getEntry(date), isNull);
    });

    test('an incoming entry with trackDeletedAt set removes the local track', () async {
      final home = HomeRepository();
      await home.init();
      final date = DateTime(2024, 1, 1);
      home.addEntry(date);
      await home.replaceTrackPoints(date, [
        TrackPoint(lat: 1, lon: 1, time: date),
        TrackPoint(lat: 2, lon: 2, time: date),
      ]);
      expect(home.dailyTracks.containsKey(date), isTrue);

      final incoming = DayEntry(date: date, trackDeletedAt: DateTime.now());
      final changed = await home.applyIncomingEntry(incoming);

      expect(changed, isTrue);
      expect(home.dailyTracks.containsKey(date), isFalse);
      // The entry itself is untouched — only the track was tombstoned.
      expect(home.getEntry(date), isNotNull);
    });

    test('a newer local edit than the incoming updatedAt is not overwritten', () async {
      final home = HomeRepository();
      await home.init();
      final date = DateTime(2024, 1, 1);
      home.addEntry(date);
      final local = home.getEntry(date)!;
      local.notes = 'local edit';
      home.saveEntry(local, changedFields: {'notes'});
      // saveEntry starts a 2s debounce timer; applyIncomingEntry skips any
      // date with one still running (an edit is "about to push"), which
      // would otherwise make this test pass for the wrong reason.
      await Future.delayed(const Duration(seconds: 3));

      // An incoming version whose updatedAt predates the local edit.
      final staleIncoming = DayEntry(
        date: date,
        notes: 'stale remote value',
        updatedAt: DateTime.now().subtract(const Duration(days: 1)),
      );
      final changed = await home.applyIncomingEntry(staleIncoming);

      expect(changed, isFalse);
      expect(home.getEntry(date)!.notes, 'local edit');
    });

    test('returns false when there is nothing to change', () async {
      final home = HomeRepository();
      await home.init();
      final date = DateTime(2024, 1, 1);

      // Incoming delete for a date with no local entry and no local track —
      // both removal branches are no-ops.
      final incoming = DayEntry(date: date, deletedAt: DateTime.now());
      final changed = await home.applyIncomingEntry(incoming);

      expect(changed, isFalse);
    });

    test('respectLocalEdit: false (forceSync) applies the incoming version '
        'even over a newer local edit', () async {
      final home = HomeRepository();
      await home.init();
      final date = DateTime(2024, 1, 1);
      home.addEntry(date);
      final local = home.getEntry(date)!;
      local.notes = 'local edit';
      home.saveEntry(local, changedFields: {'notes'});
      await Future.delayed(const Duration(seconds: 3));

      final remoteWins = DayEntry(
        date: date,
        notes: 'remote wins',
        updatedAt: DateTime.now().subtract(const Duration(days: 1)),
      );
      final changed = await home.applyIncomingEntry(remoteWins, respectLocalEdit: false);

      expect(changed, isTrue);
      expect(home.getEntry(date)!.notes, 'remote wins');
    });
  });

  group('datesToTombstone (restore reconciliation — see wiki "Backup restore '
      'does not actually replace cloud data")', () {
    test('a server entry absent from the restored set is tombstoned', () {
      final serverOnly = DateTime(2024, 1, 1);
      final restored = DateTime(2024, 1, 2);
      final result = HomeRepository.datesToTombstone(
        [DayEntry(date: serverOnly), DayEntry(date: restored)],
        {restored},
      );
      expect(result, {serverOnly});
    });

    test('an already-tombstoned server entry is not tombstoned again', () {
      final date = DateTime(2024, 1, 1);
      final result = HomeRepository.datesToTombstone(
        [DayEntry(date: date, deletedAt: DateTime.now())],
        <DateTime>{},
      );
      expect(result, isEmpty);
    });

    test('a server entry present in the restored set is kept', () {
      final date = DateTime(2024, 1, 1);
      final result = HomeRepository.datesToTombstone(
        [DayEntry(date: date)],
        {date},
      );
      expect(result, isEmpty);
    });
  });

  group('reconcileCloudAfterRestore (unattached)', () {
    test('is a no-op when no cloud service is attached (local-mode users '
        'never restore-reconcile against a cloud they never connected to)',
        () async {
      final home = HomeRepository();
      await home.init();
      final date = DateTime(2024, 1, 1);
      home.addEntry(date);

      await home.reconcileCloudAfterRestore();

      expect(home.getEntry(date), isNotNull);
      expect(home.pendingDeleteDatesForTesting, isEmpty);
    });
  });
}
