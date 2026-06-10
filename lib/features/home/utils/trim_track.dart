/// GPS track cleaning pipeline — Dart port of gpx_filter_reference_v5.py.
///
/// v5 upgrade: robustness to GPS dropouts / teleports (a logging gap where the
/// receiver re-acquires at a new position).  Two changes:
///   (a) the moving-window speed/spread is GAP-AWARE — the window never spans a
///       flagged spike, so berth fixes adjacent to a departure glitch still read
///       as stationary;
///   (b) the stop-merge never bridges across a flagged spike, so a teleport
///       cannot fuse the pre- and post-jump pauses into one bogus wide "stop".
///
/// Pipeline order (v5):
///   1. Annotate  — initial windowed speed + spread (simple window, no spikes yet).
///   2. Spikes    — flag physically implausible moving fixes BEFORE stop detection.
///   3. Re-annotate — gap-aware window now that spike positions are known.
///   4. Detect    — find ALL stationary segments (start, mid, end).
///   5. Cold-start — flag GPS warm-up fixes at track start.
///   6. Smooth    — sliding-median on the kept moving track.
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
  bool coldStart     = false;  // GPS cold-start convergence (only at track start)

  _Fix(this.pt);
}

// ── Pass 1 — annotate ────────────────────────────────────────────────────────

