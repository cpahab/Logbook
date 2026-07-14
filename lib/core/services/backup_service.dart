import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../../features/emergency/data/emergency_repository.dart';
import '../../features/home/data/home_repository.dart';
import '../../features/home/utils/photo_service.dart';
import '../../features/settings/domain/theme_provider.dart';
import 'backup_mapper.dart';

/// Bump whenever the JSON shape in [backup_mapper.dart] changes in a way
/// that would break parsing an older backup.
const int backupSchemaVersion = 1;

class BackupFormatException implements Exception {
  final String message;
  BackupFormatException(this.message);
  @override
  String toString() => message;
}

/// Exports the active logbook (day entries, GPS tracks, crew roster,
/// emergency contacts, and locally-reachable photos) to a single
/// human-readable `.zip`, and restores one back — replacing whatever is
/// currently in the active logbook.
class BackupService {
  static const JsonEncoder _prettyJson = JsonEncoder.withIndent('  ');

  static Future<Uint8List> exportBackup({
    required HomeRepository home,
    required EmergencyRepository emergency,
    required ThemeProvider theme,
    required String logbookId,
    required String logbookName,
    required String appVersion,
  }) async {
    final entries = home.entries;
    final vesselName = theme.vesselName;
    final exportedAt = DateTime.now().toUtc().toIso8601String();

    final manifest = {
      'schemaVersion': backupSchemaVersion,
      'exportedAt': exportedAt,
      'logbookId': logbookId,
      'logbookName': logbookName,
      'vesselName': vesselName,
      'appVersion': appVersion,
    };

    final entriesJson = <Map<String, dynamic>>[];
    final photoPaths = <String>{};
    for (final e in entries) {
      final normalized = DateTime(e.date.year, e.date.month, e.date.day);
      entriesJson.add(dayEntryToJson(e, track: home.dailyTracks[normalized]));
      photoPaths.addAll(e.photos);
    }

    final data = {
      'entries': entriesJson,
      'roster': home.roster.map(crewMemberToJson).toList(),
      'emergencyContacts': emergency.contacts.map(emergencyContactToJson).toList(),
      'vessel': _vesselInfoToJson(theme),
    };

    final archive = Archive();
    void addTextFile(String name, String content) {
      final bytes = utf8.encode(content);
      archive.addFile(ArchiveFile(name, bytes.length, bytes));
    }

    addTextFile('manifest.json', _prettyJson.convert(manifest));
    addTextFile('data.json', _prettyJson.convert(data));

    var photosIncluded = 0;
    for (final path in photoPaths) {
      final file = await PhotoService.localFile(path);
      if (file == null) continue;
      final bytes = await file.readAsBytes();
      archive.addFile(ArchiveFile('photos/${path.split('/').last}', bytes.length, bytes));
      photosIncluded++;
    }

    addTextFile(
      'README.txt',
      _buildReadme(
        logbookName: logbookName,
        vesselName: vesselName,
        exportedAt: exportedAt,
        entryCount: entries.length,
        photosIncluded: photosIncluded,
        photosTotal: photoPaths.length,
      ),
    );

    final zipBytes = ZipEncoder().encode(archive);
    if (zipBytes == null) throw Exception('Failed to build backup archive.');
    return Uint8List.fromList(zipBytes);
  }

  static String _buildReadme({
    required String logbookName,
    required String vesselName,
    required String exportedAt,
    required int entryCount,
    required int photosIncluded,
    required int photosTotal,
  }) {
    final missing = photosTotal - photosIncluded;
    final photosLine = photosTotal == 0
        ? 'none attached'
        : '$photosIncluded of $photosTotal included'
            '${missing > 0 ? ' ($missing could not be reached at export time)' : ''}';

    return '''
Logbook Backup
==============

Logbook:      $logbookName
Vessel:       $vesselName
Exported:     $exportedAt
Day entries:  $entryCount
Photos:       $photosLine

Contents
--------
manifest.json   Archive format version and export metadata.
data.json       All day entries (log, GPS track, stats, crew), the
                persistent crew roster, emergency contacts, and vessel/VHF
                info (name, MMSI, call sign, safety equipment) — plain,
                indented JSON, readable without any special tooling.
photos/         Photos attached to day entries, named by their original
                file name.

Restoring
---------
Restore this archive from within the Logbook app, under
Settings > Backup & Restore > Restore from File. Restoring REPLACES all
data in whichever logbook is active in the app at the time — it does not
merge with data already there.
''';
  }

