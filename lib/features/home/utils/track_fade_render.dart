import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../domain/track_point.dart';
import 'trim_track.dart';

/// Standard haversine great-circle distance in metres.
double _haversineM(double lat1, double lon1, double lat2, double lon2) {
  const r = 6371000.0;
  final dLat = (lat2 - lat1) * pi / 180;
  final dLon = (lon2 - lon1) * pi / 180;
  final a = sin(dLat / 2) * sin(dLat / 2) +
      cos(lat1 * pi / 180) * cos(lat2 * pi / 180) * sin(dLon / 2) * sin(dLon / 2);
  return r * 2 * atan2(sqrt(a), sqrt(1 - a));
}

/// Splits a [SegmentKind.moving] polyline into full-opacity runs (outside
/// every cloud's R95 radius) and faded runs (inside one, linearly ramping
/// opacity down to 0 at its centroid — same "distance / R95" ramp the
/// fade-zone design doc specifies). A stop candidate that failed validation
/// (GPS spread too wide to count as a confirmed, haloed stop — see
/// FilterSettings.maxStopSpreadM) stays classified as ordinary moving track
/// and would otherwise render as a solid tangle of raw GPS noise right where
/// [EstimatedCloudLayer] is already drawing rings for it; this makes the
/// line agree with those rings instead of fighting them. A point near more
/// than one cloud uses whichever gives it the lowest (most faded) opacity.
List<Polyline> fadeMovingNearCloud(
  TrackSegment seg, {
  required List<EstimatedCloud> clouds,
  required Color color,
  required double strokeWidth,
  double borderStrokeWidth = 0,
  Color borderColor = Colors.black,
}) {
  if (seg.points.length < 2 || clouds.isEmpty) return const [];

  double alphaAt(TrackPoint p) {
    var alpha = 1.0;
    for (final cloud in clouds) {
      final d = _haversineM(p.lat, p.lon, cloud.lat, cloud.lon);
      final a = d >= cloud.r95M ? 1.0 : (d / cloud.r95M).clamp(0.0, 1.0);
      if (a < alpha) alpha = a;
    }
    return alpha;
  }

  final polylines = <Polyline>[];
  var runPoints = <TrackPoint>[seg.points.first];
  var runFaded = alphaAt(seg.points.first) < 1.0;

  void flushRun() {
    if (runPoints.length < 2) return;
    if (!runFaded) {
      polylines.add(Polyline(
        points: runPoints.map((p) => LatLng(p.lat, p.lon)).toList(),
        strokeWidth: strokeWidth,
        color: color,
        borderStrokeWidth: borderStrokeWidth,
        borderColor: borderColor,
      ));
    } else {
      for (int i = 0; i < runPoints.length - 1; i++) {
        final a0 = runPoints[i];
        final a1 = runPoints[i + 1];
        final alpha = (alphaAt(a0) + alphaAt(a1)) / 2;
        polylines.add(Polyline(
          points: [LatLng(a0.lat, a0.lon), LatLng(a1.lat, a1.lon)],
          strokeWidth: strokeWidth,
          color: color.withValues(alpha: color.a * alpha),
          borderStrokeWidth: borderStrokeWidth,
          borderColor: borderColor.withValues(alpha: borderColor.a * alpha),
        ));
      }
    }
  }

  for (int i = 1; i < seg.points.length; i++) {
    final p = seg.points[i];
    final faded = alphaAt(p) < 1.0;
    if (faded != runFaded) {
      runPoints.add(p); // shared boundary point closes this run cleanly
      flushRun();
      runPoints = [p];
      runFaded = faded;
    } else {
      runPoints.add(p);
    }
  }
  flushRun();

  return polylines;
}

/// True on native iOS/Android; false on web and desktop. Used to select
/// tooltip trigger mode: tap on touch, hover+longPress on desktop — shared
/// so every map screen's estimated-cloud marker behaves identically.
bool get isTouchPlatform =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.iOS ||
     defaultTargetPlatform == TargetPlatform.android);

/// Splits a stop-entry/exit connector into short mini-polylines with
/// linearly interpolated opacity, so a straight synthetic connector line
/// (see [SegmentKind.stopEntry]/[SegmentKind.stopExit] in trim_track.dart)
/// reads as a smooth fade into/out of the stop's uncertainty circle instead
/// of one flat translucent line. Direction is derived from [seg.kind]:
/// stopEntry fades 1.0→0.0 across its points (arriving at the stop),
/// stopExit fades 0.0→1.0 (departing from it). [color]/[borderColor]'s own
/// alpha is used as the fade's *peak* (scaled down from there towards the
/// stop), not overwritten — so a caller passing an already-translucent
/// color (e.g. an unselected track) keeps that ceiling.
List<Polyline> fadeConnectorPolylines(
  TrackSegment seg, {
  required Color color,
  required double strokeWidth,
  double borderStrokeWidth = 0,
  Color borderColor = Colors.black,
  int steps = 8,
}) {
  if (seg.points.length < 2) return const [];
  final p0 = seg.points.first;
  final p1 = seg.points.last;
  final reverse = seg.kind == SegmentKind.stopExit;

  final polylines = <Polyline>[];
  for (int i = 0; i < steps; i++) {
    final t0 = i / steps;
    final t1 = (i + 1) / steps;
    final a0 = LatLng(p0.lat + (p1.lat - p0.lat) * t0, p0.lon + (p1.lon - p0.lon) * t0);
    final a1 = LatLng(p0.lat + (p1.lat - p0.lat) * t1, p0.lon + (p1.lon - p0.lon) * t1);
    // Opacity at the midpoint of this mini-segment.
    final tMid = (t0 + t1) / 2;
    final alpha = reverse ? tMid : (1.0 - tMid);
    polylines.add(Polyline(
      points: [a0, a1],
      strokeWidth: strokeWidth,
      color: color.withValues(alpha: color.a * alpha),
      borderStrokeWidth: borderStrokeWidth,
      borderColor: borderColor.withValues(alpha: borderColor.a * alpha),
    ));
  }
  return polylines;
}

