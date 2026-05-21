import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';

class DayDetailScreen extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final date = DateTime(year, month, day);
    final weekday = DateFormat('EEEE').format(date);
    final formatted = DateFormat('d MMMM yyyy').format(date);

    return Scaffold(
      appBar: AppBar(
        title: Text("Day $day"),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),

      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // HEADER
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
              ],
            ),
          ),

          const SizedBox(height: 24),

          // MAP PLACEHOLDER
          Container(
            height: 200,
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Center(
              child: Text(
                "Map / GPX Track\n(coming soon)",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
            ),
          ),

          const SizedBox(height: 24),

          // STATISTICS PLACEHOLDER
          Container(
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
          ),

          const SizedBox(height: 24),

          // TIMELINE PLACEHOLDER
          const Text(
            "Timeline",
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 8),

          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              "No timeline entries yet.\nTap + to add notes, weather, events...",
              style: TextStyle(color: Colors.grey),
            ),
          ),

          const SizedBox(height: 80),
        ],
      ),

      floatingActionButton: FloatingActionButton(
        onPressed: () {
          // TODO: Add timeline entry dialog
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}
