import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;

import 'map_render_helpers.dart' show BaseVectorMapLayer;

/// Fixed output size for every PDF map image. Deliberately matches the
/// aspect ratio of the container this image is actually embedded into
/// (pdf_exporter.dart's _buildTrackMap: a fixed 160pt-tall pw.Container,
/// pw.BoxFit.cover, inside a flex-8-of-13 column on an A4 page with 40pt
/// horizontal margins and a 20pt row gap — (595.28 - 80 - 20) * 8/13 / 160
/// ≈ 1.905:1) — not just an arbitrary "high enough resolution" choice.
/// A prior version of this constant was 1280x1024 (1.25:1, inherited from
/// the old raster-tile-grid canvas this replaced) and mismatched the real
/// embed target badly enough that BoxFit.cover cropped ~17% off the top
/// and bottom of every exported map image, clipping tracks that ran close
/// to vertical. If pdf_exporter.dart's track-map layout ever changes,
/// recompute this ratio to match — otherwise the crop comes back.
const _kCaptureSize = Size(1280, 672);

/// Renders [points] (+ optional [entryPositions]) on the same vector base
/// map used on-screen, offscreen, and returns it as PNG bytes — the
/// vector-tile equivalent of the old manual Mercator-projection/canvas-tile-
/// compositing pipeline this replaces, reusing the real PolylineLayer/Marker
/// widgets instead of hand-drawing lookalikes on a bare Canvas.
///
/// Must be called on the main isolate with a live, mounted [context].
Future<Uint8List?> captureTrackMapImage(
  BuildContext context, {
  required List<({double lat, double lon})> points,
  List<(double, double)> entryPositions = const [],
}) async {
  if (points.length < 2) return null;
  final trackPoints = points.map((p) => LatLng(p.lat, p.lon)).toList();
  final allPoints = [
    ...trackPoints,
    for (final (lat, lon) in entryPositions) LatLng(lat, lon),
  ];
  final bounds = LatLngBounds.fromPoints(allPoints);

  return _capture(context, bounds: bounds, children: [
    const BaseVectorMapLayer(),
    PolylineLayer(polylines: [
      Polyline(points: trackPoints, strokeWidth: 6.0, color: const Color(0xCCFFFFFF)),
      Polyline(points: trackPoints, strokeWidth: 3.0, color: const Color(0xDD003366)),
    ]),
    MarkerLayer(markers: [
      for (final (lat, lon) in entryPositions)
        _dotMarker(LatLng(lat, lon), const Color(0xFF003366)),
      _dotMarker(trackPoints.first, const Color(0xFF2E7D32)),
      _dotMarker(trackPoints.last, const Color(0xFFC62828)),
    ]),
    const _NorthIndicator(),
  ]);
}

/// Same as [captureTrackMapImage] but for discrete positions with no
/// continuous track.
Future<Uint8List?> capturePositionsMapImage(
  BuildContext context,
  List<(double, double)> positions,
) async {
  if (positions.isEmpty) return null;
  final points = positions.map((p) => LatLng(p.$1, p.$2)).toList();
  final bounds = LatLngBounds.fromPoints(points);

  return _capture(context, bounds: bounds, children: [
    const BaseVectorMapLayer(),
    if (points.length >= 2)
      PolylineLayer(polylines: [
        Polyline(points: points, strokeWidth: 6.0, color: const Color(0xCCFFFFFF)),
        Polyline(points: points, strokeWidth: 3.0, color: const Color(0xDD003366)),
      ]),
    MarkerLayer(markers: [
      for (int i = 0; i < points.length; i++)
        _dotMarker(
          points[i],
          points.length >= 2 && i == 0
              ? const Color(0xFF2E7D32)
              : points.length >= 2 && i == points.length - 1
                  ? const Color(0xFFC62828)
                  : const Color(0xFF003366),
        ),
    ]),
    const _NorthIndicator(),
  ]);
}

Marker _dotMarker(LatLng point, Color color) => Marker(
      point: point,
      width: 14,
      height: 14,
      alignment: Alignment.center,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          border: Border.all(color: Colors.white, width: 2),
        ),
      ),
    );

/// Small "N" compass badge in the map image's top-right corner — matches
/// the old canvas-drawn version this replaces (a circular badge containing
/// a triangular compass-needle arrow + stem, with a bold "N" label above
/// it) rather than a generic up-arrow, since an arrow alone doesn't say
/// *which* direction is up the way the letter does.
class _NorthIndicator extends StatelessWidget {
  const _NorthIndicator();

  @override
  Widget build(BuildContext context) => Positioned(
        right: 16,
        top: 12,
        child: IgnorePointer(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Text(
                'N',
                style: TextStyle(
                  color: Color(0xFF003366),
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 2),
              Container(
                width: 32,
                height: 32,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xCCE8EEF4),
                  border: Border.fromBorderSide(BorderSide(color: Color(0xFF8FA8BF))),
                ),
                child: CustomPaint(painter: _CompassNeedlePainter()),
              ),
            ],
          ),
        ),
      );
}

