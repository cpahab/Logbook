import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart' show DateTimeRange;
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:archive/archive.dart';
import 'package:logbook/core/services/backup_service.dart';
import 'package:logbook/features/emergency/data/emergency_repository.dart';
import 'package:logbook/features/emergency/domain/emergency_contact.dart';
import 'package:logbook/features/home/data/home_repository.dart';
import 'package:logbook/features/home/domain/crew_member.dart';
import 'package:logbook/features/home/domain/daily_track.dart';
import 'package:logbook/features/home/domain/day_entry.dart';
import 'package:logbook/features/home/domain/timeline_amendment.dart';
import 'package:logbook/features/home/domain/timeline_entry.dart';
import 'package:logbook/features/home/domain/track_point.dart';
import 'package:logbook/features/settings/domain/theme_provider.dart';

import 'test_helpers/secure_storage_mock.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    mockSecureStorage();
    tempDir = await Directory.systemTemp.createTemp('backup_service_test_');
    Hive.init(tempDir.path);
    if (!Hive.isAdapterRegistered(11)) Hive.registerAdapter(DayEntryAdapter());
    if (!Hive.isAdapterRegistered(2)) Hive.registerAdapter(TimelineEntryAdapter());
    if (!Hive.isAdapterRegistered(14)) Hive.registerAdapter(TimelineAmendmentAdapter());
    if (!Hive.isAdapterRegistered(3)) Hive.registerAdapter(DailyTrackAdapter());
    if (!Hive.isAdapterRegistered(4)) Hive.registerAdapter(TrackPointAdapter());
    if (!Hive.isAdapterRegistered(12)) Hive.registerAdapter(CrewMemberAdapter());
    if (!Hive.isAdapterRegistered(13)) Hive.registerAdapter(EmergencyContactAdapter());
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('exportBackup includes vessel info in data.json', () async {
    final home = HomeRepository();
    await home.init();
    final emergency = EmergencyRepository();
    await emergency.init();
    final theme = ThemeProvider();
    await theme.init();

    theme.setVesselName('Sea Breeze');
    theme.setVesselMmsi('123456789');
    theme.setVesselCallSign('ABCD1');
    theme.setLifeRaftInfo('6-person, aft locker');
    theme.setEpirbInfo('Cat 1, port cockpit locker');
    theme.setFireSuppInfo('Engine bay, automatic');

    final bytes = await BackupService.exportBackup(
      home: home,
      emergency: emergency,
      theme: theme,
      logbookId: 'logbook-1',
      logbookName: 'Logbook',
      appVersion: '1.0.0+1',
    );

    final archive = ZipDecoder().decodeBytes(bytes);
    final dataFile = archive.findFile('data.json');
    expect(dataFile, isNotNull, reason: 'data.json must exist in the export');

    final data = json.decode(utf8.decode(dataFile!.content as List<int>))
        as Map<String, dynamic>;

    expect(data.containsKey('vessel'), isTrue,
        reason: 'data.json is missing the "vessel" key entirely');
    final vessel = data['vessel'] as Map<String, dynamic>;
    expect(vessel['vesselName'], 'Sea Breeze');
    expect(vessel['vesselMmsi'], '123456789');
    expect(vessel['vesselCallSign'], 'ABCD1');
    expect(vessel['lifeRaftInfo'], '6-person, aft locker');
    expect(vessel['epirbInfo'], 'Cat 1, port cockpit locker');
    expect(vessel['fireSuppInfo'], 'Engine bay, automatic');
  });

  test('restoreBackup round-trips vessel info back into ThemeProvider', () async {
    final home = HomeRepository();
    await home.init();
    final emergency = EmergencyRepository();
    await emergency.init();
    final theme = ThemeProvider();
    await theme.init();
    theme.setVesselName('Sea Breeze');
    theme.setVesselMmsi('123456789');

    final bytes = await BackupService.exportBackup(
      home: home,
      emergency: emergency,
      theme: theme,
      logbookId: 'logbook-1',
      logbookName: 'Logbook',
      appVersion: '1.0.0+1',
    );

    // Simulate a fresh device/logbook: blank vessel info before restoring.
    theme.setVesselName('');
    theme.setVesselMmsi('');
    expect(theme.vesselName, '');

    await BackupService.restoreBackup(
      zipBytes: bytes,
      home: home,
      emergency: emergency,
      theme: theme,
      mode: BackupImportMode.replace,
    );

    expect(theme.vesselName, 'Sea Breeze');
    expect(theme.vesselMmsi, '123456789');
  });

  test('exportBackup with a dateRange only includes entries inside it, but '
      'roster/contacts/vessel stay in full', () async {
    final home = HomeRepository();
    await home.init();
    home.addEntry(DateTime(2024, 1, 1));   // outside the range
    home.addEntry(DateTime(2024, 6, 15));  // inside the range
    final emergency = EmergencyRepository();
    await emergency.init();
    final theme = ThemeProvider();
    await theme.init();
    theme.setVesselName('Sea Breeze');

    final bytes = await BackupService.exportBackup(
      home: home,
      emergency: emergency,
      theme: theme,
      logbookId: 'logbook-1',
      logbookName: 'Logbook',
      appVersion: '1.0.0+1',
      dateRange: DateTimeRange(
          start: DateTime(2024, 6, 1), end: DateTime(2024, 6, 30)),
    );

    final archive = ZipDecoder().decodeBytes(bytes);
    final manifest = json.decode(
        utf8.decode(archive.findFile('manifest.json')!.content as List<int>)) as Map<String, dynamic>;
    final data = json.decode(
        utf8.decode(archive.findFile('data.json')!.content as List<int>)) as Map<String, dynamic>;

    expect(manifest.containsKey('exportRange'), isTrue,
        reason: 'a partial export must record its range in the manifest — '
            'restoreBackup relies on this to scope tombstoning correctly');
    final entries = data['entries'] as List;
    expect(entries.length, 1,
        reason: 'only the entry inside the date range should be exported');
    expect(data['vessel'], isNotNull,
        reason: 'vessel info is never date-filtered');
  });

  test('exportBackup with no dateRange omits exportRange from the manifest '
      'entirely (matches today\'s full-export behavior exactly)', () async {
    final home = HomeRepository();
    await home.init();
    final emergency = EmergencyRepository();
    await emergency.init();
    final theme = ThemeProvider();
    await theme.init();

    final bytes = await BackupService.exportBackup(
      home: home,
      emergency: emergency,
      theme: theme,
      logbookId: 'logbook-1',
      logbookName: 'Logbook',
      appVersion: '1.0.0+1',
    );

    final archive = ZipDecoder().decodeBytes(bytes);
    final manifest = json.decode(
        utf8.decode(archive.findFile('manifest.json')!.content as List<int>)) as Map<String, dynamic>;
    expect(manifest.containsKey('exportRange'), isFalse);
  });

  test('restoreBackup in update mode only merges day entries — vessel info '
      'already present locally is left completely untouched', () async {
    final home = HomeRepository();
    await home.init();
    final emergency = EmergencyRepository();
    await emergency.init();
    final theme = ThemeProvider();
    await theme.init();
    theme.setVesselName('Backup Boat');

    final bytes = await BackupService.exportBackup(
      home: home,
      emergency: emergency,
      theme: theme,
      logbookId: 'logbook-1',
      logbookName: 'Logbook',
      appVersion: '1.0.0+1',
    );

    // A different logbook/device already has its own vessel name set —
    // "update" mode must never overwrite this with the backup's.
    theme.setVesselName('Current Boat');

    await BackupService.restoreBackup(
      zipBytes: bytes,
      home: home,
      emergency: emergency,
      theme: theme,
      mode: BackupImportMode.update,
    );

    expect(theme.vesselName, 'Current Boat');
  });

  test('restoreBackup in update mode adds a backup-only entry without '
      'touching an existing, unrelated local entry', () async {
    final home = HomeRepository();
    await home.init();
    home.addEntry(DateTime(2024, 1, 1));
    final emergency = EmergencyRepository();
    await emergency.init();
    final theme = ThemeProvider();
    await theme.init();

    final bytes = await BackupService.exportBackup(
      home: home,
      emergency: emergency,
      theme: theme,
      logbookId: 'logbook-1',
      logbookName: 'Logbook',
      appVersion: '1.0.0+1',
    );

    // A fresh local entry the backup never saw — must survive an update-mode
    // restore of a backup taken before it existed.
    home.addEntry(DateTime(2024, 2, 1));

    await BackupService.restoreBackup(
      zipBytes: bytes,
      home: home,
      emergency: emergency,
      theme: theme,
      mode: BackupImportMode.update,
    );

    expect(home.getEntry(DateTime(2024, 1, 1)), isNotNull);
    expect(home.getEntry(DateTime(2024, 2, 1)), isNotNull);
  });

  group('previewUpdate / applyUpdate (interactive "update" mode — the '
      'conflict screen, not the silent auto-merge path)', () {
    test('previewUpdate splits entries into pure additions vs. genuine '
        'conflicts', () async {
      final home = HomeRepository();
      await home.init();
      home.addEntry(DateTime(2024, 1, 1)); // will conflict with the backup
      final emergency = EmergencyRepository();
      await emergency.init();
      final theme = ThemeProvider();
      await theme.init();

      final bytes = await BackupService.exportBackup(
        home: home, emergency: emergency, theme: theme,
        logbookId: 'logbook-1', logbookName: 'Logbook', appVersion: '1.0.0+1',
      );

      // A backup-only date the current logbook has never seen.
      home.addEntry(DateTime(2024, 3, 1));

      final preview = await BackupService.previewUpdate(zipBytes: bytes, home: home);

      expect(preview.additions, isEmpty,
          reason: '2024-01-01 is the only date in the backup, and it already '
              'exists locally — so it must show up as a conflict, not an addition');
      expect(preview.conflicts, hasLength(1));
      expect(preview.conflicts.single.backup.entry.date, DateTime(2024, 1, 1));
    });

    test('applyUpdate applies additions unconditionally, regardless of the '
        'useBackup list (which only covers conflicts)', () async {
      final home = HomeRepository();
      await home.init();
      final emergency = EmergencyRepository();
      await emergency.init();
      final theme = ThemeProvider();
      await theme.init();

      final bytes = await BackupService.exportBackup(
        home: home, emergency: emergency, theme: theme,
        logbookId: 'logbook-1', logbookName: 'Logbook', appVersion: '1.0.0+1',
      );
      home.addEntry(DateTime(2024, 4, 1)); // added after export, unrelated

      final preview = await BackupService.previewUpdate(zipBytes: bytes, home: home);
      await BackupService.applyUpdate(
        home: home,
        additions: preview.additions,
        conflicts: preview.conflicts,
        resolutions: const [],
        photoBytesByFilename: preview.photoBytesByFilename,
      );

      expect(home.getEntry(DateTime(2024, 4, 1)), isNotNull);
    });

    test('applyUpdate only overwrites a conflicting day if its resolution '
        'says to use backup fields', () async {
      final home = HomeRepository();
      await home.init();
      home.addEntry(DateTime(2024, 1, 1));
      final current = home.getEntry(DateTime(2024, 1, 1))!;
      current.notes = 'current notes';
      home.saveEntry(current, changedFields: {'notes'});
      final emergency = EmergencyRepository();
      await emergency.init();
      final theme = ThemeProvider();
      await theme.init();

      final bytes = await BackupService.exportBackup(
        home: home, emergency: emergency, theme: theme,
        logbookId: 'logbook-1', logbookName: 'Logbook', appVersion: '1.0.0+1',
      );

      final preview = await BackupService.previewUpdate(zipBytes: bytes, home: home);
      expect(preview.conflicts, hasLength(1));

      // User explicitly chooses to keep their own version despite whatever
      // the computed default suggested.
      await BackupService.applyUpdate(
        home: home,
        additions: preview.additions,
        conflicts: preview.conflicts,
        resolutions: [
          ConflictResolution(useBackupFields: false, timeline: preview.conflicts.single.current.timeline),
        ],
        photoBytesByFilename: preview.photoBytesByFilename,
      );

      expect(home.getEntry(DateTime(2024, 1, 1))!.notes, 'current notes');
    });

    test('applyUpdate overwrites a conflicting day when its resolution uses backup fields '
        'for it, even overriding a suggested default that pointed the '
        'other way', () async {
      final home = HomeRepository();
      await home.init();
      final emergency = EmergencyRepository();
      await emergency.init();
      final theme = ThemeProvider();
      await theme.init();
      home.addEntry(DateTime(2024, 1, 1));
      final original = home.getEntry(DateTime(2024, 1, 1))!;
      original.notes = 'original notes';
      home.saveEntry(original, changedFields: {'notes'});

      // Backup captures "original notes" at this point in time.
      final bytes = await BackupService.exportBackup(
        home: home, emergency: emergency, theme: theme,
        logbookId: 'logbook-1', logbookName: 'Logbook', appVersion: '1.0.0+1',
      );

      // A later local edit — the backup is now the *older* version, so the
      // computed default should prefer current, not the backup.
      await Future.delayed(const Duration(milliseconds: 10));
      final edited = home.getEntry(DateTime(2024, 1, 1))!;
      edited.notes = 'edited after backup';
      home.saveEntry(edited, changedFields: {'notes'});

      final preview = await BackupService.previewUpdate(zipBytes: bytes, home: home);
      expect(preview.conflicts.single.backupWinsByDefault, isFalse,
          reason: 'the backup is older than the current local edit, so the '
              'computed default must not prefer it');

      // User overrides the suggested default and picks the (older) backup
      // anyway — applyUpdate must honor that explicit choice.
      await BackupService.applyUpdate(
        home: home,
        additions: preview.additions,
        conflicts: preview.conflicts,
        resolutions: [
          ConflictResolution(useBackupFields: true, timeline: preview.conflicts.single.backup.entry.timeline),
        ],
        photoBytesByFilename: preview.photoBytesByFilename,
      );

      expect(home.getEntry(DateTime(2024, 1, 1))!.notes, 'original notes');
    });

    test('previewUpdate with a dateRange ignores entries outside it — '
        'neither as additions nor as conflicts', () async {
      final home = HomeRepository();
      await home.init();
      home.addEntry(DateTime(2024, 1, 1)); // will conflict, but is outside the chosen range
      final emergency = EmergencyRepository();
      await emergency.init();
      final theme = ThemeProvider();
      await theme.init();

      final bytes = await BackupService.exportBackup(
        home: home, emergency: emergency, theme: theme,
        logbookId: 'logbook-1', logbookName: 'Logbook', appVersion: '1.0.0+1',
      );
      home.addEntry(DateTime(2024, 3, 1)); // a backup-only addition, also outside the range

      final preview = await BackupService.previewUpdate(
        zipBytes: bytes,
        home: home,
        dateRange: DateTimeRange(start: DateTime(2024, 6, 1), end: DateTime(2024, 6, 30)),
      );

      expect(preview.additions, isEmpty);
      expect(preview.conflicts, isEmpty);
    });

    test('applyUpdate saves a merged timeline built from individually '
        'selected entries on both sides, not just one side wholesale', () async {
      final home = HomeRepository();
      await home.init();
      home.addEntry(DateTime(2024, 1, 1));
      home.addTimelineEntry(
          DateTime(2024, 1, 1), TimelineEntry(time: DateTime(2024, 1, 1, 8), remarks: 'shared-morning'));
      final emergency = EmergencyRepository();
      await emergency.init();
      final theme = ThemeProvider();
      await theme.init();

      // Backup captures just the 08:00 entry.
      final bytes = await BackupService.exportBackup(
        home: home, emergency: emergency, theme: theme,
        logbookId: 'logbook-1', logbookName: 'Logbook', appVersion: '1.0.0+1',
      );

      // After export: the 08:00 entry is edited locally, and a second,
      // backup-unseen entry is added at 14:00.
      final current = home.getEntry(DateTime(2024, 1, 1))!;
      current.timeline[0].remarks = 'mine-edited-morning';
      current.timeline.add(TimelineEntry(time: DateTime(2024, 1, 1, 14), remarks: 'mine-afternoon'));
      home.saveEntry(current, changedFields: {'timeline'});

      final preview = await BackupService.previewUpdate(zipBytes: bytes, home: home);
      expect(preview.conflicts, hasLength(1));
      final conflict = preview.conflicts.single;
      expect(conflict.backup.entry.timeline, hasLength(1));
      expect(conflict.current.timeline, hasLength(2));

      // Hand-pick a merge that takes the *backup's* original 08:00 entry
      // (not the locally-edited one) plus the current's own 14:00 entry —
      // proof the merged timeline genuinely draws from both sides rather
      // than falling back to one side wholesale.
      final merged = [
        conflict.backup.entry.timeline[0], // 08:00, 'shared-morning'
        conflict.current.timeline[1], // 14:00, 'mine-afternoon'
      ]..sort((a, b) => a.time.compareTo(b.time));

      await BackupService.applyUpdate(
        home: home,
        additions: preview.additions,
        conflicts: preview.conflicts,
        resolutions: [ConflictResolution(useBackupFields: false, timeline: merged)],
        photoBytesByFilename: preview.photoBytesByFilename,
      );

      final result = home.getEntry(DateTime(2024, 1, 1))!.timeline;
      expect(result.map((e) => e.remarks), ['shared-morning', 'mine-afternoon']);
    });
  });
}
