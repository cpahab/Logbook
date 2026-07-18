import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:provider/provider.dart';

import '../../../core/constants/map_config.dart';
import '../../../l10n/l10n_extension.dart';
import '../../settings/domain/theme_provider.dart';
import '../domain/day_entry.dart';
import '../domain/timeline_entry.dart';
import '../widgets/entry_tooltip.dart';
import '../widgets/map_render_helpers.dart';

// ── Full-screen map for a positions-only day ──────────────────────────────────
/// Full-screen version of the day-detail screen's positions-only map (opened
/// from its fullscreen button): same simplified rendering — a polyline once
/// there are 2+ logged positions, otherwise just the pin(s) — plus its own
/// satellite toggle and dropped-marker state, so it works standalone without
/// the day-detail screen's state.
class PositionsOnlyMapFullScreen extends StatefulWidget {
  final DayEntry entry;
  final List<TimelineEntry> positioned; // pre-sorted by the caller
  final bool initialSatellite;

  const PositionsOnlyMapFullScreen({
    super.key,
    required this.entry,
    required this.positioned,
    required this.initialSatellite,
  });

  @override
  State<PositionsOnlyMapFullScreen> createState() => _PositionsOnlyMapFullScreenState();
}

class _PositionsOnlyMapFullScreenState extends State<PositionsOnlyMapFullScreen> {
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

  /// Renders the same map layers as the day-detail screen's own
  /// positions-only map, sized to fill the whole screen, with its own
  /// zoom/recenter/satellite/close controls.
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final points = widget.positioned.map((t) => LatLng(t.latitude!, t.longitude!)).toList();
    final positionsColor = _satelliteView ? cs.secondaryFixed : cs.primary;
    final positionsPolylines = <Polyline>[
      if (points.length >= 2)
        Polyline(
          points: points,
          strokeWidth: 4,
          color: positionsColor,
          borderStrokeWidth: _satelliteView ? 1.5 : 0,
          borderColor: Colors.black.withValues(alpha: 0.45),
        ),
    ];

    final markers = <Marker>[
      for (final t in widget.positioned)
        Marker(
          point: LatLng(t.latitude!, t.longitude!),
          width: 20,
          height: 20,
          alignment: Alignment.center,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _dropMarker(
              LatLng(t.latitude!, t.longitude!),
              buildEntryTooltip(t, context.l10n,
                  context.read<ThemeProvider>().vesselEquipment.activeSlots),
            ),
            child: Center(
              child: Container(
                width: 11,
                height: 11,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: cs.surface,
                  border: Border.all(color: cs.primary, width: 2.5),
                ),
              ),
            ),
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
            heroTag: 'posfs_close',
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
            initialCenter: points.length == 1 ? points.first : const LatLng(0, 0),
            initialZoom: 13,
            initialCameraFit: points.length >= 2
                ? CameraFit.bounds(
                    bounds: LatLngBounds.fromPoints(points),
                    padding: const EdgeInsets.all(60),
                  )
                : null,
          ),
          children: [
            mapTileLayer(satelliteView: _satelliteView),
            PolylineLayer(polylines: positionsPolylines, cullingMargin: null, simplificationTolerance: 0),
            MarkerLayer(markers: markers),
            mapAttribution(satelliteView: _satelliteView),
          ],
        ),
        Positioned(
          right: 10, bottom: 10,
          child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            if (defaultTargetPlatform == TargetPlatform.macOS) ...[
              mapZoomButton(Icons.add, () => _mapController.move(_mapController.camera.center, _mapController.camera.zoom + 1), cs, heroTagPrefix: 'posfs_'),
              const SizedBox(height: 6),
              mapZoomButton(Icons.remove, () => _mapController.move(_mapController.camera.center, _mapController.camera.zoom - 1), cs, heroTagPrefix: 'posfs_'),
              const SizedBox(height: 6),
              mapZoomButton(Icons.explore, () {
                if (points.length >= 2) {
                  _mapController.fitCamera(CameraFit.bounds(bounds: LatLngBounds.fromPoints(points), padding: const EdgeInsets.all(60)));
                } else if (points.isNotEmpty) {
                  _mapController.move(points.first, 13);
                }
              }, cs, heroTagPrefix: 'posfs_'),
              const SizedBox(height: 6),
            ],
            FloatingActionButton.small(
              heroTag: 'posfs_satellite',
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
