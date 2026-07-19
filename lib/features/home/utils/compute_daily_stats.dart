/// Trip statistics — Dart port of gpx_trip_stats.py.
///
/// Design decisions (matching the Python reference):
///   1. Stops (detected stationary segments) are excluded from distance and
///      speed.  Only consecutive moving fixes contribute.
///   2. Two average speeds are reported:
///        avgOverGroundKn: moving_distance / moving_time — honest mechanical avg.
///        avgMakingWayKn:  only fixes ≥ 1.0 kn — "how fast when actually sailing".
///   3. Max speed is reported robustly (p99 of moving inst. speeds) to suppress
///      lone GPS glitches, with the raw max available separately.
///   4. Stationary time is the sum of stop durations; moving time is the rest.
library;

import 'dart:math';

import '../domain/track_point.dart';
import 'filter_settings.dart';
import 'trim_track.dart';

/// Computed trip statistics for one day's GPS track (see [computeDailyStats]).
class DailyStats {
  final double distanceNm;

  final Duration totalDuration;
  final Duration movingDuration;
  final Duration stationaryDuration;

  /// Moving distance / moving time — honest average including slow stretches.
  final double avgOverGroundKn;

  /// Average speed counting only fixes at or above 1.0 kn.
  final double avgMakingWayKn;

  /// Robust max speed (p99 of instantaneous moving speeds).
  final double maxSpeedKn;

  /// True single-fix maximum — reported alongside to flag potential spikes.
  final double maxSpeedRawKn;

  final int nStops;
  final int nSpikes;

  // Backward-compat aliases used by existing UI code.
  double get avgSpeed => avgOverGroundKn;
  double get maxSpeed => maxSpeedKn;
  int    get stopCount => nStops;

  const DailyStats({
    required this.distanceNm,
    required this.totalDuration,
    required this.movingDuration,
    required this.stationaryDuration,
    required this.avgOverGroundKn,
    required this.avgMakingWayKn,
    required this.maxSpeedKn,
    required this.maxSpeedRawKn,
    required this.nStops,
    required this.nSpikes,
  });
}

/// Computes distance/duration/speed statistics from a day's raw GPS
/// [rawPoints], first running them through [trimTrackWithAnchors] to strip
/// stationary anchor periods and GPS noise before measuring anything.
DailyStats computeDailyStats(
  List<TrackPoint> rawPoints, {
  FilterSettings settings = const FilterSettings(),
}) {
  if (rawPoints.length < 2) {
    return const DailyStats(
      distanceNm: 0,
      totalDuration: Duration.zero,
      movingDuration: Duration.zero,
      stationaryDuration: Duration.zero,
      avgOverGroundKn: 0,
      avgMakingWayKn: 0,
      maxSpeedKn: 0,
      maxSpeedRawKn: 0,
      nStops: 0,
      nSpikes: 0,
    );
  }

  final result  = trimTrackWithAnchors(rawPoints, settings: settings);
  final pts     = result.points;
  final anchors = result.anchors;

  final totalDuration =
      rawPoints.last.time.difference(rawPoints.first.time).abs();
  final stationaryS = anchors.fold<double>(
      0.0, (s, a) => s + a.durationMinutes * 60.0);

  if (pts.length < 2) {
    return DailyStats(
      distanceNm: 0,
      totalDuration: totalDuration,
      movingDuration: Duration.zero,
      stationaryDuration: Duration(seconds: stationaryS.round()),
      avgOverGroundKn: 0,
      avgMakingWayKn: 0,
      maxSpeedKn: 0,
      maxSpeedRawKn: 0,
      nStops: anchors.length,
      nSpikes: result.nSpikes,
    );
  }

  const mpsToKn            = 1.94384;
  final makingWayThresholdKn = settings.makingWayThresholdKn;
  final maxSpeedPercentile   = settings.topSpeedPercentile.clamp(0.0, 1.0);

  double distanceM    = 0;
  double makewayDistM = 0;
  double makewayTimeS = 0;

  for (int i = 1; i < pts.length; i++) {
    final p1 = pts[i - 1];
    final p2 = pts[i];
    final dt = p2.time.difference(p1.time).inSeconds.toDouble();
    if (dt <= 0) continue;

    final d       = _haversineM(p1.lat, p1.lon, p2.lat, p2.lon);
    final speedKn = d / dt * mpsToKn;

    // Distance is summed across every consecutive pair in `pts`, including
    // the one pair bracketing a stop trimTrackWithAnchors excised (its own
    // points removed) — left as-is since a stop's position barely moves
    // (anchor swing/GPS drift only), so that pair's distance contribution
    // is negligible either way.
    distanceM += d;

    if (speedKn >= makingWayThresholdKn) {
      makewayDistM += d;
      makewayTimeS += dt;
    }
  }

  // Moving time is "the rest" after subtracting stationary time from the
  // total elapsed span (see file header) — NOT the sum of consecutive-fix
  // deltas in `pts` the way distance above is. trimTrackWithAnchors removes
  // each stop's own points from `pts` entirely, so the one delta bracketing
  // an excised stop would otherwise still count that whole stop's duration
  // as "moving" — in practice making movingTimeS come out close to
  // totalDuration for any track with a real stop in it.
  final movingTimeS =
      (totalDuration.inSeconds.toDouble() - stationaryS).clamp(0.0, double.infinity);

  // Use pre-computed moving instantaneous speeds from the pipeline (v5).
  // These are derived before smoothing, so they reflect real GPS velocity.
  final instantSpeeds = List<double>.from(result.movingInstSpeedsKn)..sort();

  double maxSpeedKn    = 0;
  double maxSpeedRawKn = 0;
  if (instantSpeeds.isNotEmpty) {
    final idx = ((instantSpeeds.length - 1) * maxSpeedPercentile).floor();
    maxSpeedKn    = instantSpeeds[idx.clamp(0, instantSpeeds.length - 1)];
    maxSpeedRawKn = instantSpeeds.last;
  }

  return DailyStats(
    distanceNm:        distanceM / 1852.0,
    totalDuration:     totalDuration,
    movingDuration:    Duration(seconds: movingTimeS.round()),
    stationaryDuration: Duration(seconds: stationaryS.round()),
    avgOverGroundKn:   movingTimeS > 0 ? distanceM / movingTimeS * mpsToKn : 0.0,
    avgMakingWayKn:    makewayTimeS > 0 ? makewayDistM / makewayTimeS * mpsToKn : 0.0,
    maxSpeedKn:        maxSpeedKn,
    maxSpeedRawKn:     maxSpeedRawKn,
    nStops:            anchors.length,
    nSpikes:           result.nSpikes,
  );
}

/// Great-circle distance in metres between two lat/lon points.
double _haversineM(double lat1, double lon1, double lat2, double lon2) {
  const r   = 6371000.0;
  final dLat = (lat2 - lat1) * pi / 180;
  final dLon = (lon2 - lon1) * pi / 180;
  final a   = sin(dLat / 2) * sin(dLat / 2) +
      cos(lat1 * pi / 180) * cos(lat2 * pi / 180) *
          sin(dLon / 2) * sin(dLon / 2);
  return r * 2 * atan2(sqrt(a), sqrt(1 - a));
}
