import '../domain/timeline_entry.dart';
import '../domain/track_point.dart';

/// Correlates timeline entries with the closest track point.
/// Returns a list of tuples: (TimelineEntry, TrackPoint)
List<(TimelineEntry, TrackPoint)> correlateTimelineWithTrack(
  List<TimelineEntry> timeline,
  List<TrackPoint> trackPoints,
) {
  final result = <(TimelineEntry, TrackPoint)>[];

  if (trackPoints.isEmpty) {
    //print("⚠️ correlateTimelineWithTrack: No track points available.");
    return result;
  }

  //print("🔍 Starting correlation...");
  //print("📌 Track has ${trackPoints.length} points.");
  //print("📌 Timeline has ${timeline.length} entries.");

  for (final t in timeline) {
    //print("\n----------------------------------------");
    //print("🕒 Timeline entry at: ${t.time}");

    // Use timeline date + timeline time
    final target = DateTime(
      t.time.year,
      t.time.month,
      t.time.day,
      t.time.hour,
      t.time.minute,
      t.time.second,
    );

    //print("🎯 Target datetime for correlation: $target");

    TrackPoint? best;
    Duration bestDiff = const Duration(days: 9999);

    for (final p in trackPoints) {
      final diff = p.time.toLocal().difference(target).abs();

      //print("  • GPX point: ${p.time.toLocal()}  → diff: ${diff.inSeconds}s");

      if (diff < bestDiff) {
        bestDiff = diff;
        best = p;
      }
    }

    if (best != null) {
      //print("✅ Closest GPX point: ${best.time}  (Δ ${bestDiff.inSeconds}s)");
      result.add((t, best));
    } else {
      //print("❌ No matching GPX point found.");
    }
  }

  //print("\n🎉 Correlation complete. ${result.length} matches found.");
  //print("----------------------------------------\n");

  return result;
}
