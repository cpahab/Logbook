import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:gpx/gpx.dart';
import 'package:hive/hive.dart';

import '../domain/day_entry.dart';
import '../domain/timeline_entry.dart';
import '../domain/daily_track.dart';
import '../domain/track_point.dart';
import '../utils/gpx_parser.dart';
import '../../../core/services/firestore_service.dart';
import '../../../core/services/storage_service.dart';

class HomeRepository extends ChangeNotifier {
  // Hive boxes
  late Box<DayEntry> _dayBox;
  late Box<DailyTrack> _trackBox;

  // In-memory caches
  final Map<DateTime, DayEntry> _entries = {};
  final Map<DateTime, DailyTrack> dailyTracks = {};

  // Cloud services (null until attach* is called)
  FirestoreService? _firestore;
  StorageService? _storage;

  // Debounce timers keyed by entry date — avoids flooding Firestore on rapid typing
  final Map<DateTime, Timer> _syncTimers = {};

  // Public getter
  List<DayEntry> get entries =>
      _entries.values.toList()..sort((a, b) => a.date.compareTo(b.date));

  /// Participants from the most recent entry that has any, used as prefill.
  List<String> get lastParticipants {
    for (final e in entries.reversed) {
      if (e.participantsList.isNotEmpty) {
        return List<String>.from(e.participantsList);
      }
    }
    return [];
  }

  // ------------------------------------------------------------
  // INITIALIZATION
  // ------------------------------------------------------------
  Future<void> init() async {
    _dayBox = await Hive.openBox<DayEntry>('daily_entries');
    _trackBox = await Hive.openBox<DailyTrack>('daily_tracks');

    for (final e in _dayBox.values) {
      _entries[e.date] = e;
    }
    for (final t in _trackBox.values) {
      dailyTracks[t.day] = t;
    }

    notifyListeners();
  }

  /// Attaches Firestore. When [initialSync] is true (first launch after the
  /// cloud feature was introduced) all local Hive entries are pushed up first,
  /// then any cloud-only entries are pulled down.
  Future<void> attachFirestore(FirestoreService service,
      {bool initialSync = false}) async {
    _firestore = service;
    try {
      if (initialSync) {
        for (final e in _entries.values) {
          await service.saveEntry(e);
        }
      }
      final missing =
          await service.fetchMissingEntries(_entries.keys.toSet());
      for (final e in missing) {
        _entries[e.date] = e;
        await _dayBox.put(e.date.toIso8601String(), e);
      }
      if (missing.isNotEmpty) notifyListeners();
    } catch (_) {
      // Offline or timeout — continue with local data.
    }
  }

