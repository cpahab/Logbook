import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart' show DateTimeRange;

import '../../features/emergency/data/emergency_repository.dart';
import '../../features/emergency/domain/emergency_contact.dart';
import '../../features/home/data/home_repository.dart';
import '../../features/home/domain/crew_member.dart';
import '../../features/home/domain/day_entry.dart';
import '../../features/home/domain/timeline_entry.dart';
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

/// How [BackupService.restoreBackup] applies a backup:
/// - [replace]: today's original, unchanged behavior — wipes all local
///   data (entries, roster, contacts, vessel/settings info) and repopulates
///   from the backup exactly, then tombstones any cloud day/track absent
///   from the restored set (scoped to the backup's own export range, if
///   it was a partial one — see HomeRepository.datesToTombstone).
/// - [update]: day entries get additions and newer-wins overwrites (see
///   HomeRepository.backupEntryWins), never deletions. The crew roster,
///   vessel/settings info, and emergency contacts are all *optionally*
///   replaced wholesale from the backup — see BackupScreen's sync-roster/
///   sync-settings/sync-emergency toggles — each defaulting to "keep the
///   current logbook's" when not explicitly opted into.
enum BackupImportMode { replace, update }

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
  // Null for a full (unranged) export. Set for a partial/date-ranged one —
  // threaded into reconcileCloudAfterRestore's restrictTo so "replace"-mode
  // restoring a partial backup only tombstones cloud dates inside this
  // range, never the days outside it that were never meant to be touched.
  DateTimeRange? exportRange,
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

  // Absent for a full export (the common case) — present only for a
  // partial/date-ranged one (see BackupService.exportBackup's dateRange
  // param). Defensive parsing (a malformed/partial range is treated as "no
  // range known") matches this file's existing tolerance for older/odd
  // backups rather than failing the whole restore over one optional field.
  final exportRangeJson = manifest['exportRange'] as Map<String, dynamic>?;
  DateTimeRange? exportRange;
  if (exportRangeJson != null) {
    final start = DateTime.tryParse(exportRangeJson['start'] as String? ?? '');
    final end = DateTime.tryParse(exportRangeJson['end'] as String? ?? '');
    if (start != null && end != null) {
      exportRange = DateTimeRange(start: start, end: end);
    }
  }

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
    exportRange: exportRange,
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
    // Null (the default) exports every entry, exactly as before this
    // parameter existed. When set, only entries within [start, end]
    // (inclusive) are exported — roster/emergencyContacts/vessel are
    // still always included in full regardless, since they aren't
    // date-scoped and a partial safety-document list would be actively
    // dangerous. The range itself is recorded in manifest.json so a
    // restore of this backup knows it was partial — see
    // HomeRepository.datesToTombstone's restrictTo parameter for why
    // that matters.
    DateTimeRange? dateRange,
  }) async {
    final allEntries = home.entries;
    final entries = dateRange == null
        ? allEntries
        : allEntries.where((e) =>
            !e.date.isBefore(dateRange.start) && !e.date.isAfter(dateRange.end));
    final vesselName = theme.vesselName;
    final exportedAt = DateTime.now().toUtc().toIso8601String();

    final manifest = {
      'schemaVersion': backupSchemaVersion,
      'exportedAt': exportedAt,
      'logbookId': logbookId,
      'logbookName': logbookName,
      'vesselName': vesselName,
      'appVersion': appVersion,
      if (dateRange != null)
        'exportRange': {
          'start': dateRange.start.toIso8601String(),
          'end': dateRange.end.toIso8601String(),
        },
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
      // The full settings snapshot (vessel/VHF/safety info *and* track-filter
      // tuning) — see ThemeProvider.settingsSnapshot's doc comment for why
      // this is read directly from the live-sync map rather than a
      // separately maintained field list.
      'vessel': theme.settingsSnapshot,
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
      dateRange: dateRange,
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
    DateTimeRange? dateRange,
  }) {
    final missing = photosTotal - photosIncluded;
    final photosLine = photosTotal == 0
        ? 'none attached'
        : '$photosIncluded of $photosTotal included'
            '${missing > 0 ? ' ($missing could not be reached at export time)' : ''}';
    final rangeLine = dateRange == null
        ? 'All entries'
        : '${dateRange.start.toIso8601String().substring(0, 10)} to '
            '${dateRange.end.toIso8601String().substring(0, 10)} only — '
            'this is a partial export, not the full logbook';

    return '''
Logbook Backup
==============

Logbook:      $logbookName
Vessel:       $vesselName
Exported:     $exportedAt
Range:        $rangeLine
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
Settings > Backup & Restore > Restore from File. Two modes are offered:
"Replace" wipes all data in whichever logbook is active in the app and
repopulates it exactly from this archive (roster, contacts, and vessel/
settings info too). "Update" only adds or updates day entries found
here by default — it never deletes anything — but can optionally also
replace the crew roster, vessel/settings info, and/or emergency contacts
wholesale from this archive, if chosen at restore time.
''';
  }

  /// Legacy backups (schemaVersion 1, before settings became a full
  /// snapshot) stored vessel/VHF/safety info under camelCase keys distinct
  /// from the snake_case keys ThemeProvider's live settings sync uses
  /// internally (see ThemeProvider.settingsSnapshot). Maps those old keys
  /// onto the new shape so pre-existing backups still restore correctly;
  /// a map already in the new shape (has e.g. 'vessel_name') passes
  /// through unchanged. Track-filter keys simply don't exist in an old
  /// backup — [ThemeProvider.restoreSettings] leaves anything absent
  /// untouched, so this never needs to invent values for them.
  static Map<String, String> normalizeSettingsMap(Map<String, dynamic> raw) {
    if (raw.containsKey('vessel_name')) {
      return raw.map((k, v) => MapEntry(k, v as String? ?? ''));
    }
    const legacyKeyMap = {
      'vesselName': 'vessel_name',
      'vesselMmsi': 'vessel_mmsi',
      'vesselCallSign': 'vessel_call_sign',
      'vesselEquipment': 'vessel_equipment',
      'lifeRaftInfo': 'life_raft_info',
      'epirbInfo': 'epirb_info',
      'fireSuppInfo': 'fire_supp_info',
      'vhf1Label': 'vhf_1_label', 'vhf1Desc': 'vhf_1_desc',
      'vhf2Label': 'vhf_2_label', 'vhf2Desc': 'vhf_2_desc',
      'vhf3Label': 'vhf_3_label', 'vhf3Desc': 'vhf_3_desc',
      'vhf4Label': 'vhf_4_label', 'vhf4Desc': 'vhf_4_desc',
    };
    return {
      for (final entry in raw.entries)
        if (legacyKeyMap[entry.key] != null)
          legacyKeyMap[entry.key]!: entry.value as String? ?? '',
    };
  }

  static Future<void> restoreBackup({
    required Uint8List zipBytes,
    required HomeRepository home,
    required EmergencyRepository emergency,
    required ThemeProvider theme,
    required BackupImportMode mode,
  }) async {
    // Archive decode + JSON parsing is pure computation on the zip bytes
    // alone — runs off the UI isolate. A malformed archive throws from
    // inside compute() before anything below touches local data.
    final parsed = await compute(_parseBackupArchive, zipBytes);

    if (mode == BackupImportMode.update) {
      await _mergeBackup(parsed, home: home);
      return;
    }

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
    // not a merge, so this is the intended behavior. restrictTo scopes
    // that tombstoning to the backup's own export range (null for a full
    // export) — otherwise restoring a partial/date-ranged backup would
    // wipe every day outside that range too.
    await home.reconcileCloudAfterRestore(restrictTo: parsed.exportRange);
    await emergency.restoreContacts(parsed.contacts);

    final vessel = parsed.vessel;
    if (vessel != null) {
      await theme.restoreSettings(normalizeSettingsMap(vessel));
    }

    for (final p in parsed.entries) {
      for (final path in p.entry.photos) {
        final bytes = parsed.photoBytesByFilename[path.split('/').last];
        if (bytes != null) await PhotoService.restorePhoto(path, bytes);
      }
    }
  }

  /// "Update" mode's whole flow: per the [BackupImportMode.update] doc
  /// comment, this only ever touches day entries (additions and
  /// newer-wins overwrites via [HomeRepository.mergeEntryFromBackup]) —
  /// roster/contacts/vessel are never read from [parsed] here at all, and
  /// nothing is ever deleted, so there's no clearLocalData and no
  /// reconcileCloudAfterRestore call (that method's whole job is
  /// tombstoning what's absent, which "update" mode must never do).
  static Future<void> _mergeBackup(
    _ParsedBackup parsed, {
    required HomeRepository home,
  }) async {
    for (final p in parsed.entries) {
      final applied = await home.mergeEntryFromBackup(p.entry);
      if (!applied) continue;

      final track = p.track;
      if (track != null) {
        await home.replaceTrackPoints(p.entry.date, track.points);
      }
      for (final path in p.entry.photos) {
        final bytes = parsed.photoBytesByFilename[path.split('/').last];
        if (bytes != null) await PhotoService.restorePhoto(path, bytes);
      }
    }
  }

  /// Parses [zipBytes] and splits its entries into pure additions (no
  /// local conflict at all — `home.getEntry(date)` is null) and genuine
  /// conflicts (a date present in both) — used to show
  /// ImportConflictsScreen *before* applying anything for "update" mode,
  /// so the resolution is always visible and confirmed by the user, never
  /// silent. Nothing is written to local state or Firestore by this call.
  static Future<UpdatePreview> previewUpdate({
    required Uint8List zipBytes,
    required HomeRepository home,
    // Null (the default) previews every entry in the backup. When set, only
    // entries within [start, end] (inclusive) are considered at all — the
    // rest are neither added nor shown as conflicts, letting the user work
    // through a large backup's ambiguities in smaller batches rather than
    // reviewing every conflicting day at once.
    DateTimeRange? dateRange,
  }) async {
    final parsed = await compute(_parseBackupArchive, zipBytes);
    final additions = <ParsedDayEntry>[];
    final conflicts = <UpdateConflict>[];
    for (final p in parsed.entries) {
      if (dateRange != null &&
          (p.entry.date.isBefore(dateRange.start) || p.entry.date.isAfter(dateRange.end))) {
        continue;
      }
      final normalized = DateTime(p.entry.date.year, p.entry.date.month, p.entry.date.day);
      final current = home.getEntry(normalized);
      if (current == null) {
        additions.add(p);
      } else {
        conflicts.add(UpdateConflict(
          current: current,
          backup: p,
          backupWinsByDefault: HomeRepository.backupEntryWins(current, p.entry),
        ));
      }
    }
    return (
      additions: additions,
      conflicts: conflicts,
      photoBytesByFilename: parsed.photoBytesByFilename,
      vessel: parsed.vessel,
      contacts: parsed.contacts,
      roster: parsed.roster,
    );
  }

  /// Applies the backup's vessel/settings info wholesale — the "update"
  /// mode opt-in counterpart to [restoreBackup]'s replace-mode vessel
  /// restore, using the exact same normalization for older backups.
  /// No-op if [vessel] is null (an old backup predating vessel/settings
  /// info entirely, vanishingly rare in practice).
  static Future<void> applyUpdateSettings({
    required ThemeProvider theme,
    required Map<String, dynamic>? vessel,
  }) async {
    if (vessel == null) return;
    await theme.restoreSettings(normalizeSettingsMap(vessel));
  }

  /// Applies the backup's crew roster wholesale — the "update" mode opt-in
  /// counterpart to [restoreBackup]'s replace-mode roster restore.
  static Future<void> applyUpdateRoster({
    required HomeRepository home,
    required List<CrewMember> roster,
  }) async {
    await home.restoreRoster(roster);
  }

  /// Applies the backup's emergency contacts wholesale — the "update" mode
  /// opt-in counterpart to [restoreBackup]'s replace-mode contacts restore.
  static Future<void> applyUpdateContacts({
    required EmergencyRepository emergency,
    required List<EmergencyContact> contacts,
  }) async {
    await emergency.restoreContacts(contacts);
  }

  /// Applies a [previewUpdate] result: every addition is applied
  /// unconditionally (nothing to decide there), and each conflict is
  /// applied per its matching entry in [resolutions] — the user's own
  /// decision from ImportConflictsScreen (whether per-day, per-entry, or
  /// via one of its bulk actions), never an automatic silent one.
  /// [resolutions] must have the same length and order as [conflicts].
  static Future<void> applyUpdate({
    required HomeRepository home,
    required List<ParsedDayEntry> additions,
    required List<UpdateConflict> conflicts,
    required List<ConflictResolution> resolutions,
    required Map<String, List<int>> photoBytesByFilename,
  }) async {
    assert(resolutions.length == conflicts.length);

    Future<void> restorePhotos(List<String> photos) async {
      for (final path in photos) {
        final bytes = photoBytesByFilename[path.split('/').last];
        if (bytes != null) await PhotoService.restorePhoto(path, bytes);
      }
    }

    for (final p in additions) {
      await home.applyEntryFromBackup(p.entry);
      final track = p.track;
      if (track != null) await home.replaceTrackPoints(p.entry.date, track.points);
      await restorePhotos(p.entry.photos);
    }

    for (var i = 0; i < conflicts.length; i++) {
      final conflict = conflicts[i];
      final resolution = resolutions[i];
      // Whichever side wins the non-timeline fields (notes, crew, harbor,
      // stats, photos) also supplies the DayEntry object that gets saved —
      // its timeline is then overwritten with the (possibly hand-merged
      // from both sides) list the user actually chose.
      final entry = resolution.useBackupFields ? conflict.backup.entry : conflict.current;
      entry.timeline = resolution.timeline;
      await home.applyEntryFromBackup(entry);
      if (resolution.useBackupFields) {
        final track = conflict.backup.track;
        if (track != null) await home.replaceTrackPoints(entry.date, track.points);
      }
      await restorePhotos(entry.photos);
    }
  }
}

