import 'dart:math';

import '../domain/track_point.dart';

double _haversineM(double lat1, double lon1, double lat2, double lon2) {
  const r = 6371000.0;
  final dLat = (lat2 - lat1) * pi / 180;
  final dLon = (lon2 - lon1) * pi / 180;
  final a = sin(dLat / 2) * sin(dLat / 2) +
      cos(lat1 * pi / 180) * cos(lat2 * pi / 180) *
          sin(dLon / 2) * sin(dLon / 2);
  return r * 2 * atan2(sqrt(a), sqrt(1 - a));
}

/// Trims stationary sections at the very start and end of a GPS track.
///
/// Uses **net displacement** from each candidate point rather than cumulative
/// path length — this is robust against GPS positional noise that would
/// otherwise inflate path lengths while the boat is at rest.
///
/// A point is accepted as the movement start/end if, within [windowSeconds]
/// forward (or backward for the end), the boat reaches at least
/// [minDisplacementM] away from it.
///
/// The search is limited to the first/last [maxTrimSeconds] of the track so
/// mid-trip stops (anchorages, locks) are never accidentally trimmed.
List<TrackPoint> trimStationaryEnds(
  List<TrackPoint> points, {
  int windowSeconds = 300,        // 5-min detection window
  double minDisplacementM = 80.0, // ≈ 0.52 kn effective speed over window
  int maxTrimSeconds = 1800,      // don't trim more than 30 min from each end
}) {
  if (points.length < 4) return points;

  final totalSecs =
      points.last.time.difference(points.first.time).abs().inSeconds;
  final effectiveMaxTrim = min(maxTrimSeconds, totalSecs ~/ 2);

  final fwdDeadline =
      points.first.time.add(Duration(seconds: effectiveMaxTrim));
  final bwdHorizon =
      points.last.time.subtract(Duration(seconds: effectiveMaxTrim));

  // Forward scan: find first point from which the boat reaches
  // minDisplacementM within windowSeconds.
  int startIdx = 0;
  outerFwd:
  for (int i = 0; i < points.length - 1; i++) {
    if (points[i].time.isAfter(fwdDeadline)) break;
    final t0 = points[i].time;
    for (int j = i + 1; j < points.length; j++) {
      if (points[j].time.difference(t0).inSeconds > windowSeconds) break;
      final disp = _haversineM(
          points[i].lat, points[i].lon, points[j].lat, points[j].lon);
      if (disp >= minDisplacementM) {
        startIdx = i;
        break outerFwd;
      }
    }
  }

  // Backward scan: find last point from which the boat was >= minDisplacementM
  // away within the previous windowSeconds.
  int endIdx = points.length - 1;
  outerBwd:
  for (int i = points.length - 1; i > 0; i--) {
    if (points[i].time.isBefore(bwdHorizon)) break;
    final t0 = points[i].time;
    for (int j = i - 1; j >= 0; j--) {
      if (t0.difference(points[j].time).inSeconds > windowSeconds) break;
      final disp = _haversineM(
          points[i].lat, points[i].lon, points[j].lat, points[j].lon);
      if (disp >= minDisplacementM) {
        endIdx = i;
        break outerBwd;
      }
    }
  }

  if (endIdx <= startIdx) return points;
  return points.sublist(startIdx, endIdx + 1);
}
