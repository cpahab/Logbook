import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../data/home_repository.dart';
import '../domain/day_entry.dart';
import '../utils/compute_daily_stats.dart';
import '../widgets/nav_bar.dart';
import '../../settings/domain/theme_provider.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int? _selectedYear;
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
    if (!exists) repo.addEntry(picked);
    if (!mounted) return;

    setState(() {
      _selectedYear = picked.year;
      _pendingScrollDate = picked;
    });
    GoRouter.of(context)
        .push('/day/${picked.year}/${picked.month}/${picked.day}');
  }

  String _entryKey(DateTime date) =>
      '${date.year}-${date.month}-${date.day}';

  void _scrollToSelectedDay() {
    final target = _pendingScrollDate;
    if (target == null) return;
    final ctx = _dayKeys[_entryKey(target)]?.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(ctx,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOut,
        alignment: 0.15);
    _pendingScrollDate = null;
  }

  String _entryTitle(DayEntry entry) {
    final from = entry.fromHarbor;
    final to = entry.toHarbor;
    if ((from?.isNotEmpty ?? false) && (to?.isNotEmpty ?? false)) {
      return '$from → $to';
    }
    if (from?.isNotEmpty ?? false) return from!;
    if (to?.isNotEmpty ?? false) return to!;
    return DateFormat('EEEE', 'de_CH').format(entry.date);
  }

  IconData _weatherIcon(String? weather) {
    if (weather == null) return Icons.wb_sunny_outlined;
    final w = weather.toLowerCase();
    if (w.contains('sonn') || w.contains('klar') || w.contains('sun')) {
      return Icons.wb_sunny;
    }
    if (w.contains('regen') || w.contains('rain')) return Icons.water_drop_outlined;
    if (w.contains('wolke') || w.contains('bewölkt') || w.contains('cloud')) {
      return Icons.cloud_outlined;
    }
    if (w.contains('wind') || w.contains('sturm') || w.contains('storm')) {
      return Icons.air;
    }
    return Icons.wb_sunny_outlined;
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<HomeRepository>();
    final entries = repo.entries;
    final title = context.watch<ThemeProvider>().logbuchTitle;
    final cs = Theme.of(context).colorScheme;

    final years = entries.map((e) => e.date.year).toSet().toList()
      ..sort((a, b) => b.compareTo(a));

    final effectiveYear =
        _selectedYear ?? (years.isNotEmpty ? years.first : null);

    // Newest first for the timeline
    final filtered = ((effectiveYear == null)
            ? [...entries]
            : entries.where((e) => e.date.year == effectiveYear).toList())
        .reversed
        .toList();

    // Aggregate stats for selected year
    double totalNm = 0;
    int daysAtSea = 0;
    for (final entry in filtered) {
      final track = repo.dailyTracks[
          DateTime(entry.date.year, entry.date.month, entry.date.day)];
      if (track != null && track.points.isNotEmpty) {
        totalNm += computeDailyStats(track.points).distanceNm;
        daysAtSea++;
      }
    }

    WidgetsBinding.instance
        .addPostFrameCallback((_) => _scrollToSelectedDay());

    return Scaffold(
      backgroundColor: cs.surface,
      // ── Light app bar ──────────────────────────────────────────
      appBar: AppBar(
        backgroundColor: cs.surface,
        foregroundColor: cs.primary,
        elevation: 0,
        scrolledUnderElevation: 1,
        shadowColor: Colors.black12,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.menu),
          tooltip: 'Einstellungen',
          onPressed: () => context.push('/settings'),
        ),
        title: Text(
          title.toUpperCase(),
          style: GoogleFonts.newsreader(
            color: cs.primary,
            fontSize: 22,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.account_circle_outlined),
            tooltip: 'Einstellungen',
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      // ── FAB: navy circle with gold border ──────────────────────
      floatingActionButton: FloatingActionButton(
        onPressed: _createNewEntry,
        tooltip: 'Neuen Tag hinzufügen',
        backgroundColor: cs.primary,
        foregroundColor: cs.onPrimary,
        elevation: 8,
        shape: CircleBorder(
          side: BorderSide(color: cs.secondaryFixed, width: 2),
        ),
        child: const Icon(Icons.add, size: 28),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      // ── Bottom nav ─────────────────────────────────────────────
      bottomNavigationBar: AppBottomNav(
        active: NavTab.journal,
        onSelect: (tab) {
          if (tab == NavTab.map) context.push('/tracks');
          if (tab == NavTab.settings) context.push('/settings');
        },
      ),
      body: entries.isEmpty
          ? _buildEmpty(cs)
          : CustomScrollView(
              controller: _scrollController,
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildYearPills(years, effectiveYear, cs),
                        const SizedBox(height: 20),
                        if (filtered.isNotEmpty) ...[
                          _buildStatsBento(totalNm, daysAtSea, cs),
                          const SizedBox(height: 24),
                        ],
                        Text(
                          'Einträge',
                          style: GoogleFonts.newsreader(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: cs.primary,
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (_, i) {
                        final key = _dayKeys.putIfAbsent(
                            _entryKey(filtered[i].date), () => GlobalKey());
                        return _buildTimelineItem(
                            filtered[i], i, filtered.length, repo, cs,
                            itemKey: key);
                      },
                      childCount: filtered.length,
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  // ── Year filter pills ─────────────────────────────────────────────
  Widget _buildYearPills(
      List<int> years, int? effectiveYear, ColorScheme cs) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: years.map((year) {
          final active = year == effectiveYear;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => setState(() => _selectedYear = year),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: active
                      ? cs.primary
                      : cs.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: active ? cs.primary : cs.outlineVariant,
                  ),
                  boxShadow: active
                      ? [
                          BoxShadow(
                            color: cs.primary.withValues(alpha: 0.25),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                          // ring-1 ring-secondary-fixed/30
                          BoxShadow(
                            color: cs.secondaryFixed.withValues(alpha: 0.30),
                            blurRadius: 0,
                            spreadRadius: 1.5,
                          ),
                        ]
                      : null,
                ),
                child: Text(
                  '$year',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5,
                    color:
                        active ? cs.onPrimary : cs.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── Stats bento grid ─────────────────────────────────────────────
  Widget _buildStatsBento(
      double totalNm, int daysAtSea, ColorScheme cs) {
    return Row(
      children: [
        Expanded(
          child: _statCard(
            icon: Icons.straighten,
            iconBg: cs.primaryContainer,
            iconColor: const Color(0xFF87A4CC),
            label: 'Distanz',
            value: totalNm >= 1000
                ? '${(totalNm / 1000).toStringAsFixed(1)}k'
                : totalNm.toStringAsFixed(0),
            unit: 'nm',
            cs: cs,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _statCard(
            icon: Icons.calendar_today,
            iconBg: cs.secondaryContainer,
            iconColor: cs.onSecondaryContainer,
            label: 'Seetage',
            value: '$daysAtSea',
            unit: 'Tage',
            cs: cs,
          ),
        ),
      ],
    );
  }

  Widget _statCard({
    required IconData icon,
    required Color iconBg,
    required Color iconColor,
    required String label,
    required String value,
    required String unit,
    required ColorScheme cs,
  }) {
    return Container(
      height: 128,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Icon box — rounded-lg per spec
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: Icon(icon, color: iconColor, size: 18),
          ),
          const Spacer(),
          Text(
            label.toUpperCase(),
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.5,
              color: cs.outline,
            ),
          ),
          const SizedBox(height: 2),
          RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: value,
                  style: GoogleFonts.newsreader(
                    fontSize: 24,
                    fontWeight: FontWeight.w500,
                    color: cs.primary,
                    height: 1.1,
                  ),
                ),
                TextSpan(
                  text: ' $unit',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Timeline entry ────────────────────────────────────────────────
  Widget _buildTimelineItem(
    DayEntry entry,
    int index,
    int total,
    HomeRepository repo,
    ColorScheme cs, {
    Key? itemKey,
  }) {
    final isActive = index == 0; // most recent = active
    final dayKey =
        DateTime(entry.date.year, entry.date.month, entry.date.day);
    final track = repo.dailyTracks[dayKey];
    DailyStats? stats;
    if (track != null && track.points.isNotEmpty) {
      stats = computeDailyStats(track.points);
    }
    final firstTl = entry.timeline.isNotEmpty ? entry.timeline.first : null;
    final note = (entry.notes?.isNotEmpty ?? false)
        ? entry.notes
        : firstTl?.remarks;

    return IntrinsicHeight(
      key: itemKey,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Node + spine ────────────────────────────────────────
          SizedBox(
            width: 24,
            child: Column(
              children: [
                const SizedBox(height: 8),
                Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                    border: Border.all(
                      color: isActive ? cs.primary : cs.outlineVariant,
                      width: 2,
                    ),
                  ),
                  child: Center(
                    child: Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isActive ? cs.primary : cs.outlineVariant,
                      ),
                    ),
                  ),
                ),
                if (index < total - 1)
                  Expanded(
                    child: Center(
                      child: Container(width: 2, color: cs.outlineVariant),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // ── Card ────────────────────────────────────────────────
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: GestureDetector(
                onTap: () => context.push(
                    '/day/${entry.date.year}/${entry.date.month}/${entry.date.day}'),
                child: Opacity(
                  opacity: isActive
                      ? 1.0
                      : (index == 1 ? 0.9 : 0.8),
                  child: Container(
                    decoration: BoxDecoration(
                      color: isActive
                          ? cs.surfaceContainerLowest
                          : cs.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(12),
                      border: Border(
                        left: BorderSide(
                          color: isActive
                              ? cs.secondaryFixed
                              : cs.outlineVariant,
                          width: 4,
                        ),
                      ),
                      boxShadow: isActive
                          ? [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.05),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ]
                          : null,
                    ),
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Date + weather icon
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                DateFormat('d. MMM yyyy', 'de_CH')
                                    .format(entry.date)
                                    .toUpperCase(),
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1.5,
                                  color: cs.outline,
                                ),
                              ),
                            ),
                            Icon(
                              _weatherIcon(firstTl?.weather),
                              size: 20,
                              color: isActive
                                  ? cs.secondary
                                  : cs.outline,
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        // Route title
                        Text(
                          _entryTitle(entry),
                          style: GoogleFonts.inter(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: isActive
                                ? cs.primary
                                : cs.onSurfaceVariant,
                          ),
                        ),
                        // Italic note
                        if (note?.isNotEmpty ?? false) ...[
                          const SizedBox(height: 2),
                          Text(
                            note!,
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontStyle: FontStyle.italic,
                              color: cs.onSurfaceVariant,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        // Data chips — only for the most recent active entry
                        if (isActive) ...[
                          if (stats != null ||
                              firstTl?.course != null ||
                              firstTl?.wind != null) ...[
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                if (stats != null &&
                                    stats.distanceNm > 0)
                                  _chip(
                                    Icons.straighten,
                                    '${stats.distanceNm.toStringAsFixed(1)} nm',
                                    cs,
                                  ),
                                if (stats != null && stats.maxSpeed > 0)
                                  _chip(
                                    Icons.speed,
                                    '${stats.maxSpeed.toStringAsFixed(1)} kn',
                                    cs,
                                  ),
                                if (firstTl?.course != null)
                                  _chip(
                                    Icons.navigation,
                                    '${firstTl!.course!.toStringAsFixed(0)}°',
                                    cs,
                                  ),
                                if (firstTl?.wind?.isNotEmpty ?? false)
                                  _chip(
                                    Icons.air,
                                    firstTl!.wind!,
                                    cs,
                                  ),
                              ],
                            ),
                          ],
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

  Widget _chip(IconData icon, String label, ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: cs.onSurface),
          const SizedBox(width: 4),
          Text(
            label.toUpperCase(),
            style: GoogleFonts.inter(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.0,
              color: cs.primary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty(ColorScheme cs) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.anchor_outlined, size: 48, color: cs.outlineVariant),
          const SizedBox(height: 12),
          Text('Logbuch ist leer',
              style: Theme.of(context).textTheme.bodyLarge),
        ],
      ),
    );
  }
}
