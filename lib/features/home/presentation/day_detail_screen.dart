import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
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
    final homeRepository = context.watch<HomeRepository>();
    homeRepository.addEntry(DateTime(widget.year, widget.month, widget.day)); // Ensure entry exists
    final entry = homeRepository.entries.firstWhere(
      (e) =>
          e.date.year == widget.year &&
          e.date.month == widget.month &&
          e.date.day == widget.day,
      orElse: () => DayEntry.empty(
        DateTime(widget.year, widget.month, widget.day),
      ),
    );

    final date = DateTime(widget.year, widget.month, widget.day);
    final formatted = DateFormat('d MMMM yyyy').format(date);
    final weekday = DateFormat('EEEE').format(date);

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
            _buildStatisticsPlaceholder(entry),
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
        height: 300,
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

    final points = entry.track.map((p) => LatLng(p.lat, p.lon)).toList();
    final bounds = LatLngBounds.fromPoints(points);

    return SizedBox(
      height: 300,
      child: FlutterMap(
        options: MapOptions(
          initialCameraFit: CameraFit.bounds(
            bounds: bounds,
            padding: const EdgeInsets.all(20),
          ),
        ),
        children: [
          TileLayer(
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

  // ---------------- STATISTICS ----------------

  Widget _buildStatisticsPlaceholder(DayEntry entry) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Daily Summary",
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text("• Distance: ${entry.distanceNm.toStringAsFixed(1)} NM"),
          Text("• Total: ${_formatDuration(entry.totalDuration)}"),
          Text("• Moving: ${_formatDuration(entry.movingDuration)}"),
          Text("• Avg speed: ${entry.avgSpeedKnots.toStringAsFixed(1)} kn"),
          Text("• Max speed: ${entry.maxSpeedKnots.toStringAsFixed(1)} kn"),
        ],
      ),
    );
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    return "${h}h ${m}m";
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

        final List<String> details = [];

        if (t.course != null) details.add("Course: ${t.course}°");
        if (t.speed != null) details.add("Speed: ${t.speed} kn");
        if (t.wind != null) details.add("Wind: ${t.wind}");
        if (t.sea != null) details.add("Sea: ${t.sea}");

        final detailStr = details.join(" • ");

        return ListTile(
          leading: const Icon(Icons.circle, size: 12, color: Colors.blue),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (detailStr.isNotEmpty)
                Text(detailStr, style: const TextStyle(fontSize: 14)),
              if (t.remarks != null)
                Text(t.remarks!, style: const TextStyle(fontSize: 14)),
            ],
          ),
          subtitle: Text(timeStr),
        );
      }).toList(),
    );
  }


  // ---------------- ADD TIMELINE ENTRY ----------------

  Future<void> _addTimelineEntry(BuildContext context) async {
    final homeRepository = context.read<HomeRepository>();

    final remarksController = TextEditingController();
    final courseController = TextEditingController();
    final speedController = TextEditingController();
    final windController = TextEditingController();
    final seaController = TextEditingController();

    TimeOfDay selectedTime = TimeOfDay.now();

    final result = await showDialog<Map<String, dynamic>?>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Add Timeline Entry"),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Time picker
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

                const SizedBox(height: 12),

                // Course
                TextField(
                  controller: courseController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: "Course (°)",
                  ),
                ),

                // Speed
                TextField(
                  controller: speedController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: "Speed (kn)",
                  ),
                ),

                // Wind
                TextField(
                  controller: windController,
                  decoration: const InputDecoration(
                    labelText: "Wind",
                  ),
                ),

                // Sea
                TextField(
                  controller: seaController,
                  decoration: const InputDecoration(
                    labelText: "Sea",
                  ),
                ),

                const SizedBox(height: 12),

                // Remarks (last field)
                TextField(
                  controller: remarksController,
                  decoration: const InputDecoration(
                    labelText: "Remarks",
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context, {
                  "time": selectedTime,
                  "course": courseController.text,
                  "speed": speedController.text,
                  "wind": windController.text,
                  "sea": seaController.text,
                  "remarks": remarksController.text,
                });
              },
              child: const Text("Add"),
            ),
          ],
        );
      },
    );

    if (result == null) return;

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
      TimelineEntry(
        time: dateTime,
        course: double.tryParse(result["course"] ?? ""),
        speed: double.tryParse(result["speed"] ?? ""),
        wind: (result["wind"] as String).isEmpty ? null : result["wind"],
        sea: (result["sea"] as String).isEmpty ? null : result["sea"],
        remarks: (result["remarks"] as String).isEmpty ? null : result["remarks"],
      ),
    );

    setState(() {});
  }

  // ---------------- GPX IMPORT ----------------

  Future<void> _importGpxFile() async {
    final homeRepository = context.read<HomeRepository>();

    //final result = await FilePicker.pickFiles(
     // type: FileType.custom,
      //allowedExtensions: ['gpx'],
    //);
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['gpx'],
      allowMultiple: false,
      withData: false,
      withReadStream: false,
      lockParentWindow: true,
    );

    if (result == null) return;

    final file = File(result.files.single.path!);

    await homeRepository.importGpx(
      DateTime(widget.year, widget.month, widget.day),
      file,
    );

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("GPX file imported successfully"),
        duration: Duration(seconds: 2),
      ),
    );

    setState(() {});
  }
}