  static Map<String, dynamic> _vesselInfoToJson(ThemeProvider p) => {
        'vesselName': p.vesselName,
        'vesselMmsi': p.vesselMmsi,
        'vesselCallSign': p.vesselCallSign,
        'vesselEquipment': p.vesselEquipment.toJsonString(),
        'lifeRaftInfo': p.lifeRaftInfo,
        'epirbInfo': p.epirbInfo,
        'fireSuppInfo': p.fireSuppInfo,
        'vhf1Label': p.vhf1Label, 'vhf1Desc': p.vhf1Desc,
        'vhf2Label': p.vhf2Label, 'vhf2Desc': p.vhf2Desc,
        'vhf3Label': p.vhf3Label, 'vhf3Desc': p.vhf3Desc,
        'vhf4Label': p.vhf4Label, 'vhf4Desc': p.vhf4Desc,
      };

  static Future<void> restoreBackup({
    required Uint8List zipBytes,
    required HomeRepository home,
    required EmergencyRepository emergency,
    required ThemeProvider theme,
  }) async {
    final archive = ZipDecoder().decodeBytes(zipBytes);

    final manifestFile = archive.findFile('manifest.json');
    final dataFile = archive.findFile('data.json');
    if (manifestFile == null || dataFile == null) {
      throw BackupFormatException('backupInvalidFile');
    }

    final Map<String, dynamic> manifest;
    final Map<String, dynamic> data;
    try {
      manifest = json.decode(utf8.decode(manifestFile.content as List<int>))
          as Map<String, dynamic>;
      data = json.decode(utf8.decode(dataFile.content as List<int>))
          as Map<String, dynamic>;
    } catch (_) {
      throw BackupFormatException('backupInvalidFile');
    }

    final schemaVersion = manifest['schemaVersion'] as int?;
    if (schemaVersion == null || schemaVersion > backupSchemaVersion) {
      throw BackupFormatException('backupSchemaTooNew');
    }

    final List<ParsedDayEntry> parsedEntries;
    final List<dynamic> rosterJson;
    final List<dynamic> contactsJson;
    try {
      parsedEntries = [
        for (final e in (data['entries'] as List? ?? const []))
          dayEntryFromJson(e as Map<String, dynamic>),
      ];
      rosterJson = data['roster'] as List? ?? const [];
      contactsJson = data['emergencyContacts'] as List? ?? const [];
    } catch (_) {
      throw BackupFormatException('backupInvalidFile');
    }

    final roster = [
      for (final m in rosterJson) crewMemberFromJson(m as Map<String, dynamic>),
    ];
    final contacts = [
      for (final c in contactsJson) emergencyContactFromJson(c as Map<String, dynamic>),
    ];
    // Optional: absent in a backup made before vessel info was included.
    final vessel = data['vessel'] as Map<String, dynamic>?;

    final photoBytesByFilename = <String, List<int>>{
      for (final f in archive.files)
        if (f.isFile && f.name.startsWith('photos/'))
          f.name.substring('photos/'.length): f.content as List<int>,
    };

    // Nothing wiped until here — everything above only parsed into local
    // variables, so a malformed archive is rejected without touching data.
    await home.clearLocalData();
    await emergency.clearLocalData();

    await home.restoreFromBackup(
      entries: [for (final p in parsedEntries) p.entry],
      roster: roster,
    );
    for (final p in parsedEntries) {
      final track = p.track;
      if (track != null) {
        await home.replaceTrackPoints(p.entry.date, track.points);
      }
    }
    await emergency.restoreContacts(contacts);

    if (vessel != null) {
      await theme.restoreVesselSettings(
        vesselName:         vessel['vesselName'] as String? ?? '',
        vesselMmsi:         vessel['vesselMmsi'] as String? ?? '',
        vesselCallSign:     vessel['vesselCallSign'] as String? ?? '',
        vesselEquipmentJson: vessel['vesselEquipment'] as String? ?? '',
        lifeRaftInfo:       vessel['lifeRaftInfo'] as String? ?? '',
        epirbInfo:          vessel['epirbInfo'] as String? ?? '',
        fireSuppInfo:       vessel['fireSuppInfo'] as String? ?? '',
        vhf1Label: vessel['vhf1Label'] as String? ?? 'Channel 16',
        vhf1Desc:  vessel['vhf1Desc']  as String? ?? 'Distress · 156.800 MHz',
        vhf2Label: vessel['vhf2Label'] as String? ?? 'Channel 67',
        vhf2Desc:  vessel['vhf2Desc']  as String? ?? 'Ship to Ship · 156.375 MHz',
        vhf3Label: vessel['vhf3Label'] as String? ?? 'Channel 06',
        vhf3Desc:  vessel['vhf3Desc']  as String? ?? 'Search & Rescue · 156.300 MHz',
        vhf4Label: vessel['vhf4Label'] as String? ?? 'Channel 13',
        vhf4Desc:  vessel['vhf4Desc']  as String? ?? 'Bridge to Bridge · 156.650 MHz',
      );
    }

    for (final p in parsedEntries) {
      for (final path in p.entry.photos) {
        final bytes = photoBytesByFilename[path.split('/').last];
        if (bytes != null) await PhotoService.restorePhoto(path, bytes);
      }
    }
  }
}
