import 'timeline_entry.dart';
import 'track_point.dart';

class DayEntry {
  final DateTime date;
  final List<TimelineEntry> timeline = [];
  final List<TrackPoint> track = [];

  bool hasGpx = false;

  // optional metadata
  String? fromHarbor;
  String? toHarbor;

  // computed statistics
  double distanceNm = 0.0;
  Duration totalDuration = Duration.zero;
  Duration movingDuration = Duration.zero;
  double avgSpeedKnots = 0.0;
  double maxSpeedKnots = 0.0;

  DayEntry({required this.date});

  factory DayEntry.empty(DateTime date) => DayEntry(date: date);
}