  /// Attaches Storage. When [initialSync] is true all local Hive tracks are
  /// reconstructed as GPX and uploaded, then cloud-only tracks are downloaded.
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
      final missing =
          cloudDates.where((d) => !dailyTracks.containsKey(d)).toList();
      for (final date in missing) {
        final bytes = await service.downloadTrack(date);
        if (bytes == null || bytes.isEmpty) continue;
        final points = GpxParser().parseBytes(bytes);
        if (points.isEmpty) continue;
        await _saveTrack(date, '$date.gpx', points);
      }
    } catch (_) {
      // Offline or timeout — continue with local data.
    }
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

  // ------------------------------------------------------------
  // DAY ENTRY MANAGEMENT
  // ------------------------------------------------------------
  void addEntry(DateTime date) {
    final normalized = DateTime(date.year, date.month, date.day);
    if (_entries.containsKey(normalized)) return;

    final entry = DayEntry(date: normalized, timeline: [], participantsList: lastParticipants);
    _entries[normalized] = entry;
    _dayBox.put(normalized.toIso8601String(), entry);
    _syncToFirestore(entry);
    notifyListeners();
  }

  DayEntry? getEntry(DateTime date) {
    final normalized = DateTime(date.year, date.month, date.day);
    return _entries[normalized];
  }

  Future<void> removeEntry(DateTime date) async {
    final normalized = DateTime(date.year, date.month, date.day);

    _entries.remove(normalized);
    await _dayBox.delete(normalized.toIso8601String());

    if (dailyTracks.containsKey(normalized)) {
      dailyTracks.remove(normalized);
      await _trackBox.delete(normalized.toIso8601String());
    }

    _firestore?.deleteEntry(normalized).catchError((_) {});
    notifyListeners();
  }

  // ------------------------------------------------------------
  // SAVE (field edits from the UI call this instead of entry.save())
  // ------------------------------------------------------------

  /// Persists [entry] to Hive immediately, then syncs to Firestore with a
  /// 2-second debounce so rapid text-field changes don't flood Firestore.
  void saveEntry(DayEntry entry) {
    entry.save();
    notifyListeners();
    _debouncedSync(entry);
  }

  // ------------------------------------------------------------
  // TIMELINE MANAGEMENT
  // ------------------------------------------------------------
  void addTimelineEntry(DateTime day, TimelineEntry entry) {
    final normalized = DateTime(day.year, day.month, day.day);
    final d = _entries[normalized];
    if (d == null) return;

    d.timeline.add(entry);
    d.timeline.sort((a, b) => a.time.compareTo(b.time));
    _dayBox.put(normalized.toIso8601String(), d);
    _syncToFirestore(d);
    notifyListeners();
  }

  // ------------------------------------------------------------
  // GPX IMPORT (tracks stay local-only)
  // ------------------------------------------------------------
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
    final track =
        DailyTrack(day: normalized, fileName: fileName, points: points);
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
      entry.hasGpx = false;
      await _dayBox.put(normalized.toIso8601String(), entry);
      _syncToFirestore(entry);
    }

    notifyListeners();
  }

  // ------------------------------------------------------------
  // CROSS-CORRELATION: FIND CLOSEST TRACK POINT
  // ------------------------------------------------------------
  TrackPoint? findClosestPoint(DateTime day, DateTime time) {
    final normalized = DateTime(day.year, day.month, day.day);
    final track = dailyTracks[normalized];
    if (track == null || track.points.isEmpty) return null;

    TrackPoint? best;
    Duration bestDiff = const Duration(days: 9999);

    for (final p in track.points) {
      final diff = p.time.toLocal().difference(time).abs();
      if (diff < bestDiff) {
        bestDiff = diff;
        best = p;
      }
    }

    return best;
  }

  // ------------------------------------------------------------
  // SYNC
  // ------------------------------------------------------------

  /// Uploads all local entries then pulls every remote entry, with remote
  /// winning for conflicting dates. Throws if no Firestore service is attached.
  Future<void> forceSync() async {
    final fs = _firestore;
    if (fs == null) throw Exception('Cloud-Sync nicht verfügbar.');

    for (final e in _entries.values) {
      await fs.saveEntry(e);
    }

    final all = await fs.fetchAllEntries();
    var changed = false;
    for (final e in all) {
      _entries[e.date] = e;
      await _dayBox.put(e.date.toIso8601String(), e);
      changed = true;
    }
    if (changed) notifyListeners();

    final st = _storage;
    if (st != null) {
      final cloudDates = await st.listTrackDates();
      final missingDates = cloudDates.where((d) => !dailyTracks.containsKey(d)).toList();
      for (final date in missingDates) {
        final bytes = await st.downloadTrack(date);
        if (bytes == null || bytes.isEmpty) continue;
        final points = GpxParser().parseBytes(bytes);
        if (points.isEmpty) continue;
        await _saveTrack(date, '$date.gpx', points);
      }
    }
  }

  /// Switches to new cloud services and runs a full bidirectional sync.
  Future<void> reattachAndSync(
      FirestoreService firestoreService, StorageService storageService) async {
    for (final t in _syncTimers.values) t.cancel();
    _syncTimers.clear();
    _firestore = firestoreService;
    _storage = storageService;
    await forceSync();
  }

  // ------------------------------------------------------------
  // PRIVATE FIRESTORE HELPERS
  // ------------------------------------------------------------

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
    for (final t in _syncTimers.values) {
      t.cancel();
    }
    super.dispose();
  }
}
