import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import '../domain/day_entry.dart';
import '../domain/timeline_entry.dart';
import '../domain/daily_track.dart';
import '../domain/track_point.dart';
import '../utils/gpx_parser.dart';

class HomeRepository extends ChangeNotifier {
  // Hive boxes
  late Box<DayEntry> _dayBox;
  late Box<DailyTrack> _trackBox;

  // In‑memory caches
  final Map<DateTime, DayEntry> _entries = {};
  final Map<DateTime, DailyTrack> dailyTracks = {};

  // Public getter
  List<DayEntry> get entries =>
      _entries.values.toList()..sort((a, b) => a.date.compareTo(b.date));

  // ------------------------------------------------------------
  // INITIALIZATION
  // ------------------------------------------------------------
  Future<void> init() async {
    _dayBox = await Hive.openBox<DayEntry>('daily_entries');
    _trackBox = await Hive.openBox<DailyTrack>('daily_tracks');

    // Load entries
    for (final e in _dayBox.values) {
      _entries[e.date] = e;
    }

    // Load tracks
    for (final t in _trackBox.values) {
      dailyTracks[t.day] = t;
    }

    notifyListeners();
  }

  // ------------------------------------------------------------
  // DAY ENTRY MANAGEMENT
  // ------------------------------------------------------------
  void addEntry(DateTime date) {
    final normalized = DateTime(date.year, date.month, date.day);

    if (_entries.containsKey(normalized)) return;

    final entry = DayEntry(date: normalized, timeline: []);
    _entries[normalized] = entry;
    _dayBox.put(normalized.toIso8601String(), entry);

    notifyListeners();
  }

  DayEntry? getEntry(DateTime date) {
    final normalized = DateTime(date.year, date.month, date.day);
    return _entries[normalized];
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
    notifyListeners();
  }

  // ------------------------------------------------------------
  // GPX IMPORT
  // ------------------------------------------------------------
  Future<void> importGpx(DateTime day, File file) async {
    final normalized = DateTime(day.year, day.month, day.day);

    final parser = GpxParser();
    final points = await parser.parse(file);

    if (points.isEmpty) return;

    // Sort by time
    points.sort((a, b) => a.time.compareTo(b.time));

    final track = DailyTrack(
      day: normalized,
      fileName: file.path.split('/').last,
      points: points,
    );

    dailyTracks[normalized] = track;
    await _trackBox.put(normalized.toIso8601String(), track);

    notifyListeners();
  }

  // ------------------------------------------------------------
  // CROSS‑CORRELATION: FIND CLOSEST TRACK POINT
  // ------------------------------------------------------------
  TrackPoint? findClosestPoint(DateTime day, DateTime time) {
    final normalized = DateTime(day.year, day.month, day.day);
    final track = dailyTracks[normalized];
    if (track == null || track.points.isEmpty) return null;

    TrackPoint? best;
    Duration bestDiff = const Duration(days: 9999);

    for (final p in track.points) {
      final diff = p.time.difference(time).abs();
      if (diff < bestDiff) {
        bestDiff = diff;
        best = p;
      }
    }

    return best;
  }
}
