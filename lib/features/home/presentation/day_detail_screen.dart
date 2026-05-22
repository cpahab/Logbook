import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/home_repository.dart';
import '../domain/day_entry.dart';
import '../domain/daily_track.dart';
import '../domain/timeline_entry.dart';
//import '../domain/track_point.dart';

import '../widgets/add_timeline_entry_dialog.dart';
import '../utils/compute_daily_stats.dart';
import '../utils/track_correlation.dart';

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

  Widget _buildContent(
      DayEntry entry, DailyTrack? track, HomeRepository repo, DailyStats? stats) {
    return Column(
      children: [
        _buildHeader(stats, entry),
        Expanded(flex: 2, child: _buildMap(entry, track)),
        Expanded(flex: 3, child: _buildTimeline(entry)),
      ],
    );
  }

  // ------------------------------------------------------------
  // HEADER
  // ------------------------------------------------------------
  Widget _buildHeader(DailyStats? stats, DayEntry entry) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: const BoxDecoration(color: Colors.transparent),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: TextEditingController(text: entry.fromHarbor ?? "")
                    ..selection = TextSelection.collapsed(
                        offset: (entry.fromHarbor ?? "").length),
                  decoration: const InputDecoration(
                    labelText: "Start",
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (value) {
                    entry.fromHarbor = value;
                    entry.save();
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: TextEditingController(text: entry.toHarbor ?? "")
                    ..selection = TextSelection.collapsed(
                        offset: (entry.toHarbor ?? "").length),
                  decoration: const InputDecoration(
                    labelText: "Destination",
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (value) {
                    entry.toHarbor = value;
                    entry.save();
                  },
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),
          const Text(
            "Statistics",
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          if (stats != null)
            Text(
              "${stats.distanceNm.toStringAsFixed(2)} nm   •   "
              "${_formatDuration(stats.duration)}   •   "
              "${stats.avgSpeed.toStringAsFixed(2)} kn avg   •   "
              "${stats.maxSpeed.toStringAsFixed(2)} kn max",
              style: const TextStyle(
                fontSize: 16,
                color: Colors.blue,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  // ------------------------------------------------------------
  // TOOLTIP FORMATTER
  // ------------------------------------------------------------
  String _timelineTooltip(TimelineEntry t) {
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
  // MAP WITH CORRELATED MARKERS
  // ------------------------------------------------------------
  Widget _buildMap(DayEntry entry, DailyTrack? track) {
    if (track == null || track.points.isEmpty) {
      return const Center(child: Text("No GPX track for this day"));
    }

    final polylinePoints =
        track.points.map((p) => LatLng(p.lat, p.lon)).toList();

    final correlated =
        correlateTimelineWithTrack(entry.timeline, track.points);

    final markers = correlated.map((pair) {
      final t = pair.$1;
      final p = pair.$2;

      return Marker(
        point: LatLng(p.lat, p.lon),
        width: 40,
        height: 40,
        child: Tooltip(
          message: _timelineTooltip(t),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.black87,
            borderRadius: BorderRadius.circular(6),
          ),
          textStyle: const TextStyle(color: Colors.white),
          child: GestureDetector(
            onTap: () => _showTimelinePopup(t),
            child: const Icon(
              Icons.location_on,
              color: Color.fromARGB(255, 133, 5, 5),
              size: 20,
            ),
          ),
        ),
      );
    }).toList();

    return FlutterMap(
      options: MapOptions(
        initialCameraFit: CameraFit.bounds(
          bounds: LatLngBounds.fromPoints(polylinePoints),
          padding: const EdgeInsets.all(40),
        ),
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
              strokeWidth: 2,
              color: Colors.blue,
            ),
          ],
        ),

        if (markers.isNotEmpty) MarkerLayer(markers: markers),

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
        final timeStr = TimeOfDay.fromDateTime(t.time).format(context);

        return ListTile(
          leading: const Icon(Icons.schedule),
          title: Text(timeStr),
          subtitle: Text(_formatTimelineEntry(t)),
          onTap: () => _showTimelinePopup(t),
          trailing: SizedBox(
            width: 40,
            child: PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert), // ⭐ sichtbar in Material 3
              onSelected: (value) {
                if (value == "delete") {
                  _deleteTimelineEntry(entry, t);
                }
              },
              itemBuilder: (context) => [
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

    if (newEntry == null) return;


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
