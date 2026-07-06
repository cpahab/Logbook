import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/theme/theme_extensions.dart';
import '../../home/data/home_repository.dart';
import '../../home/domain/day_entry.dart';
import '../../home/utils/compute_daily_stats.dart';
import '../../home/domain/track_point.dart';
import '../../home/utils/trim_track.dart'
    show trimStationaryEnds, buildDisplayModel, DisplayModel, SegmentKind,
        splitTrackSegments;
import '../../home/widgets/nav_bar.dart';
import '../../home/widgets/stat_inline.dart';
import '../../settings/domain/theme_provider.dart';
import '../../../l10n/l10n_extension.dart';
import '../../../core/constants/map_config.dart';

// Bearing (radians, clockwise from north) between two LatLng points.
double _trackBearing(LatLng from, LatLng to) {
  final lat1 = from.latitude * pi / 180;
  final lat2 = to.latitude * pi / 180;
  final dLon = (to.longitude - from.longitude) * pi / 180;
  final y = sin(dLon) * cos(lat2);
  final x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon);
  return atan2(y, x);
}

// Haversine distance in metres between two LatLng points.
double _distanceM(LatLng a, LatLng b) {
  const r = 6371000.0;
  final lat1 = a.latitude * pi / 180;
  final lat2 = b.latitude * pi / 180;
  final dLat = (b.latitude - a.latitude) * pi / 180;
  final dLon = (b.longitude - a.longitude) * pi / 180;
  final s = sin(dLat / 2) * sin(dLat / 2) +
      cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2);
  return r * 2 * atan2(sqrt(s), sqrt(1 - s));
}

// Bearing for the departure arrow: bearing from start toward the point that
// is ≥ 500 m cumulative along track. Falls back to start→furthest for short tracks.
double _departureBearing(List<LatLng> pts) {
  if (pts.length < 2) return 0;
  const targetM = 500.0;
  double cum = 0;
  for (int i = 1; i < pts.length; i++) {
    cum += _distanceM(pts[i - 1], pts[i]);
    if (cum >= targetM) return _trackBearing(pts[0], pts[i]);
  }
  double maxDist = 0;
  int farIdx = 1;
  for (int i = 1; i < pts.length; i++) {
    final d = _distanceM(pts[0], pts[i]);
    if (d > maxDist) {
      maxDist = d;
      farIdx = i;
    }
  }
  return _trackBearing(pts[0], pts[farIdx]);
}

enum _FilterPreset { year1, month1, week1, custom }

class TracksScreen extends StatefulWidget {
  const TracksScreen({super.key});

  @override
  State<TracksScreen> createState() => _TracksScreenState();
}

class _TracksScreenState extends State<TracksScreen> {
  final MapController _mapController = MapController();
  int? _selectedIndex;

  // Date-range filter and map style are `static` (process lifetime) rather
  // than instance fields: the bottom nav pushes a fresh TracksScreen route
  // on every tab switch, which would otherwise silently reset the user's
  // filter choice back to the default every time they left and returned to
  // this tab. Static fields survive that, but still reset to their declared
  // defaults on a genuine cold start (fresh process).
  static _FilterPreset _preset = _FilterPreset.month1;
  static DateTimeRange? _customRange;
  static bool _satelliteView = false;
  @override
  void initState() {
    super.initState();
  }

  // Golden-angle hue palette: each sequential track steps ~137.5° around the
  // hue wheel, guaranteeing maximum perceptual separation between adjacent days.
  static Color _colorForIndex(int index, int _) {
    const goldenAngle = 137.508; // 360° / φ²
    const startHue = 200.0;     // begin at nautical blue
    final hue = (startHue + index * goldenAngle) % 360;
    return HSLColor.fromAHSL(1.0, hue, 0.75, 0.48).toColor();
  }

  DateTimeRange? get _effectiveRange {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    switch (_preset) {
      case _FilterPreset.year1:
        return DateTimeRange(
            start: DateTime(now.year - 1, now.month, now.day), end: today);
      case _FilterPreset.month1:
        return DateTimeRange(
            start: DateTime(now.year, now.month - 1, now.day), end: today);
      case _FilterPreset.week1:
        return DateTimeRange(
            start: today.subtract(const Duration(days: 7)), end: today);
      case _FilterPreset.custom:
        return _customRange;
    }
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  LatLngBounds? _boundsFor(List<LatLng> pts) {
    final finite = pts.where((p) => p.latitude.isFinite && p.longitude.isFinite).toList();
    if (finite.isEmpty) return null;
    double minLat = finite.first.latitude, maxLat = finite.first.latitude;
    double minLng = finite.first.longitude, maxLng = finite.first.longitude;
    for (final p in finite) {
      minLat = min(minLat, p.latitude);
      maxLat = max(maxLat, p.latitude);
      minLng = min(minLng, p.longitude);
      maxLng = max(maxLng, p.longitude);
    }
    return LatLngBounds(LatLng(minLat, minLng), LatLng(maxLat, maxLng));
  }

  void _focusTrack(List<LatLng> pts) {
    final bounds = _boundsFor(pts);
    if (bounds == null) return;
    _mapController.fitCamera(
        CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(40)));
  }

