import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../data/home_repository.dart';
import '../domain/day_entry.dart';
import 'package:my_app/app.dart';


class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // Track expanded years and months
  final Set<int> expandedYears = {};
  final Map<int, Set<int>> expandedMonths = {};

  Future<void> _createNewEntry() async {
    final repo = context.read<HomeRepository>();
    final now = DateTime.now();

    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );

    if (picked == null) return;

    final exists = repo.entries.any((e) =>
        e.date.year == picked.year &&
        e.date.month == picked.month &&
        e.date.day == picked.day);

    if (!exists) {
      repo.addEntry(picked);
    }

    // Auto-expand year + month
    expandedYears.add(picked.year);
    expandedMonths.putIfAbsent(picked.year, () => {}).add(picked.month);

    // ⭐ Correct navigation
    final router = GoRouter.of(context);
    router.push('/day/${picked.year}/${picked.month}/${picked.day}');
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<HomeRepository>();
    final entries = repo.entries;

    // ⭐ Capture router from the correct context
    final router = GoRouter.of(context);

    if (entries.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text("Logbook")),
        floatingActionButton: FloatingActionButton(
          onPressed: _createNewEntry,
          child: const Icon(Icons.add),
        ),
        body: const Center(
          child: Text(
            "Your logbook is empty",
            style: TextStyle(fontSize: 18),
          ),
        ),
      );
    }

    final grouped = _groupEntries(entries);

    return Scaffold(
      appBar: AppBar(title: const Text("Logbook")),
      floatingActionButton: FloatingActionButton(
        onPressed: _createNewEntry,
        child: const Icon(Icons.add),
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: _buildYearMonthDayList(grouped, router),
      ),
    );
  }

  Map<int, Map<int, List<DayEntry>>> _groupEntries(List<DayEntry> entries) {
    final Map<int, Map<int, List<DayEntry>>> grouped = {};

    for (final entry in entries) {
      final y = entry.date.year;
      final m = entry.date.month;

      grouped.putIfAbsent(y, () => {});
      grouped[y]!.putIfAbsent(m, () => []);
      grouped[y]![m]!.add(entry);
    }

    // Sort days
    for (final year in grouped.keys) {
      for (final month in grouped[year]!.keys) {
        grouped[year]![month]!.sort((a, b) => a.date.day.compareTo(b.date.day));
      }
    }

    return grouped;
  }

  List<Widget> _buildYearMonthDayList(
    Map<int, Map<int, List<DayEntry>>> grouped,
    GoRouter router,
  ) {
    final years = grouped.keys.toList()..sort((a, b) => b.compareTo(a));

    return years.map((year) {
      final months = grouped[year]!.keys.toList()..sort();

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // YEAR HEADER
          ListTile(
            title: Text(
              "$year",
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            trailing: Icon(
              expandedYears.contains(year)
                  ? Icons.expand_less
                  : Icons.expand_more,
            ),
            onTap: () {
              setState(() {
                if (expandedYears.contains(year)) {
                  expandedYears.remove(year);
                } else {
                  expandedYears.add(year);
                }
              });
            },
          ),

          // MONTHS
          if (expandedYears.contains(year))
            ...months.map((month) {
              final isExpanded =
                  expandedMonths[year]?.contains(month) ?? false;

              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 16),
                    child: ListTile(
                      title: Text(_monthName(month)),
                      trailing: Icon(
                        isExpanded
                            ? Icons.expand_less
                            : Icons.expand_more,
                      ),
                      onTap: () {
                        setState(() {
                          expandedMonths.putIfAbsent(year, () => {});
                          if (isExpanded) {
                            expandedMonths[year]!.remove(month);
                          } else {
                            expandedMonths[year]!.add(month);
                          }
                        });
                      },
                    ),
                  ),

                  // DAYS
                  if (isExpanded)
                    ...grouped[year]![month]!.map((entry) {
                      final day = entry.date.day;

                      return Padding(
                        padding: const EdgeInsets.only(left: 32),
                        child: ListTile(
                          title: Text("Day $day"),
                          trailing: const Icon(Icons.chevron_right),

                          // ⭐ Correct navigation using router
                          onTap: () {
                            router.push(
                              "/day/${entry.date.year}/$month/$day",
                            );
                          },
                        ),
                      );
                    }),
                ],
              );
            }),

          const SizedBox(height: 16),
        ],
      );
    }).toList();
  }

  String _monthName(int month) {
    const names = [
      "January","February","March","April","May","June",
      "July","August","September","October","November","December"
    ];
    return names[month - 1];
  }
}
