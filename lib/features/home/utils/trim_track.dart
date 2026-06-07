/// GPS track cleaning pipeline — Dart port of gpx_filter_reference_v3.py.
///
/// v3 upgrade: detects ALL stationary segments (dock, anchor, harbor stops
/// mid-track) rather than trimming only the leading/trailing ends.  A genuine
/// stop must last ≥ [FilterSettings.minStopMinutes] AND stay within
/// [FilterSettings.maxStopSpreadM] of its centroid.
///
/// Four passes in order:
///   1. Annotate  — windowed speed + positional spread for every fix.
///   2. Detect    — find ALL stationary segments (start, mid, end).
///   3. Spikes    — flag physically implausible moving fixes.
///   4. Smooth    — sliding-median on the kept track.
library;

import 'dart:math';

import '../domain/track_point.dart';
import 'filter_settings.dart';

// ── Constants ────────────────────────────────────────────────────────────────

const _mpsToKn    = 1.94384;
const _maxSpeedKn = 12.0;
const _accelSigma = 4.0;
const _mergeGap   = 4; // merge stationary runs separated by ≤ this many moving fixes

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
  double instSpeedKn = 0;
  double winSpeedKn  = 0;
  double winSpreadM  = 0;
  bool stationary    = false;
  bool flagged       = false;

  _Fix(this.pt);
}

// ── Pass 1 — annotate ────────────────────────────────────────────────────────