  void _refitToDisplayed() {
    final repo      = context.read<HomeRepository>();
    final settings  = context.read<ThemeProvider>().filterSettings;
    final range     = _effectiveRange;
    final pts = repo.dailyTracks.entries
        .where((e) =>
            range == null ||
            (!e.key.isBefore(range.start) && !e.key.isAfter(range.end)))
        .expand((e) {
          final trimmed = trimStationaryEnds(e.value.points, settings: settings);
          return trimmed.map((p) => LatLng(p.lat, p.lon));
        })
        .toList();
    final bounds = _boundsFor(pts);
    if (bounds == null) return;
    _mapController.fitCamera(
        CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(24)));
  }

  void _applyPreset(_FilterPreset preset, {DateTimeRange? custom}) {
    setState(() {
      _preset = preset;
      if (custom != null) _customRange = custom;
      _selectedIndex = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _refitToDisplayed());
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final initial = _effectiveRange ??
        DateTimeRange(
            start: DateTime(now.year, now.month - 1, now.day), end: now);
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: now,
      initialDateRange: initial,
      locale: context.read<ThemeProvider>().materialLocale,
      builder: (context, child) => MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.0,
        child: child!,
      ),
    );
    if (range != null) _applyPreset(_FilterPreset.custom, custom: range);
  }

  @override
  Widget build(BuildContext context) {
    final repo           = context.watch<HomeRepository>();
    final provider       = context.watch<ThemeProvider>();
    final filterSettings = provider.filterSettings;
    final showRawTrack   = provider.showRawTrack;
    final cs             = Theme.of(context).colorScheme;

    final trackedDays = repo.dailyTracks.keys.toList()..sort();
    final totalTracks =
        trackedDays.where((d) => repo.dailyTracks[d]!.points.isNotEmpty).length;

    final List<_DayTrackData> trackData = [];
    int trackIdx = 0;
    for (final day in trackedDays) {
      final track = repo.dailyTracks[day]!;
      if (track.points.isEmpty) continue;
      final display = buildDisplayModel(track.points, settings: filterSettings);
      trackData.add(_DayTrackData(
        day: day,
        display: display,
        rawPoints: display.rawMovingPoints,
        color: _colorForIndex(trackIdx, totalTracks),
        entry: repo.getEntry(day),
        stats: computeDailyStats(track.points, settings: filterSettings),
        startTime: display.firstMovingPoint?.time.toLocal(),
      ));
      trackIdx++;
    }


    final range = _effectiveRange;
    final displayed = range == null
        ? trackData
        : trackData
            .where((d) =>
                !d.day.isBefore(range.start) && !d.day.isAfter(range.end))
            .toList();

    // Build per-day polyline groups; selected day is drawn last (on top).
    final polylinesByDay = displayed.asMap().entries.map((e) {
      final isSelected = _selectedIndex == e.key;
      final color = isSelected ? e.value.color : e.value.color.withValues(alpha: 0.65);
      final width = isSelected ? 5.0 : 3.0;
      final segs = <Polyline>[];
      for (final seg in e.value.display.segments) {
        if (seg.kind == SegmentKind.moving && seg.points.length >= 2) {
          segs.add(Polyline(
            points: seg.points.map((p) => LatLng(p.lat, p.lon)).toList(),
            color: color,
            strokeWidth: width,
          ));
        } else if ((seg.kind == SegmentKind.stopEntry ||
                    seg.kind == SegmentKind.stopExit) &&
                   seg.points.length >= 2) {
          segs.add(Polyline(
            points: seg.points.map((p) => LatLng(p.lat, p.lon)).toList(),
            color: e.value.color.withValues(alpha: isSelected ? 0.40 : 0.26),
            strokeWidth: width * 0.6,
          ));
        }
        // teleportBreak: no polyline — gap is the visual signal
      }
      return segs;
    }).toList();
    final polylines = <Polyline>[];
    for (int i = 0; i < polylinesByDay.length; i++) {
      if (i != _selectedIndex) polylines.addAll(polylinesByDay[i]);
    }
    if (_selectedIndex != null && _selectedIndex! < polylinesByDay.length) {
      polylines.addAll(polylinesByDay[_selectedIndex!]);
    }

    // Departure arrows at the start of each displayed track
    final arrowMarkers = <Marker>[];
    for (final d in displayed) {
      final movPts = d.display.movingPoints().map((p) => LatLng(p.lat, p.lon)).toList();
      if (movPts.length < 2) continue;
      final bearing = _departureBearing(movPts);
      arrowMarkers.add(Marker(
        point: movPts[0],
        width: 13,
        height: 13,
        child: Transform.rotate(
          angle: bearing,
          child: Container(
            width: 13,
            height: 13,
            decoration: BoxDecoration(
              color: d.color.withValues(alpha: 0.9),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 1),
            ),
            alignment: Alignment.center,
            child: const Icon(Icons.arrow_upward,
                color: Colors.white, size: 7),
          ),
        ),
      ));
    }

    final anchorCircles = <CircleMarker>[];
    for (final d in displayed) {
      for (final stop in d.display.stops) {
        anchorCircles.add(CircleMarker(
          point: LatLng(stop.lat, stop.lon),
          radius: stop.r95M,
          useRadiusInMeter: true,
          color: d.color.withValues(alpha: 0.07),
        ));
        anchorCircles.add(CircleMarker(
          point: LatLng(stop.lat, stop.lon),
          radius: stop.cep50M,
          useRadiusInMeter: true,
          color: d.color.withValues(alpha: 0.22),
          borderStrokeWidth: 1.5,
          borderColor: d.color.withValues(alpha: 0.50),
        ));
      }
    }


    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        centerTitle: true,
        title: Text(context.l10n.tracksTitle),
      ),
      bottomNavigationBar: AppBottomNav(
        active: NavTab.map,
        showFab: false,
        onSelect: (tab) {
          if (tab == NavTab.journal) context.go('/');
          if (tab == NavTab.settings) context.go('/settings');
          if (tab == NavTab.safety) context.go('/emergency');
        },
      ),
      body: trackData.isEmpty
          ? _buildEmpty(cs)
          : Column(
              children: [
                // ── Filter strip (above map) ───────────────────────────
                _buildFilterStrip(cs, displayed),
                // ── Map ────────────────────────────────────────────────
                Expanded(
                  flex: 3,
                  child: _buildMapSection(
                      displayed, polylines, showRawTrack,
                      anchorCircles, arrowMarkers, cs),
                ),
                // ── List ───────────────────────────────────────────────
                Expanded(
                  flex: 2,
                  child: displayed.isEmpty
                      ? _buildEmptyFilter(cs)
                      : _buildListSection(displayed, cs),
                ),
              ],
            ),
    );
  }

  // ── Filter strip ──────────────────────────────────────────────────
  Widget _buildFilterStrip(ColorScheme cs, List<_DayTrackData> displayed) {
    final fmt = DateFormat('d.M.yy');
    final customLabel =
        (_preset == _FilterPreset.custom && _customRange != null)
            ? '${fmt.format(_customRange!.start)}–${fmt.format(_customRange!.end)}'
            : context.l10n.tracksCustom.toUpperCase();

    return Container(
      color: cs.surface,
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _chip(context.l10n.tracksOneYear.toUpperCase(), _FilterPreset.year1, cs),
            const SizedBox(width: 8),
            _chip(context.l10n.tracksOneMonth.toUpperCase(), _FilterPreset.month1, cs),
            const SizedBox(width: 8),
            _chip(context.l10n.tracksOneWeek.toUpperCase(), _FilterPreset.week1, cs),
            const SizedBox(width: 8),
            _chip(customLabel, _FilterPreset.custom, cs, isCustom: true),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, _FilterPreset preset, ColorScheme cs,
      {bool isCustom = false}) {
    final isActive = _preset == preset;
    return GestureDetector(
      onTap: () => isCustom ? _pickDateRange() : _applyPreset(preset),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? cs.primary : cs.surfaceContainer,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall!.copyWith(
            color: isActive ? cs.onPrimary : cs.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  // ── Map section ────────────────────────────────────────────────────
  Widget _buildMapSection(
    List<_DayTrackData> displayed,
    List<Polyline> polylines,
    bool showRawTrack,
    List<CircleMarker> anchorCircles,
    List<Marker> arrowMarkers,
    ColorScheme cs,
  ) {
    final initialBounds = _boundsFor(
      displayed.expand((d) => d.display.allPoints().map((p) => LatLng(p.lat, p.lon))).toList(),
    );
    final uncertaintyPolygons = [
      for (final d in displayed)
        for (final ring in d.display.uncertaintyBands())
          Polygon(
            points: ring.map((c) => LatLng(c.$1, c.$2)).toList(),
            color: d.color.withValues(alpha: 0.10),
            borderStrokeWidth: 0,
          ),
    ];
    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCameraFit: initialBounds != null
                ? CameraFit.bounds(bounds: initialBounds, padding: const EdgeInsets.all(24))
                : null,
          ),
          children: [
            TileLayer(
              urlTemplate: _satelliteView ? kSatelliteUrl : kBaseTileUrl,
              userAgentPackageName: 'com.logbook.app',
              // Keep more of the surrounding tile grid loaded across a
              // pan/zoom transition so fewer tiles need a fresh fetch right
              // when the gesture ends (default is 2).
              keepBuffer: 4,
              // Default is `.none`, which never retries a tile that failed
              // once (transient network blip, tile-server rate limit) — it
              // stays blank until this whole map widget is rebuilt. Evicting
              // once it scrolls out of view lets it be re-fetched next time
              // it's needed.
              evictErrorTileStrategy: EvictErrorTileStrategy.notVisibleRespectMargin,
              errorTileCallback: kDebugMode
                  ? (tile, error, stackTrace) =>
                      debugPrint('[Map] tile ${tile.coordinates} failed to load: $error')
                  : null,
              // Fade-in on arrival is TileLayer's default (tileDisplay:
              // TileDisplay.fadeIn()); this only overrides the tile that
              // failed to load, in place of a blank grey square.
              tileBuilder: (context, tileWidget, tile) => tile.loadError
                  ? Container(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      child: const Icon(Icons.map_outlined, size: 20),
                    )
                  : tileWidget,
            ),
            Builder(builder: (ctx) {
              if (MapCamera.of(ctx).zoom <= 15) return const SizedBox.shrink();
              return PolygonLayer(polygons: uncertaintyPolygons);
            }),
            Builder(builder: (ctx) {
              if (anchorCircles.isEmpty || MapCamera.of(ctx).zoom <= 15) return const SizedBox.shrink();
              return CircleLayer(circles: anchorCircles);
            }),
            PolylineLayer(polylines: polylines, cullingMargin: null, simplificationTolerance: 0),
            Builder(builder: (ctx) {
              if (!showRawTrack || MapCamera.of(ctx).zoom <= 15) return const SizedBox.shrink();
              return PolylineLayer(
                polylines: [
                  for (final d in displayed)
                    for (final seg in splitTrackSegments(d.rawPoints))
                      if (seg.length >= 2)
                        Polyline(
                          points: seg.map((p) => LatLng(p.lat, p.lon)).toList(),
                          strokeWidth: 1.0,
                          color: d.color.withValues(alpha: 0.20),
                        ),
                ],
                cullingMargin: null,
                simplificationTolerance: 0,
              );
            }),
            MarkerLayer(markers: arrowMarkers),
            RichAttributionWidget(
              attributions: [
                // MapTiler version (temporarily disabled, see map_config.dart):
                // TextSourceAttribution(kBaseAttributionLabel, onTap: () async {
                //   final uri = Uri.parse(kBaseAttributionUrl);
                //   if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
                // }),
                // if (!_satelliteView)
                //   TextSourceAttribution(kOsmAttributionLabel, onTap: () async {
                //     final uri = Uri.parse(kOsmAttributionUrl);
                //     if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
                //   }),
                if (_satelliteView)
                  TextSourceAttribution(kSatelliteAttributionLabel, onTap: () async {
                    final uri = Uri.parse(kSatelliteAttributionUrl);
                    if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
                  })
                else
                  TextSourceAttribution(kBaseAttributionLabel, onTap: () async {
                    final uri = Uri.parse(kBaseAttributionUrl);
                    if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }),
              ],
            ),
          ],
        ),
        // Map controls — bottom-right (zoom + center on macOS, satellite always)
        Positioned(
          right: 16,
          bottom: 16,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (defaultTargetPlatform == TargetPlatform.macOS) ...[
                _mapButton(
                  icon: Icons.add,
                  bgColor: cs.surfaceContainerLowest,
                  fgColor: cs.primary,
                  tooltip: context.l10n.tracksZoomIn,
                  onTap: () => _mapController.move(
                    _mapController.camera.center,
                    _mapController.camera.zoom + 1,
                  ),
                ),
                const SizedBox(height: 8),
                _mapButton(
                  icon: Icons.remove,
                  bgColor: cs.surfaceContainerLowest,
                  fgColor: cs.primary,
                  tooltip: context.l10n.tracksZoomOut,
                  onTap: () => _mapController.move(
                    _mapController.camera.center,
                    _mapController.camera.zoom - 1,
                  ),
                ),
                const SizedBox(height: 8),
                _mapButton(
                  icon: Icons.explore,
                  bgColor: cs.primary,
                  fgColor: cs.onPrimary,
                  tooltip: context.l10n.tracksShowAll,
                  onTap: () {
                    setState(() => _selectedIndex = null);
                    _refitToDisplayed();
                  },
                ),
                const SizedBox(height: 8),
              ],
              _mapButton(
                icon: Icons.fullscreen,
                bgColor: cs.surfaceContainerLowest,
                fgColor: cs.primary,
                tooltip: context.l10n.tracksFullscreen,
                onTap: () => context.push(
                  '/tracks/fullscreen',
                  extra: _TracksFullScreenArgs(
                    displayed: displayed,
                    initialBounds: initialBounds,
                    initialSatellite: _satelliteView,
                    selectedIndex: _selectedIndex,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              _mapButton(
                icon: _satelliteView ? Icons.map_outlined : Icons.satellite_alt,
                bgColor: cs.surfaceContainerLowest,
                fgColor: cs.primary,
                tooltip: _satelliteView ? context.l10n.tracksMapView : context.l10n.tracksSatelliteView,
                onTap: () => setState(() => _satelliteView = !_satelliteView),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _mapButton({
    required IconData icon,
    required Color bgColor,
    required Color fgColor,
    required VoidCallback onTap,
    String? tooltip,
  }) {
    return Tooltip(
      message: tooltip ?? '',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Icon(icon, size: 20, color: fgColor),
        ),
      ),
    );
  }

  // ── List section ──────────────────────────────────────────────────
  Widget _buildListSection(List<_DayTrackData> displayed, ColorScheme cs) {
    // Only count legs and distance where actual movement was detected —
    // mirrors the dashboard's gate so both screens report consistent numbers.
    final movingLegs = displayed.where((d) => (d.stats?.distanceNm ?? 0) > 0).toList();
    final totalNm =
        movingLegs.fold<double>(0, (s, d) => s + d.stats!.distanceNm);

    return Column(
      children: [
        // Stats summary
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
          child: Row(
            children: [
              Expanded(child: _statSummaryBox('${movingLegs.length}', context.l10n.statSailingDays, Icons.sailing, cs, unit: context.l10n.statSailingDays)),
              const SizedBox(width: 10),
              Expanded(
                child: _statSummaryBox(
                  totalNm.toStringAsFixed(0), context.l10n.statDistance, Icons.straighten, cs, unit: 'nm'),
              ),
            ],
          ),
        ),
        // List
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            itemCount: displayed.length,
            itemBuilder: (ctx, listIdx) {
              // Newest first
              final i = displayed.length - 1 - listIdx;
              return _buildListItem(i, displayed[i], displayed.length, cs);
            },
          ),
        ),
      ],
    );
  }

  Widget _statSummaryBox(String value, String label, IconData icon, ColorScheme cs, {String unit = ''}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: cs.primaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: Icon(icon, color: cs.onPrimaryContainer, size: 18),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label.toUpperCase(),
                style: GoogleFonts.dmSans(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                  color: cs.mutedLabel,
                ),
              ),
              const SizedBox(height: 2),
              RichText(
                text: TextSpan(
                  children: [
                    TextSpan(
                      text: value,
                      style: GoogleFonts.dmSans(
                        fontSize: 22,
                        fontWeight: FontWeight.w500,
                        color: cs.primary,
                        height: 1.1,
                      ),
                    ),
                    if (unit.isNotEmpty)
                      TextSpan(
                        text: ' $unit',
                        style: Theme.of(context).textTheme.bodySmall!.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildListItem(
      int index, _DayTrackData d, int total, ColorScheme cs) {
    const cardHeight = 110.0;

    final isSelected = _selectedIndex == index;
    final locStr = context.read<ThemeProvider>().localeString;
    final dateLabel = DateFormat('EEEE, d. MMM yyyy', locStr).format(d.day);
    final fromHarbor = d.entry?.fromHarbor;
    final toHarbor = d.entry?.toHarbor;
    final routeTitle = (fromHarbor?.isNotEmpty ?? false) ||
            (toHarbor?.isNotEmpty ?? false)
        ? [
            if (fromHarbor?.isNotEmpty ?? false) fromHarbor!,
            if (toHarbor?.isNotEmpty ?? false) toHarbor!,
          ].join(' → ')
        : DateFormat('EEEE', locStr).format(d.day);

    final notes = d.entry?.notes ?? d.entry?.timeline.firstOrNull?.remarks;
    final wind = d.entry?.timeline.firstOrNull?.wind;

    final listIdx = total - 1 - index;
    final isLast = listIdx == total - 1;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Spine + node ──────────────────────────────────────────
          SizedBox(
            width: 20,
            height: cardHeight,
            child: Column(
              children: [
                const SizedBox(height: 6),
                Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: cs.surface,
                    border: Border.all(color: cs.primary, width: 2),
                  ),
                  child: Center(
                    child: Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: cs.primary,
                      ),
                    ),
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Center(
                      child: Container(width: 2, color: cs.outlineVariant),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // ── Card ──────────────────────────────────────────────────
          Expanded(
            child: GestureDetector(
              onTap: () {
                setState(() => _selectedIndex = index);
                _focusTrack(d.display.allPoints().map((p) => LatLng(p.lat, p.lon)).toList());
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                height: cardHeight,
                decoration: BoxDecoration(
                  color: isSelected
                      ? d.color.withValues(alpha: 0.07)
                      : cs.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected
                        ? d.color
                        : cs.outlineVariant.withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  children: [
                    // Colour bar
                    Container(
                      width: 4,
                      decoration: BoxDecoration(
                        color: d.color,
                        borderRadius: const BorderRadius.horizontal(
                            left: Radius.circular(11)),
                      ),
                    ),
                    // Content
                    Expanded(
                      child: ClipRect(
                        child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Date
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    dateLabel.toUpperCase(),
                                    style: Theme.of(context).textTheme.labelSmall!.copyWith(
                                      color: cs.mutedLabel,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            // Route title
                            Text(
                              routeTitle,
                              style: GoogleFonts.dmSans(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: cs.primary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            // Notes excerpt
                            if (notes?.isNotEmpty == true) ...[
                              const SizedBox(height: 2),
                              Text(
                                notes!,
                                style: Theme.of(context).textTheme.bodySmall!.copyWith(
                                  fontStyle: FontStyle.italic,
                                  color: cs.onSurfaceVariant,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                            // Stats
                            if (wind != null ||
                                (d.stats?.avgMakingWayKn ?? 0) > 0) ...[
                              const SizedBox(height: 4),
                              Wrap(
                                spacing: 10,
                                runSpacing: 2,
                                children: [
                                  if (wind != null)
                                    statInline(Icons.air, wind, cs),
                                  if ((d.stats?.avgMakingWayKn ?? 0) > 0)
                                    statInline(
                                      Icons.speed,
                                      // Moving average, not distance/total-elapsed-time —
                                      // avgSpeed (avgOverGroundKn) would be diluted by any
                                      // stop in the middle of the track.
                                      '${d.stats!.avgMakingWayKn.toStringAsFixed(1)} kn',
                                      cs,
                                    ),
                                  if (d.stats != null &&
                                      d.stats!.distanceNm > 0)
                                    statInline(
                                      Icons.straighten,
                                      '${d.stats!.distanceNm.toStringAsFixed(1)} nm',
                                      cs,
                                    ),
                                ],
                              ),
                            ],
                          ],
                        ),   // Column
                      ),     // Padding
                    ),       // ClipRect
                  ),         // Expanded
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty(ColorScheme cs) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.map_outlined, size: 48, color: cs.outlineVariant),
          const SizedBox(height: 12),
          Text(context.l10n.tracksNoTracks,
              style: Theme.of(context).textTheme.bodyLarge),
        ],
      ),
    );
  }

  Widget _buildEmptyFilter(ColorScheme cs) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.filter_alt_outlined, size: 36, color: cs.outlineVariant),
          const SizedBox(height: 10),
          Text(
            context.l10n.tracksNoTracksInPeriod,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _DayTrackData {
  final DateTime day;
  final DisplayModel display;
  final List<TrackPoint> rawPoints;
  final Color color;
  final DayEntry? entry;
  final DailyStats? stats;
  final DateTime? startTime;

  const _DayTrackData({
    required this.day,
    required this.display,
    required this.rawPoints,
    required this.color,
    required this.entry,
    required this.stats,
    required this.startTime,
  });
}

// ── Full-screen overview map ───────────────────────────────────────────────────

class _TracksFullScreenArgs {
  final List<_DayTrackData> displayed;
  final LatLngBounds? initialBounds;
  final bool initialSatellite;
  final int? selectedIndex;

  const _TracksFullScreenArgs({
    required this.displayed,
    required this.initialBounds,
    required this.initialSatellite,
    this.selectedIndex,
  });
}

/// GoRoute builder registered at `/tracks/fullscreen`.
/// Kept here so private types stay within this file.
Widget tracksFullScreenRouteBuilder(BuildContext context, GoRouterState state) {
  final args = state.extra! as _TracksFullScreenArgs;
  return _TracksMapFullScreen(
    displayed: args.displayed,
    initialBounds: args.initialBounds,
    initialSatellite: args.initialSatellite,
    selectedIndex: args.selectedIndex,
  );
}

class _TracksMapFullScreen extends StatefulWidget {
  final List<_DayTrackData> displayed;
  final LatLngBounds? initialBounds;
  final bool initialSatellite;
  final int? selectedIndex;

  const _TracksMapFullScreen({
    required this.displayed,
    required this.initialBounds,
    required this.initialSatellite,
    this.selectedIndex,
  });

  @override
  State<_TracksMapFullScreen> createState() => _TracksMapFullScreenState();
}

class _TracksMapFullScreenState extends State<_TracksMapFullScreen> {
  final MapController _mapController = MapController();
  late bool _satelliteView;

  @override
  void initState() {
    super.initState();
    _satelliteView = widget.initialSatellite;
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  Widget _mapButton({
    required IconData icon,
    required Color bgColor,
    required Color fgColor,
    required VoidCallback onTap,
    String? tooltip,
  }) => Tooltip(
    message: tooltip ?? '',
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40, height: 40,
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(8),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 6, offset: const Offset(0, 2))],
        ),
        child: Icon(icon, size: 20, color: fgColor),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final cs           = Theme.of(context).colorScheme;
    final displayed    = widget.displayed;
    final showRawTrack = context.watch<ThemeProvider>().showRawTrack;

    final sel = widget.selectedIndex;
    final fsPolylinesByDay = displayed.asMap().entries.map((e) {
      final isSelected = sel == e.key;
      final color = isSelected ? e.value.color : e.value.color.withValues(alpha: 0.65);
      final width = isSelected ? 5.0 : 3.0;
      final segs = <Polyline>[];
      for (final seg in e.value.display.segments) {
        if (seg.kind == SegmentKind.moving && seg.points.length >= 2) {
          segs.add(Polyline(
            points: seg.points.map((p) => LatLng(p.lat, p.lon)).toList(),
            color: color,
            strokeWidth: width,
          ));
        } else if ((seg.kind == SegmentKind.stopEntry ||
                    seg.kind == SegmentKind.stopExit) &&
                   seg.points.length >= 2) {
          segs.add(Polyline(
            points: seg.points.map((p) => LatLng(p.lat, p.lon)).toList(),
            color: e.value.color.withValues(alpha: isSelected ? 0.40 : 0.26),
            strokeWidth: width * 0.6,
          ));
        }
      }
      return segs;
    }).toList();
    final polylines = <Polyline>[];
    for (int i = 0; i < fsPolylinesByDay.length; i++) {
      if (i != sel) polylines.addAll(fsPolylinesByDay[i]);
    }
    if (sel != null && sel < fsPolylinesByDay.length) {
      polylines.addAll(fsPolylinesByDay[sel]);
    }

    final arrowMarkers = <Marker>[];
    for (final d in displayed) {
      final movPts = d.display.movingPoints().map((p) => LatLng(p.lat, p.lon)).toList();
      if (movPts.length < 2) continue;
      final bearing = _departureBearing(movPts);
      arrowMarkers.add(Marker(
        point: movPts[0], width: 13, height: 13,
        child: Transform.rotate(
          angle: bearing,
          child: Container(
            width: 13, height: 13,
            decoration: BoxDecoration(
              color: d.color.withValues(alpha: 0.9),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 1),
            ),
            alignment: Alignment.center,
            child: const Icon(Icons.arrow_upward, color: Colors.white, size: 7),
          ),
        ),
      ));
    }

    final anchorCircles = <CircleMarker>[];
    for (final d in displayed) {
      for (final stop in d.display.stops) {
        anchorCircles.add(CircleMarker(point: LatLng(stop.lat, stop.lon), radius: stop.r95M, useRadiusInMeter: true, color: d.color.withValues(alpha: 0.07)));
        anchorCircles.add(CircleMarker(point: LatLng(stop.lat, stop.lon), radius: stop.cep50M, useRadiusInMeter: true,
            color: d.color.withValues(alpha: 0.22), borderStrokeWidth: 1.5, borderColor: d.color.withValues(alpha: 0.50)));
      }
    }

    final fsUncertaintyPolygons = [
      for (final d in displayed)
        for (final ring in d.display.uncertaintyBands())
          Polygon(
            points: ring.map((c) => LatLng(c.$1, c.$2)).toList(),
            color: d.color.withValues(alpha: 0.10),
            borderStrokeWidth: 0,
          ),
    ];

    final allPts = displayed
        .expand((d) => d.display.allPoints().map((p) => LatLng(p.lat, p.lon)))
        .toList();

    void refitAll() {
      if (allPts.isEmpty) return;
      double minLat = allPts.first.latitude,  maxLat = allPts.first.latitude;
      double minLng = allPts.first.longitude, maxLng = allPts.first.longitude;
      for (final p in allPts) {
        if (p.latitude  < minLat) minLat = p.latitude;
        if (p.latitude  > maxLat) maxLat = p.latitude;
        if (p.longitude < minLng) minLng = p.longitude;
        if (p.longitude > maxLng) maxLng = p.longitude;
      }
      _mapController.fitCamera(CameraFit.bounds(
        bounds: LatLngBounds(LatLng(minLat, minLng), LatLng(maxLat, maxLng)),
        padding: const EdgeInsets.all(32),
      ));
    }

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: Padding(
          padding: const EdgeInsets.all(8),
          child: _mapButton(
            icon: Icons.fullscreen_exit,
            bgColor: cs.surfaceContainerLowest.withValues(alpha: 0.9),
            fgColor: cs.primary,
            tooltip: context.l10n.close,
            onTap: () => Navigator.pop(context),
          ),
        ),
      ),
      body: Stack(children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCameraFit: widget.initialBounds != null
                ? CameraFit.bounds(bounds: widget.initialBounds!, padding: const EdgeInsets.all(32))
                : null,
          ),
          children: [
            TileLayer(
              urlTemplate: _satelliteView ? kSatelliteUrl : kBaseTileUrl,
              userAgentPackageName: 'com.logbook.app',
              // Keep more of the surrounding tile grid loaded across a
              // pan/zoom transition so fewer tiles need a fresh fetch right
              // when the gesture ends (default is 2).
              keepBuffer: 4,
              // Default is `.none`, which never retries a tile that failed
              // once (transient network blip, tile-server rate limit) — it
              // stays blank until this whole map widget is rebuilt. Evicting
              // once it scrolls out of view lets it be re-fetched next time
              // it's needed.
              evictErrorTileStrategy: EvictErrorTileStrategy.notVisibleRespectMargin,
              errorTileCallback: kDebugMode
                  ? (tile, error, stackTrace) =>
                      debugPrint('[Map] tile ${tile.coordinates} failed to load: $error')
                  : null,
              // Fade-in on arrival is TileLayer's default (tileDisplay:
              // TileDisplay.fadeIn()); this only overrides the tile that
              // failed to load, in place of a blank grey square.
              tileBuilder: (context, tileWidget, tile) => tile.loadError
                  ? Container(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      child: const Icon(Icons.map_outlined, size: 20),
                    )
                  : tileWidget,
            ),
            Builder(builder: (ctx) {
              if (MapCamera.of(ctx).zoom <= 15) return const SizedBox.shrink();
              return PolygonLayer(polygons: fsUncertaintyPolygons);
            }),
            Builder(builder: (ctx) {
              if (anchorCircles.isEmpty || MapCamera.of(ctx).zoom <= 15) return const SizedBox.shrink();
              return CircleLayer(circles: anchorCircles);
            }),
            PolylineLayer(polylines: polylines, cullingMargin: null, simplificationTolerance: 0),
            Builder(builder: (ctx) {
              if (!showRawTrack || MapCamera.of(ctx).zoom <= 15) return const SizedBox.shrink();
              return PolylineLayer(
                polylines: [
                  for (final d in displayed)
                    for (final seg in splitTrackSegments(d.rawPoints))
                      if (seg.length >= 2)
                        Polyline(
                          points: seg.map((p) => LatLng(p.lat, p.lon)).toList(),
                          strokeWidth: 1.0,
                          color: d.color.withValues(alpha: 0.20),
                        ),
                ],
                cullingMargin: null,
                simplificationTolerance: 0,
              );
            }),
            MarkerLayer(markers: arrowMarkers),
            RichAttributionWidget(attributions: [
              // MapTiler version (temporarily disabled, see map_config.dart):
              // TextSourceAttribution(kBaseAttributionLabel, onTap: () async {
              //   final uri = Uri.parse(kBaseAttributionUrl);
              //   if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
              // }),
              // if (!_satelliteView)
              //   TextSourceAttribution(kOsmAttributionLabel, onTap: () async {
              //     final uri = Uri.parse(kOsmAttributionUrl);
              //     if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
              //   }),
              if (_satelliteView)
                TextSourceAttribution(kSatelliteAttributionLabel, onTap: () async {
                  final uri = Uri.parse(kSatelliteAttributionUrl);
                  if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
                })
              else
                TextSourceAttribution(kBaseAttributionLabel, onTap: () async {
                  final uri = Uri.parse(kBaseAttributionUrl);
                  if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
                }),
            ]),
          ],
        ),
        Positioned(
          right: 16, bottom: 16,
          child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            if (defaultTargetPlatform == TargetPlatform.macOS) ...[
              _mapButton(icon: Icons.add,    bgColor: cs.surfaceContainerLowest, fgColor: cs.primary, tooltip: context.l10n.tracksZoomIn,
                  onTap: () => _mapController.move(_mapController.camera.center, _mapController.camera.zoom + 1)),
              const SizedBox(height: 8),
              _mapButton(icon: Icons.remove, bgColor: cs.surfaceContainerLowest, fgColor: cs.primary, tooltip: context.l10n.tracksZoomOut,
                  onTap: () => _mapController.move(_mapController.camera.center, _mapController.camera.zoom - 1)),
              const SizedBox(height: 8),
              _mapButton(icon: Icons.explore, bgColor: cs.primary, fgColor: cs.onPrimary, tooltip: context.l10n.tracksShowAll,
                  onTap: refitAll),
              const SizedBox(height: 8),
            ],
            _mapButton(
              icon: _satelliteView ? Icons.map_outlined : Icons.satellite_alt,
              bgColor: cs.surfaceContainerLowest, fgColor: cs.primary,
              tooltip: _satelliteView ? context.l10n.tracksMapView : context.l10n.tracksSatelliteView,
              onTap: () => setState(() => _satelliteView = !_satelliteView),
            ),
          ]),
        ),
      ]),
    );
  }
}
