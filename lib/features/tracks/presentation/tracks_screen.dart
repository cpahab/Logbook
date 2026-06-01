import 'dart:math';
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
import '../../home/widgets/nav_bar.dart';
import '../../settings/domain/theme_provider.dart';

enum _FilterPreset { all, months3, months6, year1, custom }

class TracksScreen extends StatefulWidget {
  const TracksScreen({super.key});

  @override
  State<TracksScreen> createState() => _TracksScreenState();
}

class _TracksScreenState extends State<TracksScreen> {
  final MapController _mapController = MapController();
  int? _selectedIndex; // index into displayed list
  _FilterPreset _preset = _FilterPreset.all;
  DateTimeRange? _customRange;
  bool _satelliteView = false;

  // Blue (oldest) → purple (mid) → red (newest) — avoids the muddy grey of
  // a direct RGB lerp between blue and red.
  static Color _colorForIndex(int index, int total) {
    if (total <= 1) return const Color(0xFF1565C0);
    final t = index / (total - 1);
    if (t <= 0.5) {
      return Color.lerp(
        const Color(0xFF1565C0), // deep blue
        const Color(0xFF7B1FA2), // deep purple
        t * 2,
      )!;
    }
    return Color.lerp(
      const Color(0xFF7B1FA2), // deep purple
      const Color(0xFFC62828), // deep red
      (t - 0.5) * 2,
    )!;
  }