/// Draws the triangular compass-needle arrow + stem inside [_NorthIndicator]'s
/// circle — same geometry as the old canvas-drawn _drawNorthIndicator.
class _CompassNeedlePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    const r = 16.0;
    canvas.drawPath(
      Path()
        ..moveTo(cx, cy - r + 5)
        ..lineTo(cx - 5.5, cy + 5)
        ..lineTo(cx + 5.5, cy + 5)
        ..close(),
      Paint()..color = const Color(0xFF003366),
    );
    canvas.drawLine(
      Offset(cx, cy + 5),
      Offset(cx, cy + r - 4),
      Paint()
        ..color = const Color(0xFF8FA8BF)
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant _CompassNeedlePainter oldDelegate) => false;
}

/// Mounts [children] on an offscreen FlutterMap (fit to [bounds]) inside a
/// RepaintBoundary via an OverlayEntry, waits for the vector style/tiles to
/// settle, captures a PNG, then tears the overlay entry down.
Future<Uint8List?> _capture(
  BuildContext context, {
  required LatLngBounds bounds,
  required List<Widget> children,
}) async {
  if (!context.mounted) return null;
  final repaintKey = GlobalKey();
  final mapController = MapController();
  final cameraFit = CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(48));
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => Positioned(
      // Far outside the visible viewport rather than Offstage: fully laid
      // out and painted (Offstage/hidden trees can skip painting on some
      // engine paths), just never visible to the user.
      left: -_kCaptureSize.width - 100,
      top: 0,
      child: SizedBox(
        width: _kCaptureSize.width,
        height: _kCaptureSize.height,
        child: RepaintBoundary(
          key: repaintKey,
          child: FlutterMap(
            mapController: mapController,
            options: MapOptions(
              // Only a first-frame approximation: MapOptions.initialCameraFit
              // is computed once, at construction, and can end up fit against
              // a not-yet-final widget size here (this SizedBox sits inside
              // an Overlay/Positioned, unlike a live map mounted directly in
              // the normal widget tree with immediately-correct constraints)
              // — that raced computation is what clipped part of a track off
              // the edge of a real export. Corrected for real below, once the
              // widget has had a guaranteed-correct-size frame.
              initialCameraFit: cameraFit,
              interactionOptions: const InteractionOptions(flags: InteractiveFlag.none),
            ),
            children: children,
          ),
        ),
      ),
    ),
  );

  final overlay = Overlay.of(context, rootOverlay: true);
  overlay.insert(entry);
  try {
    await SchedulerBinding.instance.endOfFrame;
    // Re-fit now that the widget has definitely been laid out at its real
    // _kCaptureSize — see the comment on initialCameraFit above.
    mapController.fitCamera(cameraFit);
    await SchedulerBinding.instance.endOfFrame;
    await _waitUntilSettled();

    final boundary = repaintKey.currentContext?.findRenderObject();
    if (kDebugMode) {
      final camera = mapController.camera;
      debugPrint('[MapCapture] requested bounds: sw=${bounds.southWest} ne=${bounds.northEast}');
      debugPrint('[MapCapture] actual camera: zoom=${camera.zoom} visibleBounds=${camera.visibleBounds}');
      debugPrint('[MapCapture] RepaintBoundary size: ${(boundary as RenderBox?)?.size} '
          '(expected $_kCaptureSize)');
    }
    if (boundary is! RenderRepaintBoundary) return null;
    // pixelRatio: 1.0 — capture at exactly _kCaptureSize physical pixels
    // regardless of the exporting device's actual DPI, so output image
    // dimensions (and therefore on-page line weight) stay constant across
    // devices, matching the old fixed-canvas-size behavior.
    final image = await boundary.toImage(pixelRatio: 1.0);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData?.buffer.asUint8List();
  } finally {
    entry.remove();
    mapController.dispose();
  }
}

/// Waits until the engine stops scheduling new frames for a full
/// [checkInterval], as a proxy for "vector tiles have finished arriving and
/// rendering." vector_map_tiles exposes no public "tiles loaded" signal —
/// its internal tile-loading tracker is a private ChangeNotifier, not part
/// of the package's public API — but every tile arrival triggers a rebuild,
/// which schedules a frame; once nothing new arrives, frame scheduling goes
/// quiet on its own. A single fixed delay was tried first and produced
/// partially-blank captures (missing tiles) on a wider/first-time view
/// whose tiles hadn't all rendered yet — this adapts to both a fast,
/// warm-cache view and a slow, cold-cache one instead of guessing one
/// constant for both. [maxWait] bounds the total wait so a stalled or
/// offline fetch doesn't hang the export forever — better a slightly
/// incomplete capture than one that never finishes.
Future<void> _waitUntilSettled({
  Duration checkInterval = const Duration(milliseconds: 300),
  Duration maxWait = const Duration(seconds: 6),
}) async {
  final deadline = DateTime.now().add(maxWait);
  while (DateTime.now().isBefore(deadline)) {
    await Future.delayed(checkInterval);
    if (!SchedulerBinding.instance.hasScheduledFrame) return;
  }
}
