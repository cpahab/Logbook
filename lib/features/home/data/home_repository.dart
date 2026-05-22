import 'package:flutter/foundation.dart';
import '../domain/day_entry.dart';
import '../domain/timeline_entry.dart';
import 'dart:io';
import 'dart:math';
import '../utils/gpx_parser.dart';

class HomeRepository extends ChangeNotifier {
  final List<DayEntry> entries = [];

  /// Add a new day entry if it doesn't exist yet
  void addEntry(DateTime date) {
    final exists = entries.any((e) =>
        e.date.year == date.year &&
        e.date.month == date.month &&
        e.date.day == date.day);

    if (!exists) {
      entries.add(DayEntry(date: date));
      _sortEntries();
      notifyListeners();
    }
  }

  /// Add a timeline entry to a specific day
  void addTimelineEntry(DateTime date, TimelineEntry entry) {
    final day = entries.firstWhere(
      (e) =>
          e.date.year == date.year &&
          e.date.month == date.month &&
          e.date.day == date.day,
      orElse: () => throw Exception("DayEntry not found for $date"),
    );

    day.timeline.add(entry);
    day.timeline.sort((a, b) => a.time.compareTo(b.time));

    notifyListeners();
  }

  /// Sort entries by date (descending)
  void _sortEntries() {
    entries.sort((a, b) => b.date.compareTo(a.date));
  }

  /// Import GPX and compute statistics
  Future<void> importGpx(DateTime date, File file) async {
    final day = entries.firstWhere(
      (e) =>
          e.date.year == date.year &&
          e.date.month == date.month &&
          e.date.day == date.day,
    );

    // Parse all GPX points
    final points = await GpxParser.parse(file);

    // Convert timestamps to local time and filter
    final filtered = points.where((p) {
      final t = p.time.toLocal();
      return t.year == date.year &&
            t.month == date.month &&
            t.day == date.day;
    }).toList();

    // Sort by time (important for speed/distance)
    filtered.sort((a, b) => a.time.compareTo(b.time));

    day.track
      ..clear()
      ..addAll(filtered);

    day.hasGpx = filtered.isNotEmpty;

    // Compute statistics
    _computeStatistics(day);


    notifyListeners();
  }

  // ------------------------------------------------------------
  // STATISTICS ENGINE
  // ------------------------------------------------------------

  void _computeStatistics(DayEntry day) {
    final pts = day.track;
    if (pts.length < 2) {
    day.distanceNm = 0;
    day.totalDuration = Duration.zero;
    day.movingDuration = Duration.zero;
    day.avgSpeedKnots = 0;
    day.maxSpeedKnots = 0;
    return;
  }

  double totalMeters = 0.0;
  double movingMeters = 0.0;
  double maxSpeed = 0.0;
  Duration moving = Duration.zero;

  for (int i = 1; i < pts.length; i++) {
    final p1 = pts[i - 1];
    final p2 = pts[i];

    final dt = p2.time.difference(p1.time).inSeconds;
    if (dt <= 0) continue;

    final dMeters = _haversineMeters(p1.lat, p1.lon, p2.lat, p2.lon);
    totalMeters += dMeters;

    final speedMps = dMeters / dt;
    final speedKnots = speedMps * 1.94384;

    if (speedKnots > maxSpeed) maxSpeed = speedKnots;

    // Movement threshold: > 0.5 knots
    if (speedKnots > 0.5) {
      moving += Duration(seconds: dt);
      movingMeters += dMeters;
    }
  }

  final totalDuration = pts.last.time.difference(pts.first.time);

  day.distanceNm = totalMeters / 1852.0;
  day.totalDuration = totalDuration;
  day.movingDuration = moving;

  // NEW: average speed only from moving segments
  day.avgSpeedKnots =
      moving.inSeconds > 0
          ? (movingMeters / 1852.0) / (moving.inSeconds / 3600)
          : 0.0;

  day.maxSpeedKnots = maxSpeed;
}

double _haversineMeters(double lat1, double lon1, double lat2, double lon2) {
  const R = 6371000.0; // Earth radius in meters
  final dLat = _degToRad(lat2 - lat1);
  final dLon = _degToRad(lon2 - lon1);

  final a = sin(dLat / 2) * sin(dLat / 2) +
      cos(_degToRad(lat1)) *
          cos(_degToRad(lat2)) *
          sin(dLon / 2) *
          sin(dLon / 2);

  final c = 2 * atan2(sqrt(a), sqrt(1 - a));
  return R * c;
}

double _degToRad(double deg) => deg * pi / 180.0;

}

