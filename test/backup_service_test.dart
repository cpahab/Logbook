import 'dart:convert';
import 'dart:io';

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
    );

    expect(theme.vesselName, 'Sea Breeze');
    expect(theme.vesselMmsi, '123456789');
  });
}
