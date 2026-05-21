import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../data/home_repository.dart';
import '../domain/day_entry.dart';

class MonthScreen extends StatelessWidget {
  final int month;

  const MonthScreen({super.key, required this.month});

  @override
  Widget build(BuildContext context) {
    final entries = homeRepository.entries;

    // Filter entries for this month
    final monthEntries = entries
        .where((e) => e.date.month == month)
        .toList()
      ..sort((a, b) => a.date.day.compareTo(b.date.day));

    return Scaffold(
      appBar: AppBar(
        title: Text(_monthName(month)),
        centerTitle: true,
      ),

      body: monthEntries.isEmpty
          ? const Center(
              child: Text(
                "No entries for this month",
                style: TextStyle(fontSize: 18, color: Colors.grey),
              ),
            )
          : ListView.builder(
              itemCount: monthEntries.length,
              itemBuilder: (context, index) {
                final entry = monthEntries[index];
                final day = entry.date.day;

                return Card(
                  child: ListTile(
                    title: Text("Day $day"),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      context.go("${AppRoutes.home}/$month/$day");
                    },
                  ),
                );
              },
            ),
    );
  }

  String _monthName(int month) {
    const names = [
      "January","February","March","April","May","June",
      "July","August","September","October","November","December"
    ];
    return names[month - 1];
  }
}
