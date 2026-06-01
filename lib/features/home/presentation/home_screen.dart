import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

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

  Future<void> _openWeather(BuildContext context) async {
    final url = context.read<ThemeProvider>().weatherUrl;
    if (url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _scrollToSelectedDay() {
    final target = _pendingScrollDate;
    if (target == null) return;
    final key = _dayKeys[_entryKey(target)];
    final ctx = key?.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(ctx,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOut,
        alignment: 0.15);
    _pendingScrollDate = null;
  }


  @override
  Widget build(BuildContext context) {
    final repo = context.watch<HomeRepository>();
    final entries = repo.entries;
    final title = context.watch<ThemeProvider>().logbuchTitle;
    final cs = Theme.of(context).colorScheme;

    final years = entries
        .map((e) => e.date.year)
        .toSet()
        .toList()
      ..sort((a, b) => b.compareTo(a));

    // Never mutate state in build — use a local effective year.
    final effectiveYear = _selectedYear ??
        (years.isNotEmpty ? years.first : null);

    final filtered = ((effectiveYear == null)
            ? [...entries]
            : entries.where((e) => e.date.year == effectiveYear).toList())
        .reversed
        .toList();

    WidgetsBinding.instance
        .addPostFrameCallback((_) => _scrollToSelectedDay());

    return Scaffold(
      backgroundColor: cs.surface,
      // ── Dark glass top bar ──────────────────────────────────────
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A3A5C),
        foregroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.anchor, color: cs.tertiaryFixed, size: 20),
            const SizedBox(width: 8),
            Text(
              title.toUpperCase(),
              style: GoogleFonts.newsreader(
                color: cs.tertiaryFixed,
                fontSize: 18,
                fontWeight: FontWeight.w700,
                letterSpacing: 3,
              ),
            ),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(0.5),
          child: Container(
            height: 0.5,
            color: const Color(0xFF2A5080),
          ),
        ),
      ),
      // ── Bottom nav bar ──────────────────────────────────────────
      bottomNavigationBar: AppBottomNav(
        active: NavTab.logbook,
        onSelect: (tab) {
          if (tab == NavTab.maps) context.push('/tracks');
          if (tab == NavTab.weather) _openWeather(context);
          if (tab == NavTab.settings) context.push('/settings');
        },
      ),
      // ── FAB: circle with gold border ────────────────────────────
      floatingActionButton: FloatingActionButton(
        onPressed: _createNewEntry,
        tooltip: 'Neuen Tag hinzufügen',
        backgroundColor: cs.primary,
        foregroundColor: cs.onPrimary,
        shape: CircleBorder(
          side: BorderSide(
              color: cs.tertiaryFixedDim, width: 2),
        ),
        child: const Icon(Icons.add),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      body: entries.isEmpty
          ? _buildEmpty(cs)
          : _buildList(filtered, years, effectiveYear, repo, cs),
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

  Widget _buildList(List<DayEntry> filtered, List<int> years,
      int? effectiveYear, HomeRepository repo, ColorScheme cs) {
    return CustomScrollView(
      controller: _scrollController,
      slivers: [
        // ── Year filter pills ─────────────────────────────────────
        SliverToBoxAdapter(child: _buildYearPills(years, effectiveYear, cs)),
        // ── Cards ────────────────────────────────────────────────
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (_, i) => _buildCard(filtered[i], repo, cs),
              childCount: filtered.length,
            ),
          ),
        ),
      ],
    );
  }

  // ── Year pills ─────────────────────────────────────────────────
  Widget _buildYearPills(List<int> years, int? effectiveYear, ColorScheme cs) {
    return Container(
      color: cs.surface,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: years.map((year) {
            final active = year == effectiveYear;
            return Padding(
              padding: const EdgeInsets.only(right: 12),
              child: GestureDetector(
                onTap: () => setState(() => _selectedYear = year),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 12),
                  decoration: BoxDecoration(
                    color: active ? cs.primary : cs.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(50),
                    boxShadow: active
                        ? [
                            BoxShadow(
                              color: cs.primary.withValues(alpha: 0.25),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            )
                          ]
                        : null,
                  ),
                  child: Text(
                    '$year',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                      color: active ? cs.onPrimary : cs.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  // ── Entry card ─────────────────────────────────────────────────
  Widget _buildCard(DayEntry entry, HomeRepository repo, ColorScheme cs) {
    final dayKey =
        DateTime(entry.date.year, entry.date.month, entry.date.day);
    final track = repo.dailyTracks[dayKey];
    DailyStats? stats;
    if (track != null && track.points.isNotEmpty) {
      stats = computeDailyStats(track.points);
    }

    final hasTimeline = entry.timeline.isNotEmpty;
    final key =
        _dayKeys.putIfAbsent(_entryKey(entry.date), () => GlobalKey());
    final dayDateLabel = DateFormat('EEEE, d. MMMM', 'de_CH').format(entry.date);
    final routeLabel = [
      if (entry.fromHarbor?.isNotEmpty ?? false) entry.fromHarbor!,
      if (entry.toHarbor?.isNotEmpty ?? false) entry.toHarbor!,
    ].join(' → ');

    // Empty entry: dashed border, no accent, italic
    if (!hasTimeline && stats == null) {
      return Padding(
        key: key,
        padding: const EdgeInsets.only(bottom: 12),
        child: GestureDetector(
          onTap: () => context.push(
              '/day/${entry.date.year}/${entry.date.month}/${entry.date.day}'),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cs.surfaceContainerLow,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: cs.outlineVariant.withValues(alpha: 0.5),
                  width: 1,
                  style: BorderStyle.solid),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        dayDateLabel,
                        style: GoogleFonts.newsreader(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Kein Eintrag',
                        style: GoogleFonts.inter(
                          fontSize: 15,
                          fontStyle: FontStyle.italic,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.anchor, color: cs.outlineVariant, size: 22),
              ],
            ),
          ),
        ),
      );
    }

    // Active card: seafoam left accent, shadow, watermark
    final hasRoute = (entry.fromHarbor?.isNotEmpty ?? false) ||
        (entry.toHarbor?.isNotEmpty ?? false);
    return Container(
      key: key,
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: cs.outlineVariant.withValues(alpha: 0.3), width: 0.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => context.push(
              '/day/${entry.date.year}/${entry.date.month}/${entry.date.day}'),
          child: IntrinsicHeight(
            child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Seafoam left accent #b7c8de
              Container(
                  width: 4, color: cs.inversePrimary),
              // Main content
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Stack(
                    children: [
                      // Watermark compass icon
                      Positioned(
                        right: -12,
                        bottom: -12,
                        child: Icon(Icons.explore,
                            size: 80,
                            color: cs.primary.withValues(alpha: 0.04)),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  dayDateLabel,
                                  style: GoogleFonts.newsreader(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                    color: cs.primary,
                                  ),
                                ),
                              ),
                              Icon(Icons.sailing,
                                  color: cs.tertiary, size: 22),
                            ],
                          ),
                          if (stats != null) ...[
                            const SizedBox(height: 8),
                            _statPair(Icons.straighten,
                                '${stats.distanceNm.toStringAsFixed(1)} nm',
                                cs),
                          ],
                          if (hasRoute) ...[
                            const SizedBox(height: 4),
                            _statPair(Icons.route, routeLabel, cs),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
            ), // Row
          ), // IntrinsicHeight
        ),
      ),
    );
  }

  Widget _statPair(IconData icon, String label, ColorScheme cs) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20, color: cs.primary),
        const SizedBox(width: 6),
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
            color: cs.onSurface,
          ),
        ),
      ],
    );
  }
}
