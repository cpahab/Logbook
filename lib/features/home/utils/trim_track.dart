/// GPS track cleaning pipeline — Dart port of gpx_filter_reference_v2.py.
///
/// Four passes in order:
///   1. Annotate  — windowed speed + positional spread for every fix.
///   2. Trim      — find first/last moving fix using the chosen mode.
///   3. Spikes    — flag physically implausible moving fixes.
///   4. Smooth    — sliding-median on the kept track.
///
/// The trimmed-away clusters at each end are summarised as [TrackAnchor]
/// objects so the UI can render a "GPS halo" instead of raw noise points.
library;

import 'dart:math';

import '../domain/track_point.dart';
import 'filter_settings.dart';

// ── Constants ────────────────────────────────────────────────────────────────

const _mpsToKn = 1.94384; // m s⁻¹ → knots
const _maxSpeedKn = 12.0; // hard ceiling for spike detection
const _accelSigma = 4.0;  // robust sigma multiplier (median + σ × 1.4826 × MAD)

// ── Geometry ─────────────────────────────────────────────────────────────────

double _haversineM(double lat1, double lon1, double lat2, double lon2) {
  const r = 6_371_000.0;
  final dLat = (lat2 - lat1) * pi / 180;
  final dLon = (lon2 - lon1) * pi / 180;
  final a = sin(dLat / 2) * sin(dLat / 2) +
      cos(lat1 * pi / 180) * cos(lat2 * pi / 180) *
          sin(dLon / 2) * sin(dLon / 2);
  return r * 2 * atan2(sqrt(a), sqrt(1 - a));
}

// ── In-memory annotated fix ───────────────────────────────────────────────────

class _Fix {
  final TrackPoint pt;
  double instSpeedKn = 0; // instantaneous speed from previous fix
  double winSpeedKn  = 0; // centred window speed   (primary trim signal)
  double winSpreadM  = 0; // centred window spread  (secondary trim signal)
  bool stationary    = false;
  bool flagged       = false;

  _Fix(this.pt);
}

// ── Pass 1 — annotate ────────────────────────────────────────────────────────

/// Annotates each fix with [_Fix.winSpeedKn] and [_Fix.winSpreadM].
///
/// Window speed is the net displacement between fix[i-w] and fix[i+w] divided
/// by elapsed time, converted to knots.  Using net displacement (not path
/// length) keeps GPS jitter at the dock from faking forward motion.
///
/// Window spread is the mean distance of fixes in the window from their
/// centroid — independent of sample interval, so it behaves identically at
/// both 20 s and 60 s logging.
void _annotate(List<_Fix> fixes, int window) {
  final n = fixes.length;
  for (int i = 0; i < n; i++) {
    // ── Instantaneous speed ──
    if (i == 0) {
      fixes[i].instSpeedKn = 0;
    } else {
      final dt = fixes[i].pt.time.difference(fixes[i - 1].pt.time).inSeconds.toDouble();
      final d  = _haversineM(fixes[i - 1].pt.lat, fixes[i - 1].pt.lon,
                              fixes[i].pt.lat,     fixes[i].pt.lon);
      fixes[i].instSpeedKn = dt > 0 ? d / dt * _mpsToKn : 0;
    }

    // ── Window bounds ──
    final lo = max(0, i - window);
    final hi = min(n - 1, i + window);

    // ── Window speed (net displacement, time-normalised) ──
    final winDt = fixes[hi].pt.time.difference(fixes[lo].pt.time).inSeconds.toDouble();
    final winD  = _haversineM(fixes[lo].pt.lat, fixes[lo].pt.lon,
                               fixes[hi].pt.lat, fixes[hi].pt.lon);
    fixes[i].winSpeedKn = winDt > 0 ? winD / winDt * _mpsToKn : 0;

    // ── Window spread (mean distance from centroid of window slice) ──
    final slice = fixes.sublist(lo, hi + 1);
    var sumLat = 0.0, sumLon = 0.0;
    for (final f in slice) { sumLat += f.pt.lat; sumLon += f.pt.lon; }
    final cLat = sumLat / slice.length;
    final cLon = sumLon / slice.length;
    var sumDist = 0.0;
    for (final f in slice) {
      sumDist += _haversineM(cLat, cLon, f.pt.lat, f.pt.lon);
    }
    fixes[i].winSpreadM = sumDist / slice.length;
  }
}

// ── Pass 2 — trim ────────────────────────────────────────────────────────────

/// Marks [_Fix.stationary] for the leading and trailing runs of non-moving
/// fixes.  Returns `[startIdx, endIdx]` — the inclusive moving span.
///
/// In [StationaryMode.speed] a fix is stationary when its window speed is
/// below the threshold.  In [StationaryMode.both] it additionally requires the
/// positional spread to be below the spread threshold — this prevents an anchor
/// swing (≈0 speed, wide arc) from being treated as a stationary hold.
List<int> _trimEnds(List<_Fix> fixes, FilterSettings settings) {
  final n = fixes.length;

  bool isStationary(int i) {
    if (settings.stationaryMode == StationaryMode.both) {
      return fixes[i].winSpeedKn < settings.speedThresholdKn &&
          fixes[i].winSpreadM < settings.spreadThresholdM;
    }
    return fixes[i].winSpeedKn < settings.speedThresholdKn;
  }

  int start = 0;
  while (start < n && isStationary(start)) { start++; }
  if (start >= n) start = 0; // whole track stationary — keep everything

  int end = n - 1;
  while (end > start && isStationary(end)) { end--; }

  for (int i = 0; i < n; i++) {
    fixes[i].stationary = !(i >= start && i <= end);
  }
  return [start, end];
}

// ── Pass 3 — spike detection ─────────────────────────────────────────────────

