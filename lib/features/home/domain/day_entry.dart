import 'timeline_entry.dart';
import 'track_point.dart';

class DayEntry {
  final DateTime date;
  final List<TimelineEntry> timeline;
  final List<TrackPoint> track;
  bool hasGpx;

  DayEntry({
    required this.date,
    this.hasGpx = false,
    List<TimelineEntry>? timeline,
    List<TrackPoint>? track,
  })  : timeline = timeline ?? [],
        track = track ?? [];
}