  DateTimeRange? get _effectiveRange {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    switch (_preset) {
      case _FilterPreset.all:
        return null;
      case _FilterPreset.months3:
        return DateTimeRange(
            start: DateTime(now.year, now.month - 3, now.day), end: today);
      case _FilterPreset.months6:
        return DateTimeRange(
            start: DateTime(now.year, now.month - 6, now.day), end: today);
      case _FilterPreset.year1:
        return DateTimeRange(
            start: DateTime(now.year - 1, now.month, now.day), end: today);
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
        .expand((e) => e.value.points.map((p) => LatLng(p.lat, p.lon)))
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
    if (range != null) {
      _applyPreset(_FilterPreset.custom, custom: range);
    }
  }

  Future<void> _openWeather(BuildContext context) async {
    final url = context.read<ThemeProvider>().weatherUrl;
    if (url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<HomeRepository>();
    final cs = Theme.of(context).colorScheme;

    // Build full track list sorted by date. Colors are assigned from the
    // full list so they remain stable when the date filter changes.
    final trackedDays = repo.dailyTracks.keys.toList()..sort();
    final totalTracks = trackedDays
        .where((d) => repo.dailyTracks[d]!.points.isNotEmpty)
        .length;

    final List<_DayTrackData> trackData = [];
    int trackIdx = 0;
    for (final day in trackedDays) {
      final track = repo.dailyTracks[day]!;
      final pts = track.points.map((p) => LatLng(p.lat, p.lon)).toList();
      if (pts.isEmpty) continue;
      trackData.add(_DayTrackData(
        day: day,
        points: pts,
        color: _colorForIndex(trackIdx, totalTracks),
        entry: repo.getEntry(day),
        stats: computeDailyStats(track.points),
      ));
      trackIdx++;
    }

    // Apply date filter for list and polylines
    final range = _effectiveRange;
    final displayed = range == null
        ? trackData
        : trackData
            .where((d) =>
                !d.day.isBefore(range.start) && !d.day.isAfter(range.end))
            .toList();

    // Polylines for displayed tracks; selected drawn last (on top)
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

    // Initial camera fit over all tracks (before any filter is applied)
    final initialBounds = _boundsFor(trackData.expand((d) => d.points).toList());

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A3A5C),
        foregroundColor: Colors.white,
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.map, color: cs.tertiaryFixed, size: 20),
            const SizedBox(width: 8),
            Text(
              'TRACKS',
              style: GoogleFonts.newsreader(
                color: cs.tertiaryFixed,
                fontSize: 18,
                fontWeight: FontWeight.w700,
                letterSpacing: 3,
              ),
            ),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(0.5),
          child: Container(height: 0.5, color: const Color(0xFF2A5080)),
        ),
      ),
      bottomNavigationBar: AppBottomNav(
        active: NavTab.maps,
        onSelect: (tab) {
          if (tab == NavTab.logbook) context.go('/');
          if (tab == NavTab.weather) _openWeather(context);
          if (tab == NavTab.settings) context.push('/settings');
        },
      ),
      body: trackData.isEmpty
          ? _buildEmpty(cs)
          : Column(
              children: [
                // ── Map with overlay fit button ────────────────────────
                Expanded(
                  flex: 3,
                  child: Stack(
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
                          RichAttributionWidget(
                            attributions: [
                              if (_satelliteView)
                                TextSourceAttribution(
                                  '© Esri World Imagery',
                                  onTap: () async {
                                    final uri = Uri.parse('https://www.esri.com');
                                    if (await canLaunchUrl(uri)) {
                                      await launchUrl(uri,
                                          mode: LaunchMode.externalApplication);
                                    }
                                  },
                                )
                              else
                                TextSourceAttribution(
                                  '© OpenStreetMap contributors',
                                  onTap: () async {
                                    final uri = Uri.parse(
                                        'https://www.openstreetmap.org/copyright');
                                    if (await canLaunchUrl(uri)) {
                                      await launchUrl(uri,
                                          mode: LaunchMode.externalApplication);
                                    }
                                  },
                                ),
                            ],
                          ),
                        ],
                      ),
                      // Map overlay buttons (fit + satellite toggle)
                      Positioned(
                        right: 12,
                        bottom: 12,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            FloatingActionButton.small(
                              heroTag: 'tracks_fit_button',
                              onPressed: () {
                                setState(() => _selectedIndex = null);
                                _refitToDisplayed();
                              },
                              tooltip: 'Angezeigte Tracks einpassen',
                              child: const Icon(Icons.fit_screen_outlined),
                            ),
                            const SizedBox(height: 8),
                            FloatingActionButton.small(
                              heroTag: 'tracks_satellite_button',
                              onPressed: () =>
                                  setState(() => _satelliteView = !_satelliteView),
                              tooltip: _satelliteView
                                  ? 'Kartenansicht'
                                  : 'Satellitenansicht',
                              child: Icon(_satelliteView
                                  ? Icons.map_outlined
                                  : Icons.satellite_alt),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                // ── Filter strip ──────────────────────────────────────
                _buildFilterStrip(cs, displayed),
                // ── List ─────────────────────────────────────────────
                Expanded(
                  flex: 2,
                  child: displayed.isEmpty
                      ? _buildEmptyFilter(cs)
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          itemCount: displayed.length,
                          itemBuilder: (ctx, index) {
                            // Newest first
                            final i = displayed.length - 1 - index;
                            return _buildListItem(ctx, i, displayed[i], cs);
                          },
                        ),
                ),
              ],
            ),
    );
  }

  // ── Filter strip ───────────────────────────────────────────────────────
  Widget _buildFilterStrip(ColorScheme cs, List<_DayTrackData> displayed) {
    final fmt = DateFormat('dd.MM.yy');
    final customLabel =
        (_preset == _FilterPreset.custom && _customRange != null)
            ? '${fmt.format(_customRange!.start)} – ${fmt.format(_customRange!.end)}'
            : null;
    final totalNm =
        displayed.fold<double>(0, (s, d) => s + (d.stats?.distanceNm ?? 0));

    return Container(
      color: cs.surfaceContainerLow,
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _chip('Alle', _FilterPreset.all, cs),
                      const SizedBox(width: 6),
                      _chip('3 Mon.', _FilterPreset.months3, cs),
                      const SizedBox(width: 6),
                      _chip('6 Mon.', _FilterPreset.months6, cs),
                      const SizedBox(width: 6),
                      _chip('1 Jahr', _FilterPreset.year1, cs),
                      if (customLabel != null) ...[
                        const SizedBox(width: 6),
                        _chip(customLabel, _FilterPreset.custom, cs),
                      ],
                    ],
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.calendar_month_outlined),
                iconSize: 20,
                tooltip: 'Zeitraum wählen',
                style: IconButton.styleFrom(
                  foregroundColor: _preset == _FilterPreset.custom
                      ? cs.primary
                      : cs.onSurfaceVariant,
                ),
                onPressed: _pickDateRange,
              ),
            ],
          ),
          if (displayed.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              '${displayed.length} Track${displayed.length == 1 ? '' : 's'} · ${totalNm.toStringAsFixed(1)} nm gesamt',
              style: GoogleFonts.inter(
                fontSize: 12,
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _chip(String label, _FilterPreset preset, ColorScheme cs) {
    final isActive = _preset == preset;
    return GestureDetector(
      onTap: () => _applyPreset(preset),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? cs.primary : cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
            color: isActive ? cs.onPrimary : cs.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  // ── List item ──────────────────────────────────────────────────────────
  Widget _buildListItem(
      BuildContext context, int index, _DayTrackData d, ColorScheme cs) {
    final isSelected = _selectedIndex == index;
    final dayDateLabel =
        DateFormat('EEEE, d. MMMM yyyy', 'de_CH').format(d.day);
    final fromHarbor = d.entry?.fromHarbor;
    final toHarbor = d.entry?.toHarbor;
    final hasRoute =
        (fromHarbor?.isNotEmpty ?? false) || (toHarbor?.isNotEmpty ?? false);
    final routeLabel = [
      if (fromHarbor?.isNotEmpty ?? false) fromHarbor!,
      if (toHarbor?.isNotEmpty ?? false) toHarbor!,
    ].join(' → ');

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          color: isSelected
              ? d.color.withValues(alpha: 0.08)
              : cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected
                ? d.color
                : cs.outlineVariant.withValues(alpha: 0.4),
            width: isSelected ? 1.5 : 0.5,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () {
              setState(() => _selectedIndex = index);
              _focusTrack(d.points);
            },
            child: Row(
              children: [
                // Colored left bar matching the map polyline
                Container(
                  width: 5,
                  height: 60,
                  decoration: BoxDecoration(
                    color: d.color,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(9),
                      bottomLeft: Radius.circular(9),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Day info
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          dayDateLabel,
                          style: GoogleFonts.newsreader(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: cs.onSurface,
                          ),
                        ),
                        if (hasRoute) ...[
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Icon(Icons.route,
                                  size: 13, color: cs.onSurfaceVariant),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  routeLabel,
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    color: cs.onSurfaceVariant,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                // Distance badge in the track's colour
                if (d.stats != null && d.stats!.distanceNm > 0)
                  Padding(
                    padding: const EdgeInsets.only(right: 14),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          d.stats!.distanceNm.toStringAsFixed(1),
                          style: GoogleFonts.inter(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: d.color,
                          ),
                        ),
                        Text(
                          'nm',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
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

  const _DayTrackData({
    required this.day,
    required this.points,
    required this.color,
    required this.entry,
    required this.stats,
  });
}
