import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:provider/provider.dart';

import '../../../core/constants/map_config.dart';
import '../../../l10n/l10n_extension.dart';
import '../../settings/domain/theme_provider.dart';
import '../../tracks/data/track_computation_cache.dart';
import '../domain/day_entry.dart';
import '../domain/daily_track.dart';
import '../domain/track_point.dart';
import '../utils/bearing_utils.dart';
import '../utils/filter_settings.dart';
import '../utils/track_correlation.dart';
import '../utils/trim_track.dart';
import '../widgets/day_detail_display_helpers.dart';
import '../widgets/entry_tooltip.dart';
import '../widgets/map_layers.dart';
import '../widgets/map_render_helpers.dart';

// ── Full-screen map for a single day ──────────────────────────────────────────
/// Full-screen version of the day-detail screen's own track map (opened from
/// its fullscreen button): same rendering, plus its own satellite toggle and
/// dropped-marker state, so it works standalone without the day-detail
/// screen's state.
class DayMapFullScreen extends StatefulWidget {
  final DayEntry entry;
  final DailyTrack track;
  final FilterSettings filterSettings;
  final bool initialSatellite;
  final bool showRawTrack;

  const DayMapFullScreen({
    super.key,
    required this.entry,
    required this.track,
    required this.filterSettings,
    required this.initialSatellite,
    required this.showRawTrack,
  });

  @override
  State<DayMapFullScreen> createState() => _DayMapFullScreenState();
}

class _DayMapFullScreenState extends State<DayMapFullScreen> {
  final MapController _mapController = MapController();
  late bool _satelliteView;
  LatLng? _droppedMarkerLatLng;
  String? _droppedMarkerLabel;
  Timer? _markerDismissTimer;

  @override
  void initState() {
    super.initState();
    _satelliteView = widget.initialSatellite;
  }

