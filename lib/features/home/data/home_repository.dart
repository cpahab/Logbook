import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:gpx/gpx.dart';
import 'package:hive/hive.dart';

import '../domain/day_entry.dart';
import '../domain/crew_member.dart';
import '../domain/timeline_entry.dart';
import '../domain/daily_track.dart';
import '../domain/track_point.dart';
import '../utils/gpx_parser.dart';
import '../../../core/services/firestore_service.dart';
import '../../../core/services/storage_service.dart';

class HomeRepository extends ChangeNotifier {
  // ── Hive boxes ─────────────────────────────────────────────────────────────
  late Box<DayEntry> _dayBox;
  late Box<DailyTrack> _trackBox;
  late Box<CrewMember> _rosterBox;

  /// Stores two kinds of integers keyed by string:
  ///   'last_sync_at'           → epoch-ms of the last successful Firestore pull
  ///   'entry_{isoDate}_at'     → epoch-ms of the last *local* edit for that entry
  late Box<int> _syncStateBox;

  // ── In-memory caches ───────────────────────────────────────────────────────
  final Map<DateTime, DayEntry> _entries = {};
  final Map<DateTime, DailyTrack> dailyTracks = {};

  // ── Cloud services (null until attach* is called) ──────────────────────────
  FirestoreService? _firestore;
  StorageService? _storage;

  // ── Debounce timers (keyed by entry date) ──────────────────────────────────
  final Map<DateTime, Timer> _syncTimers = {};

  // ── Real-time Firestore stream subscriptions ───────────────────────────────
  StreamSubscription<void>? _entrySub;
  StreamSubscription<void>? _rosterSub;

  // ── Public getters ─────────────────────────────────────────────────────────

  List<DayEntry> get entries =>
      _entries.values.toList()..sort((a, b) => a.date.compareTo(b.date));

  List<String> get lastParticipants {
    for (final e in entries.reversed) {
      if (e.participantsList.isNotEmpty) return List<String>.from(e.participantsList);
    }
    return [];
  }

  ({int? oilLevel, int? fuelLevel, bool? keelDown}) get lastVesselStatus {
    int? oil;
    int? fuel;
    bool? keel;
    for (final e in entries.reversed) {
      oil  ??= e.oilLevel;
      fuel ??= e.fuelLevel;
      keel ??= e.keelDown;
      if (oil != null && fuel != null && keel != null) break;
    }
    return (oilLevel: oil, fuelLevel: fuel, keelDown: keel);
  }

  List<CrewMember> get roster {
    final members = _rosterBox.values.toList();
    members.sort((a, b) => a.name.compareTo(b.name));
    return members;
  }

  List<CrewMember> get lastCrew {
    for (final e in entries.reversed) {
      if (e.crew.isNotEmpty) {
        return e.crew
            .map((m) => CrewMember(
                  name: m.name,
                  bloodType: m.bloodType,
                  allergies: m.allergies,
                  conditions: m.conditions,
                  remarks: m.remarks,
                ))
            .toList();
      }
    }
    return [];
  }

  // ── Sync-state helpers ─────────────────────────────────────────────────────

  static String _syncKey(DateTime date) =>
      'entry_${date.toIso8601String()}_at';

  /// Records the current wall-clock time as the last local edit for [date].
  void _recordLocalEdit(DateTime date) =>
      _syncStateBox.put(_syncKey(date), DateTime.now().millisecondsSinceEpoch);

