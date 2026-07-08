import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../app/route_names.dart';
import '../../../app/theme/theme_extensions.dart';
import '../data/home_repository.dart';
import '../domain/day_entry.dart';
import '../utils/compute_daily_stats.dart';
import '../utils/filter_settings.dart';
import '../widgets/nav_bar.dart';
import '../widgets/stat_inline.dart';
import '../../settings/domain/theme_provider.dart';
import '../../../core/services/gps_consent_service.dart';
import '../../../l10n/l10n_extension.dart';

/// The app's home/landing screen: a year-filterable timeline of day entries,
/// an aggregate stats card (days at sea, total distance), and the FAB for
/// creating a new day or a new timeline entry on the most recent day.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int? _selectedYear;
  bool _showAllYears = false;
  final ScrollController _scrollController = ScrollController();
  final Map<String, GlobalKey> _dayKeys = {};
  DateTime? _pendingScrollDate;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) GpsConsentService.requestIfNeeded(context);
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// Prompts for a date (excluding ones that already have an entry), creates
  /// the entry, and navigates to its day-detail screen.
  Future<void> _createNewEntry() async {
    final repo = context.read<HomeRepository>();
    final now = DateTime.now();

    final existing = repo.entries
        .map((e) => DateTime(e.date.year, e.date.month, e.date.day))
        .toSet();

    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      selectableDayPredicate: (date) =>
          !existing.contains(DateTime(date.year, date.month, date.day)),
    );
    if (picked == null) return;

    repo.addEntry(picked);
    if (!mounted) return;

    setState(() {
      _selectedYear = picked.year;
      _pendingScrollDate = picked;
    });
    GoRouter.of(context).pushNamed(AppRoute.dayDetail, pathParameters: {
      'year': '${picked.year}',
      'month': '${picked.month}',
      'day': '${picked.day}',
    });
  }

  /// Navigates to the most recent day's detail screen with its add-entry
  /// dialog open, or falls back to [_createNewEntry] if there are no entries yet.
  void _createTimelineEntry() {
    final entries = context.read<HomeRepository>().entries;
    if (entries.isEmpty) {
      _createNewEntry();
      return;
    }
    final recent = entries.last;
    context.pushNamed(
      AppRoute.dayDetail,
      pathParameters: {
        'year': '${recent.date.year}',
        'month': '${recent.date.month}',
        'day': '${recent.date.day}',
      },
      queryParameters: const {'addEntry': '1'},
    );
  }

  /// Shows the FAB's two-option popup ("new day" / "add entry") as a
  /// custom slide-up dialog rather than a stock menu, to match the design
  /// spec's pill-button styling.
  void _showAddMenu() {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: '',
      barrierColor: Colors.black.withValues(alpha: 0.4),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (ctx, _, _) {
        final cs = Theme.of(ctx).colorScheme;
        return Material(
          type: MaterialType.transparency,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: EdgeInsets.only(
                bottom: AppBottomNav.totalHeight(context) + 8,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _menuPill(cs, Icons.calendar_today, ctx.l10n.homeNewDay, () {
                    Navigator.of(ctx).pop();
                    _createNewEntry();
                  }),
                  const SizedBox(height: 12),
                  _menuPill(cs, Icons.edit_square, ctx.l10n.homeAddEntry, () {
                    Navigator.of(ctx).pop();
                    _createTimelineEntry();
                  }),
                ],
              ),
            ),
          ),
        );
      },
      transitionBuilder: (ctx, anim, _, child) => FadeTransition(
        opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.12),
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOut)),
          child: child,
        ),
      ),
    );
  }

  /// One rounded pill button in the FAB's add-menu popup.
  Widget _menuPill(
      ColorScheme cs, IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 220,
        padding:
            const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        decoration: BoxDecoration(
          color: cs.primaryContainer,
          borderRadius: BorderRadius.circular(999),
          border:
              Border.all(color: cs.outline.withValues(alpha: 0.2)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: cs.onPrimaryContainer, size: 20),
            const SizedBox(width: 12),
            Text(
              label,
              style: Theme.of(context).textTheme.bodyLarge!.copyWith(fontSize: 15, fontWeight: FontWeight.w500, color: cs.onPrimaryContainer),
            ),
          ],
        ),
      ),
    );
  }

  /// Lookup key for [_dayKeys], identifying one day's timeline card.
  String _entryKey(DateTime date) =>
      '${date.year}-${date.month}-${date.day}';

  /// Scrolls the just-created/navigated-to day into view, if one is pending
  /// (set by [_createNewEntry]). Called on every frame via a post-frame
  /// callback since the target day's GlobalKey isn't attached until its
  /// widget has actually been laid out.
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

  /// Distinct weather icons to show on a day's timeline card, inferred by
  /// keyword-matching each timeline entry's free-text weather field
  /// (German and English keywords both supported).
  List<IconData> _weatherIcons(List<dynamic> timeline) {
    final seen = <IconData>{};
    for (final tl in timeline) {
      final raw = tl.weather as String?;
      if (raw == null || raw.isEmpty) continue;
      final w = raw.toLowerCase();
      if (w.contains('sonn') || w.contains('klar') || w.contains('sun')) {
        seen.add(Icons.wb_sunny);
      }
      if (w.contains('regen') || w.contains('rain')) {
        seen.add(Icons.water_drop_outlined);
      }
      if (w.contains('wolke') || w.contains('bewölkt') || w.contains('cloud')) {
        seen.add(Icons.cloud_outlined);
      }
      if (w.contains('sturm') || w.contains('storm')) {
        seen.add(Icons.air);
      }
    }
    return seen.toList();
  }

  // Returns the highest wind speed in knots across all timeline entries, or null.
  int? _maxWindKnots(List<dynamic> timeline) {
    int? max;
    for (final tl in timeline) {
      final raw = tl.wind as String?;
      if (raw == null || raw.isEmpty) continue;
      final match = RegExp(r'\d+').firstMatch(raw);
      if (match == null) continue;
      final knots = int.tryParse(match.group(0)!);
      if (knots != null && (max == null || knots > max)) max = knots;
    }
    return max;
  }

  @override
  Widget build(BuildContext context) {
    final repo           = context.watch<HomeRepository>();
    final themeProvider  = context.watch<ThemeProvider>();
    final entries        = repo.entries;
    final vesselName     = themeProvider.vesselName;
    final filterSettings = themeProvider.filterSettings;
    final cs             = Theme.of(context).colorScheme;

    final years = entries.map((e) => e.date.year).toSet().toList()
      ..sort((a, b) => b.compareTo(a));

    final effectiveYear = _showAllYears
        ? null
        : (_selectedYear ?? (years.isNotEmpty ? years.first : null));

    // Newest first for the timeline
    final filtered = ((effectiveYear == null)
            ? [...entries]
            : entries.where((e) => e.date.year == effectiveYear).toList())
        .reversed
        .toList();

    // Group by month (order preserved: newest month first)
    final monthKeys = <String>[];
    final grouped = <String, List<DayEntry>>{};
    for (final e in filtered) {
      final key = '${e.date.year}-${e.date.month}';
      if (!grouped.containsKey(key)) monthKeys.add(key);
      grouped.putIfAbsent(key, () => []).add(e);
    }

    // Flat items list: String = month header, DayEntry = day row
    // Only the first (most recent) month is open by default.
    final items = <Object>[];
    for (final monthKey in monthKeys) {
      items.add(monthKey);
      final isFirst = monthKey == monthKeys.first;
      if (themeProvider.getMonthExpanded(monthKey, defaultOpen: isFirst)) {
        items.addAll(grouped[monthKey]!);
      }
    }

    // Aggregate distance: prefer GPS track stats, fall back to DayEntry.distanceNm.
    // Day count includes every logged day regardless of whether it has a track.
    double totalNm = 0;
    final countedDays = <DateTime>{};
    for (final day in repo.dailyTracks.keys) {
      if (effectiveYear != null && day.year != effectiveYear) continue;
      final track = repo.dailyTracks[day]!;
      if (track.points.isEmpty) continue;
      final stats = computeDailyStats(track.points, settings: filterSettings);
      if (stats.distanceNm > 0) {
        totalNm += stats.distanceNm;
        countedDays.add(day);
      }
    }
    for (final e in filtered) {
      final day = DateTime(e.date.year, e.date.month, e.date.day);
      if (countedDays.contains(day)) continue;
      if (e.distanceNm > 0) totalNm += e.distanceNm;
    }
    final daysAtSea = filtered.length;

    WidgetsBinding.instance
        .addPostFrameCallback((_) => _scrollToSelectedDay());

    return Scaffold(
      backgroundColor: cs.surface,
      // ── Light app bar ──────────────────────────────────────────
      appBar: AppBar(
        centerTitle: true, // branded hero title stays centered, unlike the flat/left-aligned default
        automaticallyImplyLeading: false,
        toolbarHeight: 72,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              context.l10n.appTitle.toUpperCase(),
              style: GoogleFonts.newsreader(
                color: cs.primary,
                fontSize: 28,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
                height: 1.0,
              ),
            ),
            if (vesselName.isNotEmpty)
              Text(
                vesselName,
                style: GoogleFonts.newsreader(
                  color: cs.primary,
                  fontSize: 20,
                  fontWeight: FontWeight.w500,
                  fontStyle: FontStyle.italic,
                  height: 1.1,
                ),
              ),
          ],
        ),
      ),
      // ── Bottom nav with raised centre FAB ──────────────────────
      bottomNavigationBar: AppBottomNav(
        active: NavTab.journal,
        onFabTap: _showAddMenu,
        onSelect: (tab) {
          if (tab == NavTab.map) context.pushNamed(AppRoute.tracks);
          if (tab == NavTab.settings) context.pushNamed(AppRoute.settings);
          if (tab == NavTab.safety) context.pushNamed(AppRoute.emergencyManifest);
        },
      ),
      body: Column(
        children: [
          Expanded(
            child: entries.isEmpty
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
                        Row(
                          children: [
                            Text(
                              context.l10n.homeRecentEntries,
                              style: Theme.of(context).textTheme.fieldValueProse.copyWith(color: cs.primary),
                            ),
                            const Spacer(),
                          ],
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
                        final item = items[i];
                        if (item is String) {
                          return _buildMonthHeader(item, item == monthKeys.first, grouped, cs);
                        }
                        final entry = item as DayEntry;
                        final monthKey =
                            '${entry.date.year}-${entry.date.month}';
                        final isLastInGroup =
                            entry == grouped[monthKey]!.last;
                        final isFirst = filtered.isNotEmpty &&
                            entry == filtered.first;
                        final key = _dayKeys.putIfAbsent(
                            _entryKey(entry.date), () => GlobalKey());
                        return _buildTimelineItem(
                          entry, repo, cs,
                          filterSettings: filterSettings,
                          isActive: isFirst,
                          showConnector: !isLastInGroup,
                          itemKey: key,
                        );
                      },
                      childCount: items.length,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Year filter pills ─────────────────────────────────────────────
  /// Horizontally scrollable row of year filter pills, plus an "ALL" pill,
  /// centered when they all fit within the available width.
  Widget _buildYearPills(
      List<int> years, int? effectiveYear, ColorScheme cs) {
    final pillsRow = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => setState(() => _showAllYears = true),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: _showAllYears ? cs.primary : cs.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: _showAllYears ? cs.primary : cs.outlineVariant,
                  ),
                ),
                child: Text(
                  context.l10n.homeAllButton.toUpperCase(),
                  style: Theme.of(context).textTheme.labelSmall!.copyWith(
                    color: _showAllYears ? cs.onPrimary : cs.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
          ...years.map((year) {
          final active = !_showAllYears && year == effectiveYear;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => setState(() { _showAllYears = false; _selectedYear = year; }),
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
                ),
                child: Text(
                  '$year',
                  style: Theme.of(context).textTheme.labelSmall!.copyWith(
                    color:
                        active ? cs.onPrimary : cs.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          );
        }),
      ],
    );
    return LayoutBuilder(builder: (context, constraints) {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: constraints.maxWidth),
          child: Center(child: pillsRow),
        ),
      );
    });
  }

  // ── Stats bento grid ─────────────────────────────────────────────
  /// Two-card row: sailing days and total distance for the current filter.
  Widget _buildStatsBento(
      double totalNm, int daysAtSea, ColorScheme cs) {
    final l10n = context.l10n;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _statCard(
              icon: Icons.sailing,
              iconBg: cs.primaryContainer,
              iconColor: cs.onPrimaryContainer,
              label: l10n.statSailingDays,
              value: '$daysAtSea',
              unit: l10n.statSailingDays,
              cs: cs,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _statCard(
              icon: Icons.straighten,
              iconBg: cs.primaryContainer,
              iconColor: cs.onPrimaryContainer,
              label: l10n.statDistance,
              //value: totalNm.toStringAsFixed(0),
              value: NumberFormat.decimalPattern(context.read<ThemeProvider>().localeString).format(totalNm.round()),
              unit: 'nm',
              cs: cs,
            ),
          ),
        ],
      ),
    );
  }

  /// One icon + label + value/unit card within [_buildStatsBento].
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
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: Icon(icon, color: iconColor, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label.toUpperCase(),
                  style: Theme.of(context).textTheme.labelSmall!.copyWith(fontSize: 10, color: cs.mutedLabel),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                RichText(
                  text: TextSpan(
                    children: [
                      TextSpan(
                        text: value,
                        style: Theme.of(context).textTheme.titleLarge!.copyWith(fontWeight: FontWeight.w500, height: 1.1, color: cs.primary),
                      ),
                      TextSpan(
                        text: ' $unit',
                        style: Theme.of(context).textTheme.bodySmall!.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Month group header ────────────────────────────────────────────
  /// Collapsible section header for one month's group of day entries; shows
  /// an entry-count badge only while collapsed.
  Widget _buildMonthHeader(String monthKey, bool isFirst,
      Map<String, List<DayEntry>> grouped, ColorScheme cs) {
    final parts = monthKey.split('-');
    final dt = DateTime(int.parse(parts[0]), int.parse(parts[1]));
    final tp = context.read<ThemeProvider>();
    final label = DateFormat('MMMM yyyy', tp.localeString).format(dt).toUpperCase();
    final expanded = tp.getMonthExpanded(monthKey, defaultOpen: isFirst);
    final count = grouped[monthKey]!.length;

    return GestureDetector(
      onTap: () => tp.setMonthExpanded(monthKey, !expanded),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(32, 12, 0, 4),
        child: Row(
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall!.copyWith(
                color: cs.secondary,
              ),
            ),
            if (!expanded) ...[
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: cs.secondaryContainer,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$count',
                  style: Theme.of(context).textTheme.labelSmall!.copyWith(fontSize: 10, letterSpacing: 0, color: cs.onSecondaryContainer),
                ),
              ),
            ],
            const Spacer(),
            Icon(
              expanded ? Icons.expand_less : Icons.expand_more,
              size: 18,
              color: cs.secondary,
            ),
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }

  // ── Timeline entry ────────────────────────────────────────────────
  /// One day's card on the home timeline: date/weather line, route (if
  /// harbors are set), a one-line narrative, and moving-average-speed/
  /// distance stats — plus the vertical "spine" connector dot linking it to
  /// adjacent days.
  Widget _buildTimelineItem(
    DayEntry entry,
    HomeRepository repo,
    ColorScheme cs, {
    required FilterSettings filterSettings,
    required bool isActive,
    required bool showConnector,
    Key? itemKey,
  }) {
    final dayKey =
        DateTime(entry.date.year, entry.date.month, entry.date.day);
    final track = repo.dailyTracks[dayKey];
    DailyStats? stats;
    if (track != null && track.points.isNotEmpty) {
      stats = computeDailyStats(track.points, settings: filterSettings);
    }
    final firstTl = entry.timeline.isNotEmpty ? entry.timeline.first : null;
    final note = (entry.notes?.isNotEmpty ?? false)
        ? entry.notes
        : firstTl?.remarks;

    // Stack-based layout: spine is Positioned so the card Column has no tight
    // height constraint (avoids IntrinsicHeight rounding overflows).
    return Stack(
      key: itemKey,
      clipBehavior: Clip.none,
      children: [
        // ── Card (determines Stack height) ──────────────────────
        Padding(
          padding: const EdgeInsets.only(left: 32, bottom: 16),
          child: GestureDetector(
            onTap: () => context.pushNamed(AppRoute.dayDetail, pathParameters: {
                  'year': '${entry.date.year}',
                  'month': '${entry.date.month}',
                  'day': '${entry.date.day}',
                }),
            child: Opacity(
              opacity: isActive ? 1.0 : 0.85,
              child: Container(
                decoration: BoxDecoration(
                  color: isActive
                      ? cs.surfaceContainerLowest
                      : cs.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(12),
                  border: Border(
                    left: BorderSide(
                      color: isActive ? cs.secondaryContainer : cs.outlineVariant,
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
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                        // Line 1: Day · Date + weather icon
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${DateFormat('EEEE', context.read<ThemeProvider>().localeString).format(entry.date).toUpperCase()} · ${DateFormat('d. MMM', context.read<ThemeProvider>().localeString).format(entry.date).toUpperCase()}',
                                style: Theme.of(context).textTheme.labelSmall!.copyWith(
                                  color: cs.mutedLabel,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            ..._weatherIcons(entry.timeline).map((ic) => Padding(
                              padding: const EdgeInsets.only(left: 4),
                              child: Icon(ic, size: 16, color: cs.secondary),
                            )),
                            Builder(builder: (context) {
                              final wind = _maxWindKnots(entry.timeline);
                              if (wind == null || wind <= 5) return const SizedBox.shrink();
                              final strong = wind > 20;
                              return Padding(
                                padding: const EdgeInsets.only(left: 4),
                                child: Icon(
                                  strong ? Icons.storm : Icons.air,
                                  size: 16,
                                  color: cs.secondary,
                                ),
                              );
                            }),
                          ],
                        ),
                        // Line 2: Route (only if harbor info is available)
                        if ((entry.fromHarbor?.isNotEmpty ?? false) ||
                            (entry.toHarbor?.isNotEmpty ?? false)) ...[
                          const SizedBox(height: 3),
                          Text(
                            [
                              if (entry.fromHarbor?.isNotEmpty ?? false)
                                entry.fromHarbor!,
                              if (entry.toHarbor?.isNotEmpty ?? false)
                                entry.toHarbor!,
                            ].join(' → '),
                            style: Theme.of(context).textTheme.bodyMedium!.copyWith(fontWeight: FontWeight.w600, color: isActive ? cs.primary : cs.onSurfaceVariant),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        // Line 3: Narrative
                        if (note?.isNotEmpty == true) ...[
                          const SizedBox(height: 2),
                          Text(
                            note!,
                            style: Theme.of(context).textTheme.bodySmall!.copyWith(
                              fontStyle: FontStyle.italic,
                              color: cs.onSurfaceVariant,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        // Line 4: Stats (average speed + distance)
                        if (stats != null &&
                            (stats.avgMakingWayKn > 0 ||
                                stats.distanceNm > 0)) ...[
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 10,
                            runSpacing: 2,
                            children: [
                              if (stats.avgMakingWayKn > 0)
                                statInline(context, 
                                  Icons.speed,
                                  // Moving average, not distance/total-elapsed-time —
                                  // avgSpeed (avgOverGroundKn) would be diluted by any
                                  // stop in the middle of the track.
                                  '${stats.avgMakingWayKn.toStringAsFixed(1)} kn',
                                  cs,
                                ),
                              if (stats.distanceNm > 0)
                                statInline(context, 
                                  Icons.straighten,
                                  '${stats.distanceNm.toStringAsFixed(1)} nm',
                                  cs,
                                ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
        // ── end card ──
        // ── Spine (Positioned overlay, fills card height) ────────
        Positioned(
          left: 0,
          top: 0,
          bottom: 16,
          width: 24,
          child: Column(
            children: [
              const SizedBox(height: 8),
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: cs.surfaceContainerLowest,
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
              if (showConnector)
                Expanded(
                  child: Center(
                    child: Container(width: 2, color: cs.outlineVariant),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  /// Placeholder shown when the logbook has no entries at all yet.
  Widget _buildEmpty(ColorScheme cs) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.anchor_outlined, size: 48, color: cs.outlineVariant),
          const SizedBox(height: 12),
          Text(context.l10n.homeEmpty,
              style: Theme.of(context).textTheme.bodyLarge),
        ],
      ),
    );
  }
}
