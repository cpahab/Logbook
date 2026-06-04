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

import '../../home/data/home_repository.dart';
import '../../home/domain/day_entry.dart';
import '../../home/utils/compute_daily_stats.dart';
import '../../home/utils/trim_track.dart';
import '../../home/widgets/nav_bar.dart';

enum _FilterPreset { year1, months6, months3, custom }

class TracksScreen extends StatefulWidget {
  const TracksScreen({super.key});

  @override
  State<TracksScreen> createState() => _TracksScreenState();
}

class _TracksScreenState extends State<TracksScreen> {
  final MapController _mapController = MapController();
  int? _selectedIndex;
  _FilterPreset _preset = _FilterPreset.months3;
  DateTimeRange? _customRange;
  bool _satelliteView = false;

  // Golden-angle hue palette: each sequential track steps ~137.5° around the
  // hue wheel, guaranteeing maximum perceptual separation between adjacent days.
  static Color _colorForIndex(int index, int _) {
    const goldenAngle = 137.508; // 360° / φ²
    const startHue = 200.0;     // begin at nautical blue
    final hue = (startHue + index * goldenAngle) % 360;
    return HSLColor.fromAHSL(1.0, hue, 0.75, 0.48).toColor();
  }

  // Bearing (radians, clockwise from north) between two LatLng points.
  static double _trackBearing(LatLng from, LatLng to) {
    final lat1 = from.latitude * pi / 180;
    final lat2 = to.latitude * pi / 180;
    final dLon = (to.longitude - from.longitude) * pi / 180;
    final y = sin(dLon) * cos(lat2);
    final x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon);
    return atan2(y, x);
  }

  DateTimeRange? get _effectiveRange {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    switch (_preset) {
      case _FilterPreset.year1:
        return DateTimeRange(
            start: DateTime(now.year - 1, now.month, now.day), end: today);
      case _FilterPreset.months6:
        return DateTimeRange(
            start: DateTime(now.year, now.month - 6, now.day), end: today);
      case _FilterPreset.months3:
        return DateTimeRange(
            start: DateTime(now.year, now.month - 3, now.day), end: today);
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
    if (pts.isEmpty) return null;
    double minLat = pts.first.latitude, maxLat = pts.first.latitude;
    double minLng = pts.first.longitude, maxLng = pts.first.longitude;
    for (final p in pts) {
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
    final repo = context.read<HomeRepository>();
    final range = _effectiveRange;
    final pts = repo.dailyTracks.entries
        .where((e) =>
            range == null ||
            (!e.key.isBefore(range.start) && !e.key.isAfter(range.end)))
        .expand((e) {
          final trimmed = trimStationaryEnds(e.value.points);
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
            start: DateTime(now.year, now.month - 6, now.day), end: now);
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: now,
      initialDateRange: initial,
      locale: const Locale('de', 'CH'),
    );
    if (range != null) _applyPreset(_FilterPreset.custom, custom: range);
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<HomeRepository>();
    final cs = Theme.of(context).colorScheme;

    final trackedDays = repo.dailyTracks.keys.toList()..sort();
    final totalTracks =
        trackedDays.where((d) => repo.dailyTracks[d]!.points.isNotEmpty).length;

    final List<_DayTrackData> trackData = [];
    int trackIdx = 0;
    for (final day in trackedDays) {
      final track = repo.dailyTracks[day]!;
      if (track.points.isEmpty) continue;
      final trimmed = trimStationaryEnds(track.points);
      final pts = trimmed.map((p) => LatLng(p.lat, p.lon)).toList();
      trackData.add(_DayTrackData(
        day: day,
        points: pts,
        color: _colorForIndex(trackIdx, totalTracks),
        entry: repo.getEntry(day),
        stats: computeDailyStats(trimmed),
        startTime: trimmed.first.time.toLocal(),
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

    // Polylines: selected drawn last (on top)
    final polylines = displayed.asMap().entries.map((e) {
      final isSelected = _selectedIndex == e.key;
      return Polyline(
        points: e.value.points,
        color: isSelected
            ? e.value.color
            : e.value.color.withValues(alpha: 0.65),
        strokeWidth: isSelected ? 5 : 3,
      );
    }).toList();
    if (_selectedIndex != null && _selectedIndex! < polylines.length) {
      polylines.add(polylines.removeAt(_selectedIndex!));
    }

    // Departure arrows at the start of each displayed track
    final arrowMarkers = <Marker>[];
    for (final d in displayed) {
      if (d.points.length < 2) continue;
      final bearing = _trackBearing(d.points[0], d.points[1]);
      arrowMarkers.add(Marker(
        point: d.points[0],
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

    final initialBounds =
        _boundsFor(displayed.expand((d) => d.points).toList());

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: cs.surface,
        foregroundColor: cs.primary,
        elevation: 0,
        scrolledUnderElevation: 1,
        shadowColor: Colors.black12,
        centerTitle: true,
        automaticallyImplyLeading: false,
        leading: IconButton(
          icon: const Icon(Icons.anchor),
          tooltip: 'Journal',
          onPressed: () => context.go('/'),
        ),
        title: Text(
          'Karte',
          style: GoogleFonts.newsreader(
            fontSize: 24,
            fontWeight: FontWeight.w500,
            letterSpacing: -0.24,
            color: cs.primary,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.account_circle_outlined),
            tooltip: 'Einstellungen',
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      bottomNavigationBar: AppBottomNav(
        active: NavTab.map,
        showFab: false,
        onSelect: (tab) {
          if (tab == NavTab.journal) context.go('/');
          if (tab == NavTab.settings) context.push('/settings');
          if (tab == NavTab.safety) context.push('/emergency');
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
                      displayed, initialBounds, polylines, arrowMarkers, cs),
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
    final fmt = DateFormat('dd.MM.yy');
    final customLabel =
        (_preset == _FilterPreset.custom && _customRange != null)
            ? '${fmt.format(_customRange!.start)} – ${fmt.format(_customRange!.end)}'
            : 'EIGENE';

    return Container(
      color: cs.surface,
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _chip('JAHR', _FilterPreset.year1, cs),
            const SizedBox(width: 8),
            _chip('6 MON', _FilterPreset.months6, cs),
            const SizedBox(width: 8),
            _chip('3 MON', _FilterPreset.months3, cs),
            const SizedBox(width: 8),
            _chip(customLabel, _FilterPreset.custom, cs,
                isCustom: true),
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? cs.primary : cs.surfaceContainer,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.5,
            color: isActive ? cs.onPrimary : cs.outline,
          ),
        ),
      ),
    );
  }

  // ── Map section ────────────────────────────────────────────────────
  Widget _buildMapSection(
    List<_DayTrackData> displayed,
    LatLngBounds? initialBounds,
    List<Polyline> polylines,
    List<Marker> arrowMarkers,
    ColorScheme cs,
  ) {
    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: initialBounds != null
              ? MapOptions(
                  initialCameraFit: CameraFit.bounds(
                    bounds: initialBounds,
                    padding: const EdgeInsets.all(24),
                  ),
                )
              : const MapOptions(
                  initialCenter: LatLng(47.0, 8.3),
                  initialZoom: 8,
                ),
          children: [
            TileLayer(
              urlTemplate: _satelliteView
                  ? 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}'
                  : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.logbook.app',
              tileProvider: NetworkTileProvider(),
            ),
            PolylineLayer(polylines: polylines),
            MarkerLayer(markers: arrowMarkers),
            RichAttributionWidget(
              attributions: [
                if (_satelliteView)
                  TextSourceAttribution('© Esri World Imagery',
                      onTap: () async {
                    final uri = Uri.parse('https://www.esri.com');
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(uri,
                          mode: LaunchMode.externalApplication);
                    }
                  })
                else
                  TextSourceAttribution('© OpenStreetMap contributors',
                      onTap: () async {
                    final uri = Uri.parse(
                        'https://www.openstreetmap.org/copyright');
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(uri,
                          mode: LaunchMode.externalApplication);
                    }
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
                  onTap: () => _mapController.move(
                    _mapController.camera.center,
                    _mapController.camera.zoom - 1,
                  ),
                ),
                const SizedBox(height: 8),
                _mapButton(
                  icon: Icons.explore,
                  bgColor: cs.primary,
                  fgColor: const Color(0xFFFFE088),
                  onTap: () {
                    setState(() => _selectedIndex = null);
                    _refitToDisplayed();
                  },
                ),
                const SizedBox(height: 8),
              ],
              _mapButton(
                icon: _satelliteView ? Icons.map_outlined : Icons.satellite_alt,
                bgColor: cs.surfaceContainerLowest,
                fgColor: cs.primary,
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
  }) {
    return GestureDetector(
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
    );
  }

  // ── List section ──────────────────────────────────────────────────
  Widget _buildListSection(List<_DayTrackData> displayed, ColorScheme cs) {
    final totalNm =
        displayed.fold<double>(0, (s, d) => s + (d.stats?.distanceNm ?? 0));

    return Column(
      children: [
        // Stats summary
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
          child: Row(
            children: [
              Expanded(child: _statSummaryBox('${displayed.length}', 'ETAPPEN', cs)),
              const SizedBox(width: 10),
              Expanded(
                child: _statSummaryBox(
                  totalNm.toStringAsFixed(1), 'NM GESAMT', cs),
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

  Widget _statSummaryBox(String value, String label, ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: GoogleFonts.newsreader(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: cs.primary,
              height: 1.1,
            ),
          ),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.5,
              color: cs.outline,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildListItem(
      int index, _DayTrackData d, int total, ColorScheme cs) {
    const cardHeight = 110.0;

    final isSelected = _selectedIndex == index;
    final timeLabel = d.startTime != null
        ? DateFormat('HH:mm').format(d.startTime!)
        : DateFormat('d. MMM', 'de_CH').format(d.day);
    final dateLabel = DateFormat('d. MMM yyyy', 'de_CH').format(d.day);
    final fromHarbor = d.entry?.fromHarbor;
    final toHarbor = d.entry?.toHarbor;
    final routeTitle = (fromHarbor?.isNotEmpty ?? false) ||
            (toHarbor?.isNotEmpty ?? false)
        ? [
            if (fromHarbor?.isNotEmpty ?? false) fromHarbor!,
            if (toHarbor?.isNotEmpty ?? false) toHarbor!,
          ].join(' → ')
        : DateFormat('EEEE', 'de_CH').format(d.day);

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
                _focusTrack(d.points);
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
                        padding: const EdgeInsets.all(10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Time + date
                            Row(
                              children: [
                                Text(
                                  timeLabel,
                                  style: GoogleFonts.inter(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 1.5,
                                    color: cs.secondary,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    dateLabel.toUpperCase(),
                                    style: GoogleFonts.inter(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.5,
                                      color: cs.outline,
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
                              style: GoogleFonts.inter(
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
                                style: GoogleFonts.newsreader(
                                  fontSize: 13,
                                  fontStyle: FontStyle.italic,
                                  color: cs.onSurfaceVariant,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                            // Chips
                            if (wind != null ||
                                (d.stats?.avgSpeed ?? 0) > 0) ...[
                              const SizedBox(height: 4),
                              Wrap(
                                spacing: 6,
                                children: [
                                  if (wind != null)
                                    _miniChip(Icons.air, wind, cs),
                                  if ((d.stats?.avgSpeed ?? 0) > 0)
                                    _miniChip(
                                      Icons.speed,
                                      '${d.stats!.avgSpeed.toStringAsFixed(1)} kn',
                                      cs,
                                    ),
                                  if (d.stats != null &&
                                      d.stats!.distanceNm > 0)
                                    _miniChip(
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

  Widget _miniChip(IconData icon, String label, ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: cs.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(
            label.toUpperCase(),
            style: GoogleFonts.inter(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
              color: cs.primary,
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
          Text('Keine Tracks vorhanden',
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
            'Keine Tracks im gewählten Zeitraum',
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
  final List<LatLng> points;
  final Color color;
  final DayEntry? entry;
  final DailyStats? stats;
  final DateTime? startTime;

  const _DayTrackData({
    required this.day,
    required this.points,
    required this.color,
    required this.entry,
    required this.stats,
    required this.startTime,
  });
}
