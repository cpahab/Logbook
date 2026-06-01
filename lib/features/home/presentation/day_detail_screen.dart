import 'dart:io';
import 'dart:math' show Point;
import 'dart:ui' show ImageFilter;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/home_repository.dart';
import '../domain/day_entry.dart';
import '../domain/daily_track.dart';
import '../domain/timeline_entry.dart';
import '../domain/track_point.dart';
import '../widgets/add_timeline_entry_dialog.dart';
import '../widgets/nav_bar.dart';
import '../utils/compute_daily_stats.dart';
import '../../settings/domain/theme_provider.dart';
import '../utils/gpx_parser.dart';
import '../utils/track_correlation.dart';

class _StatsItem {
  final String label;
  final String value;
  final IconData icon;

  const _StatsItem(
      {required this.label, required this.value, required this.icon});
}

class DayDetailScreen extends StatefulWidget {
  final int year;
  final int month;
  final int day;

  const DayDetailScreen({
    super.key,
    required this.year,
    required this.month,
    required this.day,
  });

  @override
  State<DayDetailScreen> createState() => _DayDetailScreenState();
}

class _DayDetailScreenState extends State<DayDetailScreen> {
  final MapController _mapController = MapController();
  TextEditingController? _notesController;
  TextEditingController? _fromHarborController;
  TextEditingController? _toHarborController;
  LatLng? _droppedMarkerLatLng;
  bool _satelliteView = false;
  bool _isMarkerSheetOpen = false;

  static const _controlledItems = [
    'Motoröl geprüft',
    'Benzin geprüft',
    'Sicherheitsausrüstung kontrolliert',
  ];

