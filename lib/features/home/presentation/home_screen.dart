import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';

import '../../../app/route_names.dart';
import '../../../app/theme/theme_extensions.dart';
import '../data/home_repository.dart';
import '../domain/day_entry.dart';
import '../domain/track_point.dart';
import '../widgets/map_capture.dart';
import '../utils/compute_daily_stats.dart';
import '../utils/filter_settings.dart';
import '../utils/pdf_exporter.dart';
import '../utils/photo_service.dart';
import '../utils/trim_track.dart' show TimePrecision;
import '../../tracks/utils/track_computation_cache.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/date_range_picker.dart';
import '../../../core/widgets/nav_bar.dart';
import '../../../core/widgets/progress_snackbar.dart';
import '../../../core/widgets/stat_inline.dart';
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
  DateTimeRange? _customRange;
  bool _exportingRange = false;
  final ScrollController _scrollController = ScrollController();
  final Map<String, GlobalKey> _dayKeys = {};
  DateTime? _pendingScrollDate;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) GpsConsentService.requestIfNeeded(context);
    });
    // The live entries listener alone isn't reliable enough on its own —
    // its underlying stream can go stale while this device was
    // backgrounded — so give every visit to this screen a fresh,
    // lightweight incremental check too. Mirrors EmergencyRepository/
    // ThemeProvider's identical refresh-on-screen-open methods.
    context.read<HomeRepository>().refreshEntries();
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
    final today = DateTime(now.year, now.month, now.day);

    final existing = repo.entries
        .map((e) => DateTime(e.date.year, e.date.month, e.date.day))
        .toSet();

    // showDatePicker requires initialDate to itself satisfy
    // selectableDayPredicate — it throws on open otherwise. Today already
    // having an entry (the common case once you've logged today) doesn't
    // mean there's no valid initial date to show, so search forward for
    // the next selectable day instead of just handing it `now` blindly.
    var initialDate = today;
    while (existing.contains(initialDate) && initialDate.year < 2100) {
      initialDate = initialDate.add(const Duration(days: 1));
    }

    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
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

  /// Shows the system date-range picker and switches the day list's filter
  /// to the picked custom range, clearing the year-pill filter.
  Future<void> _pickDateRange() async {
    final range = await pickDateRange(context, initialRange: _customRange);
    if (range == null || !mounted) return;
    setState(() {
      _customRange = range;
      _showAllYears = false;
    });
  }

  /// The date range to export for the currently active filter — the custom
  /// range if one is picked, the selected year's calendar bounds, or the
  /// earliest-to-latest span of every logged day when "All" is active.
  /// Null only when there are no entries at all.
  DateTimeRange? _effectiveExportRange({
    required DateTimeRange? customRange,
    required int? effectiveYear,
    required List<DayEntry> entries,
  }) {
    if (customRange != null) return customRange;
    if (effectiveYear != null) {
      return DateTimeRange(
        start: DateTime(effectiveYear, 1, 1),
        end: DateTime(effectiveYear, 12, 31),
      );
    }
    if (entries.isEmpty) return null;
    return DateTimeRange(start: entries.first.date, end: entries.last.date);
  }

  /// Shows a short confirmation dialog naming [range] before exporting,
  /// returning true only if the user taps Export.
  Future<bool> _confirmExportRange(DateTimeRange range) async {
    final locale = context.read<ThemeProvider>().localeString;
    final fmt = DateFormat('d. MMM yyyy', locale);
    final rangeStr = '${fmt.format(range.start)} – ${fmt.format(range.end)}';

    return showConfirmDialog(
      context,
      title: context.l10n.homeExportRangeConfirmTitle,
      body: context.l10n.homeExportRangeConfirmBody(rangeStr),
      confirmLabel: context.l10n.homeExportRangeConfirmButton,
    );
  }

  /// Builds a single PDF covering every logged day in [range] (cover page +
  /// one page per day) and opens the share sheet. Runs the whole pipeline —
  /// photo loading, track-image rendering, PDF assembly — behind a progress
  /// snackbar, since it can take real time for a range with many days/photos.
  Future<void> _exportRangePdf(DateTimeRange range) async {
    if (_exportingRange) return;

    final repo = context.read<HomeRepository>();
    final rangeEntries = repo.entries.where((e) {
      final d = DateTime(e.date.year, e.date.month, e.date.day);
      return !d.isBefore(range.start) && !d.isAfter(range.end);
    }).toList(); // repo.entries is already sorted ascending by date

    if (rangeEntries.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.homeExportRangeEmpty)),
      );
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    setState(() => _exportingRange = true);
    showProgressSnackBar(context, context.l10n.homeExportRangeInProgress);

    try {
      final p = context.read<ThemeProvider>();
      final l10n = context.l10n;
      final filterSettings = p.filterSettings;

      final days = <RangeDayInput>[];
      for (final entry in rangeEntries) {
        final day = DateTime(entry.date.year, entry.date.month, entry.date.day);
        final track = repo.dailyTracks[day];
        final cached = track != null && track.points.isNotEmpty
            ? TrackComputationCache.get(
                day: day,
                sourcePoints: track.points,
                settings: filterSettings,
              )
            : null;
        final trackPoints = cached?.display.allPoints() ?? const <TrackPoint>[];
        final stats = cached?.stats;
        final photoBytes = <Uint8List>[];
        for (final path in entry.photos) {
          final file = await PhotoService.localFile(path);
          if (file != null) photoBytes.add(await file.readAsBytes());
        }
        if (!mounted) return;
        // Captured sequentially, one day at a time (not in parallel like the
        // old per-tile network fetches): each capture mounts its own
        // offscreen map widget, and running several concurrently risks tile-
        // fetch contention and murkier settle timing for little benefit in
        // a personal-logbook export that isn't latency-critical.
        final trackImageBytes = trackPoints.length >= 2
            ? await captureTrackMapImage(context,
                points: trackPoints.map((p) => (lat: p.lat, lon: p.lon)).toList(),
                entryPositions: entryMarkerPositions(entry, trackPoints))
            : await capturePositionsMapImage(context, positionedFixes(entry));
        if (!mounted) return;
        days.add(RangeDayInput(
          entry: entry,
          stats: stats,
          trackImageBytes: trackImageBytes,
          photoBytes: photoBytes,
          departureTime:      cached?.display.departureTime,
          departurePrecision: cached?.display.departurePrecision ?? TimePrecision.unknown,
          arrivalTime:        cached?.display.arrivalTime,
          arrivalPrecision:   cached?.display.arrivalPrecision ?? TimePrecision.unknown,
        ));
      }

      final pdfStrings = PdfStrings(
        voyageLog:        l10n.pdfVoyageLog,
        notes:            l10n.pdfNotes,
        date:             l10n.pdfDate,
        distance:         l10n.pdfDistance,
        avgSpeedUnderway: l10n.pdfAvgSpeedUnderway,
        max:              l10n.pdfMax,
        duration:         l10n.pdfDuration,
        statistics:       l10n.pdfStatistics,
        crew:             l10n.pdfCrew,
        skipper:          l10n.pdfSkipper,
        crewMember:       l10n.pdfCrewMember,
        logEntries:       l10n.pdfLogEntries,
        timeCol:          l10n.pdfTimeCol,
        courseCol:        l10n.pdfCourseCol,
        windCol:          l10n.pdfWindCol,
        seaCol:           l10n.pdfSeaCol,
        positionCol:      l10n.pdfPositionCol,
        remarksCol:       l10n.pdfRemarksCol,
        trackMap:         l10n.pdfTrackMap,
        locale:           l10n.pdfLocale,
        generatedOn:      l10n.pdfGeneratedOn,
        crewNoteLabel:    l10n.dataCrewNote,
        skipperLabel:     l10n.labelSkipper,
        oilLabel:         l10n.vesselOilLabel,
        fuelLabel:        l10n.vesselFuelLabel,
        keelLabel:        l10n.entryDialogKeelLabel,
        keelDownLabel:    l10n.vesselKeelDown,
        keelUpLabel:      l10n.vesselKeelUp,
        passageToTemplate:       l10n.pdfPassageTo('\u0000'),
        departureFromTemplate:   l10n.pdfDepartureFrom('\u0000'),
        departureFromAtTemplate: l10n.pdfDepartureFromAt('\u0000', '\u0000'),
        arrivalAtTemplate:       l10n.pdfArrivalAt('\u0000'),
        pageOfTemplate:          l10n.pdfPageOf(-1, -2),
      );

      final bytes = await buildRangeVoyagePdf(
        days:        days,
        logbookName: l10n.appTitle,
        vesselName:  p.vesselName,
        range:       range,
        strings:     pdfStrings,
        equipment:   p.vesselEquipment,
      );

      messenger.hideCurrentSnackBar();
      if (!mounted) return;

      final fmt = DateFormat('yyyy-MM-dd');
      final fileName =
          'logbuch_${fmt.format(range.start)}_${fmt.format(range.end)}.pdf';
      await Printing.sharePdf(bytes: bytes, filename: fileName);

      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(context.l10n.homeExportRangeSuccess)),
      );
    } catch (e, st) {
      if (kDebugMode) debugPrint('_exportRangePdf failed: $e\n$st');
      messenger.hideCurrentSnackBar();
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(context.l10n.homeExportRangeError)),
      );
    } finally {
      if (mounted) setState(() => _exportingRange = false);
    }
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
    final customRange = _customRange;
    final filtered = ((customRange != null)
            ? entries.where((e) {
                final d = DateTime(e.date.year, e.date.month, e.date.day);
                return !d.isBefore(customRange.start) && !d.isAfter(customRange.end);
              }).toList()
            : (effectiveYear == null)
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
      final stats = TrackComputationCache.get(
        day: day,
        sourcePoints: track.points,
        settings: filterSettings,
      ).stats;
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
              style: Theme.of(context).textTheme.brandTitle.copyWith(color: cs.primary),
            ),
            if (vesselName.isNotEmpty)
              Text(
                vesselName,
                style: Theme.of(context).textTheme.brandSubtitle.copyWith(color: cs.primary),
              ),
          ],
        ),
        actions: [
          _exportingRange
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : IconButton(
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  tooltip: context.l10n.homeExportRangeTooltip,
                  color: cs.primary,
                  onPressed: () async {
                    final range = _effectiveExportRange(
                      customRange: customRange,
                      effectiveYear: effectiveYear,
                      entries: entries,
                    );
                    if (range == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(context.l10n.homeExportRangeEmpty)),
                      );
                      return;
                    }
                    if (!await _confirmExportRange(range)) return;
                    if (!context.mounted) return;
                    _exportRangePdf(range);
                  },
                ),
        ],
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
              onTap: () => setState(() {
                _showAllYears = true;
                _customRange  = null;
              }),
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
          final active = _customRange == null && !_showAllYears && year == effectiveYear;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => setState(() {
                _showAllYears = false;
                _selectedYear = year;
                _customRange  = null;
              }),
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
        _buildCustomRangeChip(cs),
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

  /// Trailing pill that opens the date-range picker (mirrors TracksScreen's
  /// "custom" filter chip); once a range is picked it becomes the active
  /// filter and shows the picked dates instead of its default label.
  Widget _buildCustomRangeChip(ColorScheme cs) {
    final active = _customRange != null;
    final fmt = DateFormat('d.M.yy');
    final label = active
        ? '${fmt.format(_customRange!.start)}–${fmt.format(_customRange!.end)}'
        : context.l10n.tracksCustom.toUpperCase();
    return GestureDetector(
      onTap: _pickDateRange,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: active ? cs.primary : cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: active ? cs.primary : cs.outlineVariant,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.date_range,
                size: 13, color: active ? cs.onPrimary : cs.onSurfaceVariant),
            const SizedBox(width: 5),
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall!.copyWith(
                color: active ? cs.onPrimary : cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
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
            color: cs.cardShadowColor,
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
      stats = TrackComputationCache.get(
        day: dayKey,
        sourcePoints: track.points,
        settings: filterSettings,
      ).stats;
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
                                  stats.avgMakingWayKn.toStringAsFixed(1),
                                  cs,
                                  unit: 'kn',
                                ),
                              if (stats.distanceNm > 0)
                                statInline(context,
                                  Icons.straighten,
                                  stats.distanceNm.toStringAsFixed(1),
                                  cs,
                                  unit: 'nm',
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