  /// Returns when [date]'s entry was last edited locally, or null if never.
  DateTime? _localEditTime(DateTime date) {
    final ms = _syncStateBox.get(_syncKey(date));
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  void _clearLocalEdit(DateTime date) => _syncStateBox.delete(_syncKey(date));

  /// The timestamp of the last successful pull from Firestore.
  /// Defaults to the Unix epoch so the first incremental pull fetches everything.
  DateTime get _lastSyncAt {
    final ms = _syncStateBox.get('last_sync_at');
    return ms == null
        ? DateTime.fromMillisecondsSinceEpoch(0)
        : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  void _setLastSyncAt() =>
      _syncStateBox.put('last_sync_at', DateTime.now().millisecondsSinceEpoch);

  // ── Initialization ─────────────────────────────────────────────────────────

  Future<void> init() async {
    _dayBox       = await Hive.openBox<DayEntry>('daily_entries');
    _trackBox     = await Hive.openBox<DailyTrack>('daily_tracks');
    _rosterBox    = await Hive.openBox<CrewMember>('crew_roster');
    _syncStateBox = await Hive.openBox<int>('entry_sync_state');

    for (final e in _dayBox.values) { _entries[e.date] = e; }
    for (final t in _trackBox.values) { dailyTracks[t.day] = t; }

    notifyListeners();
  }

  // ── Firestore attachment ───────────────────────────────────────────────────

  /// Attaches Firestore and starts syncing.
  ///
  /// On every call (startup or reconnect):
  ///   1. Push any entries edited locally since the last successful pull.
  ///   2. Pull all entries whose server `updatedAt` is newer than the last pull.
  ///      (First-ever sync with [initialSync]=true pushes all local entries and
  ///       pulls only missing ones, preserving data already on both devices.)
  ///   3. Subscribe to the Firestore collection for live updates while the app
  ///      is running.
  Future<void> attachFirestore(FirestoreService service,
      {bool initialSync = false}) async {
    _firestore = service;

    // Cancel any previous stream subscription (e.g. after reattach).
    await _entrySub?.cancel();
    _entrySub = null;

    try {
      final lastSync = _lastSyncAt;

      // ── Step 1: push offline edits ────────────────────────────────────────
      if (initialSync) {
        for (final e in _entries.values) {
          await service.saveEntry(e);
        }
      } else {
        for (final e in _entries.values) {
          final editAt = _localEditTime(e.date);
          if (editAt != null && editAt.isAfter(lastSync)) {
            await service.saveEntry(e);
          }
        }
      }

      // ── Step 2: pull remote changes ───────────────────────────────────────
      final List<DayEntry> remote;
      if (initialSync) {
        // Conservative first sync: pull only entries absent locally to avoid
        // overwriting any data already present on this device.
        remote = await service.fetchMissingEntries(_entries.keys.toSet());
      } else {
        // Incremental: only entries updated on the server since our last pull.
        remote = await service.fetchEntriesUpdatedSince(lastSync);
      }

      var changed = false;
      for (final e in remote) {
        // Do not overwrite an entry that was edited locally after the last sync
        // — we just pushed that version in step 1, and the stream will echo it
        // back; skipping here avoids a transient overwrite flash.
        final localEdit = _localEditTime(e.date);
        if (localEdit != null && localEdit.isAfter(lastSync)) continue;

        _entries[e.date] = e;
        await _dayBox.put(e.date.toIso8601String(), e);
        changed = true;
      }
      if (changed) notifyListeners();

      _setLastSyncAt();
    } catch (_) {
      // Offline or timeout — local data remains available.
    }

    // ── Step 3: real-time listener ────────────────────────────────────────────
    // The stream emits the full collection on first subscription, then only
    // changed documents.  Both cases are handled by _applyRemoteEntries.
    _entrySub = service
        .entryChanges()
        .asyncMap(_applyRemoteEntries)
        .listen((_) {}, onError: (_) {});

    // ── Step 4: roster sync ───────────────────────────────────────────────────
    try {
      final remote = await service.fetchRoster();
      if (remote.isNotEmpty) {
        await _applyRemoteRoster(remote);
      }
    } catch (_) {}

    await _rosterSub?.cancel();
    _rosterSub = service
        .rosterChanges()
        .asyncMap(_applyRemoteRoster)
        .listen((_) {}, onError: (_) {});
  }

  /// Applies a batch of entries received from Firestore.
  ///
  /// Entries with an active debounce timer are skipped — the user is actively
  /// editing that entry locally and the Firestore push is pending.
  Future<void> _applyRemoteEntries(List<DayEntry> entries) async {
    var changed = false;
    for (final e in entries) {
      if (_syncTimers.containsKey(e.date)) continue;
      _entries[e.date] = e;
      await _dayBox.put(e.date.toIso8601String(), e);
      changed = true;
    }
    if (changed) {
      _setLastSyncAt();
      notifyListeners();
    }
  }

  // ── Storage attachment ─────────────────────────────────────────────────────

  Future<void> attachStorage(StorageService service,
      {bool initialSync = false}) async {
    _storage = service;
    try {
      if (initialSync) {
        for (final entry in dailyTracks.entries) {
          final bytes = _trackToGpxBytes(entry.value);
          await service.uploadTrack(entry.key, bytes);
        }
      }
      final cloudDates = await service.listTrackDates();
      final missing = cloudDates.where((d) => !dailyTracks.containsKey(d)).toList();
      for (final date in missing) {
        final bytes = await service.downloadTrack(date);
        if (bytes == null || bytes.isEmpty) continue;
        final points = GpxParser().parseBytes(bytes);
        if (points.isEmpty) continue;
        await _saveTrack(date, '$date.gpx', points);
      }
    } catch (_) {}
  }

  static Uint8List _trackToGpxBytes(DailyTrack track) {
    final gpx = Gpx();
    gpx.trks = [
      Trk(trksegs: [
        Trkseg(
          trkpts: track.points
              .map((p) => Wpt(lat: p.lat, lon: p.lon, time: p.time.toUtc()))
              .toList(),
        ),
      ]),
    ];
    return Uint8List.fromList(utf8.encode(GpxWriter().asString(gpx)));
  }

  // ── Day entry management ───────────────────────────────────────────────────

  void addEntry(DateTime date) {
    final normalized = DateTime(date.year, date.month, date.day);
    if (_entries.containsKey(normalized)) return;

    // Vessel status from the closest past day (never from future entries).
    int? oil, fuel;
    bool? keel;
    for (final e in entries.reversed) {
      if (!e.date.isBefore(normalized)) continue;
      oil  ??= e.oilLevel;
      fuel ??= e.fuelLevel;
      keel ??= e.keelDown;
      if (oil != null && fuel != null && keel != null) break;
    }

    final entry = DayEntry(
      date: normalized,
      timeline: [],
      participantsList: lastParticipants,
      crew: lastCrew,
      oilLevel:  oil,
      fuelLevel: fuel,
      keelDown:  keel,
    );
    _entries[normalized] = entry;
    _dayBox.put(normalized.toIso8601String(), entry);
    _recordLocalEdit(normalized);
    _syncToFirestore(entry);
    notifyListeners();
  }

  DayEntry? getEntry(DateTime date) {
    final normalized = DateTime(date.year, date.month, date.day);
    return _entries[normalized];
  }

  Future<bool> changeEntryDate(DateTime oldDate, DateTime newDate) async {
    final oldNorm = DateTime(oldDate.year, oldDate.month, oldDate.day);
    final newNorm = DateTime(newDate.year, newDate.month, newDate.day);
    if (oldNorm == newNorm) return true;
    if (_entries.containsKey(newNorm)) return false;

    final entry = _entries[oldNorm];
    if (entry == null) return false;

    entry.date = newNorm;
    _entries.remove(oldNorm);
    _entries[newNorm] = entry;
    await _dayBox.delete(oldNorm.toIso8601String());
    await _dayBox.put(newNorm.toIso8601String(), entry);

    // Transfer local-edit tracking to the new key.
    _clearLocalEdit(oldNorm);
    _recordLocalEdit(newNorm);

    final track = dailyTracks[oldNorm];
    if (track != null) {
      track.day = newNorm;
      dailyTracks.remove(oldNorm);
      dailyTracks[newNorm] = track;
      await _trackBox.delete(oldNorm.toIso8601String());
      await _trackBox.put(newNorm.toIso8601String(), track);

      if (_storage != null) {
        final bytes = _trackToGpxBytes(track);
        _storage!.uploadTrack(newNorm, bytes).catchError((_) {});
        _storage!.deleteTrack(oldNorm).catchError((_) {});
      }
    }

    _firestore?.deleteEntry(oldNorm).catchError((_) {});
    _syncToFirestore(entry);

    notifyListeners();
    return true;
  }

  Future<void> removeEntry(DateTime date) async {
    final normalized = DateTime(date.year, date.month, date.day);

    _syncTimers[normalized]?.cancel();
    _syncTimers.remove(normalized);
    _clearLocalEdit(normalized);

    _entries.remove(normalized);
    await _dayBox.delete(normalized.toIso8601String());

    if (dailyTracks.containsKey(normalized)) {
      dailyTracks.remove(normalized);
      await _trackBox.delete(normalized.toIso8601String());
    }

    _firestore?.deleteEntry(normalized).catchError((_) {});
    notifyListeners();
  }

  // ── Save ───────────────────────────────────────────────────────────────────

  void saveEntry(DayEntry entry) {
    entry.save();
    _recordLocalEdit(entry.date);
    notifyListeners();
    _debouncedSync(entry);
  }

  // ── Timeline management ────────────────────────────────────────────────────

  /// Propagates the most recent keelDown value from [d]'s timeline entries
  /// back to [d.keelDown]. Call after any timeline mutation.
  void syncKeelFromTimeline(DayEntry d) {
    for (final t in d.timeline.reversed) {
      if (t.keelDown != null) {
        d.keelDown = t.keelDown;
        return;
      }
    }
  }

  void addTimelineEntry(DateTime day, TimelineEntry entry) {
    final normalized = DateTime(day.year, day.month, day.day);
    final d = _entries[normalized];
    if (d == null) return;

    // On the very first timeline entry, auto-snapshot the crew list.
    if (d.timeline.isEmpty && d.crew.isNotEmpty) {
      d.timeline.add(TimelineEntry(
        time: entry.time,
        vesselStatusNote: buildCrewNote(d.crew),
      ));
    }

    d.timeline.add(entry);
    d.timeline.sort((a, b) => a.time.compareTo(b.time));
    syncKeelFromTimeline(d);
    _dayBox.put(normalized.toIso8601String(), d);
    _recordLocalEdit(normalized);
    _syncToFirestore(d);
    notifyListeners();
  }

  // ── GPX import ─────────────────────────────────────────────────────────────

  Future<void> importGpx(DateTime day, File file) async {
    final normalized = DateTime(day.year, day.month, day.day);
    final bytes = await file.readAsBytes();
    final points = GpxParser().parseBytes(bytes);
    if (points.isEmpty) return;
    await _saveTrack(normalized, file.uri.pathSegments.last, points);
    _storage?.uploadTrack(normalized, bytes).catchError((_) {});
  }

  Future<void> importGpxFromBytes(
      DateTime day, Uint8List bytes, String fileName) async {
    final normalized = DateTime(day.year, day.month, day.day);
    final points = GpxParser().parseBytes(bytes);
    if (points.isEmpty) return;
    await _saveTrack(normalized, fileName, points);
    _storage?.uploadTrack(normalized, bytes).catchError((_) {});
  }

  Future<void> _saveTrack(
      DateTime normalized, String fileName, List<TrackPoint> points) async {
    final track = DailyTrack(day: normalized, fileName: fileName, points: points);
    dailyTracks[normalized] = track;
    await _trackBox.put(normalized.toIso8601String(), track);
    notifyListeners();
  }

  Future<void> removeGpx(DateTime day) async {
    final normalized = DateTime(day.year, day.month, day.day);

    dailyTracks.remove(normalized);
    await _trackBox.delete(normalized.toIso8601String());
    _storage?.deleteTrack(normalized).catchError((_) {});

    final entry = _entries[normalized];
    if (entry != null) {
      await _dayBox.put(normalized.toIso8601String(), entry);
      _recordLocalEdit(normalized);
      _syncToFirestore(entry);
    }

    notifyListeners();
  }

  // ── Cross-correlation ──────────────────────────────────────────────────────

  TrackPoint? findClosestPoint(DateTime day, DateTime time) {
    final normalized = DateTime(day.year, day.month, day.day);
    final track = dailyTracks[normalized];
    if (track == null || track.points.isEmpty) return null;

    TrackPoint? best;
    Duration bestDiff = const Duration(days: 9999);
    for (final p in track.points) {
      final diff = p.time.toLocal().difference(time).abs();
      if (diff < bestDiff) { bestDiff = diff; best = p; }
    }
    return best;
  }

  // ── Full sync / re-attach ──────────────────────────────────────────────────

  /// Pushes every local entry to Firestore, then pulls every remote entry
  /// (remote wins for the same date).  Also syncs GPX tracks.
  Future<void> forceSync() async {
    final fs = _firestore;
    if (fs == null) throw Exception('Cloud-Sync nicht verfügbar.');

    // Push all local entries.
    for (final e in _entries.values) {
      await fs.saveEntry(e);
      _recordLocalEdit(e.date);
    }

    // Pull all remote entries (remote wins for conflicts on force-sync).
    final all = await fs.fetchAllEntries();
    var changed = false;
    for (final e in all) {
      _entries[e.date] = e;
      await _dayBox.put(e.date.toIso8601String(), e);
      changed = true;
    }
    if (changed) notifyListeners();

    _setLastSyncAt();

    // GPX tracks.
    final st = _storage;
    if (st != null) {
      final cloudDates = await st.listTrackDates();
      final missing = cloudDates.where((d) => !dailyTracks.containsKey(d)).toList();
      for (final date in missing) {
        final bytes = await st.downloadTrack(date);
        if (bytes == null || bytes.isEmpty) continue;
        final points = GpxParser().parseBytes(bytes);
        if (points.isEmpty) continue;
        await _saveTrack(date, '$date.gpx', points);
      }
    }
  }

  /// Switches to a different logbook code: wipes local data and pulls from cloud.
  Future<void> reattachAndSync(
      FirestoreService firestoreService, StorageService storageService) async {
    await _entrySub?.cancel();
    _entrySub = null;
    await _rosterSub?.cancel();
    _rosterSub = null;

    for (final t in _syncTimers.values) { t.cancel(); }
    _syncTimers.clear();

    await _dayBox.clear();
    await _trackBox.clear();
    await _syncStateBox.clear();
    await _rosterBox.clear();
    _entries.clear();
    dailyTracks.clear();

    _firestore = firestoreService;
    _storage = storageService;

    try {
      final all = await firestoreService.fetchAllEntries();
      for (final e in all) {
        _entries[e.date] = e;
        await _dayBox.put(e.date.toIso8601String(), e);
      }
      _setLastSyncAt();
    } catch (_) {}

    try {
      final cloudDates = await storageService.listTrackDates();
      for (final date in cloudDates) {
        final bytes = await storageService.downloadTrack(date);
        if (bytes == null || bytes.isEmpty) continue;
        final points = GpxParser().parseBytes(bytes);
        if (points.isEmpty) continue;
        await _saveTrack(date, '$date.gpx', points);
      }
    } catch (_) {}

    notifyListeners();

    // Re-subscribe to the new logbook's streams.
    _entrySub = firestoreService
        .entryChanges()
        .asyncMap(_applyRemoteEntries)
        .listen((_) {}, onError: (_) {});

    try {
      final remoteRoster = await firestoreService.fetchRoster();
      if (remoteRoster.isNotEmpty) await _applyRemoteRoster(remoteRoster);
    } catch (_) {}

    _rosterSub = firestoreService
        .rosterChanges()
        .asyncMap(_applyRemoteRoster)
        .listen((_) {}, onError: (_) {});
  }

  // ── Crew roster CRUD ───────────────────────────────────────────────────────

  void saveRosterMember(CrewMember m) {
    m.id ??= _newId();
    _rosterBox.put(m.id!, m);
    _syncRosterToFirestore();
    notifyListeners();
  }

  void deleteRosterMember(String id) {
    _rosterBox.delete(id);
    _syncRosterToFirestore();
    notifyListeners();
  }

  Future<void> _applyRemoteRoster(List<CrewMember> members) async {
    await _rosterBox.clear();
    for (final m in members) {
      if (m.id != null) await _rosterBox.put(m.id!, m);
    }
    notifyListeners();
  }

  void _syncRosterToFirestore() {
    _firestore?.saveRoster(_rosterBox.values.toList()).catchError((_) {});
  }

  static String _newId() {
    final r = Random.secure();
    return List.generate(16, (_) => r.nextInt(256))
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  static String buildCrewNote(List<CrewMember> crew) {
    final parts = crew.asMap().entries.map((e) =>
        e.key == 0 ? '${e.value.name} (Skipper)' : e.value.name).toList();
    return 'Besatzung: ${parts.join(' · ')}';
  }

  // ── Private Firestore helpers ──────────────────────────────────────────────

  void _debouncedSync(DayEntry entry) {
    _syncTimers[entry.date]?.cancel();
    _syncTimers[entry.date] = Timer(const Duration(seconds: 2), () {
      _syncToFirestore(entry);
      _syncTimers.remove(entry.date);
    });
  }

  void _syncToFirestore(DayEntry entry) {
    _firestore?.saveEntry(entry).catchError((_) {});
  }

  @override
  void dispose() {
    _entrySub?.cancel();
    _rosterSub?.cancel();
    for (final t in _syncTimers.values) { t.cancel(); }
    super.dispose();
  }
}
