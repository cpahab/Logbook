import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';

import '../data/home_repository.dart';
import '../domain/day_entry.dart';
import '../domain/daily_track.dart';
import '../domain/timeline_entry.dart';
import '../domain/track_point.dart';

import '../widgets/add_timeline_entry_dialog.dart';
import '../utils/gpx_parser.dart';
import 'package:url_launcher/url_launcher.dart';
import '../utils/compute_daily_stats.dart';

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
  @override
  Widget build(BuildContext context) {
    final repo = context.watch<HomeRepository>();

    final day = DateTime(widget.year, widget.month, widget.day);
    final entry = repo.getEntry(day);
    final track = repo.dailyTracks[day];

    // ⭐ NEW: compute stats
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

  // ------------------------------------------------------------
  // MAIN LAYOUT
  // ------------------------------------------------------------
  Widget _buildContent(
      DayEntry entry, DailyTrack? track, HomeRepository repo, DailyStats? stats) {
    return Column(
      children: [
        _buildHeader(entry, track, stats),
        Expanded(
          flex: 2,
          child: _buildMap(entry, track, repo),
        ),
        Expanded(
          flex: 3,
          child: _buildTimeline(entry),
        ),
      ],
    );
  }

  // ------------------------------------------------------------
  // HEADER WITH STATS 
  // ------------------------------------------------------------
  Widget _buildHeader(DayEntry entry, DailyTrack? track, DailyStats? stats) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.transparent,
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade400),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Text(
            "Statistics",
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 6),

          if (stats != null)
            Text(
              "${stats.distanceNm.toStringAsFixed(2)} nm   •   "
              "${_formatDuration(stats.duration)}   •   "
              "${stats.avgSpeed.toStringAsFixed(2)} kn avg   •   "
              "${stats.maxSpeed.toStringAsFixed(2)} kn max",
              style: const TextStyle(fontSize: 16, color: Colors.blue,
              fontWeight: FontWeight.w600),
            ),


          const SizedBox(height: 10),
        ],
      ),
    );
  }

  // ------------------------------------------------------------
  // MAP WITH POLYLINE + MARKERS
  // ------------------------------------------------------------
  Widget _buildMap(
      DayEntry entry, DailyTrack? track, HomeRepository repo) {
    if (track == null || track.points.isEmpty) {
      return const Center(child: Text("No GPX track for this day"));
    }

    final polylinePoints =
        track.points.map((p) => LatLng(p.lat, p.lon)).toList();

    final markers = <Marker>[];

    for (final t in entry.timeline) {
      final p = repo.findClosestPoint(entry.date, t.time);
      if (p == null) continue;

      markers.add(
        Marker(
          point: LatLng(p.lat, p.lon),
          width: 40,
          height: 40,
          child: GestureDetector(
            onTap: () => _showTimelinePopup(t),
            child: const Icon(Icons.location_on, color: Colors.red, size: 32),
          ),
        ),
      );
    }

    return FlutterMap(
      options: MapOptions(
        initialCenter: polylinePoints.first,
        initialZoom: 13,
      ),
      children: [
        TileLayer(
          urlTemplate: "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
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
        final timeStr =
            TimeOfDay.fromDateTime(t.time).format(context);

        return ListTile(
          leading: const Icon(Icons.schedule),
          title: Text(timeStr),
          subtitle: Text(_formatTimelineEntry(t)),
          onTap: () => _showTimelinePopup(t),
        );
      },
    );
  }

  // ------------------------------------------------------------
  // POPUP DIALOG
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

  // ------------------------------------------------------------
  // FORMAT TIMELINE ENTRY
  // ------------------------------------------------------------
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

  // ------------------------------------------------------------
  // ADD TIMELINE ENTRY
  // ------------------------------------------------------------
  void _addTimelineEntry(BuildContext context) async {
    final newEntry = await showDialog<TimelineEntry>(
      context: context,
      builder: (_) => const AddTimelineEntryDialog(),
    );

    if (newEntry == null) return;

    final repo = context.read<HomeRepository>();
    final day = DateTime(widget.year, widget.month, widget.day);

    repo.addTimelineEntry(day, newEntry);
  }

  // ------------------------------------------------------------
  // IMPORT GPX
  // ------------------------------------------------------------
  void _importGpx() async {
    final repo = context.read<HomeRepository>();
    final day = DateTime(widget.year, widget.month, widget.day);

    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['gpx'],
    );

    if (result == null || result.files.isEmpty) return;

    final file = File(result.files.single.path!);

    await repo.importGpx(day, file);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Imported GPX track for ${day.toIso8601String()}")),
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
