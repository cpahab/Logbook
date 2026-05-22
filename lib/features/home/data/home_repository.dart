import 'package:flutter/foundation.dart';
import '../domain/day_entry.dart';
import '../domain/timeline_entry.dart';
import 'package:gpx/gpx.dart';
import 'dart:io';
import '../domain/track_point.dart';
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

    // Sort timeline by time
    day.timeline.sort((a, b) => a.time.compareTo(b.time));

    notifyListeners();
  }

  /// Sort entries by date (descending)
  void _sortEntries() {
    entries.sort((a, b) => b.date.compareTo(a.date));
  }

  Future<void> importGpx(DateTime date, File file) async {
    final day = entries.firstWhere(
      (e) =>
          e.date.year == date.year &&
          e.date.month == date.month &&
          e.date.day == date.day,
    );

    final points = await GpxParser.parse(file);

    day.track
      ..clear()
      ..addAll(points);

    day.hasGpx = points.isNotEmpty;

    notifyListeners();
  }

}

final homeRepository = HomeRepository();
