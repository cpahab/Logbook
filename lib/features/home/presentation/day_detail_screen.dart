import 'dart:io';
import 'package:flutter/material.dart';
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
  bool _expandAdditionalFields = false;
  final MapController _mapController = MapController();

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
            icon: const Icon(Icons.upload_file),
            tooltip: "Import GPX",
            onPressed: _importGpx,
          ),
          if (track != null)
            IconButton(
              icon: const Icon(Icons.delete),
              tooltip: "Remove GPX",
              onPressed: _removeGpx,
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
    return Column(
      children: [
        _buildHeader(entry, track),
        if (stats != null) _buildStatisticsCard(stats),
        Expanded(flex: 2, child: _buildMap(entry, track)),
        Expanded(flex: 3, child: _buildTimeline(entry)),
      ],
    );
  }

  // ------------------------------------------------------------
  // HEADER
  // ------------------------------------------------------------
  Widget _buildHeader(DayEntry entry, DailyTrack? track) {
    final dateLabel = DateFormat('EEEE, d MMMM yyyy').format(entry.date);

    return Material(
      elevation: 2,
      borderRadius: BorderRadius.circular(20),
      color: Theme.of(context).colorScheme.surface,
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
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.upload_file),
                      tooltip: 'Import GPX',
                      onPressed: _importGpx,
                    ),
                    if (track != null)
                      IconButton(
                        icon: const Icon(Icons.delete),
                        tooltip: 'Delete GPX',
                        onPressed: _removeGpx,
                      ),
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert),
                      itemBuilder: (context) => const [
                        PopupMenuItem<String>(
                          value: 'none',
                          enabled: false,
                          child: Text('No options yet'),
                        ),
                      ],
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

  }

  Widget _buildStatisticsCard(DailyStats stats) {
    final statItems = [
      _StatsItem(label: 'Distance', value: '${stats.distanceNm.toStringAsFixed(2)} nm'),
      _StatsItem(label: 'Moving time', value: _formatDuration(stats.movingDuration)),
      _StatsItem(label: 'Avg speed', value: '${stats.avgSpeed.toStringAsFixed(2)} kn'),
      _StatsItem(label: 'Max speed', value: '${stats.maxSpeed.toStringAsFixed(2)} kn'),
      _StatsItem(
        label: 'Elevation gain',
        value: stats.elevationGainMeters != null
            ? '${stats.elevationGainMeters!.toStringAsFixed(0)} m'
            : 'N/A',
      ),
      _StatsItem(label: 'Stops', value: '${stats.stopCount}'),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 16, 0, 0),
      child: Material(
        elevation: 2,
        borderRadius: BorderRadius.circular(20),
        color: Theme.of(context).colorScheme.surface,
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
                childAspectRatio: 3.2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                children: statItems.map((item) {
                  return Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          item.value,
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          item.label,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------
  // TOOLTIP FORMATTER
  // ------------------------------------------------------------
  String _timelineTooltip(TimelineEntry t) {
    final timeStr = '${t.time.hour.toString().padLeft(2, '0')}:${t.time.minute.toString().padLeft(2, '0')}';
    final title = t.remarks?.isNotEmpty == true ? t.remarks! : 'Timeline entry';
    return '$title\n$timeStr';
  }

  String _gpxPointTooltip(TrackPoint p) {
    final time = p.time.toLocal();
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}';
  }

  List<Marker> _buildGpxHoverMarkers(List<TrackPoint> points) {
    if (points.isEmpty) return [];

    final step = (points.length / 200).ceil();
    final markers = <Marker>[];

    for (var index = 0; index < points.length; index += step) {
      final p = points[index];
      markers.add(
        Marker(
          point: LatLng(p.lat, p.lon),
          width: 24,
          height: 24,
          child: Container(
            color: Colors.transparent,
          ),
        ),
      );
    }

    return markers;
  }

  // ------------------------------------------------------------
  // MAP WITH CORRELATED MARKERS
  // ------------------------------------------------------------
  // ------------------------------------------------------------
  Widget _buildMap(DayEntry entry, DailyTrack? track) {
    if (track == null || track.points.isEmpty) {
      return SizedBox(
        height: 340,
        child: Center(child: Text('No GPX track for this day')),
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
        width: 24,
        height: 24,
        child: Tooltip(
          excludeFromSemantics: true,
          message: _timelineTooltip(t),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color.fromARGB(221, 77, 27, 27),
            borderRadius: BorderRadius.circular(6),
          ),
          textStyle: const TextStyle(color: Colors.white),
          child: GestureDetector(
            onTap: () => _showTimelinePopup(t),
            child: Container(
              width: 12,
              height: 12,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.blue,
              ),
            ),
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

    return SizedBox(
      height: 340,
      child: Material(
        elevation: 2,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            FlutterMap(
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
                      color: Colors.blue,
                    ),
                  ],
                ),
                MarkerLayer(markers: markers),
                RichAttributionWidget(
                  attributions: [
                    TextSourceAttribution(
                      '© OpenStreetMap contributors',
                      onTap: () => launchUrl(
                        Uri.parse('https://www.openstreetmap.org/copyright'),
                      ),
                    ),
                  ],
                ),
              ],
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
                      _mapController.fitBounds(
                        LatLngBounds.fromPoints(polylinePoints),
                        options: const FitBoundsOptions(padding: EdgeInsets.all(40)),
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
  // TIMELINE LIST
  // ------------------------------------------------------------
  Widget _buildTimeline(DayEntry entry) {
    if (entry.timeline.isEmpty) {
      return const Center(child: Text("No timeline entries yet"));
    }

    return ListView.builder(
      itemCount: entry.timeline.length,
      itemBuilder: (context, index) {
        final t = entry.timeline[index];
        final timeStr = TimeOfDay.fromDateTime(t.time).format(context);

        return ListTile(
          leading: const Icon(Icons.schedule),
          title: Text(timeStr),
          subtitle: Text(_formatTimelineEntry(t)),
          onTap: () => _showTimelinePopup(t),
          trailing: SizedBox(
            width: 100,
            child: PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert), // ⭐ sichtbar in Material 3
              onSelected: (value) {
                if (value == "delete") {
                  _deleteTimelineEntry(entry, t);
                } else if (value == "edit") {
                  _editTimelineEntry(entry, t);
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: "edit",
                  child: Text("Edit"),
                ),
                const PopupMenuItem(
                  value: "delete",
                  child: Text("Delete"),
                ),
              ],
            ),
          ),
        );


      },
    );
  }

  // ------------------------------------------------------------
  // POPUP
  // ------------------------------------------------------------
  void _showTimelinePopup(TimelineEntry t) {
    final timeStr = TimeOfDay.fromDateTime(t.time).format(context);

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text("Timeline $timeStr"),
        content: Text(_formatTimelineEntry(t)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Close"),
          ),
        ],
      ),
    );
  }

  String _formatTimelineEntry(TimelineEntry t) {
    final parts = <String>[];

    if (t.course != null) parts.add("Course: ${t.course}°");
    if (t.speed != null) parts.add("Speed: ${t.speed} kn");
    if (t.wind != null) parts.add("Wind: ${t.wind}");
    if (t.sea != null) parts.add("Sea: ${t.sea}");
    if (t.weather != null) parts.add("Weather: ${t.weather}");
    if (t.remarks != null) parts.add("Remarks: ${t.remarks}");

    return parts.join("\n");
  }
  String _additionalInfoSummary(DayEntry entry) {
    final parts = <String>[];
    if (entry.participants?.isNotEmpty == true) {
      parts.add("Participants: ${entry.participants}");
    }
    if (entry.controlled?.isNotEmpty == true) {
      parts.add("Controlled: ${entry.controlled}");
    }
    if (parts.isEmpty) {
      return "No additional info";
    }
    return parts.join(" • ");
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
      withData: false,
    );

    if (result == null || result.files.isEmpty) return;

    final file = File(result.files.single.path!);

    await repo.importGpx(day, file);

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Imported GPX track for ${day.toIso8601String()}")),
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