void _annotate(List<_Fix> fixes, int window) {
  final n = fixes.length;

  // A "break" at position k means the window must not cross the k-1 ↔ k
  // boundary: either fix is a flagged spike.  On the first pass (before spikes
  // are flagged) this is always false, so the window expands normally.
  bool isBreakAt(int k) =>
      k > 0 && (fixes[k].flagged || fixes[k - 1].flagged);

  for (int i = 0; i < n; i++) {
    if (i == 0) {
      fixes[i].instSpeedKn = 0;
    } else {
      final dt = fixes[i].pt.time.difference(fixes[i - 1].pt.time).inSeconds.toDouble();
      final d  = _haversineM(fixes[i - 1].pt.lat, fixes[i - 1].pt.lon,
                              fixes[i].pt.lat,     fixes[i].pt.lon);
      fixes[i].instSpeedKn = dt > 0 ? d / dt * _mpsToKn : 0;
    }

    // Expand centred window but stop at any spike boundary (v5 gap-aware).
    var lo = i;
    while (lo > max(0, i - window) && !isBreakAt(lo)) { lo--; }
    var hi = i;
    while (hi < min(n - 1, i + window) && !isBreakAt(hi + 1)) { hi++; }

    if (hi > lo) {
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
    } else {
      // Fix isolated between two spike boundaries: fall back to instantaneous.
      fixes[i].winSpeedKn = fixes[i].instSpeedKn;
      fixes[i].winSpreadM = 0.0;
    }
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
  //    v5: never bridge a gap that contains a flagged spike fix — those are
  //    teleports/dropouts that must NOT be absorbed into a stop segment.
  final merged = <List<int>>[];
  for (final run in raw) {
    if (merged.isNotEmpty && run[0] - merged.last[1] - 1 <= _mergeGap) {
      final gapStart = merged.last[1] + 1;
      final gapEnd   = run[0] - 1;
      bool hasSpike  = false;
      for (int k = gapStart; k <= gapEnd; k++) {
        if (fixes[k].flagged) { hasSpike = true; break; }
      }
      if (!hasSpike) {
        merged.last[1] = run[1];
      } else {
        merged.add([run[0], run[1]]);
      }
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

// ── Pass 3b — GPS cold-start convergence at track start ──────────────────────

/// Flags leading fixes in the start-stop cloud that sit anomalously far from
/// the settled berth position — the coarse, inward-converging output of a GPS
/// receiver before it has acquired a solid satellite lock.
///
/// Method mirrors gpx_filter_reference_v4.flag_cold_start():
///   • Take the second half of the start-stop segment as the "settled" cloud.
///   • threshold = settled_mean + settleFactor * max(settled_pstdev, 0.5 m)
///   • Walk forward from fix 0; flag each consecutive fix beyond the threshold
///     as cold_start.  Stop at the first converged fix (non-sequential cold
///     starts don't happen).  Capped at 20 leading fixes.
///
/// Flagged fixes get [_Fix.coldStart] = true.  They are already inside the
/// start stop (so [_Fix.stationary] = true and excluded from the cleaned
/// track), but the separate flag lets the UI show a "GPS warm-up" state and
/// lets [_computeAnchor] exclude them from cloud statistics.
int _flagColdStart(
  List<_Fix> fixes,
  List<_StopSegment> stops,
  double settleFactor,
) {
  final startStop = stops.where((s) => s.kind == AnchorKind.start).firstOrNull;
  if (startStop == null) return 0;

  final seg = fixes.sublist(startStop.startIdx, startStop.endIdx + 1);
  if (seg.length < 6) return 0;

  final settled = seg.sublist(seg.length ~/ 2);
  var sumLat = 0.0, sumLon = 0.0;
  for (final f in settled) { sumLat += f.pt.lat; sumLon += f.pt.lon; }
  final cLat = sumLat / settled.length;
  final cLon = sumLon / settled.length;

  final sdist = settled
      .map((f) => _haversineM(cLat, cLon, f.pt.lat, f.pt.lon))
      .toList();
  final smean = sdist.reduce((a, b) => a + b) / sdist.length;
  final variance = sdist.map((d) => (d - smean) * (d - smean)).reduce((a, b) => a + b) /
      sdist.length;
  final sstd = settled.length > 1 ? sqrt(variance) : 0.0;
  final threshold = smean + settleFactor * max(sstd, 0.5);

  const maxLead = 20;
  var count = 0;
  for (int i = 0; i < min(maxLead, seg.length); i++) {
    if (_haversineM(cLat, cLon, seg[i].pt.lat, seg[i].pt.lon) > threshold) {
      seg[i].coldStart = true;
      count++;
    } else {
      break;
    }
  }
  return count;
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

  /// Instantaneous speeds (knots) of the kept moving fixes, in track order.
  /// Pre-computed by the pipeline so callers don't need to re-derive them.
  final List<double> movingInstSpeedsKn;

  /// Number of GPS fixes flagged as implausible speed spikes.
  final int nSpikes;

  /// Number of GPS cold-start convergence fixes stripped from the track start.
  final int nColdStart;

  const TrimResult({
    required this.points,
    this.anchors             = const [],
    this.movingInstSpeedsKn  = const [],
    this.nSpikes             = 0,
    this.nColdStart          = 0,
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

  final fixes = points.map(_Fix.new).toList();

  // Pass 1 — initial annotate (simple window; no spikes flagged yet)
  _annotate(fixes, settings.window);

  // Pass 2 — flag spikes BEFORE stop detection
  final nSpikes = _flagSpikes(fixes);

  // Pass 3 — re-annotate now that spike positions are known (gap-aware window)
  _annotate(fixes, settings.window);

  // Pass 4 — find all stationary segments (uses spike-aware annotations)
  final stops = _findStationarySegments(fixes, settings);

  // Pass 5 — GPS cold-start (only at start stop; sets .coldStart on leading fixes)
  final nColdStart = settings.detectColdStart
      ? _flagColdStart(fixes, stops, settings.coldStartSettleFactor)
      : 0;

  // Build anchors, excluding cold-start fixes from the start-stop cloud so
  // the displayed position and rings reflect the settled GPS fix.
  final anchors = stops.map((s) {
    final allInSeg = fixes.sublist(s.startIdx, s.endIdx + 1);
    final settled  = allInSeg.where((f) => !f.coldStart).toList();
    final cluster  = (settled.length >= 3 ? settled : allInSeg)
        .map((f) => f.pt)
        .toList();
    return _computeAnchor(cluster, s.kind, s.durationMinutes);
  }).toList();

  // Collect kept fixes (moving, non-spiked)
  final keptFixes = fixes.where((f) => !f.stationary && !f.flagged).toList();

  if (keptFixes.isEmpty) {
    return TrimResult(points: points, anchors: anchors, nSpikes: nSpikes, nColdStart: nColdStart);
  }

  // Collect instantaneous speeds of kept fixes for robust max-speed computation.
  final movingInstSpeedsKn = keptFixes
      .map((f) => f.instSpeedKn)
      .where((s) => s > 0)
      .toList();

  // Pass 6 — smooth the kept track
  final kept     = keptFixes.map((f) => f.pt).toList();
  final smoothed = settings.smoothWindow >= 2
      ? _smoothMedian(kept, settings.smoothWindow)
      : kept;

  return TrimResult(
    points:              smoothed,
    anchors:             anchors,
    movingInstSpeedsKn:  movingInstSpeedsKn,
    nSpikes:             nSpikes,
    nColdStart:          nColdStart,
  );
}

/// Convenience wrapper — returns only the cleaned point list.
List<TrackPoint> trimStationaryEnds(
  List<TrackPoint> points, {
  FilterSettings settings = const FilterSettings(),
}) =>
    trimTrackWithAnchors(points, settings: settings).points;
