import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../data/home_repository.dart';
import '../domain/day_entry.dart';
import '../domain/timeline_entry.dart';

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
    final entry = homeRepository.entries.firstWhere(
      (e) =>
          e.date.year == widget.year &&
          e.date.month == widget.month &&
          e.date.day == widget.day,
    );

    final date = DateTime(widget.year, widget.month, widget.day);
    final weekday = DateFormat('EEEE').format(date);
    final formatted = DateFormat('d MMMM yyyy').format(date);

    return Scaffold(
      appBar: AppBar(
        title: Text("Day ${widget.day}"),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        actions: [
          IconButton(
            icon: Icon(
              entry.hasGpx ? Icons.route : Icons.route_outlined,
              color: entry.hasGpx ? Colors.green : Colors.grey,
            ),
            tooltip: entry.hasGpx ? "GPX file loaded" : "Import GPX file",
            onPressed: _importGpxFile,
          ),
        ],
      ),

      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: Column(
              children: [
                Text(
                  formatted,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  weekday,
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey.shade700,
                  ),
                ),
                if (entry.hasGpx) ...[
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Icon(Icons.check_circle, color: Colors.green, size: 18),
                      SizedBox(width: 6),
                      Text(
                        "GPX track available",
                        style: TextStyle(color: Colors.green),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),

          if (entry.hasGpx) ...[
            const SizedBox(height: 24),
            _buildMap(entry),
            const SizedBox(height: 24),
            _buildStatisticsPlaceholder(),
          ],

          const SizedBox(height: 24),

          const Text(
            "Timeline",
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),

          _buildTimeline(entry),

          const SizedBox(height: 80),
        ],
      ),

      floatingActionButton: FloatingActionButton(
        onPressed: () => _addTimelineEntry(context),
        child: const Icon(Icons.add),
      ),
    );
  }

  // ---------------- MAP ----------------

  Widget _buildMap(DayEntry entry) {
    if (entry.track.isEmpty) {
      return Container(
        height: 250,
        decoration: BoxDecoration(
          color: Colors.grey.shade200,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(
          child: Text(
            "No track data",
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
    }

    final points = entry.track
        .map((p) => LatLng(p.lat, p.lon))
        .toList();

    print("Rendering map with ${points.length} points");

    return SizedBox(
      height: 300,
      child: FlutterMap(
        options: MapOptions(
          initialCenter: points.first,
          initialZoom: 13,
        ),
        children: [
          TileLayer(
            // Windows‑safe OSM tile server
            urlTemplate: "https://tile.openstreetmap.de/{z}/{x}/{y}.png",
            userAgentPackageName: 'com.logbook.app',
          ),
          PolylineLayer(
            polylines: [
              Polyline(
                points: points,
                strokeWidth: 4,
                color: Colors.blue,
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---------------- STATISTICS PLACEHOLDER ----------------

  Widget _buildStatisticsPlaceholder() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Text(
            "Daily Summary",
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 8),
          Text("• Distance: —"),
          Text("• Duration: —"),
          Text("• Max speed: —"),
          Text("• Weather: —"),
        ],
      ),
    );
  }

  // ---------------- TIMELINE ----------------

  Widget _buildTimeline(DayEntry entry) {
    if (entry.timeline.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Text(
          "No timeline entries yet.\nTap + to add notes, weather, events...",
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    return Column(
      children: entry.timeline.map((t) {
        final timeStr = TimeOfDay.fromDateTime(t.time).format(context);

        return ListTile(
          leading: const Icon(Icons.circle, size: 12, color: Colors.blue),
          title: Text(t.text),
          subtitle: Text(timeStr),
        );
      }).toList(),
    );
  }

  // ---------------- ADD TIMELINE ENTRY ----------------

  Future<void> _addTimelineEntry(BuildContext context) async {
    final controller = TextEditingController();
    TimeOfDay selectedTime = TimeOfDay.now();

    final result = await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Add Timeline Entry"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                decoration: const InputDecoration(
                  labelText: "Description",
                ),
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () async {
                  final t = await showTimePicker(
                    context: context,
                    initialTime: selectedTime,
                  );
                  if (t != null) selectedTime = t;
                },
                child: const Text("Pick Time"),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context, {
                  "text": controller.text,
                  "time": selectedTime,
                });
              },
              child: const Text("Add"),
            ),
          ],
        );
      },
    );

    if (result != null) {
      final text = result["text"] as String;
      final time = result["time"] as TimeOfDay;

      final dateTime = DateTime(
        widget.year,
        widget.month,
        widget.day,
        time.hour,
        time.minute,
      );

      homeRepository.addTimelineEntry(
        DateTime(widget.year, widget.month, widget.day),
        TimelineEntry(time: dateTime, text: text),
      );

      setState(() {});
    }
  }

  // ---------------- GPX IMPORT ----------------

  Future<void> _importGpxFile() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['gpx'],
    );

    if (result == null) return;

    final file = File(result.files.single.path!);

    print("Importing GPX file: ${file.path}");

    await homeRepository.importGpx(
      DateTime(widget.year, widget.month, widget.day),
      file,
    );

    final entry = homeRepository.entries.firstWhere(
      (e) =>
          e.date.year == widget.year &&
          e.date.month == widget.month &&
          e.date.day == widget.day,
    );

    print("GPX imported. Track points: ${entry.track.length}");
    print("hasGpx: ${entry.hasGpx}");

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("GPX file imported successfully"),
        duration: Duration(seconds: 2),
      ),
    );

    setState(() {});
  }
}
