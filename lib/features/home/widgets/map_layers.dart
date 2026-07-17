import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;

import '../domain/track_point.dart';
import '../utils/trim_track.dart';

/// Shows the GPS accuracy rings (CEP50 / R95) only at harbour zoom (> 15).
/// flutter_map propagates MapCamera via InheritedWidget, so this widget
/// rebuilds automatically whenever the camera zoom changes.
class ZoomAwareCircleLayer extends StatelessWidget {
  final List<CircleMarker> circles;
  const ZoomAwareCircleLayer({super.key, required this.circles});

  @override
  Widget build(BuildContext context) {
    if (circles.isEmpty) return const SizedBox.shrink();
    final zoom = MapCamera.of(context).zoom;
    if (zoom <= 15) return const SizedBox.shrink();
    return CircleLayer(circles: circles);
  }
}

/// Shows the ±GPS uncertainty corridor only at harbour/detail zoom (> 15).
/// At route zoom the band is sub-pixel and would only hurt performance.
/// Fixed blue colour regardless of theme — reads as "confidence", not alarm.
class ZoomAwareUncertaintyLayer extends StatelessWidget {
  final List<Polygon> polygons;
  const ZoomAwareUncertaintyLayer({super.key, required this.polygons});

  @override
  Widget build(BuildContext context) {
    if (polygons.isEmpty) return const SizedBox.shrink();
    if (MapCamera.of(context).zoom <= 15) return const SizedBox.shrink();
    return PolygonLayer(polygons: polygons);
  }
}

/// Shows the raw (unfiltered) GPS fixes only at harbour/detail zoom (> 15),
/// as faint blue texture inside the uncertainty band — not a competing line.
/// At route zoom two overlapping tracks just look like a mess.
class ZoomAwareRawTrackLayer extends StatelessWidget {
  final List<TrackPoint> rawPoints;
  const ZoomAwareRawTrackLayer({super.key, required this.rawPoints});

  static const _rawColor = Color(0x3342A5F5); // Blue 400 at ~20 %

  @override
  Widget build(BuildContext context) {
    if (rawPoints.isEmpty) return const SizedBox.shrink();
    if (MapCamera.of(context).zoom <= 15) return const SizedBox.shrink();
    return PolylineLayer(
      polylines: [
        for (final seg in splitTrackSegments(rawPoints))
          if (seg.length >= 2)
            Polyline(
              points: seg.map((p) => LatLng(p.lat, p.lon)).toList(),
              strokeWidth: 1.0,
              color: _rawColor,
            ),
      ],
      cullingMargin: null,
      simplificationTolerance: 0,
    );
  }
}
