import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../data/home_repository.dart';
import '../domain/day_entry.dart';
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // Track expanded years and months
  final Set<int> expandedYears = {};
  final Map<int, Set<int>> expandedMonths = {};
  final ScrollController _scrollController = ScrollController();
  final Map<String, GlobalKey> _dayKeys = {};
  DateTime? _pendingScrollDate;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

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

    if (!mounted) return;

    // Auto-expand year + month and scroll to the new entry when returning.
    setState(() {
      expandedYears.add(picked.year);
      expandedMonths.putIfAbsent(picked.year, () => {}).add(picked.month);
      _pendingScrollDate = picked;
    });

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

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToSelectedDay();
    });

    return Scaffold(
      appBar: AppBar(title: const Text("Logbook")),
      floatingActionButton: FloatingActionButton(
        onPressed: _createNewEntry,
        child: const Icon(Icons.add),
      ),
      body: ListView(
        controller: _scrollController,
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

  String _entryKey(DateTime date) => '${date.year}-${date.month}-${date.day}';

  void _scrollToSelectedDay() {
    final targetDate = _pendingScrollDate;
    if (targetDate == null) return;

    final key = _dayKeys[_entryKey(targetDate)];
    final context = key?.currentContext;
    if (context == null) return;

    Scrollable.ensureVisible(
      context,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOut,
      alignment: 0.15,
    );

    _pendingScrollDate = null;
  }

  Widget _buildBadge(int count, BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '$count',
        style: TextStyle(
          color: Theme.of(context).colorScheme.onPrimaryContainer,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  List<Widget> _buildYearMonthDayList(
    Map<int, Map<int, List<DayEntry>>> grouped,
    GoRouter router,
  ) {
    final years = grouped.keys.toList()..sort((a, b) => b.compareTo(a));

    return years.map((year) {
      final months = List.generate(12, (index) => index + 1);
      final totalYearCount = months.fold<int>(
        0,
        (sum, month) => sum + (grouped[year]?[month]?.length ?? 0),
      );
      final yearExpanded = expandedYears.contains(year);

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Material(
            elevation: 2,
            color: Theme.of(context).colorScheme.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            clipBehavior: Clip.antiAlias,
            child: ExpansionTile(
              initiallyExpanded: yearExpanded,
              onExpansionChanged: (expanded) {
                setState(() {
                  if (expanded) {
                    expandedYears.add(year);
                  } else {
                    expandedYears.remove(year);
                  }
                });
              },
              tilePadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              title: Text(
                '$year',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildBadge(totalYearCount, context),
                  const SizedBox(width: 12),
                  Icon(
                    yearExpanded ? Icons.expand_less : Icons.expand_more,
                  ),
                ],
              ),
              children: [
                AnimatedSize(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeInOut,
                  child: Column(
                    children: months.map((month) {
                      final monthEntries = grouped[year]?[month] ?? [];
                      final monthCount = monthEntries.length;
                      final monthExpanded =
                          expandedMonths[year]?.contains(month) ?? false;
                      final disabled = monthCount == 0;

                      return AnimatedOpacity(
                        duration: const Duration(milliseconds: 250),
                        opacity: disabled ? 0.45 : 1.0,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                          child: Material(
                            elevation: 1,
                            color: Theme.of(context).colorScheme.surfaceVariant,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: disabled
                                ? ListTile(
                                    title: Text(
                                      _monthName(month),
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
                                      ),
                                    ),
                                    trailing: _buildBadge(monthCount, context),
                                  )
                                : ExpansionTile(
                                    key: PageStorageKey(
                                        'year-$year-month-$month'),
                                    initiallyExpanded: monthExpanded,
                                    onExpansionChanged: (expanded) {
                                      setState(() {
                                        expandedMonths.putIfAbsent(
                                            year, () => {});
                                        if (expanded) {
                                          expandedMonths[year]!.add(month);
                                        } else {
                                          expandedMonths[year]!.remove(month);
                                        }
                                      });
                                    },
                                    tilePadding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 12,
                                    ),
                                    title: Text(
                                      _monthName(month),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        _buildBadge(monthCount, context),
                                        const SizedBox(width: 10),
                                        Icon(monthExpanded
                                            ? Icons.expand_less
                                            : Icons.expand_more),
                                      ],
                                    ),
                                    children: monthEntries.map((entry) {
                                      final day = entry.date.day;
                                      final key = _dayKeys.putIfAbsent(
                                        _entryKey(entry.date),
                                        () => GlobalKey(),
                                      );

                                      return ListTile(
                                        key: key,
                                        dense: true,
                                        title: Text('Day $day'),
                                        trailing:
                                            const Icon(Icons.chevron_right),
                                        onTap: () {
                                          router.push(
                                            '/day/${entry.date.year}/$month/$day',
                                          );
                                        },
                                      );
                                    }).toList(),
                                  ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
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
