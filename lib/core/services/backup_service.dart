import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart' show compute;

import '../../features/emergency/data/emergency_repository.dart';
import '../../features/emergency/domain/emergency_contact.dart';
import '../../features/home/data/home_repository.dart';
import '../../features/home/domain/crew_member.dart';
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

/// Inputs to [_buildBackupZip] — plain, isolate-sendable data only (no
/// repository/provider references), so archive+zip building (the CPU-heavy
/// part of export) can run via [compute] off the UI isolate.
typedef _BackupZipInput = ({
  Map<String, dynamic> manifest,
  Map<String, dynamic> data,
  String readme,
  Map<String, List<int>> photoBytesByFilename,
});

/// Builds the backup archive (manifest, data, README, photos) and zip-encodes
/// it. Top-level so it can be handed to [compute] — JSON + zip encoding is
/// CPU-heavy for a logbook with many entries/photos.
Uint8List _buildBackupZip(_BackupZipInput input) {
  const prettyJson = JsonEncoder.withIndent('  ');
  final archive = Archive();
  void addTextFile(String name, String content) {
    final bytes = utf8.encode(content);
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  }

  addTextFile('manifest.json', prettyJson.convert(input.manifest));
  addTextFile('data.json', prettyJson.convert(input.data));
  for (final entry in input.photoBytesByFilename.entries) {
    archive.addFile(
        ArchiveFile('photos/${entry.key}', entry.value.length, entry.value));
  }
  addTextFile('README.txt', input.readme);

  final zipBytes = ZipEncoder().encode(archive);
  if (zipBytes == null) throw Exception('Failed to build backup archive.');
  return Uint8List.fromList(zipBytes);
}

/// Inputs to [_parseBackupArchive] — just the raw zip bytes, so archive
/// decoding + JSON parsing (the CPU-heavy part of restore) can run via
/// [compute] off the UI isolate.
typedef _ParsedBackup = ({
  List<ParsedDayEntry> entries,
  List<CrewMember> roster,
  List<EmergencyContact> contacts,
  Map<String, dynamic>? vessel,
  Map<String, List<int>> photoBytesByFilename,
});

/// Decodes and parses a backup archive into plain data — no repository/
/// provider access, so it's safe to run via [compute]. Top-level for the
/// same reason as [_buildBackupZip].
_ParsedBackup _parseBackupArchive(Uint8List zipBytes) {
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
    for (final c in contactsJson)
      emergencyContactFromJson(c as Map<String, dynamic>),
  ];
  // Optional: absent in a backup made before vessel info was included.
  final vessel = data['vessel'] as Map<String, dynamic>?;

  final photoBytesByFilename = <String, List<int>>{
    for (final f in archive.files)
      if (f.isFile && f.name.startsWith('photos/'))
        f.name.substring('photos/'.length): f.content as List<int>,
  };

  return (
    entries: parsedEntries,
    roster: roster,
    contacts: contacts,
    vessel: vessel,
    photoBytesByFilename: photoBytesByFilename,
  );
}

/// Exports the active logbook (day entries, GPS tracks, crew roster,
/// emergency contacts, and locally-reachable photos) to a single
/// human-readable `.zip`, and restores one back — replacing whatever is
/// currently in the active logbook.
class BackupService {
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

    // Photo reads are I/O-bound (Storage/disk plugin calls) so they stay on
    // the UI isolate; only the CPU-heavy JSON/zip encoding below moves off it.
    final photoBytesByFilename = <String, List<int>>{};
    var photosIncluded = 0;
    for (final path in photoPaths) {
      final file = await PhotoService.localFile(path);
      if (file == null) continue;
      final bytes = await file.readAsBytes();
      photoBytesByFilename[path.split('/').last] = bytes;
      photosIncluded++;
    }

    final readme = _buildReadme(
      logbookName: logbookName,
      vesselName: vesselName,
      exportedAt: exportedAt,
      entryCount: entries.length,
      photosIncluded: photosIncluded,
      photosTotal: photoPaths.length,
    );

    return compute(_buildBackupZip, (
      manifest: manifest,
      data: data,
      readme: readme,
      photoBytesByFilename: photoBytesByFilename,
    ));
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
    // Archive decode + JSON parsing is pure computation on the zip bytes
    // alone — runs off the UI isolate. A malformed archive throws from
    // inside compute() before anything below touches local data.
    final parsed = await compute(_parseBackupArchive, zipBytes);

    await home.clearLocalData();
    await emergency.clearLocalData();

    await home.restoreFromBackup(
      entries: [for (final p in parsed.entries) p.entry],
      roster: parsed.roster,
    );
    for (final p in parsed.entries) {
      final track = p.track;
      if (track != null) {
        await home.replaceTrackPoints(p.entry.date, track.points);
      }
    }
    // Entries/tracks now fully reflect the backup — anything still in the
    // cloud but absent from this restored state (created after the backup
    // was taken, or on another device) must be told to go away too, or it
    // reappears on the next sync. Restore is documented as a full replace,
    // not a merge, so this is the intended behavior.
    await home.reconcileCloudAfterRestore();
    await emergency.restoreContacts(parsed.contacts);

    final vessel = parsed.vessel;
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

    for (final p in parsed.entries) {
      for (final path in p.entry.photos) {
        final bytes = parsed.photoBytesByFilename[path.split('/').last];
        if (bytes != null) await PhotoService.restorePhoto(path, bytes);
      }
    }
  }
}
