/// GPS track cleaning pipeline — Dart port of gpx_filter_reference_v6.py.
///
/// v6 adds detection of a BAD FIRST FIX: a single wrong GPS position at fix[0]
/// that sits far from where the receiver settled in the following fixes. Unlike
/// cold-start (gradual convergence over several minutes), this is one outlier
/// that jumps immediately to the correct position at fix[1]. Observed in 3 of 9
/// real Idefix logs: 28 Jun (256 m off), 18 Apr (89 m off), 02 May (75 m off).
/// Two targeted changes:
///   (a) _detectBadFirstFix() flags fix[0] when it is a single outlier relative
///       to the tight cluster formed by the next ~10 fixes.
///   (b) _findStationarySegments() now EXCLUDES flagged fixes from the spread
///       calculation so a flagged fix[0] cannot inflate the berth spread and
///       cause it to be rejected by the maxStopSpreadM gate.
///
/// Pipeline order (v6):
///   1. Annotate   — initial windowed speed + spread (simple window, no spikes yet).
///   2. Spikes     — flag physically implausible moving fixes BEFORE stop detection.
///   3. BadFirst   — flag fix[0] if it is a single position outlier.
///   4. Re-annotate — gap-aware window now that all flagged positions are known.
///   5. Detect     — find ALL stationary segments (spread excludes flagged fixes).
///   6. Cold-start — flag GPS warm-up fixes at track start.
///   7. Smooth     — sliding-median on the kept moving track.
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
  const r = 6371000.0;
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

// ── Pass 2b — bad first fix detection ────────────────────────────────────────

