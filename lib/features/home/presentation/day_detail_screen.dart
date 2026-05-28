import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
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
import '../utils/compute_daily_stats.dart';
import '../utils/track_correlation.dart';

class _StatsItem {
  final String label;
  final String value;

  const _StatsItem({required this.label, required this.value});
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

  static const _controlledItems = [
    'Engine oil checked',
    'Gasoline checked',
    'Safety gear verified',
  ];

  @override
  void dispose() {
    _notesController?.dispose();
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

    return Scaffold(
      appBar: AppBar(
        title: Text("${widget.year}-${widget.month}-${widget.day}"),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _addTimelineEntry(context),
        child: const Icon(Icons.add),
      ),
      body: entry == null
          ? const Center(child: Text("No entry for this day"))
          : _buildContent(entry, track, repo, stats),
    );
  }

  Widget _buildContent(
      DayEntry entry, DailyTrack? track, HomeRepository repo, DailyStats? stats) {
    _notesController ??= TextEditingController(text: entry.notes ?? '');

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
                    SliverToBoxAdapter(child: _buildHeader(entry, track)),
                    SliverToBoxAdapter(child: _buildAnimatedStats(stats)),
                    SliverToBoxAdapter(
                        child: _buildAnimatedMap(entry, track)),
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
            SliverToBoxAdapter(child: _buildHeader(entry, track)),
            SliverToBoxAdapter(child: _buildAnimatedStats(stats)),
            SliverToBoxAdapter(child: _buildAnimatedMap(entry, track)),
            SliverToBoxAdapter(child: _buildAdditionalInfoCard(entry)),
            ..._timelineSlivers(entry, correlatedMap),
          ],
        );
      },
    );
  }

  Widget _buildAnimatedStats(DailyStats? stats) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 350),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, -0.15),
            end: Offset.zero,
          ).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
          child: child,
        ),
      ),
      child: stats != null
          ? KeyedSubtree(
              key: const ValueKey('stats'), child: _buildStatisticsCard(stats))
          : const SizedBox.shrink(key: ValueKey('no-stats')),
    );
  }

  Widget _buildAnimatedMap(DayEntry entry, DailyTrack? track) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 400),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
        child: child,
      ),
      child: KeyedSubtree(
        key: ValueKey<bool>(track != null && track.points.isNotEmpty),
        child: _buildMap(entry, track),
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
                Text('No entries yet — tap + to add one',
                    style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          ),
        ),
      ];
    }
    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate(
            (ctx, index) {
              final t = entry.timeline[index];
              return _buildTimelineItem(
                entry, t, correlatedMap[t], index, entry.timeline.length,
              );
            },
            childCount: entry.timeline.length,
          ),
        ),
      ),
    ];
  }

  // ------------------------------------------------------------
  // HEADER
  // ------------------------------------------------------------
  Widget _buildHeader(DayEntry entry, DailyTrack? track) {
    final dateLabel = DateFormat('EEEE, d MMMM yyyy').format(entry.date);

    return Card(
      elevation: 2,
      margin: EdgeInsets.zero,
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        dateLabel,
                        style: Theme.of(context)
                            .textTheme
                            .headlineMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Logbook details for the selected day',
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert),
                  onSelected: (value) {
                    if (value == 'import_gpx') _importGpx();
                    if (value == 'delete_gpx') _removeGpx();
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem<String>(
                      value: 'import_gpx',
                      child: Row(
                        children: [
                          _gpxUploadIcon(),
                          const SizedBox(width: 12),
                          const Text('Import GPX'),
                        ],
                      ),
                    ),
                    if (track != null)
                      PopupMenuItem<String>(
                        value: 'delete_gpx',
                        child: Row(
                          children: [
                            Icon(Icons.delete_outline,
                                color: Theme.of(context).colorScheme.error),
                            const SizedBox(width: 12),
                            Text(
                              'Delete GPX',
                              style: TextStyle(
                                  color:
                                      Theme.of(context).colorScheme.error),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatisticsCard(DailyStats stats) {
    final statItems = <_StatsItem>[
      _StatsItem(label: 'Distance', value: '${stats.distanceNm.toStringAsFixed(2)} nm'),
      _StatsItem(label: 'Moving time', value: _formatDuration(stats.movingDuration)),
      _StatsItem(label: 'Avg speed', value: '${stats.avgSpeed.toStringAsFixed(1)} kn'),
      _StatsItem(label: 'Max speed', value: '${stats.maxSpeed.toStringAsFixed(1)} kn'),
      if (stats.elevationGainMeters != null && stats.elevationGainMeters! > 0)
        _StatsItem(
          label: 'Elevation gain',
          value: '${stats.elevationGainMeters!.toStringAsFixed(0)} m',
        ),
    ];

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(top: 12),
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Statistics',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            GridView.count(
              physics: const NeverScrollableScrollPhysics(),
              shrinkWrap: true,
              crossAxisCount: 2,
              childAspectRatio: 4.2,
              crossAxisSpacing: 8,
              mainAxisSpacing: 6,
              children: statItems.map((item) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        item.value,
                        style: Theme.of(context)
                            .textTheme
                            .labelLarge
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        item.label,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSecondaryContainer
                                  .withValues(alpha: 0.7),
                            ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ],
        ),
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
  // HOURLY MARKERS
  // ------------------------------------------------------------
  List<Marker> _buildHourlyMarkers(List<TrackPoint> points) {
    if (points.length < 2) return [];

    final first = points.first.time.toLocal();
    final last = points.last.time.toLocal();

    var hour = DateTime(first.year, first.month, first.day, first.hour)
        .add(const Duration(hours: 1));

    if (hour.isAfter(last)) return [];

    final result = <Marker>[];

    while (!hour.isAfter(last)) {
      final hourUtc = hour.toUtc();
      TrackPoint? closest;
      var bestMs = const Duration(minutes: 30).inMilliseconds;

      for (final p in points) {
        final diff = p.time.difference(hourUtc).abs().inMilliseconds;
        if (diff < bestMs) {
          bestMs = diff;
          closest = p;
        }
      }

      if (closest != null) {
        final label = '${hour.hour.toString().padLeft(2, '0')}:00';
        result.add(
          Marker(
            point: LatLng(closest.lat, closest.lon),
            width: 16,
            height: 16,
            child: Tooltip(
              excludeFromSemantics: true,
              message: label,
              child: Center(
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Theme.of(context).colorScheme.surface,
                    border: Border.all(
                      color: Theme.of(context)
                          .colorScheme
                          .primary
                          .withValues(alpha: 0.7),
                      width: 1.5,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      }

      hour = hour.add(const Duration(hours: 1));
    }

    return result;
  }

  // ------------------------------------------------------------
  // TOOLTIP FORMATTER
  // ------------------------------------------------------------
  String _timelineTooltip(TimelineEntry t) {
    final timeStr =
        '${t.time.hour.toString().padLeft(2, '0')}:${t.time.minute.toString().padLeft(2, '0')}';
    final lines = <String>[timeStr];
    if (t.remarks?.isNotEmpty == true) lines.add(t.remarks!);
    if (t.course != null) lines.add('Course  ${t.course!.toStringAsFixed(0)}°');
    if (t.speed != null) lines.add('Speed  ${t.speed!.toStringAsFixed(1)} kn');
    if (t.wind != null) lines.add('Wind  ${t.wind!}');
    if (t.sea != null) lines.add('Sea  ${t.sea!}');
    if (t.weather != null) lines.add('Weather  ${t.weather!}');
    return lines.join('\n');
  }

  // ------------------------------------------------------------
  // MAP WITH CORRELATED MARKERS
  // ------------------------------------------------------------
  Widget _buildMap(DayEntry entry, DailyTrack? track) {
    if (track == null || track.points.isEmpty) {
      return Card(
        elevation: 2,
        margin: const EdgeInsets.only(top: 12),
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: SizedBox(
          height: 340,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.map_outlined,
                  size: 40,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(height: 8),
                Text(
                  'No GPX track for this day',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
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
        width: 20,
        height: 20,
        child: Tooltip(
          excludeFromSemantics: true,
          message: _timelineTooltip(t),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.inverseSurface,
            borderRadius: BorderRadius.circular(8),
          ),
          textStyle: TextStyle(
            color: Theme.of(context).colorScheme.onInverseSurface,
            fontSize: 12,
            height: 1.4,
          ),
          child: GestureDetector(
            onTap: () => _showEntryDetail(t),
            child: Icon(
              Icons.location_on,
              size: 20,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
      );
    }).toList();

    final hourlyMarkers = _buildHourlyMarkers(track.points);
    final markers = <Marker>[...hourlyMarkers, ...timelineMarkers];

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
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
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
            ),  // ExcludeSemantics
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
                    tooltip: 'Recenter',
                    child: const Icon(Icons.my_location),
                  ),
                  const SizedBox(height: 8),
                  FloatingActionButton.small(
                    heroTag: 'satellite_button',
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Satellite view coming soon'),
                        ),
                      );
                    },
                    tooltip: 'Satellite view',
                    child: const Icon(Icons.satellite_alt),
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
          'Additional Info',
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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

  Widget _buildParticipantsSection(DayEntry entry) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Participants',
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
                deleteIcon: const Icon(Icons.close, size: 16),
                onDeleted: () => _removeParticipant(entry, name),
              ),
            ),
            ActionChip(
              avatar: const Icon(Icons.person_add_outlined, size: 16),
              label: const Text('Add'),
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
          'Controlled Items',
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
          'Notes',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _notesController,
          decoration: InputDecoration(
            hintText: 'Add notes for this day…',
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
        title: const Text('Add Participant'),
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
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, ctrl.text.trim()),
            child: const Text('Add'),
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
    final timeStr =
        '${t.time.hour.toString().padLeft(2, '0')}:${t.time.minute.toString().padLeft(2, '0')}';
    final isLast = index == total - 1;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Timeline spine
          SizedBox(
            width: 52,
            child: Column(
              children: [
                Text(
                  timeStr,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                ),
                const SizedBox(height: 4),
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.only(top: 4),
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Entry card
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 12),
              child: GestureDetector(
                onTap: () => _showEntryDetail(t),
                onLongPress: () => _showTimelineActions(entry, t),
                child: Card(
                  elevation: 1,
                  margin: EdgeInsets.zero,
                  color: Theme.of(context).colorScheme.surfaceContainerHigh,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                t.remarks?.isNotEmpty == true
                                    ? t.remarks!
                                    : 'Log entry',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(fontWeight: FontWeight.w600),
                              ),
                            ),
                            if (trackedPoint != null)
                              IconButton(
                                icon: const Icon(Icons.location_on_outlined),
                                iconSize: 18,
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                tooltip: 'Show on map',
                                color: Theme.of(context).colorScheme.primary,
                                onPressed: () => _mapController.move(
                                  LatLng(trackedPoint.lat, trackedPoint.lon),
                                  14,
                                ),
                              ),
                          ],
                        ),
                        if (_hasChipData(t)) ...[
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              if (t.course != null)
                                _infoChip(Icons.navigation,
                                    '${t.course!.toStringAsFixed(0)}°'),
                              if (t.speed != null)
                                _infoChip(Icons.speed,
                                    '${t.speed!.toStringAsFixed(1)} kn'),
                              if (t.weather != null)
                                _infoChip(
                                    Icons.wb_sunny_outlined, t.weather!),
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
              ),
            ),
          ),
        ],
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(20),
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
              title: const Text('Edit'),
              onTap: () {
                Navigator.pop(context);
                _editTimelineEntry(entry, t);
              },
            ),
            ListTile(
              leading: Icon(Icons.delete_outline,
                  color: Theme.of(context).colorScheme.error),
              title: Text('Delete',
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
      const SnackBar(content: Text("Timeline entry deleted")),
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
      const SnackBar(content: Text("Timeline entry updated")),
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

    if (kIsWeb) {
      final bytes = picked.bytes;
      if (bytes == null) return;
      await repo.importGpxFromBytes(day, bytes, picked.name);
    } else {
      await repo.importGpx(day, File(picked.path!));
    }

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Imported GPX track for ${day.toIso8601String()}')),
    );
  }

  void _removeGpx() async {
    final repo = context.read<HomeRepository>();
    final day = DateTime(widget.year, widget.month, widget.day);

    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remove GPX track?'),
        content: const Text('Delete the GPX track for this day?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (!mounted || shouldDelete != true) return;

    await repo.removeGpx(day);

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('GPX track removed')),
    );
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