/// Flags physically implausible moving fixes using a hard speed ceiling plus a
/// robust statistical gate (median + [_accelSigma] × 1.4826 × MAD).
///
/// Conservative by design: across all six Idefix files the Python reference
/// flagged zero fixes, because apparent "jumps" off the dock are real
/// acceleration.  The pass exists only for occasional GPS glitches.
void _flagSpikes(List<_Fix> fixes) {
  final movingSpds = fixes
      .where((f) => !f.stationary && f.instSpeedKn > 0)
      .map((f) => f.instSpeedKn)
      .toList()
    ..sort();
  if (movingSpds.isEmpty) return;

  final med = movingSpds[movingSpds.length ~/ 2];
  final mads = movingSpds.map((s) => (s - med).abs()).toList()..sort();
  final mad  = mads[mads.length ~/ 2];
  final effectiveMad = mad < 1e-9 ? 1e-6 : mad;
  final limit = max(_maxSpeedKn, med + _accelSigma * 1.4826 * effectiveMad);

  for (final f in fixes) {
    if (!f.stationary && f.instSpeedKn > limit) f.flagged = true;
  }
}

// ── Pass 4 — smoothing ───────────────────────────────────────────────────────

/// Centred sliding-median on lat and lon — removes single-fix jitter without
/// rounding genuine course changes.  window = 3 → ±1 fix.
List<TrackPoint> _smoothMedian(List<TrackPoint> pts, int window) {
  if (window < 2 || pts.length <= window) return pts;
  final half = window ~/ 2;
  final out  = <TrackPoint>[];
  for (int i = 0; i < pts.length; i++) {
    final lo    = max(0, i - half);
    final hi    = min(pts.length, i + half + 1);
    final slice = pts.sublist(lo, hi);
    final lats  = slice.map((p) => p.lat).toList()..sort();
    final lons  = slice.map((p) => p.lon).toList()..sort();
    out.add(TrackPoint(
      lat:  lats[lats.length ~/ 2],
      lon:  lons[lons.length ~/ 2],
      time: pts[i].time,
    ));
  }
  return out;
}

// ── Anchor computation ───────────────────────────────────────────────────────

/// Centroid and RMS positional spread of a cluster of trimmed points.
/// Used to render a "GPS halo" where the stationary cloud was.
class TrackAnchor {
  final double lat;
  final double lon;

  /// RMS distance from the centroid — indicates GPS scatter.
  /// Floored at 30 m so it is always visible on the map.
  final double radiusM;

  const TrackAnchor({
    required this.lat,
    required this.lon,
    required this.radiusM,
  });
}

TrackAnchor _computeAnchor(List<TrackPoint> cluster) {
  final n = cluster.length;
  var sumLat = 0.0, sumLon = 0.0;
  for (final p in cluster) { sumLat += p.lat; sumLon += p.lon; }
  final cLat = sumLat / n;
  final cLon = sumLon / n;

  var sumSq = 0.0;
  for (final p in cluster) {
    final d = _haversineM(cLat, cLon, p.lat, p.lon);
    sumSq += d * d;
  }
  return TrackAnchor(
    lat:     cLat,
    lon:     cLon,
    radiusM: max(30.0, sqrt(sumSq / n)),
  );
}

// ── Public result type ────────────────────────────────────────────────────────

class TrimResult {
  /// Trimmed, spike-filtered, and smoothed points — ready for rendering and
  /// stats.
  final List<TrackPoint> points;

  /// Centroid of the trimmed-away stationary cluster at the start, if any
  /// points were removed from the beginning.
  final TrackAnchor? startAnchor;

  /// Centroid of the trimmed-away stationary cluster at the end, if any
  /// points were removed from the end.
  final TrackAnchor? endAnchor;

  const TrimResult({
    required this.points,
    this.startAnchor,
    this.endAnchor,
  });
}

// ── Public API ────────────────────────────────────────────────────────────────

/// Full four-pass pipeline. Returns a [TrimResult] with cleaned points and
/// optional anchors for the removed stationary clusters.
TrimResult trimTrackWithAnchors(
  List<TrackPoint> points, {
  FilterSettings settings = const FilterSettings(),
}) {
  if (points.length < 4) return TrimResult(points: points);

  // Pass 1 — annotate
  final fixes = points.map(_Fix.new).toList();
  _annotate(fixes, settings.window);

  // Pass 2 — trim
  final span  = _trimEnds(fixes, settings);
  final start = span[0];
  final end   = span[1];

  // Compute anchors from the trimmed-away clusters BEFORE any further filtering
  final startAnchor = start > 0
      ? _computeAnchor(fixes.sublist(0, start).map((f) => f.pt).toList())
      : null;
  final endAnchor = end < fixes.length - 1
      ? _computeAnchor(fixes.sublist(end + 1).map((f) => f.pt).toList())
      : null;

  // Pass 3 — spikes
  _flagSpikes(fixes);

  // Collect kept points
  final kept = fixes
      .where((f) => !f.stationary && !f.flagged)
      .map((f) => f.pt)
      .toList();

  if (kept.isEmpty) {
    return TrimResult(
        points: points, startAnchor: startAnchor, endAnchor: endAnchor);
  }

  // Pass 4 — smooth
  final smoothed = settings.smoothWindow >= 2
      ? _smoothMedian(kept, settings.smoothWindow)
      : kept;

  return TrimResult(
    points:      smoothed,
    startAnchor: startAnchor,
    endAnchor:   endAnchor,
  );
}

/// Convenience wrapper — returns only the cleaned point list.
/// Use [trimTrackWithAnchors] when the anchor halos are also needed.
List<TrackPoint> trimStationaryEnds(
  List<TrackPoint> points, {
  FilterSettings settings = const FilterSettings(),
}) =>
    trimTrackWithAnchors(points, settings: settings).points;