  @override
  void dispose() {
    _markerDismissTimer?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  /// Shows a tap-to-inspect marker at [pos] with [label], auto-dismissing
  /// after 5 seconds.
  void _dropMarker(LatLng pos, String label) {
    _markerDismissTimer?.cancel();
    setState(() {
      _droppedMarkerLatLng = pos;
      _droppedMarkerLabel  = label;
    });
    _markerDismissTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() { _droppedMarkerLatLng = null; _droppedMarkerLabel = null; });
    });
  }

  /// The track point closest to a map tap, by planar distance.
  TrackPoint? _findNearest(LatLng tap, List<TrackPoint> points) {
    if (points.isEmpty) return null;
    TrackPoint? best;
    double minDq = double.infinity;
    for (final p in points) {
      final dq = (p.lat - tap.latitude) * (p.lat - tap.latitude) +
                 (p.lon - tap.longitude) * (p.lon - tap.longitude);
      if (dq < minDq) { minDq = dq; best = p; }
    }
    return best;
  }

  /// Renders the same map layers as the day-detail screen's own track map,
  /// sized to fill the whole screen, with its own zoom/recenter/satellite/close controls.
  @override
  Widget build(BuildContext context) {
    final cs    = Theme.of(context).colorScheme;
    final track = widget.track;
    final entry = widget.entry;

    final display    = TrackComputationCache.get(
      day: track.day,
      sourcePoints: track.points,
      settings: widget.filterSettings,
    ).display;
    final correlated = correlateTimelineWithTrack(entry.timeline, display.correlationPoints);

    final startPoint = display.firstMovingPoint ?? track.points.first;
    final endPoint   = display.lastMovingPoint  ?? track.points.last;
    final cleanedLatLngs = display.movingPoints().map((p) => LatLng(p.lat, p.lon)).toList();
    final boundsLatLngs = [
      for (final s in display.segments)
        if (s.kind != SegmentKind.teleportBreak)
          for (final p in s.points)
            if (p.lat.isFinite && p.lon.isFinite) LatLng(p.lat, p.lon),
      for (final s in display.stops)
        if (s.lat.isFinite && s.lon.isFinite) LatLng(s.lat, s.lon),
    ];
    final fitLatLngs = boundsLatLngs.isNotEmpty
        ? boundsLatLngs
        : track.points
            .where((p) => p.lat.isFinite && p.lon.isFinite)
            .map((p) => LatLng(p.lat, p.lon))
            .toList();
    final trackBounds = fitLatLngs.isNotEmpty ? LatLngBounds.fromPoints(fitLatLngs) : null;

    final startStop = display.startStop;
    final endStop   = display.endStop;
    final endPositionReliable = display.endPositionReliable;
    final startPos  = startStop != null ? LatLng(startStop.lat, startStop.lon) : LatLng(startPoint.lat, startPoint.lon);
    final endPos    = endStop   != null ? LatLng(endStop.lat,   endStop.lon)   : LatLng(endPoint.lat,   endPoint.lon);

    final departureBearing = cleanedLatLngs.length >= 2 ? dayDetailDepartureBearing(cleanedLatLngs, startPos) : 0.0;
    final arrivalBearing   = cleanedLatLngs.length >= 2 ? dayDetailArrivalBearing(cleanedLatLngs, endPos) : 0.0;
    // Effective departure/arrival (from windowed speed) rather than the raw/
    // segment-based start/endPoint time — see the doc comments on
    // DisplayModel.departureTime/arrivalTime.
    final departurePrecision = display.departurePrecision;
    final startTimeStr = switch (departurePrecision) {
      TimePrecision.unknown => '—',
      TimePrecision.estimated =>
        '~ ${DateFormat('HH:mm').format((display.departureTime ?? startPoint.time).toLocal())}',
      TimePrecision.precise =>
        DateFormat('HH:mm').format((display.departureTime ?? startPoint.time).toLocal()),
    };
    final endTimeStr = (endPositionReliable ? '' : '~ ') +
        DateFormat('HH:mm').format((display.arrivalTime ?? endPoint.time).toLocal());

    final anchorCircles = <CircleMarker>[];
    for (final stop in display.stops) {
      anchorCircles.add(CircleMarker(point: LatLng(stop.lat, stop.lon), radius: stop.r95M, useRadiusInMeter: true, color: cs.primary.withValues(alpha: 0.07)));
      anchorCircles.add(CircleMarker(point: LatLng(stop.lat, stop.lon), radius: stop.cep50M, useRadiusInMeter: true,
          color: cs.primary.withValues(alpha: 0.22), borderStrokeWidth: 1.5, borderColor: cs.primary.withValues(alpha: 0.50)));
    }

    final fsUncertaintyPolygons = display.uncertaintyBands()
        .map((ring) => Polygon(
              points: ring.map((c) => LatLng(c.$1, c.$2)).toList(),
              color: const Color(0x1A42A5F5),
              borderStrokeWidth: 0,
            ))
        .toList();

    final fsTrackPolylines = <Polyline>[];
    final fsTrackColor = _satelliteView ? cs.secondaryFixed : cs.primary;
    for (final seg in display.segments) {
      if (seg.kind == SegmentKind.moving && seg.points.length >= 2) {
        fsTrackPolylines.add(Polyline(
          points: seg.points.map((p) => LatLng(p.lat, p.lon)).toList(),
          strokeWidth: 4,
          color: fsTrackColor,
          borderStrokeWidth: _satelliteView ? 1.5 : 0,
          borderColor: Colors.black.withValues(alpha: 0.45),
        ));
      } else if ((seg.kind == SegmentKind.stopEntry ||
                  seg.kind == SegmentKind.stopExit) &&
                 seg.points.length >= 2) {
        fsTrackPolylines.add(Polyline(
          points: seg.points.map((p) => LatLng(p.lat, p.lon)).toList(),
          strokeWidth: 2.5,
          color: fsTrackColor.withValues(alpha: 0.50),
          borderStrokeWidth: _satelliteView ? 1.0 : 0,
          borderColor: Colors.black.withValues(alpha: 0.35),
        ));
      }
    }

    final timelineMarkers = correlated.map((pair) {
      final t = pair.$1; final p = pair.$2;
      return Marker(
        point: LatLng(p.lat, p.lon), width: 20, height: 20, alignment: Alignment.center,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _dropMarker(
            LatLng(p.lat, p.lon),
            buildEntryTooltip(t, context.l10n,
                context.read<ThemeProvider>().vesselEquipment.activeSlots),
          ),
          child: Center(child: Container(
            width: 11, height: 11,
            decoration: BoxDecoration(shape: BoxShape.circle, color: cs.surface, border: Border.all(color: cs.primary, width: 2.5)),
          )),
        ),
      );
    }).toList();

    final fsMidStopMarkers = [
      for (final stop in display.stops.where((s) => s.kind == AnchorKind.mid))
        Marker(
          point: LatLng(stop.lat, stop.lon),
          width: 32,
          height: 32,
          alignment: Alignment.center,
          child: Tooltip(
            message: fmtDur(stop.minutes),
            triggerMode: isTouchPlatform ? TooltipTriggerMode.tap : TooltipTriggerMode.longPress,
            showDuration: isTouchPlatform ? const Duration(seconds: 4) : const Duration(milliseconds: 1500),
            waitDuration: isTouchPlatform ? Duration.zero : const Duration(milliseconds: 400),
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.85),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.5),
                boxShadow: [BoxShadow(
                  color: Colors.black.withValues(alpha: 0.20),
                  blurRadius: 3, offset: const Offset(0, 1))],
              ),
              child: Icon(
                stop.minutes >= 30 ? Icons.anchor : Icons.schedule,
                size: 14,
                color: Colors.white,
              ),
            ),
          ),
        ),
    ];

    final markers = <Marker>[
      ...timelineMarkers,
      ...fsMidStopMarkers,
      Marker(
        point: startPos, width: 82, height: 22, alignment: Alignment.centerRight,
        child: Tooltip(
          message: switch (departurePrecision) {
            TimePrecision.precise => '',
            TimePrecision.estimated => context.l10n.departureTimeEstimatedTooltip,
            TimePrecision.unknown => context.l10n.departureTimeUnknownTooltip,
          },
          child: Row(mainAxisAlignment: MainAxisAlignment.end, crossAxisAlignment: CrossAxisAlignment.center, children: [
            trackLabel(context, startTimeStr, cs), const SizedBox(width: 5),
            departurePrecision == TimePrecision.precise
                ? Transform.rotate(angle: departureBearing, child: trackArrow(cs.primary))
                : trackArrow(cs.primary, icon: Icons.gps_not_fixed),
          ]),
        ),
      ),
      Marker(
        point: endPos, width: 82, height: 22, alignment: Alignment.centerLeft,
        child: Tooltip(
          message: endPositionReliable ? '' : context.l10n.arrivalTimeUncertainTooltip,
          child: Row(mainAxisAlignment: MainAxisAlignment.start, crossAxisAlignment: CrossAxisAlignment.center, children: [
            endPositionReliable
                ? Transform.rotate(angle: arrivalBearing, child: trackArrow(cs.primary))
                : trackArrow(cs.primary, icon: Icons.gps_not_fixed),
            const SizedBox(width: 5), trackLabel(context, endTimeStr, cs),
          ]),
        ),
      ),
    ];

    if (_droppedMarkerLatLng != null) {
      markers.add(droppedMarker(
        position: _droppedMarkerLatLng!,
        label: _droppedMarkerLabel,
        context: context,
        cs: cs,
        onDismiss: () {
          _markerDismissTimer?.cancel();
          setState(() { _droppedMarkerLatLng = null; _droppedMarkerLabel = null; });
        },
      ));
    }

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: Padding(
          padding: const EdgeInsets.all(8),
          child: FloatingActionButton.small(
            heroTag: 'fs_close',
            onPressed: () => Navigator.pop(context),
            backgroundColor: cs.surfaceContainerLowest.withValues(alpha: 0.9),
            foregroundColor: cs.primary,
            elevation: 2,
            child: const Icon(Icons.fullscreen_exit, size: 20),
          ),
        ),
      ),
      body: Stack(children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            maxZoom: kMaxMapZoom,
            initialCameraFit: trackBounds != null
                ? CameraFit.bounds(bounds: trackBounds, padding: const EdgeInsets.all(60))
                : null,
            onTap: (_, latLng) {
              final nearest = _findNearest(latLng, track.points);
              if (nearest == null) return;
              _dropMarker(LatLng(nearest.lat, nearest.lon),
                  DateFormat('HH:mm').format(nearest.time.toLocal()));
            },
          ),
          children: [
            mapTileLayer(satelliteView: _satelliteView),
            ZoomAwareUncertaintyLayer(polygons: fsUncertaintyPolygons),
            ZoomAwareCircleLayer(circles: anchorCircles),
            PolylineLayer(polylines: fsTrackPolylines, cullingMargin: null, simplificationTolerance: 0),
            if (widget.showRawTrack) ZoomAwareRawTrackLayer(rawPoints: display.rawMovingPoints),
            MarkerLayer(markers: markers),
            mapAttribution(satelliteView: _satelliteView),
          ],
        ),
        Positioned(
          right: 10, bottom: 10,
          child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            if (defaultTargetPlatform == TargetPlatform.macOS) ...[
              mapZoomButton(Icons.add, () => _mapController.move(_mapController.camera.center, _mapController.camera.zoom + 1), cs, heroTagPrefix: 'fs_'),
              const SizedBox(height: 6),
              mapZoomButton(Icons.remove, () => _mapController.move(_mapController.camera.center, _mapController.camera.zoom - 1), cs, heroTagPrefix: 'fs_'),
              const SizedBox(height: 6),
              mapZoomButton(Icons.explore, () {
                if (fitLatLngs.isNotEmpty) {
                  _mapController.fitCamera(CameraFit.bounds(bounds: LatLngBounds.fromPoints(fitLatLngs), padding: const EdgeInsets.all(60)));
                }
              }, cs, heroTagPrefix: 'fs_'),
              const SizedBox(height: 6),
            ],
            FloatingActionButton.small(
              heroTag: 'fs_satellite',
              onPressed: () => setState(() => _satelliteView = !_satelliteView),
              tooltip: _satelliteView
                  ? context.l10n.tracksMapView
                  : context.l10n.tracksSatelliteView,
              child: Icon(_satelliteView ? Icons.map_outlined : Icons.satellite_alt),
            ),
          ]),
        ),
      ]),
    );
  }
}