/// One day present in both current local data and a backup being imported
/// in "update" mode — a genuine conflict needing a decision, shown on
/// ImportConflictsScreen rather than resolved silently.
class UpdateConflict {
  final DayEntry current;
  final ParsedDayEntry backup;
  /// What [HomeRepository.backupEntryWins] would decide automatically —
  /// shown as the pre-selected choice on the conflict screen, never
  /// applied on its own without the user seeing/confirming it.
  final bool backupWinsByDefault;

  UpdateConflict({
    required this.current,
    required this.backup,
    required this.backupWinsByDefault,
  });
}

/// Result of [BackupService.previewUpdate]. [vessel]/[contacts]/[roster]
/// are the backup's own vessel/settings info, emergency contacts, and crew
/// roster, carried through unconditionally (parsing them is free) so
/// BackupScreen can offer them as opt-in "sync from backup" toggles
/// without needing to re-parse the archive — see
/// [BackupService.applyUpdateSettings]/[BackupService.applyUpdateContacts]/
/// [BackupService.applyUpdateRoster].
typedef UpdatePreview = ({
  List<ParsedDayEntry> additions,
  List<UpdateConflict> conflicts,
  Map<String, List<int>> photoBytesByFilename,
  Map<String, dynamic>? vessel,
  List<EmergencyContact> contacts,
  List<CrewMember> roster,
});

/// The user's resolution for one [UpdateConflict], produced by
/// ImportConflictsScreen. [useBackupFields] decides whose non-timeline
/// fields (notes, crew, harbor, stats, photos, track) win, while [timeline]
/// is the exact list of timeline entries to save for that day — not
/// necessarily identical to either side's original timeline, since the
/// screen lets entries be picked individually from both "mine" and
/// "backup" (e.g. two systems logging the same day) rather than forcing an
/// all-or-nothing choice per day.
class ConflictResolution {
  final bool useBackupFields;
  final List<TimelineEntry> timeline;
  const ConflictResolution({required this.useBackupFields, required this.timeline});
}