  @override
  void dispose() {
    _notesController?.dispose();
    _fromHarborController?.dispose();
    _toHarborController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<HomeRepository>();

    final day = DateTime(widget.year, widget.month, widget.day);
    final entry = repo.getEntry(day);
    final track = repo.dailyTracks[day];

    DailyStats? stats;
    if (track != null && track.points.isNotEmpty) {
      stats = computeDailyStats(track.points);
    }

    final entries = repo.entries; // sorted ascending by date
    final currentIndex = entries.indexWhere(
      (e) => e.date.year == widget.year &&
             e.date.month == widget.month &&
             e.date.day == widget.day,
    );
    final prevEntry = currentIndex > 0 ? entries[currentIndex - 1] : null;
    final nextEntry = currentIndex >= 0 && currentIndex < entries.length - 1
        ? entries[currentIndex + 1]
        : null;

    void goToDay(DateTime d) =>
        context.pushReplacement('/day/${d.year}/${d.month}/${d.day}');

    final cs = Theme.of(context).colorScheme;
    final dayTitle = DateFormat('EEEE', 'de_CH').format(day);
    final dateSubtitle =
        DateFormat('d. MMM yyyy', 'de_CH').format(day).toUpperCase();

    return Scaffold(
      backgroundColor: cs.surface,
      // ── Light glass AppBar ──────────────────────────────────────
      extendBodyBehindAppBar: false,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(64),
        child: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: Container(
              decoration: BoxDecoration(
                color: cs.surface.withValues(alpha: 0.88),
                border: Border(
                    bottom: BorderSide(
                        color: cs.outlineVariant, width: 0.5)),
              ),
              child: SafeArea(
                bottom: false,
                child: SizedBox(
                  height: 56,
                  child: Row(
                    children: [
                      const SizedBox(width: 8),
                      // Title + date
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              dayTitle,
                              style: GoogleFonts.newsreader(
                                fontSize: 22,
                                fontWeight: FontWeight.w500,
                                color: cs.primary,
                                height: 1.1,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              dateSubtitle,
                              style: GoogleFonts.inter(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.5,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Prev / next
                      IconButton(
                        icon: const Icon(Icons.chevron_left),
                        color: cs.primary,
                        onPressed: prevEntry != null
                            ? () => goToDay(prevEntry.date)
                            : null,
                      ),
                      IconButton(
                        icon: const Icon(Icons.chevron_right),
                        color: cs.primary,
                        onPressed: nextEntry != null
                            ? () => goToDay(nextEntry.date)
                            : null,
                      ),
                      // Options menu
                      PopupMenuButton<String>(
                        tooltip: 'Optionen',
                        icon: Icon(Icons.more_vert, color: cs.primary),
                        onSelected: (value) {
                          if (value == 'import_gpx') _importGpx();
                          if (value == 'delete_gpx') _removeGpx();
                          if (value == 'delete_day') _deleteDay();
                        },
                        itemBuilder: (context) => [
                          PopupMenuItem<String>(
                            value: 'import_gpx',
                            child: Row(children: [
                              _gpxUploadIcon(),
                              const SizedBox(width: 12),
                              const Text('GPX importieren'),
                            ]),
                          ),
                          if (track != null)
                            PopupMenuItem<String>(
                              value: 'delete_gpx',
                              child: Row(children: [
                                Icon(Icons.delete_outline,
                                    color: cs.error),
                                const SizedBox(width: 12),
                                Text('GPX löschen',
                                    style: TextStyle(color: cs.error)),
                              ]),
                            ),
                          const PopupMenuDivider(),
                          PopupMenuItem<String>(
                            value: 'delete_day',
                            child: Row(children: [
                              Icon(Icons.delete_forever_outlined,
                                  color: cs.error),
                              const SizedBox(width: 12),
                              Text('Tag löschen',
                                  style: TextStyle(color: cs.error)),
                            ]),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      // ── Bottom nav with raised compass ──────────────────────────
      bottomNavigationBar: AppBottomNav(
        active: NavTab.logbook,
        onSelect: (tab) {
          if (tab == NavTab.logbook) context.go('/');
          if (tab == NavTab.weather) _openWeatherUrl(context);
          if (tab == NavTab.settings) context.push('/settings');
        },
      ),
      body: entry == null
          ? const Center(child: Text('Kein Eintrag für diesen Tag'))
          : _buildContent(entry, track, repo, stats),
    );
  }

  Widget _buildContent(
      DayEntry entry, DailyTrack? track, HomeRepository repo, DailyStats? stats) {
    _notesController ??= TextEditingController(text: entry.notes ?? '');
    _fromHarborController ??= TextEditingController(text: entry.fromHarbor ?? '');
    _toHarborController ??= TextEditingController(text: entry.toHarbor ?? '');

    final correlatedMap = track != null
        ? Map<TimelineEntry, TrackPoint>.fromEntries(
            correlateTimelineWithTrack(entry.timeline, track.points)
                .map((pair) => MapEntry(pair.$1, pair.$2)),
          )
        : <TimelineEntry, TrackPoint>{};

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 700;

        if (isWide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(
                        child: _buildMapSection(entry, track, stats)),
                  ],
                ),
              ),
              const VerticalDivider(width: 1, thickness: 1),
              Expanded(
                child: _buildLogbookColumn(entry, correlatedMap),
              ),
            ],
          );
        }

        return CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
                child: _buildMapSection(entry, track, stats)),
            SliverToBoxAdapter(child: _buildAdditionalInfoCard(entry)),
            ..._timelineSlivers(entry, correlatedMap),
          ],
        );
      },
    );
  }