/// Draws a dashed CEP50/R95 ring pair + a gps_not_fixed icon at each
/// [clouds] entry — one per uncertain area on the track (see
/// [DisplayModel.uncertainAreas]). Sized from each cloud's real-world R95
/// radius via the standard Web Mercator meters-per-pixel projection, so it
/// visually scales the same way
/// flutter_map's own `CircleMarker(useRadiusInMeter: true)` does. Gated to
/// the same zoom > 15 rule as the app's other stop-halo layers — sub-pixel
/// and just noise at route zoom.
class EstimatedCloudLayer extends StatelessWidget {
  final List<(EstimatedCloud cloud, Color color)> clouds;
  final String tooltipMessage;

  const EstimatedCloudLayer({
    super.key,
    required this.clouds,
    required this.tooltipMessage,
  });

  @override
  Widget build(BuildContext context) {
    if (clouds.isEmpty) return const SizedBox.shrink();
    final zoom = MapCamera.of(context).zoom;
    if (zoom <= 15) return const SizedBox.shrink();

    return MarkerLayer(markers: [
      for (final (cloud, color) in clouds)
        _cloudMarker(cloud, zoom, color),
    ]);
  }

  Marker _cloudMarker(EstimatedCloud cloud, double zoom, Color color) {
    // Standard Web Mercator meters-per-pixel at this latitude/zoom (256px
    // tiles) — the same projection the app's PDF map export already uses.
    final metersPerPixel = 156543.03392 * cos(cloud.lat * pi / 180) / pow(2, zoom);
    final r95Px   = cloud.r95M / metersPerPixel;
    final cep50Px = cloud.cep50M / metersPerPixel;
    final size = r95Px * 2 + 8;

    return Marker(
      point: LatLng(cloud.lat, cloud.lon),
      width: size,
      height: size,
      alignment: Alignment.center,
      child: Tooltip(
        message: tooltipMessage,
        triggerMode: isTouchPlatform ? TooltipTriggerMode.tap : TooltipTriggerMode.longPress,
        showDuration: isTouchPlatform ? const Duration(seconds: 4) : const Duration(milliseconds: 1500),
        waitDuration: isTouchPlatform ? Duration.zero : const Duration(milliseconds: 400),
        child: CustomPaint(
          size: Size(size, size),
          painter: _EstimatedCloudPainter(color: color, r95Px: r95Px, cep50Px: cep50Px),
        ),
      ),
    );
  }
}

class _EstimatedCloudPainter extends CustomPainter {
  final Color color;
  final double r95Px;
  final double cep50Px;

  const _EstimatedCloudPainter({
    required this.color,
    required this.r95Px,
    required this.cep50Px,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    _drawDashedCircle(canvas, center, r95Px, color.withValues(alpha: 0.55),
        strokeWidth: 1.5, dashLength: 6, gapLength: 4);
    _drawDashedCircle(canvas, center, cep50Px, color.withValues(alpha: 0.70),
        strokeWidth: 1.2, dashLength: 2, gapLength: 3);

    // gps_not_fixed glyph, painted directly (rather than an Icon widget) so
    // it composites in this same CustomPainter alongside the rings.
    final iconPainter = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(Icons.gps_not_fixed.codePoint),
        style: TextStyle(
          fontSize: 16,
          fontFamily: Icons.gps_not_fixed.fontFamily,
          package: Icons.gps_not_fixed.fontPackage,
          color: color,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    iconPainter.paint(
        canvas, center - Offset(iconPainter.width / 2, iconPainter.height / 2));
  }

  void _drawDashedCircle(
    Canvas canvas,
    Offset center,
    double radius,
    Color color, {
    required double strokeWidth,
    required double dashLength,
    required double gapLength,
  }) {
    if (radius <= 0) return;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    final circumference = 2 * pi * radius;
    final dashCount =
        (circumference / (dashLength + gapLength)).floor().clamp(1, 1000);
    final angleStep = 2 * pi / dashCount;
    final dashAngle = angleStep * (dashLength / (dashLength + gapLength));
    for (int i = 0; i < dashCount; i++) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        i * angleStep,
        dashAngle,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _EstimatedCloudPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.r95Px != r95Px ||
      oldDelegate.cep50Px != cep50Px;
}