void _annotate(List<_Fix> fixes, int window) {
  final n = fixes.length;
  for (int i = 0; i < n; i++) {
    if (i == 0) {
      fixes[i].instSpeedKn = 0;
    } else {
      final dt = fixes[i].pt.time.difference(fixes[i - 1].pt.time).inSeconds.toDouble();
      final d  = _haversineM(fixes[i - 1].pt.lat, fixes[i - 1].pt.lon,
                              fixes[i].pt.lat,     fixes[i].pt.lon);
      fixes[i].instSpeedKn = dt > 0 ? d / dt * _mpsToKn : 0;
    }

    final lo = max(0, i - window);
    final hi = min(n - 1, i + window);

    final winDt = fixes[hi].pt.time.difference(fixes[lo].pt.time).inSeconds.toDouble();
    final winD  = _haversineM(fixes[lo].pt.lat, fixes[lo].pt.lon,
                               fixes[hi].pt.lat, fixes[hi].pt.lon);
    fixes[i].winSpeedKn = winDt > 0 ? winD / winDt * _mpsToKn : 0;

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

// ── Pass 2 — find ALL stationary segments ────────────────────────────────────

class _StopSegment {
  final int    startIdx;
  final int    endIdx;
  final AnchorKind kind;
  final double durationMinutes;
  final int    fixCount;

  const _StopSegment(this.startIdx, this.endIdx, this.kind,
      this.durationMinutes, this.fixCount);
}

List<_StopSegment> _findStationarySegments(
    List<_Fix> fixes, FilterSettings settings) {
  final n = fixes.length;
  for (final f in fixes) { f.stationary = false; }

  bool isStationary(int i) {
    if (settings.stationaryMode == StationaryMode.both) {
      return fixes[i].winSpeedKn < settings.speedThresholdKn &&
             fixes[i].winSpreadM < settings.spreadThresholdM;
    }
    return fixes[i].winSpeedKn < settings.speedThresholdKn;
  }

  // 1. Collect raw consecutive runs of stationary fixes.
  final raw = <List<int>>[];
  var i = 0;
  while (i < n) {
    if (isStationary(i)) {
      var j = i;
      while (j < n && isStationary(j)) { j++; }
      raw.add([i, j - 1]);
      i = j;
    } else {
      i++;
    }
  }

  // 2. Merge runs separated by ≤ _mergeGap moving fixes (bridges GPS flicker).
  final merged = <List<int>>[];
  for (final run in raw) {
    if (merged.isNotEmpty && run[0] - merged.last[1] - 1 <= _mergeGap) {
      merged.last[1] = run[1];
    } else {
      merged.add([run[0], run[1]]);
    }
  }

  // 3. Filter and classify each merged run.
  final stops = <_StopSegment>[];
  for (final span in merged) {
    final a   = span[0];
    final b   = span[1];
    final seg = fixes.sublist(a, b + 1);

    final durationMinutes =
        fixes[b].pt.time.difference(fixes[a].pt.time).inSeconds / 60.0;

    // Centroid of this cluster.
    var sumLat = 0.0, sumLon = 0.0;
    for (final f in seg) { sumLat += f.pt.lat; sumLon += f.pt.lon; }
    final cLat = sumLat / seg.length;
    final cLon = sumLon / seg.length;

    // Maximum distance from centroid (overall_spread in Python reference).
    var maxSpread = 0.0;
    for (final f in seg) {
      final d = _haversineM(cLat, cLon, f.pt.lat, f.pt.lon);
      if (d > maxSpread) maxSpread = d;
    }

    // Gate: must last long enough AND stay tight enough.
    if (durationMinutes < settings.minStopMinutes ||
        maxSpread > settings.maxStopSpreadM) {
      continue;
    }

    final kind = a == 0
        ? AnchorKind.start
        : (b == n - 1 ? AnchorKind.end : AnchorKind.mid);

    for (final f in seg) { f.stationary = true; }
    stops.add(_StopSegment(a, b, kind, durationMinutes, seg.length));
  }

  return stops;
}

// ── Pass 3 — spike detection ─────────────────────────────────────────────────

int _flagSpikes(List<_Fix> fixes) {
  final movingSpds = fixes
      .where((f) => !f.stationary && f.instSpeedKn > 0)
      .map((f) => f.instSpeedKn)
      .toList()
    ..sort();
  if (movingSpds.isEmpty) return 0;

  final med = movingSpds[movingSpds.length ~/ 2];
  final mads = movingSpds.map((s) => (s - med).abs()).toList()..sort();
  final mad  = mads[mads.length ~/ 2];
  final effectiveMad = mad < 1e-9 ? 1e-6 : mad;
  final limit = max(_maxSpeedKn, med + _accelSigma * 1.4826 * effectiveMad);

  var count = 0;
  for (final f in fixes) {
    if (!f.stationary && f.instSpeedKn > limit) { f.flagged = true; count++; }
  }
  return count;
}

// ── Pass 4 — smoothing ───────────────────────────────────────────────────────

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

// ── Public anchor kind ────────────────────────────────────────────────────────

/// Where in the track a stationary cluster sits.
enum AnchorKind { start, mid, end }

// ── Anchor description ────────────────────────────────────────────────────────

/// Positional summary of one stationary cluster (dock / anchor / harbor stop).
/// Used by the UI to draw a "GPS halo" at each stop.
class TrackAnchor {
  final double lat;
  final double lon;

  /// Radius containing 50 % of the GPS fixes in this cluster.  Inner ring.
  /// Floored at 10 m so the marker is always visible.
  final double cep50M;

  /// Radius containing 95 % of the GPS fixes in this cluster.  Outer ring.
  /// Floored at 20 m so the marker is always visible.
  final double r95M;

  /// Duration of this stop.
  final double durationMinutes;

  /// Number of raw GPS fixes inside this cluster.
  final int fixCount;

  /// Where in the track this stop occurred.
  final AnchorKind kind;

  /// Backward-compat alias (old code used a single [radiusM]).
  double get radiusM => r95M;

  const TrackAnchor({
    required this.lat,
    required this.lon,
    required this.cep50M,
    required this.r95M,
    required this.durationMinutes,
    required this.fixCount,
    required this.kind,
  });
}

TrackAnchor _computeAnchor(
    List<TrackPoint> cluster, AnchorKind kind, double durationMinutes) {
  final n = cluster.length;
  var sumLat = 0.0, sumLon = 0.0;
  for (final p in cluster) { sumLat += p.lat; sumLon += p.lon; }
  final cLat = sumLat / n;
  final cLon = sumLon / n;

  final radii = cluster
      .map((p) => _haversineM(cLat, cLon, p.lat, p.lon))
      .toList()
    ..sort();

  // CEP50: 50th-percentile radius (inner ring).
  final cep50M = max(10.0, radii[(radii.length * 0.50).floor().clamp(0, radii.length - 1)]);
  // R95: 95th-percentile radius (outer ring).
  final r95M   = max(20.0, radii[(radii.length * 0.95).floor().clamp(0, radii.length - 1)]);

  return TrackAnchor(
    lat:             cLat,
    lon:             cLon,
    cep50M:          cep50M,
    r95M:            r95M,
    durationMinutes: durationMinutes,
    fixCount:        n,
    kind:            kind,
  );
}

// ── Public result type ────────────────────────────────────────────────────────

/// Result of the full four-pass pipeline.
class TrimResult {
  /// Trimmed, spike-filtered, and smoothed points — ready for rendering and
  /// stats.
  final List<TrackPoint> points;

  /// All detected stops (start, mid, end) in track order.  Each carries the
  /// centroid position and positional-spread statistics for halo rendering.
  final List<TrackAnchor> anchors;

  /// Number of GPS fixes flagged as implausible speed spikes.
  final int nSpikes;

  const TrimResult({
    required this.points,
    this.anchors = const [],
    this.nSpikes = 0,
  });

  // Backward-compat getters for callers that only care about the endpoints.
  TrackAnchor? get startAnchor =>
      anchors.where((a) => a.kind == AnchorKind.start).firstOrNull;
  TrackAnchor? get endAnchor =>
      anchors.where((a) => a.kind == AnchorKind.end).firstOrNull;
}

// ── Public API ────────────────────────────────────────────────────────────────

/// Full four-pass pipeline.  Returns a [TrimResult] with cleaned points, all
/// stop anchors, and the spike count.
TrimResult trimTrackWithAnchors(
  List<TrackPoint> points, {
  FilterSettings settings = const FilterSettings(),
}) {
  if (points.length < 4) return TrimResult(points: points);

  // Pass 1 — annotate
  final fixes = points.map(_Fix.new).toList();
  _annotate(fixes, settings.window);

  // Pass 2 — find all stationary segments
  final stops = _findStationarySegments(fixes, settings);
  final anchors = stops.map((s) {
    final cluster = fixes.sublist(s.startIdx, s.endIdx + 1)
        .map((f) => f.pt)
        .toList();
    return _computeAnchor(cluster, s.kind, s.durationMinutes);
  }).toList();

  // Pass 3 — spikes
  final nSpikes = _flagSpikes(fixes);

  // Collect kept points
  final kept = fixes
      .where((f) => !f.stationary && !f.flagged)
      .map((f) => f.pt)
      .toList();

  if (kept.isEmpty) {
    return TrimResult(points: points, anchors: anchors, nSpikes: nSpikes);
  }

  // Pass 4 — smooth
  final smoothed = settings.smoothWindow >= 2
      ? _smoothMedian(kept, settings.smoothWindow)
      : kept;

  return TrimResult(points: smoothed, anchors: anchors, nSpikes: nSpikes);
}

/// Convenience wrapper — returns only the cleaned point list.
List<TrackPoint> trimStationaryEnds(
  List<TrackPoint> points, {
  FilterSettings settings = const FilterSettings(),
}) =>
    trimTrackWithAnchors(points, settings: settings).points;
