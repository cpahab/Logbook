import '../domain/timeline_entry.dart';
import '../domain/track_point.dart';

/// Pairs each timeline entry with its nearest-in-time GPS track point, so a
/// manually logged event (e.g. "left harbor") can be shown/anchored at the
/// position the boat actually was at that time.
/// Returns a list of tuples: (TimelineEntry, TrackPoint)
List<(TimelineEntry, TrackPoint)> correlateTimelineWithTrack(
  List<TimelineEntry> timeline,
  List<TrackPoint> trackPoints,
) {
  final result = <(TimelineEntry, TrackPoint)>[];
  if (trackPoints.isEmpty) return result;

  for (final t in timeline) {
    final target = DateTime(
      t.time.year,
      t.time.month,
      t.time.day,
      t.time.hour,
      t.time.minute,
      t.time.second,
    );

    TrackPoint? best;
    Duration bestDiff = const Duration(days: 9999);

    for (final p in trackPoints) {
      final diff = p.time.toLocal().difference(target).abs();
      if (diff < bestDiff) {
        bestDiff = diff;
        best = p;
      }
    }

    if (best != null) result.add((t, best));
  }

  return result;
}