/// Flags fix[0] when it is a single wrong initial GPS position — one outlier
/// that sits far from where the receiver settled from fix[1] onward.
///
/// Method: compute the centroid and mean spread of the next [lookahead] fixes.
/// If fix[0] is more than [factor] × spread away from that centroid AND the
/// distance exceeds [minDistanceM], it is flagged.  The tight-cluster condition
/// (`factor × spread`) ensures this never fires on a trip that genuinely starts
/// under way (where the lookahead cluster is spread out along the track).
///
/// Returns true if fix[0] was flagged.  The caller must recompute speeds after
/// this so the window no longer spans the flagged fix.
bool _detectBadFirstFix(
  List<_Fix> fixes, {
  int lookahead       = 10,
  double factor       = 5.0,
  double minDistanceM = 30.0,
}) {
  if (fixes.length < 4) return false;

  final clusterEnd = min(lookahead + 1, fixes.length);
  final cluster    = fixes.sublist(1, clusterEnd);

  var sumLat = 0.0, sumLon = 0.0;
  for (final f in cluster) { sumLat += f.pt.lat; sumLon += f.pt.lon; }
  final cLat = sumLat / cluster.length;
  final cLon = sumLon / cluster.length;

  final d0 = _haversineM(fixes[0].pt.lat, fixes[0].pt.lon, cLat, cLon);

  var sumSpread = 0.0;
  for (final f in cluster) {
    sumSpread += _haversineM(cLat, cLon, f.pt.lat, f.pt.lon);
  }
  final spread = sumSpread / cluster.length;

  if (d0 > max(factor * spread, minDistanceM)) {
    fixes[0].flagged = true;
    return true;
  }
  return false;
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
  // v6: first non-flagged index for correct start-stop classification when
  // fix[0] was flagged as a bad first fix (the berth starts at index 1 but
  // is still a 'start' stop, not a 'mid').
  final firstNonFlagged = fixes.indexWhere((f) => !f.flagged);
  final effectiveFirst  = firstNonFlagged < 0 ? 0 : firstNonFlagged;

  final stops = <_StopSegment>[];
  for (final span in merged) {
    final a   = span[0];
    final b   = span[1];
    final seg = fixes.sublist(a, b + 1);

    final durationMinutes =
        fixes[b].pt.time.difference(fixes[a].pt.time).inSeconds / 60.0;

    // v6: exclude flagged fixes from spread so a flagged bad-first-fix cannot
    // inflate the apparent cluster radius and cause the berth to be rejected.
    final nonFlagged = seg.where((f) => !f.flagged).toList();
    if (nonFlagged.isEmpty) continue;

    var sumLat = 0.0, sumLon = 0.0;
    for (final f in nonFlagged) { sumLat += f.pt.lat; sumLon += f.pt.lon; }
    final cLat = sumLat / nonFlagged.length;
    final cLon = sumLon / nonFlagged.length;

    // Maximum distance from centroid (overall_spread in Python reference).
    var maxSpread = 0.0;
    for (final f in nonFlagged) {
      final d = _haversineM(cLat, cLon, f.pt.lat, f.pt.lon);
      if (d > maxSpread) maxSpread = d;
    }

    // Gate: must last long enough AND stay tight enough.
    if (durationMinutes < settings.minStopMinutes ||
        maxSpread > settings.maxStopSpreadM) {
      continue;
    }

    // v6: a stop beginning at or before effectiveFirst is a 'start' stop even
    // when the true first fix (index 0) was flagged.
    final kind = a <= effectiveFirst
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

  /// 1 if fix[0] was identified as a single bad initial GPS position; 0 otherwise.
  final int nBadFirstFix;

  const TrimResult({
    required this.points,
    this.anchors             = const [],
    this.movingInstSpeedsKn  = const [],
    this.nSpikes             = 0,
    this.nColdStart          = 0,
    this.nBadFirstFix        = 0,
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

  // Pass 2 — flag mid-track spikes BEFORE stop detection
  final nSpikes = _flagSpikes(fixes);

  // Pass 3 — detect bad first fix (single outlier at fix[0], distinct from cold-start)
  final nBadFirstFix = settings.detectBadFirstFix && _detectBadFirstFix(fixes) ? 1 : 0;

  // Pass 4 — re-annotate gap-aware now that all flagged positions are known
  _annotate(fixes, settings.window);

  // Pass 5 — find all stationary segments (spread excludes flagged fixes)
  final stops = _findStationarySegments(fixes, settings);

  // Pass 6 — GPS cold-start (only at start stop; sets .coldStart on leading fixes)
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
    return TrimResult(points: points, anchors: anchors, nSpikes: nSpikes,
        nColdStart: nColdStart, nBadFirstFix: nBadFirstFix);
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
    nBadFirstFix:        nBadFirstFix,
  );
}

/// Splits [points] into continuous sub-segments, starting a new segment
/// whenever the time gap between two consecutive points exceeds [breakSeconds].
///
/// Use this on [TrimResult.points] before rendering: removed fixes (spikes,
/// cold-start, stationary runs) leave large time gaps in the filtered list.
/// Connecting those gaps with a straight line would show phantom track
/// segments on the map.
///
/// [breakSeconds] defaults to 60 s — safe for GPS intervals up to ~20 s and
/// stop durations ≥ 1 minute.  Raise it for slow-logging receivers.
List<List<TrackPoint>> splitTrackSegments(
  List<TrackPoint> points, {
  int breakSeconds = 60,
}) {
  if (points.isEmpty) return [];
  final segments = <List<TrackPoint>>[];
  var current = [points.first];
  for (int i = 1; i < points.length; i++) {
    final gapS = points[i].time.difference(points[i - 1].time).inSeconds.abs();
    if (gapS > breakSeconds) {
      if (current.length >= 2) segments.add(current);
      current = [];
    }
    current.add(points[i]);
  }
  if (current.length >= 2) segments.add(current);
  return segments;
}

/// Convenience wrapper — returns only the cleaned point list.
List<TrackPoint> trimStationaryEnds(
  List<TrackPoint> points, {
  FilterSettings settings = const FilterSettings(),
}) =>
    trimTrackWithAnchors(points, settings: settings).points;

// ── Display model ─────────────────────────────────────────────────────────────

const _samePlaceM           = 100.0;
const _teleportM            = 200.0;
const _defaultBaseAccuracyM = 8.0;
const _jitterGain           = 1.5;
const _uncertaintyCapFactor = 3.0;
const _gapSeconds           = 120.0;

/// Visual category of one rendered track segment.
enum SegmentKind { moving, stopEntry, stopExit, teleportBreak }

/// One continuous piece of the rendered track.
class TrackSegment {
  /// Category determines rendering style.
  final SegmentKind kind;

  /// Ordered coordinates. Empty for [SegmentKind.teleportBreak].
  /// Entry/exit connectors contain two synthetic end-points.
  final List<TrackPoint> points;

  /// Per-fix instantaneous speed (knots), parallel to [points]. null for connectors.
  final List<double?> speedKn;

  /// Per-fix inferred GPS uncertainty (metres), parallel to [points].
  /// null for connectors and break sentinels.
  /// Half-width of the ±error band at each fix — use with [DisplayModel.uncertaintyBands].
  final List<double?> uncertaintyM;

  const TrackSegment(this.kind, this.points, this.speedKn,
      {this.uncertaintyM = const []});
}

/// Everything needed to render one stop on the map.
class StopMarker {
  final AnchorKind kind;
  final double lat;
  final double lon;

  /// Inner halo: 50th-percentile GPS spread radius.
  final double cep50M;

  /// Outer halo: 95th-percentile GPS spread radius.
  final double r95M;

  final double minutes;
  final int nFixes;
  final int nColdStart;

  /// True when departure from this stop involved a GPS teleport / gap.
  final bool hasTeleportAfter;

  const StopMarker({
    required this.kind,
    required this.lat,
    required this.lon,
    required this.cep50M,
    required this.r95M,
    required this.minutes,
    required this.nFixes,
    required this.nColdStart,
    this.hasTeleportAfter = false,
  });
}

/// Complete rendering model for one day's GPS track.
class DisplayModel {
  final List<TrackSegment> segments;
  final List<StopMarker> stops;
  final bool hasTeleport;

  /// Inferred GPS receiver base accuracy (metres) — median R95 across all stops.
  /// Floor of the per-fix uncertainty band; falls back to 8 m when no stops.
  final double baseAccuracyM;

  /// Raw (unsmoothed) GPS fixes with cold-start and stationary fixes removed.
  /// Speed spikes are retained so the filter's effect stays visible.
  /// Use this for the "raw track" overlay instead of the original track.points.
  final List<TrackPoint> rawMovingPoints;

  /// All fixes with flagged (bad first fix + spikes) and cold-start fixes
  /// removed, but including stationary/berth fixes at their correct positions.
  /// Use this for timeline-entry correlation so departure/arrival entries snap
  /// to the berth rather than to a wrong GPS position.
  final List<TrackPoint> correlationPoints;

  const DisplayModel({
    this.segments           = const [],
    this.stops              = const [],
    this.hasTeleport        = false,
    this.baseAccuracyM      = _defaultBaseAccuracyM,
    this.rawMovingPoints    = const [],
    this.correlationPoints  = const [],
  });

  /// First moving fix — departure time.
  TrackPoint? get firstMovingPoint {
    for (final s in segments) {
      if (s.kind == SegmentKind.moving && s.points.isNotEmpty) return s.points.first;
    }
    return null;
  }

  /// Last moving fix — arrival time.
  TrackPoint? get lastMovingPoint {
    for (int i = segments.length - 1; i >= 0; i--) {
      final s = segments[i];
      if (s.kind == SegmentKind.moving && s.points.isNotEmpty) return s.points.last;
    }
    return null;
  }

  /// All non-break coords in track order.
  List<TrackPoint> allPoints() => [
    for (final s in segments)
      if (s.kind != SegmentKind.teleportBreak)
        for (final p in s.points)
          if (p.lat.isFinite && p.lon.isFinite) p,
  ];

  /// Moving coords only — for bearing calculations and stats.
  List<TrackPoint> movingPoints() => [
    for (final s in segments)
      if (s.kind == SegmentKind.moving)
        for (final p in s.points)
          if (p.lat.isFinite && p.lon.isFinite) p,
  ];

  /// Start stop (kind = start) if present.
  StopMarker? get startStop =>
      stops.where((s) => s.kind == AnchorKind.start).firstOrNull;

  /// End stop (kind = end) if present.
  StopMarker? get endStop =>
      stops.where((s) => s.kind == AnchorKind.end).firstOrNull;

  /// All non-break coords split at teleport breaks, min 2 points each.
  /// Used for overview map polyline rendering.
  List<List<TrackPoint>> polylines() {
    final polys = <List<TrackPoint>>[[]];
    for (final seg in segments) {
      if (seg.kind == SegmentKind.teleportBreak) {
        if (polys.last.isNotEmpty) polys.add([]);
      } else {
        polys.last.addAll(seg.points);
      }
    }
    return polys.where((p) => p.length >= 2).toList();
  }

  /// One closed (lat, lon) polygon per continuous moving polyline forming the
  /// ±GPS uncertainty corridor. Render as a translucent filled polygon beneath
  /// the track line; meaningful only at harbour / detail zoom (≥ 15).
  List<List<(double, double)>> uncertaintyBands() {
    final bands = <List<(double, double)>>[];
    var runCoords = <(double, double)>[];
    var runUnc    = <double>[];

    void closeRun() {
      if (runCoords.length >= 2) {
        bands.add(_uncertaintyBand(runCoords, runUnc, baseAccuracyM));
      }
      runCoords = [];
      runUnc    = [];
    }

    for (final seg in segments) {
      if (seg.kind == SegmentKind.teleportBreak) {
        closeRun();
      } else if (seg.kind == SegmentKind.moving) {
        runCoords.addAll(seg.points.map((p) => (p.lat, p.lon)));
        final unc = seg.uncertaintyM;
        runUnc.addAll(List.generate(seg.points.length,
            (i) => (i < unc.length ? unc[i] : null) ?? baseAccuracyM));
      }
    }
    closeRun();
    return bands;
  }
}

// ── Uncertainty helpers ───────────────────────────────────────────────────────

/// Infer the receiver's base positional accuracy from stationary scatter.
/// Returns the median R95 across all stops (cold-start fixes excluded).
double _baseAccuracyFromStops(List<_Fix> fixes, List<_StopSegment> stops) {
  final r95s = <double>[];
  for (final s in stops) {
    final seg     = fixes.sublist(s.startIdx, s.endIdx + 1);
    final settled = seg.where((f) => !f.coldStart).toList();
    final cluster = settled.length >= 3 ? settled : seg;
    if (cluster.length < 2) continue;
    final pts    = cluster.map((f) => f.pt).toList();
    final anchor = _computeAnchor(pts, s.kind, s.durationMinutes);
    r95s.add(anchor.r95M);
  }
  if (r95s.isEmpty) return _defaultBaseAccuracyM;
  r95s.sort();
  return r95s[r95s.length ~/ 2];
}

/// Per-fix GPS uncertainty (metres) for the moving track, inferred from two
/// signals combined in quadrature:
///   base_accuracy — receiver's measured accuracy from stationary scatter.
///   local jitter  — deviation of each fix from the midpoint of its neighbours.
/// Result is capped at [_uncertaintyCapFactor] × base so a single wild fix
/// cannot blow the band to absurd widths. Jitter is not measured across a time
/// gap > [_gapSeconds] (stop boundary); those fixes keep base accuracy.
List<double> _perFixUncertainty(List<_Fix> movingFixes, double baseAccuracyM) {
  final n   = movingFixes.length;
  final cap = _uncertaintyCapFactor * baseAccuracyM;
  final unc = List<double>.filled(n, baseAccuracyM);
  for (int i = 1; i < n - 1; i++) {
    final a   = movingFixes[i - 1];
    final b   = movingFixes[i];
    final c   = movingFixes[i + 1];
    final dt1 = b.pt.time.difference(a.pt.time).inSeconds.toDouble();
    final dt2 = c.pt.time.difference(b.pt.time).inSeconds.toDouble();
    if (dt1 > _gapSeconds || dt2 > _gapSeconds) continue;
    final midLat = (a.pt.lat + c.pt.lat) / 2;
    final midLon = (a.pt.lon + c.pt.lon) / 2;
    final jitter = _haversineM(midLat, midLon, b.pt.lat, b.pt.lon);
    final combined = sqrt(baseAccuracyM * baseAccuracyM +
        (_jitterGain * jitter) * (_jitterGain * jitter));
    unc[i] = combined < cap ? combined : cap;
  }
  return unc;
}

/// Closed (lat, lon) polygon outlining the ±uncertainty corridor around a
/// polyline. Returns left-side forward + right-side reversed so the result is
/// a single ring suitable for a filled-polygon primitive.
List<(double, double)> _uncertaintyBand(
  List<(double, double)> coords,
  List<double> uncertaintyM,
  double baseAccuracyM,
) {
  final n = coords.length;
  if (n < 2) return [];
  final lat0       = coords.map((c) => c.$1).reduce((a, b) => a + b) / n;
  const mPerDegLat = 111320.0;
  final mPerDegLon = 111320.0 * cos(lat0 * pi / 180);

  (double oy, double ox) perp(int i) {
    final double dLat, dLon;
    if (i == 0) {
      dLat = coords[1].$1 - coords[0].$1;
      dLon = coords[1].$2 - coords[0].$2;
    } else if (i == n - 1) {
      dLat = coords[n - 1].$1 - coords[n - 2].$1;
      dLon = coords[n - 1].$2 - coords[n - 2].$2;
    } else {
      dLat = coords[i + 1].$1 - coords[i - 1].$1;
      dLon = coords[i + 1].$2 - coords[i - 1].$2;
    }
    final dxm    = dLon * mPerDegLon;
    final dym    = dLat * mPerDegLat;
    final length = sqrt(dxm * dxm + dym * dym);
    if (length == 0) return (0.0, 0.0);
    final u = i < uncertaintyM.length ? uncertaintyM[i] : baseAccuracyM;
    return (dxm / length * u / mPerDegLat, -dym / length * u / mPerDegLon);
  }

  final left  = <(double, double)>[];
  final right = <(double, double)>[];
  for (int i = 0; i < n; i++) {
    final (oy, ox) = perp(i);
    left.add( (coords[i].$1 + oy, coords[i].$2 + ox));
    right.add((coords[i].$1 - oy, coords[i].$2 - ox));
  }
  return [...left, ...right.reversed];
}

// ── Display model builder ─────────────────────────────────────────────────────

String _connType(double? dBefore, double? dAfter, bool hasSpike) {
  final maxD = max(dBefore ?? 0.0, dAfter ?? 0.0);
  if (hasSpike && maxD > _teleportM) return 'teleport';
  if (maxD < _samePlaceM) return 'on_track';
  return 'position_shift';
}

/// Build a [DisplayModel] from a raw GPS point list.
///
/// Runs the same v5 pipeline as [trimTrackWithAnchors] and segments the output
/// into moving runs, stop connectors, and teleport breaks — ready for
/// multi-style map rendering.
DisplayModel buildDisplayModel(
  List<TrackPoint> points, {
  FilterSettings settings = const FilterSettings(),
}) {
  if (points.length < 4) return const DisplayModel();

  final fixes = points.map(_Fix.new).toList();
  final n = fixes.length;

  _annotate(fixes, settings.window);
  _flagSpikes(fixes);
  if (settings.detectBadFirstFix) _detectBadFirstFix(fixes);
  _annotate(fixes, settings.window);
  final stops = _findStationarySegments(fixes, settings);
  if (settings.detectColdStart) {
    _flagColdStart(fixes, stops, settings.coldStartSettleFactor);
  }

  // Per-fix uncertainty: compute base accuracy from stop scatter, then
  // infer jitter-based uncertainty for every moving fix.
  final baseAccuracyM  = _baseAccuracyFromStops(fixes, stops);
  // rawMovingPoints: cold-start and stationary removed, spikes kept so the
  // filter's effect is visible when the raw overlay is shown.
  final rawMovingPoints = fixes
      .where((f) => !f.stationary && !f.coldStart &&
                    f.pt.lat.isFinite && f.pt.lon.isFinite)
      .map((f) => f.pt)
      .toList();
  // correlationPoints: flagged (bad first fix + spikes) and cold-start removed,
  // but stationary/berth fixes KEPT so timeline entries at departure/arrival
  // time snap to the correct berth position, not to a bad GPS fix.
  final correlationPoints = fixes
      .where((f) => !f.flagged && !f.coldStart)
      .map((f) => f.pt)
      .toList();
  final movingFixes    = fixes.where((f) => !f.stationary && !f.coldStart && !f.flagged).toList();
  final movingUncM     = _perFixUncertainty(movingFixes, baseAccuracyM);
  final uncByTime      = <DateTime, double>{
    for (int i = 0; i < movingFixes.length; i++)
      movingFixes[i].pt.time: movingUncM[i],
  };

  // Build anchors (same logic as trimTrackWithAnchors)
  final anchors = stops.map((s) {
    final allInSeg = fixes.sublist(s.startIdx, s.endIdx + 1);
    final settled  = allInSeg.where((f) => !f.coldStart).toList();
    final cluster  = (settled.length >= 3 ? settled : allInSeg)
        .map((f) => f.pt)
        .toList();
    return _computeAnchor(cluster, s.kind, s.durationMinutes);
  }).toList();

  // Fast lookup: raw fix index → stop index
  final inStop = <int, int>{};
  for (int si = 0; si < stops.length; si++) {
    for (int k = stops[si].startIdx; k <= stops[si].endIdx; k++) {
      inStop[k] = si;
    }
  }

  final spikeSet = <int>{
    for (int i = 0; i < n; i++)
      if (fixes[i].flagged) i,
  };

  final segments    = <TrackSegment>[];
  final stopMarkers = <StopMarker>[];
  bool hasTeleport  = false;

  final curPoints = <TrackPoint>[];
  final curSpeeds = <double?>[];
  final curUnc    = <double?>[];

  void flushMoving() {
    if (curPoints.isNotEmpty) {
      segments.add(TrackSegment(
          SegmentKind.moving, List.of(curPoints), List.of(curSpeeds),
          uncertaintyM: List.of(curUnc)));
      curPoints.clear();
      curSpeeds.clear();
      curUnc.clear();
    }
  }

  var ri = 0;
  while (ri < n) {
    final f = fixes[ri];

    if (f.coldStart || f.stationary) {
      final si = inStop[ri];
      if (si == null) { ri++; continue; }

      final s      = stops[si];
      final anchor = anchors[si];
      final clat   = anchor.lat;
      final clon   = anchor.lon;

      final nCold = fixes
          .sublist(s.startIdx, s.endIdx + 1)
          .where((fix) => fix.coldStart)
          .length;

      // Last moving fix before this stop
      TrackPoint? beforePt;
      for (int k = s.startIdx - 1; k >= 0; k--) {
        final fk = fixes[k];
        if (!fk.stationary && !fk.coldStart && !fk.flagged) {
          beforePt = fk.pt;
          break;
        }
      }

      // First moving fix after this stop
      TrackPoint? afterPt;
      for (int k = s.endIdx + 1; k < n; k++) {
        final fk = fixes[k];
        if (!fk.stationary && !fk.coldStart && !fk.flagged) {
          afterPt = fk.pt;
          break;
        }
      }

      // Any spike within ±2 positions of the stop boundary?
      final lo = max(0, s.startIdx - 2);
      final hi = min(n, s.endIdx + 3);
      var hasSpike = false;
      for (int k = lo; k < hi; k++) {
        if (spikeSet.contains(k)) { hasSpike = true; break; }
      }

      final dBefore = beforePt != null
          ? _haversineM(beforePt.lat, beforePt.lon, clat, clon) : null;
      final dAfter  = afterPt != null
          ? _haversineM(clat, clon, afterPt.lat, afterPt.lon) : null;

      final conn          = _connType(dBefore, dAfter, hasSpike);
      final teleportAfter = conn == 'teleport' &&
          (afterPt == null || (dAfter ?? 0) > _teleportM);

      // Flush moving run + optional stop_entry connector (not for the start stop)
      if (s.kind != AnchorKind.start && curPoints.isNotEmpty) {
        final entryStart = curPoints.last;
        flushMoving();
        if (_haversineM(entryStart.lat, entryStart.lon, clat, clon) > 5) {
          segments.add(TrackSegment(SegmentKind.stopEntry,
            [entryStart, TrackPoint(lat: clat, lon: clon, time: entryStart.time)],
            [null, null]));
        }
      } else {
        flushMoving();
      }

      stopMarkers.add(StopMarker(
        kind:             s.kind,
        lat:              clat,
        lon:              clon,
        cep50M:           anchor.cep50M,
        r95M:             anchor.r95M,
        minutes:          s.durationMinutes,
        nFixes:           anchor.fixCount,
        nColdStart:       nCold,
        hasTeleportAfter: teleportAfter,
      ));
      hasTeleport |= teleportAfter;

      if (teleportAfter) {
        segments.add(const TrackSegment(SegmentKind.teleportBreak, [], []));
      } else if (afterPt != null && (dAfter ?? 0) > 5) {
        segments.add(TrackSegment(SegmentKind.stopExit,
          [TrackPoint(lat: clat, lon: clon, time: afterPt.time), afterPt],
          [null, null]));
      }

      ri = s.endIdx + 1;
      continue;
    }

    if (f.flagged) {
      flushMoving();
      segments.add(const TrackSegment(SegmentKind.teleportBreak, [], []));
      hasTeleport = true;
      ri++;
      continue;
    }

    // Normal moving fix
    curPoints.add(f.pt);
    curSpeeds.add(f.instSpeedKn > 0 ? f.instSpeedKn : null);
    curUnc.add(uncByTime[f.pt.time] ?? baseAccuracyM);
    ri++;
  }

  flushMoving();

  return DisplayModel(
    segments:          segments,
    stops:             stopMarkers,
    hasTeleport:       hasTeleport,
    baseAccuracyM:     baseAccuracyM,
    rawMovingPoints:   rawMovingPoints,
    correlationPoints: correlationPoints,
  );
}
