import 'dart:io';
import 'dart:math' show Point;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/home_repository.dart';
import '../domain/day_entry.dart';
import '../domain/daily_track.dart';
import '../domain/timeline_entry.dart';
import '../domain/track_point.dart';
import '../widgets/add_timeline_entry_dialog.dart';
import '../widgets/nav_bar.dart';
import '../utils/compute_daily_stats.dart';
import '../utils/gpx_parser.dart';
import '../utils/track_correlation.dart';

class _CapitalizeWordsFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    if (newValue.text.isEmpty) return newValue;
    final words = newValue.text.split(' ');
    final capitalized = words
        .map((w) => w.isEmpty ? '' : w[0].toUpperCase() + w.substring(1))
        .join(' ');
    return newValue.copyWith(text: capitalized);
  }
}

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
  final MapController _mapController = MapController();
  TextEditingController? _notesController;
  TextEditingController? _fromHarborController;
  TextEditingController? _toHarborController;
  LatLng? _droppedMarkerLatLng;
  bool _satelliteView = false;
  bool _isMarkerSheetOpen = false;

  static const _controlledItems = [
    'Motoröl geprüft',
    'Benzin geprüft',
    'Sicherheitsausrüstung kontrolliert',
  ];

  @override
  void dispose() {
    _notesController?.dispose();
    _fromHarborController?.dispose();
    _toHarborController?.dispose();
    super.dispose();
  }

  // ── Helpers ──────────────────────────────────────────────────────
  String _routeTitle(DayEntry entry) {
    final from = entry.fromHarbor;
    final to = entry.toHarbor;
    if ((from?.isNotEmpty ?? false) && (to?.isNotEmpty ?? false)) {
      return '$from → $to';
    }
    if (from?.isNotEmpty ?? false) return from!;
    if (to?.isNotEmpty ?? false) return to!;
    return DateFormat('EEEE', 'de_CH')
        .format(DateTime(widget.year, widget.month, widget.day));
  }

  String? _timeRange(DayEntry entry, DailyTrack? track) {
    DateTime? start, end;
    if (track != null && track.points.isNotEmpty) {
      start = track.points.first.time.toLocal();
      end = track.points.last.time.toLocal();
    } else if (entry.timeline.isNotEmpty) {
      start = entry.timeline.first.time;
      end = entry.timeline.last.time;
    }
    if (start == null) return null;
    final fmt = DateFormat('HH:mm');
    if (end == null || start == end) return fmt.format(start);
    return '${fmt.format(start)} – ${fmt.format(end)}';
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    return '${h}h ${m}m';
  }

  // ── Build ─────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final repo = context.watch<HomeRepository>();
    final day = DateTime(widget.year, widget.month, widget.day);
    final entry = repo.getEntry(day);
    final track = repo.dailyTracks[day];

    DailyStats? stats;
    if (track != null && track.points.isNotEmpty) {
      stats = computeDailyStats(track.points);
    }

    final entries = repo.entries;
    final currentIndex = entries.indexWhere(
      (e) =>
          e.date.year == widget.year &&
          e.date.month == widget.month &&
          e.date.day == widget.day,
    );
    final prevEntry = currentIndex > 0 ? entries[currentIndex - 1] : null;
    final nextEntry =
        currentIndex >= 0 && currentIndex < entries.length - 1
            ? entries[currentIndex + 1]
            : null;

    void goToDay(DateTime d) =>
        context.pushReplacement('/day/${d.year}/${d.month}/${d.day}');

    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      // ── App bar: light surface, back + title + options ───────────
      appBar: AppBar(
        backgroundColor: cs.surface,
        foregroundColor: cs.primary,
        elevation: 0,
        scrolledUnderElevation: 1,
        shadowColor: Colors.black12,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/'),
        ),
        title: entry == null
            ? null
            : Text(
                _routeTitle(entry),
                style: GoogleFonts.newsreader(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: cs.primary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
        actions: [
          if (prevEntry != null)
            IconButton(
              icon: const Icon(Icons.chevron_left),
              onPressed: () => goToDay(prevEntry.date),
              tooltip: 'Vorheriger Tag',
            ),
          if (nextEntry != null)
            IconButton(
              icon: const Icon(Icons.chevron_right),
              onPressed: () => goToDay(nextEntry.date),
              tooltip: 'Nächster Tag',
            ),
          PopupMenuButton<String>(
            tooltip: 'Optionen',
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              if (value == 'import_gpx') _importGpx();
              if (value == 'delete_gpx') _removeGpx();
              if (value == 'delete_day') _deleteDay();
            },
            itemBuilder: (context) => [
              PopupMenuItem<String>(
                value: 'import_gpx',
                child: Row(children: [
                  _gpxUploadIcon(),
                  const SizedBox(width: 12),
                  const Text('GPX importieren'),
                ]),
              ),
              if (track != null)
                PopupMenuItem<String>(
                  value: 'delete_gpx',
                  child: Row(children: [
                    Icon(Icons.delete_outline, color: cs.error),
                    const SizedBox(width: 12),
                    Text('GPX löschen',
                        style: TextStyle(color: cs.error)),
                  ]),
                ),
              const PopupMenuDivider(),
              PopupMenuItem<String>(
                value: 'delete_day',
                child: Row(children: [
                  Icon(Icons.delete_forever_outlined, color: cs.error),
                  const SizedBox(width: 12),
                  Text('Tag löschen',
                      style: TextStyle(color: cs.error)),
                ]),
              ),
            ],
          ),
        ],
      ),
      // ── FAB: add log entry ───────────────────────────────────────
      floatingActionButton: FloatingActionButton(
        onPressed: () => _addTimelineEntry(context),
        tooltip: 'Logeintrag hinzufügen',
        backgroundColor: cs.primary,
        foregroundColor: cs.secondary,
        shape: CircleBorder(
          side: BorderSide(color: cs.secondary, width: 2),
        ),
        child: const Icon(Icons.add),
      ),
      // ── Bottom nav ───────────────────────────────────────────────
      bottomNavigationBar: AppBottomNav(
        active: NavTab.journal,
        onSelect: (tab) {
          if (tab == NavTab.journal) context.go('/');
          if (tab == NavTab.map) context.push('/tracks');
          if (tab == NavTab.settings) context.push('/settings');
        },
      ),
      body: entry == null
          ? const Center(child: Text('Kein Eintrag für diesen Tag'))
          : _buildBody(entry, track, stats, cs),
    );
  }

  // ── Body ──────────────────────────────────────────────────────────
  Widget _buildBody(
      DayEntry entry, DailyTrack? track, DailyStats? stats, ColorScheme cs) {
    _notesController ??= TextEditingController(text: entry.notes ?? '');
    _fromHarborController ??=
        TextEditingController(text: entry.fromHarbor ?? '');
    _toHarborController ??=
        TextEditingController(text: entry.toHarbor ?? '');

    final correlatedMap = track != null
        ? Map<TimelineEntry, TrackPoint>.fromEntries(
            correlateTimelineWithTrack(entry.timeline, track.points)
                .map((pair) => MapEntry(pair.$1, pair.$2)),
          )
        : <TimelineEntry, TrackPoint>{};

    final day = DateTime(widget.year, widget.month, widget.day);
    final dateLabel =
        DateFormat('d. MMMM yyyy', 'de_CH').format(day).toUpperCase();
    final timeRange = _timeRange(entry, track);
    final hasNotes = entry.notes?.isNotEmpty ?? false;

    return CustomScrollView(
      slivers: [
        // ── Header ─────────────────────────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'LOGBUCHEINTRAG',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5,
                    color: cs.secondary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  hasNotes
                      ? entry.notes!
                      : _routeTitle(entry),
                  style: GoogleFonts.newsreader(
                    fontSize: 24,
                    fontWeight: FontWeight.w500,
                    letterSpacing: -0.24,
                    color: cs.primary,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _headerChip(Icons.calendar_today, dateLabel, cs),
                    if (timeRange != null) ...[
                      const SizedBox(width: 8),
                      _headerChip(Icons.schedule, timeRange, cs),
                    ],
                  ],
                ),
                const SizedBox(height: 16),
                Divider(color: cs.outlineVariant, height: 1),
              ],
            ),
          ),
        ),

        // ── Map ────────────────────────────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: _buildMap(entry, track),
            ),
          ),
        ),

        // ── Stats (if track) ───────────────────────────────────────
        if (stats != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: _buildPassageStats(stats, cs),
            ),
          ),

        // ── Daily Narrative (notes) ────────────────────────────────
        if (hasNotes)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: _buildNarrative(entry.notes!, cs),
            ),
          ),

        // ── Log Entries ────────────────────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'LOGBUCHEINTRÄGE',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.5,
                      color: cs.outline,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: () => _addTimelineEntry(context),
                  icon: Icon(Icons.add_circle_outlined,
                      size: 18, color: cs.primary),
                  label: Text(
                    'EINTRAG',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.0,
                      color: cs.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        if (entry.timeline.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: cs.outlineVariant.withValues(alpha: 0.5)),
                ),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.list_alt_outlined,
                          size: 32, color: cs.onSurfaceVariant),
                      const SizedBox(height: 8),
                      Text('Noch keine Einträge',
                          style: GoogleFonts.inter(
                              fontSize: 14, color: cs.onSurfaceVariant)),
                    ],
                  ),
                ),
              ),
            ),
          )
        else
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Column(
                children: entry.timeline.asMap().entries.map((e) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _buildLogEntry(
                        entry, e.value, correlatedMap[e.value], cs),
                  );
                }).toList(),
              ),
            ),
          ),

        // ── Additional info ────────────────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
            child: _buildAdditionalInfo(entry, cs),
          ),
        ),

        const SliverToBoxAdapter(child: SizedBox(height: 80)),
      ],
    );
  }

  // ── Header chip ───────────────────────────────────────────────────
  Widget _headerChip(IconData icon, String label, ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: cs.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
              color: cs.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  // ── Daily Narrative ───────────────────────────────────────────────
  Widget _buildNarrative(String notes, ColorScheme cs) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Accent stripe — tertiary-fixed (#d3e4fb)
            Container(width: 4, color: cs.tertiaryFixed),
            Expanded(
              child: Container(
                color: cs.surfaceContainerLow,
                padding: const EdgeInsets.all(16),
                child: Stack(
                  children: [
                    Positioned(
                      right: -20,
                      bottom: -20,
                      child: Icon(Icons.description,
                          size: 120,
                          color: cs.primary.withValues(alpha: 0.04)),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'TAGEBUCH',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.5,
                            color: cs.secondary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '"$notes"',
                          style: GoogleFonts.newsreader(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            fontStyle: FontStyle.italic,
                            color: cs.onSurfaceVariant,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Log Entry Card (new Stitch format) ────────────────────────────
  Widget _buildLogEntry(DayEntry entry, TimelineEntry t,
      TrackPoint? trackedPoint, ColorScheme cs) {
    final timeStr =
        '${t.time.hour.toString().padLeft(2, '0')}:${t.time.minute.toString().padLeft(2, '0')}';

    final labelSm = GoogleFonts.inter(
      fontSize: 9,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.0,
      color: cs.outline,
    );
    final bodyBold = GoogleFonts.inter(
      fontSize: 15,
      fontWeight: FontWeight.w600,
      color: cs.onSurface,
    );

    return GestureDetector(
      onLongPress: () => _showTimelineActions(entry, t),
      child: Container(
        decoration: BoxDecoration(
          color: cs.surfaceContainerLowest,
          border: Border.all(color: cs.surfaceContainer),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Time + course | speed ──────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    timeStr,
                    style: GoogleFonts.newsreader(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: cs.primary,
                    ),
                  ),
                  if (trackedPoint != null) ...[
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () => _mapController.move(
                        LatLng(trackedPoint.lat, trackedPoint.lon),
                        14,
                      ),
                      child: Icon(Icons.location_on_outlined,
                          size: 18, color: cs.primary),
                    ),
                  ],
                  if (t.course != null) ...[
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('KURS', style: labelSm),
                        Text('${t.course!.toStringAsFixed(0)}°',
                            style: bodyBold),
                      ],
                    ),
                  ],
                  const Spacer(),
                  if (t.speed != null)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('FAHRT', style: labelSm),
                        Text('${t.speed!.toStringAsFixed(1)} kn',
                            style: bodyBold),
                      ],
                    ),
                ],
              ),
            ),
            Divider(
                height: 1, thickness: 1, color: cs.outlineVariant),
            // ── 3-col grid: wind, sea, weather ─────────────────────
            if (t.wind != null || t.sea != null || t.weather != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Row(
                  children: [
                    Expanded(child: _gridCell('WIND', t.wind, labelSm, cs)),
                    Expanded(child: _gridCell('SEE', t.sea, labelSm, cs)),
                    Expanded(
                        child: _gridCell('WETTER', t.weather, labelSm, cs)),
                  ],
                ),
              ),
            // ── Sail / motor state chips ───────────────────────────
            if (t.grossState != null ||
                t.fockState != null ||
                t.motorOn != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (t.grossState != null)
                      _infoChip(Icons.sailing, 'Gross: ${t.grossState!}', cs),
                    if (t.fockState != null)
                      _infoChip(Icons.sailing, 'Fock: ${t.fockState!}', cs),
                    if (t.motorOn != null)
                      _infoChip(Icons.directions_boat,
                          'Motor ${t.motorOn! ? 'An' : 'Aus'}', cs),
                  ],
                ),
              ),
            // ── Remarks ───────────────────────────────────────────
            if (t.remarks?.isNotEmpty == true)
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  border: Border(
                      top: BorderSide(color: cs.surfaceContainer)),
                ),
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                child: Text(
                  t.remarks!,
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontStyle: FontStyle.italic,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _gridCell(String label, String? value, TextStyle labelStyle,
      ColorScheme cs) {
    if (value == null || value.isEmpty) return const SizedBox();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: labelStyle),
        const SizedBox(height: 2),
        Text(
          value,
          style: GoogleFonts.inter(fontSize: 15, color: cs.onSurface),
        ),
      ],
    );
  }

  Widget _infoChip(IconData icon, String label, ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(50),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: cs.onSecondaryContainer),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: cs.onSecondaryContainer,
            ),
          ),
        ],
      ),
    );
  }

  // ── Passage Stats (dark tertiary card) ────────────────────────────
  Widget _buildPassageStats(DailyStats stats, ColorScheme cs) {
    // secondary-fixed (#ffe088 gold) for values, tertiary-container for bars
    const valueFg = Color(0xFFFFE088);
    const barBg = Color(0xFF2A3A4C); // tertiary-container
    const barFg = Color(0xFFFFE088);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF142435), // tertiary
        borderRadius: BorderRadius.circular(12),
      ),
      child: Stack(
        children: [
          // Watermark
          Positioned(
            top: 0,
            right: 0,
            child: Opacity(
              opacity: 0.15,
              child: Icon(Icons.directions_boat,
                  size: 64, color: valueFg),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'ÜBERFAHRT',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                  color: Colors.white.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _statsCell(
                        'DISTANZ',
                        '${stats.distanceNm.toStringAsFixed(1)} nm',
                        (stats.distanceNm / 200).clamp(0.05, 1.0),
                        valueFg, barBg, barFg),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: _statsCell(
                        'MAX. FAHRT',
                        '${stats.maxSpeed.toStringAsFixed(1)} kn',
                        (stats.maxSpeed / 15).clamp(0.05, 1.0),
                        valueFg, barBg, barFg),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _statsCell(
                        'FAHRZEIT',
                        _formatDuration(stats.movingDuration),
                        (stats.movingDuration.inMinutes / 720)
                            .clamp(0.05, 1.0),
                        valueFg, barBg, barFg),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: _statsCell(
                        'Ø FAHRT',
                        '${stats.avgSpeed.toStringAsFixed(1)} kn',
                        (stats.avgSpeed / 10).clamp(0.05, 1.0),
                        valueFg, barBg, barFg),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statsCell(String label, String value, double progress,
      Color valueFg, Color barBg, Color barFg) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.0,
            color: Colors.white.withValues(alpha: 0.7),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: GoogleFonts.newsreader(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: valueFg,
          ),
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: Stack(
            children: [
              Container(height: 6, color: barBg),
              FractionallySizedBox(
                widthFactor: progress,
                child: Container(height: 6, color: barFg),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Additional Info (collapsible) ─────────────────────────────────
  Widget _buildAdditionalInfo(DayEntry entry, ColorScheme cs) {
    _notesController ??= TextEditingController(text: entry.notes ?? '');
    _fromHarborController ??=
        TextEditingController(text: entry.fromHarbor ?? '');
    _toHarborController ??=
        TextEditingController(text: entry.toHarbor ?? '');

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        tilePadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        title: Text(
          'Weitere Informationen',
          style: GoogleFonts.newsreader(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: cs.primary,
          ),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHarborSection(entry),
                const Divider(height: 28),
                _buildParticipantsSection(entry),
                const Divider(height: 28),
                _buildControlledSection(entry),
                const Divider(height: 28),
                _buildNotesSection(entry),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Map ──────────────────────────────────────────────────────────
  Widget _buildMap(DayEntry entry, DailyTrack? track) {
    if (track == null || track.points.isEmpty) {
      return Container(
        height: 200,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(12),
        ),
        child: InkWell(
          onTap: _importGpx,
          borderRadius: BorderRadius.circular(12),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.file_upload_outlined,
                    size: 36,
                    color:
                        Theme.of(context).colorScheme.onSurfaceVariant),
                const SizedBox(height: 8),
                Text('Kein GPX-Track',
                    style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 4),
                Text('Tippen zum Importieren',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.primary)),
              ],
            ),
          ),
        ),
      );
    }

    final polylinePoints =
        track.points.map((p) => LatLng(p.lat, p.lon)).toList();
    final correlated =
        correlateTimelineWithTrack(entry.timeline, track.points);
    final startPoint = track.points.first;
    final endPoint = track.points.last;

    final timelineMarkers = correlated.map((pair) {
      final t = pair.$1;
      final p = pair.$2;
      return Marker(
        point: LatLng(p.lat, p.lon),
        width: 28,
        height: 28,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _showEntryDetail(t),
          onLongPress: () {
            setState(
                () => _droppedMarkerLatLng = LatLng(p.lat, p.lon));
            _showEntryDetail(t);
          },
          child: Icon(Icons.location_on,
              size: 28,
              color: Theme.of(context).colorScheme.primary),
        ),
      );
    }).toList();

    final markers = <Marker>[
      ...timelineMarkers,
      Marker(
        point: LatLng(startPoint.lat, startPoint.lon),
        width: 32,
        height: 32,
        child: Container(
          decoration: const BoxDecoration(
              shape: BoxShape.circle, color: Colors.green),
          child: const Icon(Icons.flag, color: Colors.white, size: 18),
        ),
      ),
      Marker(
        point: LatLng(endPoint.lat, endPoint.lon),
        width: 32,
        height: 32,
        child: Container(
          decoration: const BoxDecoration(
              shape: BoxShape.circle, color: Colors.red),
          child: const Icon(Icons.flag, color: Colors.white, size: 18),
        ),
      ),
    ];

    if (_droppedMarkerLatLng != null) {
      markers.add(Marker(
        point: _droppedMarkerLatLng!,
        width: 44,
        height: 44,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            if (_isMarkerSheetOpen) Navigator.of(context).pop();
            setState(() => _droppedMarkerLatLng = null);
          },
          onPanUpdate: (details) {
            final camera = _mapController.camera;
            final screenPt =
                camera.latLngToScreenPoint(_droppedMarkerLatLng!);
            final newPt = Point<num>(
              screenPt.x + details.delta.dx,
              screenPt.y + details.delta.dy,
            );
            setState(
                () => _droppedMarkerLatLng = camera.pointToLatLng(newPt));
          },
          onPanEnd: (_) {
            final nearest = _findNearestTrackPoint(
                _droppedMarkerLatLng!, track.points);
            if (nearest != null) _showTrackPointBottomSheet(nearest);
          },
          child:
              const Icon(Icons.place, color: Colors.deepOrange, size: 40),
        ),
      ));
    }

    return SizedBox(
      height: 280,
      child: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCameraFit: CameraFit.bounds(
                bounds: LatLngBounds.fromPoints(polylinePoints),
                padding: const EdgeInsets.all(40),
              ),
              onTap: (_, _) {
                if (_isMarkerSheetOpen) Navigator.of(context).pop();
                setState(() => _droppedMarkerLatLng = null);
              },
              onLongPress: (tapPosition, latLng) {
                final nearest =
                    _findNearestTrackPoint(latLng, track.points);
                setState(() => _droppedMarkerLatLng = latLng);
                if (nearest != null) _showTrackPointBottomSheet(nearest);
              },
            ),
            children: [
              TileLayer(
                urlTemplate: _satelliteView
                    ? 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}'
                    : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.logbook.app',
                tileProvider: NetworkTileProvider(),
              ),
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: polylinePoints,
                    strokeWidth: 4,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ],
              ),
              MarkerLayer(markers: markers),
              RichAttributionWidget(
                attributions: [
                  if (_satelliteView)
                    TextSourceAttribution('© Esri World Imagery',
                        onTap: () async {
                      final uri = Uri.parse('https://www.esri.com');
                      if (await canLaunchUrl(uri)) {
                        await launchUrl(uri,
                            mode: LaunchMode.externalApplication);
                      }
                    })
                  else
                    TextSourceAttribution('© OpenStreetMap contributors',
                        onTap: () async {
                      final uri = Uri.parse(
                          'https://www.openstreetmap.org/copyright');
                      if (await canLaunchUrl(uri)) {
                        await launchUrl(uri,
                            mode: LaunchMode.externalApplication);
                      }
                    }),
                ],
              ),
            ],
          ),
          // Satellite toggle
          Positioned(
            right: 10,
            bottom: 10,
            child: FloatingActionButton.small(
              heroTag: 'detail_satellite_button',
              onPressed: () =>
                  setState(() => _satelliteView = !_satelliteView),
              tooltip:
                  _satelliteView ? 'Kartenansicht' : 'Satellitenansicht',
              child: Icon(_satelliteView
                  ? Icons.map_outlined
                  : Icons.satellite_alt),
            ),
          ),
        ],
      ),
    );
  }

  // ── Harbor Section ────────────────────────────────────────────────
  Widget _buildHarborSection(DayEntry entry) {
    final cs = Theme.of(context).colorScheme;
    final labelStyle = Theme.of(context)
        .textTheme
        .labelLarge
        ?.copyWith(color: cs.onSurfaceVariant);
    final inputDecoration = InputDecoration(
      border:
          OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      isDense: true,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Route', style: labelStyle),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Von',
                      style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 4),
                  TextField(
                    controller: _fromHarborController,
                    decoration:
                        inputDecoration.copyWith(hintText: 'Starthafen'),
                    textInputAction: TextInputAction.next,
                    textCapitalization: TextCapitalization.words,
                    inputFormatters: [_CapitalizeWordsFormatter()],
                    onChanged: (v) {
                      entry.fromHarbor = v.trim().isEmpty ? null : v.trim();
                      context.read<HomeRepository>().saveEntry(entry);
                    },
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 20, left: 8, right: 8),
              child: Icon(Icons.arrow_forward,
                  size: 18, color: cs.onSurfaceVariant),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Nach',
                      style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 4),
                  TextField(
                    controller: _toHarborController,
                    decoration:
                        inputDecoration.copyWith(hintText: 'Zielhafen'),
                    textInputAction: TextInputAction.done,
                    textCapitalization: TextCapitalization.words,
                    inputFormatters: [_CapitalizeWordsFormatter()],
                    onChanged: (v) {
                      entry.toHarbor = v.trim().isEmpty ? null : v.trim();
                      context.read<HomeRepository>().saveEntry(entry);
                    },
                    onSubmitted: (_) =>
                        FocusScope.of(context).unfocus(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildParticipantsSection(DayEntry entry) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Teilnehmer',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            ...entry.participantsList.map(
              (name) => Chip(
                label: Text(name),
                deleteIcon: Icon(Icons.close,
                    size: 16,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurfaceVariant),
                onDeleted: () => _removeParticipant(entry, name),
                backgroundColor: Theme.of(context)
                    .colorScheme
                    .surfaceContainerHigh,
                labelStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.primary),
                side: BorderSide.none,
              ),
            ),
            ActionChip(
              avatar: Icon(Icons.person_add_outlined,
                  size: 16,
                  color: Theme.of(context).colorScheme.primary),
              label: Text('Hinzufügen',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.primary)),
              backgroundColor:
                  Theme.of(context).colorScheme.surfaceContainerHigh,
              side: BorderSide.none,
              onPressed: () => _addParticipant(entry),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildControlledSection(DayEntry entry) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Checkliste',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
        const SizedBox(height: 4),
        ..._controlledItems.map((item) {
          final checked = entry.checkedItems.contains(item);
          return CheckboxListTile(
            value: checked,
            title: Text(item,
                style: Theme.of(context).textTheme.bodyMedium),
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            onChanged: (v) =>
                _toggleCheckedItem(entry, item, v ?? false),
          );
        }),
      ],
    );
  }

  Widget _buildNotesSection(DayEntry entry) {
    _notesController ??= TextEditingController(text: entry.notes ?? '');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Notizen',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
        const SizedBox(height: 8),
        TextField(
          controller: _notesController,
          decoration: InputDecoration(
            hintText: 'Notizen für diesen Tag…',
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12)),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 10),
          ),
          minLines: 1,
          maxLines: null,
          keyboardType: TextInputType.multiline,
          textInputAction: TextInputAction.newline,
          onChanged: (v) {
            entry.notes = v.isEmpty ? null : v;
            context.read<HomeRepository>().saveEntry(entry);
          },
        ),
      ],
    );
  }

  // ── Map helpers ───────────────────────────────────────────────────
  TrackPoint? _findNearestTrackPoint(
      LatLng latLng, List<TrackPoint> points) {
    if (points.isEmpty) return null;
    TrackPoint? nearest;
    double minDistSq = double.infinity;
    for (final p in points) {
      final dlat = p.lat - latLng.latitude;
      final dlng = p.lon - latLng.longitude;
      final distSq = dlat * dlat + dlng * dlng;
      if (distSq < minDistSq) {
        minDistSq = distSq;
        nearest = p;
      }
    }
    return nearest;
  }

  void _showTrackPointBottomSheet(TrackPoint point) {
    setState(() => _isMarkerSheetOpen = true);
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              DateFormat('HH:mm').format(point.time.toLocal()),
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              DateFormat('dd. MMMM yyyy', 'de_CH')
                  .format(point.time.toLocal()),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color:
                        Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    ).whenComplete(
        () => setState(() => _isMarkerSheetOpen = false));
  }

  Widget _gpxUploadIcon() {
    return SizedBox(
      width: 26,
      height: 26,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          const Icon(Icons.file_upload_outlined, size: 22),
          Positioned(
            bottom: -3,
            right: -6,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(
                'GPX',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onPrimary,
                  fontSize: 7,
                  fontWeight: FontWeight.bold,
                  height: 1,
                  letterSpacing: 0,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Entry Detail / Actions ────────────────────────────────────────
  void _showEntryDetail(TimelineEntry t) {
    final timeStr =
        '${t.time.hour.toString().padLeft(2, '0')}:${t.time.minute.toString().padLeft(2, '0')}';
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(timeStr,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    )),
            if (t.remarks?.isNotEmpty == true) ...[
              const SizedBox(height: 4),
              Text(t.remarks!,
                  style: Theme.of(context).textTheme.titleMedium),
            ],
            const SizedBox(height: 16),
            if (t.course != null)
              _detailRow(Icons.navigation, 'Kurs',
                  '${t.course!.toStringAsFixed(0)}°'),
            if (t.speed != null)
              _detailRow(Icons.speed, 'Speed',
                  '${t.speed!.toStringAsFixed(1)} kn'),
            if (t.wind != null) _detailRow(Icons.air, 'Wind', t.wind!),
            if (t.sea != null) _detailRow(Icons.waves, 'See', t.sea!),
            if (t.weather != null)
              _detailRow(Icons.wb_sunny_outlined, 'Wetter', t.weather!),
            if (t.grossState != null)
              _detailRow(Icons.sailing, 'Gross', t.grossState!),
            if (t.fockState != null)
              _detailRow(Icons.sailing, 'Fock', t.fockState!),
            if (t.motorOn != null)
              _detailRow(Icons.directions_boat, 'Motor',
                  t.motorOn! ? 'An' : 'Aus'),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon,
              size: 18,
              color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Text('$label  ',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color:
                      Theme.of(context).colorScheme.onSurfaceVariant)),
          Text(value,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  void _showTimelineActions(DayEntry entry, TimelineEntry t) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Bearbeiten'),
              onTap: () {
                Navigator.pop(context);
                _editTimelineEntry(entry, t);
              },
            ),
            ListTile(
              leading: Icon(Icons.delete_outline,
                  color: Theme.of(context).colorScheme.error),
              title: Text('Löschen',
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.error)),
              onTap: () {
                Navigator.pop(context);
                _deleteTimelineEntry(entry, t);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ── Participant / checklist helpers ───────────────────────────────
  void _addParticipant(DayEntry entry) async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Teilnehmer hinzufügen'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Name'),
          textCapitalization: TextCapitalization.words,
          onSubmitted: (v) => Navigator.pop(context, v.trim()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Abbrechen')),
          TextButton(
              onPressed: () => Navigator.pop(context, ctrl.text.trim()),
              child: const Text('Hinzufügen')),
        ],
      ),
    );
    if (!mounted || name == null || name.isEmpty) return;
    setState(() {
      entry.participantsList.add(name);
      context.read<HomeRepository>().saveEntry(entry);
    });
  }

  void _removeParticipant(DayEntry entry, String name) {
    setState(() {
      entry.participantsList.remove(name);
      context.read<HomeRepository>().saveEntry(entry);
    });
  }

  void _toggleCheckedItem(DayEntry entry, String item, bool checked) {
    setState(() {
      if (checked) {
        entry.checkedItems.add(item);
      } else {
        entry.checkedItems.remove(item);
      }
      context.read<HomeRepository>().saveEntry(entry);
    });
  }

  // ── Timeline entry mutations ──────────────────────────────────────
  void _addTimelineEntry(BuildContext context) async {
    final repo = context.read<HomeRepository>();
    final day = DateTime(widget.year, widget.month, widget.day);
    final prefill = repo.getEntry(day)?.timeline.lastOrNull;
    final newEntry = await showDialog<TimelineEntry>(
      context: context,
      builder: (_) =>
          AddTimelineEntryDialog(day: day, prefillEntry: prefill),
    );
    if (!mounted || newEntry == null) return;
    repo.addTimelineEntry(day, newEntry);
  }

  void _deleteTimelineEntry(DayEntry entry, TimelineEntry t) {
    setState(() {
      entry.timeline.remove(t);
      context.read<HomeRepository>().saveEntry(entry);
    });
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Logeintrag gelöscht')));
  }

  void _editTimelineEntry(DayEntry entry, TimelineEntry t) async {
    final day = DateTime(widget.year, widget.month, widget.day);
    final updated = await showDialog<TimelineEntry>(
      context: context,
      builder: (_) => AddTimelineEntryDialog(day: day, initialEntry: t),
    );
    if (!mounted || updated == null) return;
    setState(() {
      final index = entry.timeline.indexOf(t);
      if (index != -1) {
        entry.timeline[index] = updated;
        entry.timeline.sort((a, b) => a.time.compareTo(b.time));
        context.read<HomeRepository>().saveEntry(entry);
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Logeintrag aktualisiert')));
  }

  // ── GPX import / delete / day delete ─────────────────────────────
  void _importGpx() async {
    final repo = context.read<HomeRepository>();
    final day = DateTime(widget.year, widget.month, widget.day);

    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['gpx'],
      allowMultiple: false,
      withData: kIsWeb,
    );
    if (result == null || result.files.isEmpty) return;
    final picked = result.files.single;

    final List<TrackPoint> preview;
    if (kIsWeb) {
      final bytes = picked.bytes;
      if (bytes == null) return;
      preview = GpxParser().parseBytes(bytes);
    } else {
      preview = await GpxParser().parse(File(picked.path!));
    }

    if (!mounted) return;

    if (preview.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'GPX-File enthält keine Wegpunkte mit Zeitstempel')));
      return;
    }

    final counts = <DateTime, int>{};
    for (final p in preview) {
      final d = DateTime(p.time.toLocal().year, p.time.toLocal().month,
          p.time.toLocal().day);
      counts[d] = (counts[d] ?? 0) + 1;
    }
    final dominantDate =
        counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
    final targetDate = DateTime(day.year, day.month, day.day);

    if (dominantDate != targetDate) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Falsches Datum?'),
          content: Text(
            'Das GPX-File enthält hauptsächlich Daten vom '
            '${DateFormat('d. MMMM yyyy', 'de_CH').format(dominantDate)}, '
            'nicht vom ${DateFormat('d. MMMM yyyy', 'de_CH').format(targetDate)}.\n\n'
            'Trotzdem importieren?',
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Abbrechen')),
            TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Trotzdem importieren')),
          ],
        ),
      );
      if (!mounted || proceed != true) return;
    }

    if (kIsWeb) {
      final bytes = picked.bytes;
      if (bytes == null) return;
      await repo.importGpxFromBytes(day, bytes, picked.name);
    } else {
      await repo.importGpx(day, File(picked.path!));
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            'GPX-Track importiert für ${DateFormat('d. MMMM yyyy', 'de_CH').format(day)}')));
  }

  void _removeGpx() async {
    final repo = context.read<HomeRepository>();
    final day = DateTime(widget.year, widget.month, widget.day);
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('GPX-Track entfernen?'),
        content: const Text('GPX-Track für diesen Tag löschen?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Abbrechen')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Löschen')),
        ],
      ),
    );
    if (!mounted || shouldDelete != true) return;
    await repo.removeGpx(day);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('GPX-Track entfernt')));
  }

  void _deleteDay() async {
    final repo = context.read<HomeRepository>();
    final day = DateTime(widget.year, widget.month, widget.day);
    final dateLabel =
        DateFormat('d. MMMM yyyy', 'de_CH').format(day);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Tag löschen?'),
        content: Text(
          'Alle Daten für den $dateLabel werden unwiderruflich gelöscht, '
          'inklusive Logeinträge und GPX-Track.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Abbrechen')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text('Löschen',
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.error))),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    await repo.removeEntry(day);
    if (!mounted) return;
    context.go('/');
  }
}