  // ------------------------------------------------------------
  // MAP + STATS PILL + STATS GRID (combined section)
  // ------------------------------------------------------------
  Widget _buildMapSection(DayEntry entry, DailyTrack? track, DailyStats? stats) {
    final hasTrack = track != null && track.points.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Map
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 400),
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: CurvedAnimation(
                  parent: animation, curve: Curves.easeOut),
              child: child,
            ),
            child: KeyedSubtree(
              key: ValueKey<bool>(hasTrack),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: _buildMap(entry, track),
              ),
            ),
          ),
          // Stats grid directly below map
          if (hasTrack && stats != null) ...[
            const SizedBox(height: 16),
            _buildStatisticsCard(stats),
          ],
        ],
      ),
    );
  }

  Widget _buildLogbookColumn(
      DayEntry entry, Map<TimelineEntry, TrackPoint> correlatedMap) {
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: _buildAdditionalInfoCard(entry)),
        ..._timelineSlivers(entry, correlatedMap),
      ],
    );
  }

  List<Widget> _timelineSlivers(
      DayEntry entry, Map<TimelineEntry, TrackPoint> correlatedMap) {
    if (entry.timeline.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.list_alt_outlined,
                    size: 40,
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
                const SizedBox(height: 8),
                Text('Noch keine Einträge',
                    style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 16),
                TextButton.icon(
                  onPressed: () => _addTimelineEntry(context),
                  icon: Icon(Icons.add_circle_outline,
                      size: 16,
                      color: Theme.of(context).colorScheme.tertiary),
                  label: Text(
                    'EINTRAG',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                      color: Theme.of(context).colorScheme.tertiary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ];
    }
    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Logbucheinträge',
                style: GoogleFonts.newsreader(
                  fontSize: 28,
                  fontWeight: FontWeight.w500,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              TextButton.icon(
                onPressed: () => _addTimelineEntry(context),
                icon: Icon(Icons.add_circle_outline,
                    size: 16,
                    color: Theme.of(context).colorScheme.tertiary),
                label: Text(
                  'EINTRAG',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                    color: Theme.of(context).colorScheme.tertiary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
          child: Column(
            children: entry.timeline.asMap().entries.map((e) {
              return _buildTimelineItem(
                entry,
                e.value,
                correlatedMap[e.value],
                e.key,
                entry.timeline.length,
              );
            }).toList(),
          ),
        ),
      ),
    ];
  }

  Widget _buildStatisticsCard(DailyStats stats) {
    final cs = Theme.of(context).colorScheme;
    final items = <_StatsItem>[
      _StatsItem(
          icon: Icons.straighten,
          label: 'DISTANZ',
          value: '${stats.distanceNm.toStringAsFixed(2)} nm'),
      _StatsItem(
          icon: Icons.schedule,
          label: 'FAHRZEIT',
          value: _formatDuration(stats.movingDuration)),
      _StatsItem(
          icon: Icons.speed,
          label: 'Ø GESCHW.',
          value: '${stats.avgSpeed.toStringAsFixed(1)} kn'),
      _StatsItem(
          icon: Icons.bolt,
          label: 'MAX. GESCHW.',
          value: '${stats.maxSpeed.toStringAsFixed(1)} kn'),
      if (stats.elevationGainMeters != null && stats.elevationGainMeters! > 0)
        _StatsItem(
            icon: Icons.trending_up,
            label: 'HÖHENGEWINN',
            value: '${stats.elevationGainMeters!.toStringAsFixed(0)} m'),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: LayoutBuilder(
        builder: (context, constraints) {
          const spacing = 8.0;
          final tileW = (constraints.maxWidth - spacing) / 2;
          return Wrap(
            spacing: spacing,
            runSpacing: spacing,
            children: items.map((item) {
              return SizedBox(
                width: tileW,
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: cs.outlineVariant.withValues(alpha: 0.6)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.03),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: cs.surfaceContainerLow,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(item.icon,
                                size: 16, color: cs.tertiary),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              item.label,
                              style: GoogleFonts.inter(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.5,
                                color: cs.onSurfaceVariant,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        item.value,
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(color: cs.primary),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          );
        },
      ),
    );
  }

  Widget _gpxUploadIcon() {
    return SizedBox(
      width: 26,
      height: 26,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          const Icon(Icons.file_upload_outlined, size: 22),
          Positioned(
            bottom: -3,
            right: -6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(
                'GPX',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onPrimary,
                  fontSize: 7,
                  fontWeight: FontWeight.bold,
                  height: 1,
                  letterSpacing: 0,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }


  // ------------------------------------------------------------
  // MAP HELPERS
  // ------------------------------------------------------------
  TrackPoint? _findNearestTrackPoint(LatLng latLng, List<TrackPoint> points) {
    if (points.isEmpty) return null;
    TrackPoint? nearest;
    double minDistSq = double.infinity;
    for (final p in points) {
      final dlat = p.lat - latLng.latitude;
      final dlng = p.lon - latLng.longitude;
      final distSq = dlat * dlat + dlng * dlng;
      if (distSq < minDistSq) {
        minDistSq = distSq;
        nearest = p;
      }
    }
    return nearest;
  }

  void _showTrackPointBottomSheet(TrackPoint point) {
    setState(() => _isMarkerSheetOpen = true);
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              DateFormat('HH:mm').format(point.time.toLocal()),
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              DateFormat('dd. MMMM yyyy', 'de_CH').format(point.time.toLocal()),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    ).whenComplete(() => setState(() => _isMarkerSheetOpen = false));
  }

  // ------------------------------------------------------------
  Widget _buildMap(DayEntry entry, DailyTrack? track) {
    if (track == null || track.points.isEmpty) {
      return Card(
        elevation: 2,
        margin: const EdgeInsets.only(top: 12),
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _importGpx,
          child: SizedBox(
            height: 340,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.file_upload_outlined,
                    size: 40,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Kein GPX-Track für diesen Tag',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Tippen zum Importieren',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                        ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final polylinePoints = track.points.map((p) => LatLng(p.lat, p.lon)).toList();
    final correlated = correlateTimelineWithTrack(entry.timeline, track.points);

    final startPoint = track.points.first;
    final endPoint = track.points.last;

    final timelineMarkers = correlated.map((pair) {
      final t = pair.$1;
      final p = pair.$2;

      return Marker(
        point: LatLng(p.lat, p.lon),
        width: 28,
        height: 28,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _showEntryDetail(t),
          onLongPress: () {
            setState(() => _droppedMarkerLatLng = LatLng(p.lat, p.lon));
            _showEntryDetail(t);
          },
          child: Icon(
            Icons.location_on,
            size: 28,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      );
    }).toList();

    final markers = <Marker>[...timelineMarkers];

    markers.add(
      Marker(
        point: LatLng(startPoint.lat, startPoint.lon),
        width: 32,
        height: 32,
        child: GestureDetector(
          onTap: () {},
          child: Container(
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.green,
            ),
            child: const Icon(
              Icons.flag,
              color: Colors.white,
              size: 18,
            ),
          ),
        ),
      ),
    );

    markers.add(
      Marker(
        point: LatLng(endPoint.lat, endPoint.lon),
        width: 32,
        height: 32,
        child: GestureDetector(
          onTap: () {},
          child: Container(
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.red,
            ),
            child: const Icon(
              Icons.flag,
              color: Colors.white,
              size: 18,
            ),
          ),
        ),
      ),
    );

    if (_droppedMarkerLatLng != null) {
      markers.add(
        Marker(
          point: _droppedMarkerLatLng!,
          width: 44,
          height: 44,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              if (_isMarkerSheetOpen) Navigator.of(context).pop();
              setState(() => _droppedMarkerLatLng = null);
            },
            onPanUpdate: (details) {
              final camera = _mapController.camera;
              final screenPt = camera.latLngToScreenPoint(_droppedMarkerLatLng!);
              final newPt = Point<num>(
                screenPt.x + details.delta.dx,
                screenPt.y + details.delta.dy,
              );
              setState(() => _droppedMarkerLatLng = camera.pointToLatLng(newPt));
            },
            onPanEnd: (_) {
              final nearest =
                  _findNearestTrackPoint(_droppedMarkerLatLng!, track.points);
              if (nearest != null) _showTrackPointBottomSheet(nearest);
            },
            child: const Icon(Icons.place, color: Colors.deepOrange, size: 40),
          ),
        ),
      );
    }

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(top: 12),
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: SizedBox(
        height: 340,
        child: Stack(
          children: [
            ExcludeSemantics(
              child: FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCameraFit: CameraFit.bounds(
                    bounds: LatLngBounds.fromPoints(polylinePoints),
                    padding: const EdgeInsets.all(40),
                  ),
                  onTap: (_, _) {
                    if (_isMarkerSheetOpen) Navigator.of(context).pop();
                    setState(() => _droppedMarkerLatLng = null);
                  },
                  onLongPress: (tapPosition, latLng) {
                    final nearest = _findNearestTrackPoint(latLng, track.points);
                    setState(() => _droppedMarkerLatLng = latLng);
                    if (nearest != null) _showTrackPointBottomSheet(nearest);
                  },
                ),
                children: [
                  TileLayer(
                    urlTemplate: _satelliteView
                        ? 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}'
                        : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.logbook.app',
                    tileProvider: NetworkTileProvider(),
                  ),
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: polylinePoints,
                        strokeWidth: 4,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ],
                  ),
                  MarkerLayer(markers: markers),
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
            ),
            Positioned(
              right: 12,
              bottom: 12,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  FloatingActionButton.small(
                    heroTag: 'recenter_button',
                    onPressed: () {
                      _mapController.fitCamera(
                        CameraFit.bounds(
                          bounds: LatLngBounds.fromPoints(polylinePoints),
                          padding: const EdgeInsets.all(40),
                        ),
                      );
                    },
                    tooltip: 'Zentrieren',
                    child: const Icon(Icons.my_location),
                  ),
                  const SizedBox(height: 8),
                  FloatingActionButton.small(
                    heroTag: 'satellite_button',
                    onPressed: () =>
                        setState(() => _satelliteView = !_satelliteView),
                    tooltip: _satelliteView ? 'Kartenansicht' : 'Satellitenansicht',
                    child: Icon(_satelliteView ? Icons.map_outlined : Icons.satellite_alt),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------
  // ADDITIONAL INFO CARD
  // ------------------------------------------------------------
  Widget _buildAdditionalInfoCard(DayEntry entry) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(top: 12),
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        title: Text(
          'Weitere Informationen',
          style: GoogleFonts.newsreader(
            fontSize: 28,
            fontWeight: FontWeight.w500,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHarborSection(entry),
                const Divider(height: 28),
                _buildParticipantsSection(entry),
                const Divider(height: 28),
                _buildControlledSection(entry),
                const Divider(height: 28),
                _buildNotesSection(entry),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHarborSection(DayEntry entry) {
    final cs = Theme.of(context).colorScheme;
    final labelStyle = Theme.of(context).textTheme.labelLarge?.copyWith(
          color: cs.onSurfaceVariant,
        );
    final inputDecoration = InputDecoration(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      isDense: true,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Route', style: labelStyle),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Von', style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 4),
                  TextField(
                    controller: _fromHarborController,
                    decoration:
                        inputDecoration.copyWith(hintText: 'Starthafen'),
                    textInputAction: TextInputAction.next,
                    onChanged: (v) {
                      entry.fromHarbor = v.trim().isEmpty ? null : v.trim();
                      entry.save();
                    },
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 20, left: 8, right: 8),
              child: Icon(Icons.arrow_forward,
                  size: 18, color: cs.onSurfaceVariant),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Nach', style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 4),
                  TextField(
                    controller: _toHarborController,
                    decoration:
                        inputDecoration.copyWith(hintText: 'Zielhafen'),
                    textInputAction: TextInputAction.done,
                    onChanged: (v) {
                      entry.toHarbor = v.trim().isEmpty ? null : v.trim();
                      entry.save();
                    },
                    onSubmitted: (_) => FocusScope.of(context).unfocus(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildParticipantsSection(DayEntry entry) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Teilnehmer',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            ...entry.participantsList.map(
              (name) => Chip(
                label: Text(name),
                deleteIcon: Icon(Icons.close,
                    size: 16,
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
                onDeleted: () => _removeParticipant(entry, name),
                backgroundColor:
                    Theme.of(context).colorScheme.surfaceContainerHigh,
                labelStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.primary),
                side: BorderSide.none,
              ),
            ),
            ActionChip(
              avatar: Icon(Icons.person_add_outlined,
                  size: 16,
                  color: Theme.of(context).colorScheme.primary),
              label: Text('Hinzufügen',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.primary)),
              backgroundColor:
                  Theme.of(context).colorScheme.surfaceContainerHigh,
              side: BorderSide.none,
              onPressed: () => _addParticipant(entry),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildControlledSection(DayEntry entry) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Checkliste',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 4),
        ..._controlledItems.map((item) {
          final checked = entry.checkedItems.contains(item);
          return CheckboxListTile(
            value: checked,
            title:
                Text(item, style: Theme.of(context).textTheme.bodyMedium),
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            onChanged: (v) => _toggleCheckedItem(entry, item, v ?? false),
          );
        }),
      ],
    );
  }

  Widget _buildNotesSection(DayEntry entry) {
    _notesController ??= TextEditingController(text: entry.notes ?? '');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Notizen',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _notesController,
          decoration: InputDecoration(
            hintText: 'Notizen für diesen Tag…',
            border:
                OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
          minLines: 1,
          maxLines: null,
          keyboardType: TextInputType.multiline,
          textInputAction: TextInputAction.newline,
          onChanged: (v) {
            entry.notes = v.isEmpty ? null : v;
            entry.save();
          },
        ),
      ],
    );
  }

  void _addParticipant(DayEntry entry) async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Teilnehmer hinzufügen'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Name'),
          textCapitalization: TextCapitalization.words,
          onSubmitted: (v) => Navigator.pop(context, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Abbrechen'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, ctrl.text.trim()),
            child: const Text('Hinzufügen'),
          ),
        ],
      ),
    );
    if (!mounted || name == null || name.isEmpty) return;
    setState(() {
      entry.participantsList.add(name);
      entry.save();
    });
  }

  void _removeParticipant(DayEntry entry, String name) {
    setState(() {
      entry.participantsList.remove(name);
      entry.save();
    });
  }

  void _toggleCheckedItem(DayEntry entry, String item, bool checked) {
    setState(() {
      if (checked) {
        entry.checkedItems.add(item);
      } else {
        entry.checkedItems.remove(item);
      }
      entry.save();
    });
  }

  // ------------------------------------------------------------
  // TIMELINE ENTRIES
  // ------------------------------------------------------------
  Widget _buildTimelineItem(
    DayEntry entry,
    TimelineEntry t,
    TrackPoint? trackedPoint,
    int index,
    int total,
  ) {
    final cs = Theme.of(context).colorScheme;
    final timeStr =
        '${t.time.hour.toString().padLeft(2, '0')}:${t.time.minute.toString().padLeft(2, '0')}';
    final isLast = index == total - 1;
    final title = t.remarks?.isNotEmpty == true ? t.remarks! : 'Logeintrag';

    return GestureDetector(
      onTap: () => _showEntryDetail(t),
      onLongPress: () => _showTimelineActions(entry, t),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Left spine: dot + line that stretches into gap ─────
            SizedBox(
              width: 20,
              child: Column(
                mainAxisSize: MainAxisSize.max,
                children: [
                  // Dot
                  Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: cs.primary, width: 2),
                      color: cs.surface,
                    ),
                    child: Center(
                      child: Container(
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: cs.primary,
                        ),
                      ),
                    ),
                  ),
                  // Line — fills all remaining height including bottom gap
                  if (!isLast)
                    Expanded(
                      child: Center(
                        child: Container(
                          width: 2,
                          color: cs.outlineVariant,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            // ── Content — bottom padding creates the gap the line fills ──
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(bottom: isLast ? 0 : 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Time + map pin
                    Row(
                      children: [
                        Text(
                          timeStr,
                          style: Theme.of(context)
                              .textTheme
                              .labelLarge
                              ?.copyWith(color: cs.onSurfaceVariant),
                        ),
                        if (trackedPoint != null) ...[
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: () => _mapController.move(
                              LatLng(trackedPoint.lat, trackedPoint.lon),
                              14,
                            ),
                            child: Icon(Icons.location_on_outlined,
                                size: 18, color: cs.primary),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    // Title
                    Text(
                      title,
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: cs.primary,
                      ),
                    ),
                    // Data chips
                    if (_hasChipData(t)) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          if (t.course != null)
                            _infoChip(Icons.navigation,
                                '${t.course!.toStringAsFixed(0)}°'),
                          if (t.speed != null)
                            _infoChip(Icons.speed,
                                '${t.speed!.toStringAsFixed(1)} kn'),
                          if (t.weather != null)
                            _infoChip(Icons.wb_sunny_outlined, t.weather!),
                          if (t.wind != null)
                            _infoChip(Icons.air, t.wind!),
                          if (t.sea != null)
                            _infoChip(Icons.waves, t.sea!),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _hasChipData(TimelineEntry t) =>
      t.course != null ||
      t.speed != null ||
      t.weather != null ||
      t.wind != null ||
      t.sea != null;

  Widget _infoChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(50),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon,
              size: 12,
              color: Theme.of(context).colorScheme.onSecondaryContainer),
          const SizedBox(width: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color:
                      Theme.of(context).colorScheme.onSecondaryContainer,
                ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------
  // ENTRY DETAIL BOTTOM SHEET
  // ------------------------------------------------------------
  void _showEntryDetail(TimelineEntry t) {
    final timeStr =
        '${t.time.hour.toString().padLeft(2, '0')}:${t.time.minute.toString().padLeft(2, '0')}';

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              timeStr,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
            ),
            if (t.remarks?.isNotEmpty == true) ...[
              const SizedBox(height: 4),
              Text(t.remarks!,
                  style: Theme.of(context).textTheme.titleMedium),
            ],
            const SizedBox(height: 16),
            if (t.course != null)
              _detailRow(Icons.navigation, 'Course',
                  '${t.course!.toStringAsFixed(0)}°'),
            if (t.speed != null)
              _detailRow(
                  Icons.speed, 'Speed', '${t.speed!.toStringAsFixed(1)} kn'),
            if (t.wind != null) _detailRow(Icons.air, 'Wind', t.wind!),
            if (t.sea != null) _detailRow(Icons.waves, 'Sea', t.sea!),
            if (t.weather != null)
              _detailRow(Icons.wb_sunny_outlined, 'Weather', t.weather!),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon,
              size: 18,
              color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Text(
            '$label  ',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          Text(value,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  // ------------------------------------------------------------
  // LONG-PRESS ACTIONS BOTTOM SHEET
  // ------------------------------------------------------------
  void _showTimelineActions(DayEntry entry, TimelineEntry t) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Bearbeiten'),
              onTap: () {
                Navigator.pop(context);
                _editTimelineEntry(entry, t);
              },
            ),
            ListTile(
              leading: Icon(Icons.delete_outline,
                  color: Theme.of(context).colorScheme.error),
              title: Text('Löschen',
                  style:
                      TextStyle(color: Theme.of(context).colorScheme.error)),
              onTap: () {
                Navigator.pop(context);
                _deleteTimelineEntry(entry, t);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
  // ------------------------------------------------------------
  // ADD TIMELINE ENTRY
  // ------------------------------------------------------------
  Future<void> _openWeatherUrl(BuildContext context) async {
    final url = context.read<ThemeProvider>().weatherUrl;
    if (url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _addTimelineEntry(BuildContext context) async {
    final repo = context.read<HomeRepository>();
    final day = DateTime(widget.year, widget.month, widget.day);
    final newEntry = await showDialog<TimelineEntry>(
      context: context,
      builder: (_) => AddTimelineEntryDialog(day: day),
    );

    if (!mounted || newEntry == null) return;

    repo.addTimelineEntry(day, newEntry);
  }
  //
  //Delete timeline entry
  //
  void _deleteTimelineEntry(DayEntry entry, TimelineEntry t) {
    setState(() {
      entry.timeline.remove(t);
      entry.save(); // Hive speichert Änderungen
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Logeintrag gelöscht')),
    );
  }

  void _editTimelineEntry(DayEntry entry, TimelineEntry t) async {
    final day = DateTime(widget.year, widget.month, widget.day);

    final updated = await showDialog<TimelineEntry>(
      context: context,
      builder: (_) => AddTimelineEntryDialog(
        day: day,
        initialEntry: t,
      ),
    );

    if (!mounted || updated == null) return;

    setState(() {
      final index = entry.timeline.indexOf(t);
      if (index != -1) {
        entry.timeline[index] = updated;
        entry.timeline.sort((a, b) => a.time.compareTo(b.time));
        entry.save();
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Logeintrag aktualisiert')),
    );
  }

  // ------------------------------------------------------------
  // FILE PICKER (FIXED)
  // ------------------------------------------------------------
  void _importGpx() async {
    final repo = context.read<HomeRepository>();
    final day = DateTime(widget.year, widget.month, widget.day);

    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['gpx'],
      allowMultiple: false,
      withData: kIsWeb,
    );

    if (result == null || result.files.isEmpty) return;

    final picked = result.files.single;

    // Parse first for date validation
    final List<TrackPoint> preview;
    if (kIsWeb) {
      final bytes = picked.bytes;
      if (bytes == null) return;
      preview = GpxParser().parseBytes(bytes);
    } else {
      preview = await GpxParser().parse(File(picked.path!));
    }

    if (!mounted) return;

    if (preview.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('GPX-File enthält keine Wegpunkte mit Zeitstempel')),
      );
      return;
    }

    // Find the date that appears most in the track
    final counts = <DateTime, int>{};
    for (final p in preview) {
      final d = DateTime(p.time.toLocal().year, p.time.toLocal().month, p.time.toLocal().day);
      counts[d] = (counts[d] ?? 0) + 1;
    }
    final dominantDate = counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
    final targetDate = DateTime(day.year, day.month, day.day);

    if (dominantDate != targetDate) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Falsches Datum?'),
          content: Text(
            'Das GPX-File enthält hauptsächlich Daten vom '
            '${DateFormat('d. MMMM yyyy', 'de_CH').format(dominantDate)}, '
            'nicht vom ${DateFormat('d. MMMM yyyy', 'de_CH').format(targetDate)}.\n\n'
            'Trotzdem importieren?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Abbrechen'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Trotzdem importieren'),
            ),
          ],
        ),
      );
      if (!mounted || proceed != true) return;
    }

    if (kIsWeb) {
      final bytes = picked.bytes;
      if (bytes == null) return;
      await repo.importGpxFromBytes(day, bytes, picked.name);
    } else {
      await repo.importGpx(day, File(picked.path!));
    }

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('GPX-Track importiert für ${DateFormat('d. MMMM yyyy', 'de_CH').format(day)}')),
    );
  }

  void _removeGpx() async {
    final repo = context.read<HomeRepository>();
    final day = DateTime(widget.year, widget.month, widget.day);

    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('GPX-Track entfernen?'),
        content: const Text('GPX-Track für diesen Tag löschen?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );

    if (!mounted || shouldDelete != true) return;

    await repo.removeGpx(day);

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('GPX-Track entfernt')),
    );
  }

  void _deleteDay() async {
    final repo = context.read<HomeRepository>();
    final day = DateTime(widget.year, widget.month, widget.day);
    final dateLabel = DateFormat('d. MMMM yyyy', 'de_CH').format(day);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Tag löschen?'),
        content: Text(
          'Alle Daten für den $dateLabel werden unwiderruflich gelöscht, '
          'inklusive Logeinträge und GPX-Track.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              'Löschen',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
      ),
    );

    if (!mounted || confirmed != true) return;

    await repo.removeEntry(day);

    if (!mounted) return;
    context.go('/');
  }

  // ------------------------------------------------------------
  // UTILS
  // ------------------------------------------------------------
  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    return "${h}h ${m}m";
  }
}
