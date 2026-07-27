import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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
    // The full live-sync settings snapshot (ThemeProvider.settingsSnapshot),
    // snake_case keys — see BackupService.normalizeSettingsMap for why an
    // *older* backup's camelCase shape is still accepted on restore.
    final vessel = data['vessel'] as Map<String, dynamic>;
    expect(vessel['vessel_name'], 'Sea Breeze');
    expect(vessel['vessel_mmsi'], '123456789');
    expect(vessel['vessel_call_sign'], 'ABCD1');
    expect(vessel['life_raft_info'], '6-person, aft locker');
    expect(vessel['epirb_info'], 'Cat 1, port cockpit locker');
    expect(vessel['fire_supp_info'], 'Engine bay, automatic');
    expect(vessel.containsKey('filter_stationary_mode'), isTrue,
        reason: 'track-filter settings must be part of the backup too, not just vessel/VHF fields');
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

  test('restoreBackup round-trips emergency contacts into another logbook\'s '
      'EmergencyRepository', () async {
    final home = HomeRepository();
    await home.init();
    final emergency = EmergencyRepository();
    await emergency.init();
    await emergency.addContact(EmergencyContact(name: 'Jane Doe', role: 'Spouse', phone: '+41791234567'));
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

    // Simulate restoring into a different (or fresh) logbook, which already
    // has its own, different contact that must not survive a full replace.
    final target = EmergencyRepository();
    await target.init();
    await target.addContact(EmergencyContact(name: 'Someone Else', role: 'Doctor', phone: '000'));

    await BackupService.restoreBackup(
      zipBytes: bytes,
      home: home,
      emergency: target,
      theme: theme,
      mode: BackupImportMode.replace,
    );

    expect(target.contacts, hasLength(1));
    expect(target.contacts.single.name, 'Jane Doe');
    expect(target.contacts.single.phone, '+41791234567');
  });

  test('BackupService.normalizeSettingsMap maps an older backup\'s camelCase '
      'vessel keys onto the new snake_case settings shape', () {
    final legacy = {
      'vesselName': 'Old Format Boat',
      'vesselMmsi': '999',
      'vesselCallSign': 'ZZ99',
      'lifeRaftInfo': 'aft',
      'epirbInfo': 'nav station',
      'fireSuppInfo': 'galley',
      'vhf1Label': 'Ch 16', 'vhf1Desc': 'Distress',
      'vhf2Label': 'Ch 67', 'vhf2Desc': 'Ship',
      'vhf3Label': 'Ch 06', 'vhf3Desc': 'SAR',
      'vhf4Label': 'Ch 13', 'vhf4Desc': 'Bridge',
    };

    final normalized = BackupService.normalizeSettingsMap(legacy);

    expect(normalized['vessel_name'], 'Old Format Boat');
    expect(normalized['vessel_mmsi'], '999');
    expect(normalized['vessel_call_sign'], 'ZZ99');
    expect(normalized['life_raft_info'], 'aft');
    expect(normalized['epirb_info'], 'nav station');
    expect(normalized['fire_supp_info'], 'galley');
    expect(normalized['vhf_1_label'], 'Ch 16');
    expect(normalized['vhf_4_desc'], 'Bridge');
    // Track-filter settings didn't exist in an old backup — must not be
    // invented, so ThemeProvider.restoreSettings leaves them untouched.
    expect(normalized.containsKey('filter_stationary_mode'), isFalse);
  });

  test('a full replace restore using a legacy camelCase vessel JSON still '
      'restores vessel info correctly', () async {
    final home = HomeRepository();
    await home.init();
    final emergency = EmergencyRepository();
    await emergency.init();
    final theme = ThemeProvider();
    await theme.init();
    theme.setVesselName('');

    final bytes = await BackupService.exportBackup(
      home: home, emergency: emergency, theme: theme,
      logbookId: 'logbook-1', logbookName: 'Logbook', appVersion: '1.0.0+1',
    );

    // Rewrite data.json in-place to simulate an older, camelCase-shaped
    // backup archive, then re-zip it.
    final archive = ZipDecoder().decodeBytes(bytes);
    final dataFile = archive.findFile('data.json')!;
    final data = json.decode(utf8.decode(dataFile.content as List<int>)) as Map<String, dynamic>;
    data['vessel'] = {
      'vesselName': 'Legacy Boat',
      'vesselMmsi': '111',
    };
    final newDataBytes = utf8.encode(json.encode(data));
    archive.addFile(ArchiveFile('data.json', newDataBytes.length, newDataBytes));
    final legacyBytes = Uint8List.fromList(ZipEncoder().encode(archive)!);

    await BackupService.restoreBackup(
      zipBytes: legacyBytes,
      home: home,
      emergency: emergency,
      theme: theme,
      mode: BackupImportMode.replace,
    );

    expect(theme.vesselName, 'Legacy Boat');
    expect(theme.vesselMmsi, '111');
  });

  test('previewUpdate carries the backup\'s vessel/settings and emergency '
      'contacts through for the opt-in "sync from backup" toggles', () async {
    final home = HomeRepository();
    await home.init();
    final emergency = EmergencyRepository();
    await emergency.init();
    await emergency.addContact(EmergencyContact(name: 'Jane Doe', role: 'Spouse', phone: '123'));
    final theme = ThemeProvider();
    await theme.init();
    theme.setVesselName('Backup Boat');

    final bytes = await BackupService.exportBackup(
      home: home, emergency: emergency, theme: theme,
      logbookId: 'logbook-1', logbookName: 'Logbook', appVersion: '1.0.0+1',
    );

    final preview = await BackupService.previewUpdate(zipBytes: bytes, home: home);

    expect(preview.vessel, isNotNull);
    expect(preview.vessel!['vessel_name'], 'Backup Boat');
    expect(preview.contacts, hasLength(1));
    expect(preview.contacts.single.name, 'Jane Doe');
  });

  test('applyUpdateSettings/applyUpdateContacts replace vessel info and '
      'emergency contacts wholesale, independent of day-entry handling', () async {
    final home = HomeRepository();
    await home.init();
    final emergency = EmergencyRepository();
    await emergency.init();
    await emergency.addContact(EmergencyContact(name: 'Backup Contact', role: 'Doctor', phone: '999'));
    final theme = ThemeProvider();
    await theme.init();
    theme.setVesselName('Backup Boat');

    final bytes = await BackupService.exportBackup(
      home: home, emergency: emergency, theme: theme,
      logbookId: 'logbook-1', logbookName: 'Logbook', appVersion: '1.0.0+1',
    );

    // A different logbook, with its own current vessel info and contact.
    final targetTheme = ThemeProvider();
    await targetTheme.init();
    targetTheme.setVesselName('Current Boat');
    final targetEmergency = EmergencyRepository();
    await targetEmergency.init();
    await targetEmergency.addContact(EmergencyContact(name: 'Current Contact', role: 'Friend', phone: '000'));

    final preview = await BackupService.previewUpdate(zipBytes: bytes, home: home);

    await BackupService.applyUpdateSettings(theme: targetTheme, vessel: preview.vessel);
    await BackupService.applyUpdateContacts(emergency: targetEmergency, contacts: preview.contacts);

    expect(targetTheme.vesselName, 'Backup Boat');
    expect(targetEmergency.contacts, hasLength(1));
    expect(targetEmergency.contacts.single.name, 'Backup Contact');
  });

  test('restoreBackup in update mode leaves the crew roster untouched by '
      'default, without the opt-in sync toggle', () async {
    final home = HomeRepository();
    await home.init();
    final backupCrew = CrewMember(name: 'Backup Crew');
    home.saveRosterMember(backupCrew);
    final emergency = EmergencyRepository();
    await emergency.init();
    final theme = ThemeProvider();
    await theme.init();

    final bytes = await BackupService.exportBackup(
      home: home, emergency: emergency, theme: theme,
      logbookId: 'logbook-1', logbookName: 'Logbook', appVersion: '1.0.0+1',
    );

    // The current roster now differs from what was backed up — "update"
    // mode must never overwrite this with the backup's, unless opted in.
    home.deleteRosterMember(backupCrew.id!);
    home.saveRosterMember(CrewMember(name: 'Current Crew'));

    await BackupService.restoreBackup(
      zipBytes: bytes,
      home: home,
      emergency: emergency,
      theme: theme,
      mode: BackupImportMode.update,
    );

    expect(home.roster.map((m) => m.name), ['Current Crew']);
  });

  test('previewUpdate carries the backup\'s roster through, and '
      'applyUpdateRoster replaces the current roster wholesale when opted '
      'into', () async {
    final home = HomeRepository();
    await home.init();
    final backupCrew = CrewMember(name: 'Backup Crew');
    home.saveRosterMember(backupCrew);
    final emergency = EmergencyRepository();
    await emergency.init();
    final theme = ThemeProvider();
    await theme.init();

    final bytes = await BackupService.exportBackup(
      home: home, emergency: emergency, theme: theme,
      logbookId: 'logbook-1', logbookName: 'Logbook', appVersion: '1.0.0+1',
    );

    home.deleteRosterMember(backupCrew.id!);
    home.saveRosterMember(CrewMember(name: 'Current Crew'));

    final preview = await BackupService.previewUpdate(zipBytes: bytes, home: home);
    expect(preview.roster.map((m) => m.name), ['Backup Crew']);

    await BackupService.applyUpdateRoster(home: home, roster: preview.roster);

    expect(home.roster.map((m) => m.name), ['Backup Crew']);
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
