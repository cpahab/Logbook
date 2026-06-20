import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/home_repository.dart';
import '../domain/day_entry.dart';
import '../domain/daily_track.dart';
import '../domain/timeline_entry.dart';
import '../domain/track_point.dart';
import '../domain/crew_member.dart';
import '../widgets/add_timeline_entry_dialog.dart';
import '../widgets/add_crew_member_dialog.dart';
import '../widgets/keel_icon.dart';
import '../widgets/nav_bar.dart';
import '../utils/compute_daily_stats.dart';
import '../utils/filter_settings.dart';
import '../utils/gpx_parser.dart';
import '../utils/track_correlation.dart';
import '../utils/gpx_exporter.dart';
import '../utils/pdf_exporter.dart';
import '../utils/photo_service.dart';
import '../utils/trim_track.dart';
import '../../settings/domain/theme_provider.dart';


class DayDetailScreen extends StatefulWidget {
  final int year;
  final int month;
  final int day;
  final bool openAddDialog;

  const DayDetailScreen({
    super.key,
    required this.year,
    required this.month,
    required this.day,
    this.openAddDialog = false,
  });

  @override
  State<DayDetailScreen> createState() => _DayDetailScreenState();
}

class _DayDetailScreenState extends State<DayDetailScreen> {
  final MapController _mapController = MapController();
  bool _satelliteView = false;
  LatLng? _droppedMarkerLatLng;
  String? _droppedMarkerLabel;
  Timer? _markerDismissTimer;
  bool _editingRoute = false;
  final Set<String> _deletingPhotos = {};
  final _fromHarborCtrl = TextEditingController();
  final _toHarborCtrl = TextEditingController();
  @override
  void initState() {
    super.initState();
    if (widget.openAddDialog) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _addTimelineEntry(context);
      });
    }
  }

  @override
  void dispose() {
    _markerDismissTimer?.cancel();
    _fromHarborCtrl.dispose();
    _toHarborCtrl.dispose();
    _mapController.dispose();
    super.dispose();
  }

  // ── Helpers ───────────────────────────────────────────────────────
  // ── Build ──────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final repo = context.watch<HomeRepository>();
    final day = DateTime(widget.year, widget.month, widget.day);
    final entry = repo.getEntry(day);
    final track = repo.dailyTracks[day];

    final filterSettings = context.watch<ThemeProvider>().filterSettings;
    DailyStats? stats;
    if (track != null && track.points.isNotEmpty) {
      stats = computeDailyStats(track.points, settings: filterSettings);
    }

    final cs = Theme.of(context).colorScheme;
    final dayName = DateFormat('EEEE', 'de_CH').format(day);
    final dateStr = DateFormat('d. MMM yyyy', 'de_CH').format(day);

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: cs.surface,
        foregroundColor: cs.primary,
        elevation: 0,
        scrolledUnderElevation: 1,
        shadowColor: Colors.black12,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: cs.primary),
          onPressed: () => context.go('/'),
        ),
        title: Text(
          '$dayName · $dateStr · LOGBUCH',
          style: GoogleFonts.inter(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.0,
            color: cs.primary,
          ),
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (entry != null)
            PopupMenuButton<String>(
              tooltip: 'Optionen',
              icon: Icon(Icons.more_vert, color: cs.primary),
              onSelected: (value) {
                if (value == 'change_date') _changeDate(entry);
                if (value == 'import_gpx') _importGpx();
                if (value == 'export_gpx') _exportGpx(track!, day);
                if (value == 'export_pdf') _exportPdf(entry, stats, track);
                if (value == 'delete_gpx') _removeGpx();
                if (value == 'delete_day') _deleteDay();
              },
              itemBuilder: (context) => [
                PopupMenuItem<String>(
                  value: 'change_date',
                  child: Row(children: [
                    Icon(Icons.calendar_today_outlined, color: cs.onSurface),
                    const SizedBox(width: 12),
                    Text('Datum ändern', style: TextStyle(color: cs.onSurface)),
                  ]),
                ),
                PopupMenuItem<String>(
                  value: 'import_gpx',
                  child: Row(children: [
                    _gpxUploadIcon(),
                    const SizedBox(width: 12),
                    Text('GPX importieren', style: TextStyle(color: cs.onSurface)),
                  ]),
                ),
                if (track != null)
                  PopupMenuItem<String>(
                    value: 'export_gpx',
                    child: Row(children: [
                      Icon(Icons.download_outlined, color: cs.onSurface),
                      const SizedBox(width: 12),
                      Text('GPX exportieren', style: TextStyle(color: cs.onSurface)),
                    ]),
                  ),
                PopupMenuItem<String>(
                  value: 'export_pdf',
                  child: Row(children: [
                    Icon(Icons.picture_as_pdf_outlined, color: cs.onSurface),
                    const SizedBox(width: 12),
                    Text('PDF exportieren', style: TextStyle(color: cs.onSurface)),
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
      bottomNavigationBar: AppBottomNav(
        active: NavTab.journal,
        onFabTap: () => _addTimelineEntry(context),
        onSelect: (tab) {
          if (tab == NavTab.journal) context.go('/');
          if (tab == NavTab.map) context.push('/tracks');
          if (tab == NavTab.settings) context.push('/settings');
          if (tab == NavTab.safety) context.push('/emergency');
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
    final correlatedMap = track != null
        ? Map<TimelineEntry, TrackPoint>.fromEntries(
            correlateTimelineWithTrack(entry.timeline, track.points)
                .map((pair) => MapEntry(pair.$1, pair.$2)),
          )
        : <TimelineEntry, TrackPoint>{};

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildCrewList(entry, cs),
            _buildReflection(entry, cs),
            _buildFreeText(entry, cs),
            _buildPhotoStrip(entry, cs),
            _buildRouteMap(entry, track, stats, cs),
            _buildLogSection(entry, correlatedMap, cs),
            _buildVesselStatus(entry, cs),
          ],
        ),
      ),
    );
  }

  // ── Free Text ─────────────────────────────────────────────────────
  Widget _buildFreeText(DayEntry entry, ColorScheme cs) {
    final hasText = entry.freeText?.isNotEmpty ?? false;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'NOTIZEN',
          style: GoogleFonts.inter(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.5,
            color: cs.secondary,
          ),
        ),
        const SizedBox(height: 8),
        if (hasText)
          GestureDetector(
            onTap: () => _editFreeText(entry),
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: cs.surfaceContainerLowest,
                border: Border.all(
                    color: cs.outlineVariant.withValues(alpha: 0.3)),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(16),
              child: Text(
                entry.freeText!,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: cs.onSurface,
                  height: 1.5,
                ),
              ),
            ),
          )
        else
          _emptyStateButton(
            Icons.notes,
            'Notizen hinzufügen…',
            () => _editFreeText(entry),
            cs,
          ),
        const SizedBox(height: 20),
      ],
    );
  }

  void _editFreeText(DayEntry entry) async {
    final result = await showDialog<String>(
      context: context,
      builder: (_) => _EditTextDialog(
        title: 'Notizen',
        initialText: entry.freeText,
        hintText: 'Freie Notizen für diesen Tag…',
      ),
    );
    if (!mounted || result == null) return;
    setState(() {
      entry.freeText = result.trim().isEmpty ? null : result.trim();
      context.read<HomeRepository>().saveEntry(entry);
    });
  }

  // ── Daily Reflection ──────────────────────────────────────────────
  Widget _buildReflection(DayEntry entry, ColorScheme cs) {
    final hasNotes = entry.notes?.isNotEmpty ?? false;
    return Column(
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
        if (hasNotes)
          GestureDetector(
            onTap: () => _editNotes(entry),
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: cs.surfaceContainerLowest,
                border: Border.all(
                    color: cs.outlineVariant.withValues(alpha: 0.3)),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(16),
              child: Text(
                '"${entry.notes!}"',
                style: GoogleFonts.newsreader(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  fontStyle: FontStyle.italic,
                  color: cs.onSurface,
                  height: 1.5,
                ),
              ),
            ),
          )
        else
          _emptyStateButton(
            Icons.edit_note,
            'Tagebucheintrag hinzufügen…',
            () => _editNotes(entry),
            cs,
          ),
        const SizedBox(height: 20),
      ],
    );
  }

  // ── Crew List ─────────────────────────────────────────────────────
  Widget _buildCrewList(DayEntry entry, ColorScheme cs) {
    final crew = entry.crew;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'BESATZUNG',
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5,
                color: cs.secondary,
              ),
            ),
            const Spacer(),
            GestureDetector(
              onTap: () => _addCrewMember(entry),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: cs.surfaceContainer,
                ),
                child: Icon(Icons.person_add, size: 20, color: cs.secondary),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (crew.isNotEmpty)
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: cs.surfaceContainerLowest,
              border: Border.all(
                  color: cs.outlineVariant.withValues(alpha: 0.3)),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            padding: const EdgeInsets.all(12),
            child: Column(
              children: crew.asMap().entries.map((e) {
                final isFirst = e.key == 0;
                final isLast = e.key == crew.length - 1;
                final member = e.value;
                return Column(
                  children: [
                    GestureDetector(
                      onTap: () => _editCrewMember(entry, e.key),
                      child: Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: cs.surfaceContainerHigh,
                            ),
                            child: Icon(Icons.person,
                                color: cs.primary, size: 22),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  member.name,
                                  style: GoogleFonts.inter(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: cs.onSurface,
                                  ),
                                ),
                                Row(
                                  children: [
                                    Text(
                                      isFirst ? 'SKIPPER' : 'BESATZUNG',
                                      style: GoogleFonts.inter(
                                        fontSize: 9,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 0.5,
                                        color: cs.outline,
                                      ),
                                    ),
                                    if (member.bloodType != null) ...[
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 1),
                                        decoration: BoxDecoration(
                                          color: cs.errorContainer,
                                          borderRadius:
                                              BorderRadius.circular(999),
                                        ),
                                        child: Text(
                                          member.bloodType!,
                                          style: GoogleFonts.inter(
                                            fontSize: 9,
                                            fontWeight: FontWeight.w700,
                                            letterSpacing: 0.3,
                                            color: cs.onErrorContainer,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),
                          Icon(Icons.chevron_right,
                              size: 18, color: cs.outlineVariant),
                        ],
                      ),
                    ),
                    if (!isLast)
                      Divider(
                        color: cs.outlineVariant.withValues(alpha: 0.3),
                        height: 16,
                      ),
                  ],
                );
              }).toList(),
            ),
          )
        else
          _emptyStateButton(
            Icons.groups,
            'Besatzung hinzufügen…',
            () => _addCrewMember(entry),
            cs,
          ),
        const SizedBox(height: 20),
      ],
    );
  }

  // ── Route & Map ───────────────────────────────────────────────────
  Widget _buildRouteMap(
      DayEntry entry, DailyTrack? track, DailyStats? stats, ColorScheme cs) {
    final hasTrack = track != null && track.points.isNotEmpty;
    final fromH = entry.fromHarbor?.isNotEmpty ?? false;
    final toH = entry.toHarbor?.isNotEmpty ?? false;
    final routeLabel = (fromH || toH)
        ? [if (fromH) entry.fromHarbor!, if (toH) entry.toHarbor!].join(' → ')
        : null;
    final div = BorderSide(color: cs.outlineVariant.withValues(alpha: 0.3));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'ROUTE & PASSAGE',
          style: GoogleFonts.inter(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.5,
            color: cs.secondary,
          ),
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Container(
            decoration: BoxDecoration(
              color: cs.surfaceContainerLowest,
              border: Border.all(
                  color: cs.outlineVariant.withValues(alpha: 0.3)),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              children: [
                // ── Etappe row ──────────────────────────────────
                _editingRoute
                    ? Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Icon(Icons.sailing,
                                size: 18, color: cs.secondary),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  TextField(
                                    controller: _fromHarborCtrl,
                                    autofocus: true,
                                    decoration: InputDecoration(
                                      hintText: 'Starthafen',
                                      border: InputBorder.none,
                                      isDense: true,
                                      contentPadding: EdgeInsets.zero,
                                      hintStyle: GoogleFonts.inter(
                                        fontSize: 15,
                                        color: cs.onSurfaceVariant,
                                      ),
                                    ),
                                    style: GoogleFonts.inter(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                      color: cs.onSurface,
                                    ),
                                    textCapitalization:
                                        TextCapitalization.words,
                                    textInputAction: TextInputAction.next,
                                  ),
                                  Divider(
                                    height: 12,
                                    color: cs.outlineVariant
                                        .withValues(alpha: 0.4),
                                  ),
                                  TextField(
                                    controller: _toHarborCtrl,
                                    decoration: InputDecoration(
                                      hintText: 'Zielhafen',
                                      border: InputBorder.none,
                                      isDense: true,
                                      contentPadding: EdgeInsets.zero,
                                      hintStyle: GoogleFonts.inter(
                                        fontSize: 15,
                                        color: cs.onSurfaceVariant,
                                      ),
                                    ),
                                    style: GoogleFonts.inter(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                      color: cs.onSurface,
                                    ),
                                    textCapitalization:
                                        TextCapitalization.words,
                                    textInputAction: TextInputAction.done,
                                    onSubmitted: (_) =>
                                        _saveRoute(entry),
                                  ),
                                ],
                              ),
                            ),
                            GestureDetector(
                              onTap: () => _saveRoute(entry),
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                child: Icon(
                                  Icons.check_circle_outline,
                                  size: 22,
                                  color: cs.primary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                    : InkWell(
                        onTap: () => _startEditRoute(entry),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          child: Row(
                            children: [
                              Icon(Icons.sailing,
                                  size: 18, color: cs.secondary),
                              const SizedBox(width: 10),
                              Expanded(
                                child: routeLabel != null
                                    ? Text(
                                        routeLabel,
                                        style: GoogleFonts.inter(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
                                          color: cs.onSurface,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      )
                                    : Text(
                                        'Etappe erfassen…',
                                        style: GoogleFonts.inter(
                                          fontSize: 15,
                                          fontStyle: FontStyle.italic,
                                          color: cs.onSurfaceVariant,
                                        ),
                                      ),
                              ),
                              Icon(Icons.edit,
                                  size: 16, color: cs.secondary),
                            ],
                          ),
                        ),
                      ),
                // ── Map or GPX prompt ────────────────────────────
                Container(
                  decoration: BoxDecoration(border: Border(top: div)),
                  child: hasTrack
                      ? Column(
                          children: [
                            SizedBox(
                              height: 220,
                              child: _buildMap(entry, track),
                            ),
                            if (stats != null) _buildStatsGrid(stats, cs),
                          ],
                        )
                      : InkWell(
                          onTap: _importGpx,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                vertical: 20, horizontal: 16),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.map_outlined,
                                    color: cs.onSurfaceVariant),
                                const SizedBox(width: 8),
                                Text(
                                  'GPX Track hinzufügen…',
                                  style: GoogleFonts.inter(
                                    fontSize: 15,
                                    fontStyle: FontStyle.italic,
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildStatsGrid(DailyStats stats, ColorScheme cs) {
    final div = BorderSide(color: cs.outlineVariant.withValues(alpha: 0.3));

    return Container(
      decoration: BoxDecoration(border: Border(top: div)),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(border: Border(right: div)),
                  padding: const EdgeInsets.all(12),
                  child: _statCell(
                      'DISTANZ', '${stats.distanceNm.toStringAsFixed(1)} NM', cs),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: _statCell(
                      'Ø Geschwindigkeit', '${stats.avgOverGroundKn.toStringAsFixed(1)} kn', cs),
                ),
              ),
            ],
          ),
          if (stats.avgMakingWayKn > 0 || stats.maxSpeedKn > 0)
            Container(
              decoration: BoxDecoration(border: Border(top: div)),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(border: Border(right: div)),
                      padding: const EdgeInsets.all(12),
                      child: _statCell(
                          'Ø Geschwindigkeit in Fahrt', '${stats.avgMakingWayKn.toStringAsFixed(1)} kn', cs),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: _statCell(
                          'MAX', '${stats.maxSpeedKn.toStringAsFixed(1)} kn', cs),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _statCell(String label, String value, ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.0,
            color: cs.outline,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: GoogleFonts.newsreader(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: cs.primary,
          ),
        ),
      ],
    );
  }

  // ── Log Section ───────────────────────────────────────────────────
  Widget _buildLogSection(DayEntry entry,
      Map<TimelineEntry, TrackPoint> correlatedMap, ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'CHRONOLOGISCHE EINTRÄGE',
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5,
                color: cs.secondary,
              ),
            ),
            const Spacer(),
            Tooltip(
              message: 'Eintrag hinzufügen',
              child: GestureDetector(
                onTap: () => _addTimelineEntry(context),
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: cs.surfaceContainer,
                  ),
                  child: Icon(Icons.add, size: 20, color: cs.secondary),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (entry.timeline.isEmpty)
          _emptyStateButton(
            Icons.add_circle_outline,
            'Ersten Logeintrag hinzufügen…',
            () => _addTimelineEntry(context),
            cs,
          )
        else
          Column(
            children: entry.timeline.asMap().entries.map((e) {
              return _buildLogEntryRow(
                entry,
                e.value,
                e.key,
                entry.timeline.length,
                correlatedMap[e.value],
                cs,
              );
            }).toList(),
          ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildLogEntryRow(DayEntry entry, TimelineEntry t, int index,
      int total, TrackPoint? trackedPoint, ColorScheme cs) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Spine + node
          SizedBox(
            width: 24,
            child: Column(
              children: [
                const SizedBox(height: 16),
                Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: cs.primary,
                    border: Border.all(color: cs.surface, width: 3),
                  ),
                ),
                if (index < total - 1)
                  Expanded(
                    child: Center(
                      child: Container(
                          width: 2,
                          color: cs.surfaceContainerHighest),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Card
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _buildLogEntryCard(
                  entry, t, index, total, trackedPoint, cs),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogEntryCard(DayEntry entry, TimelineEntry t, int index,
      int total, TrackPoint? trackedPoint, ColorScheme cs) {
    final timeStr =
        '${t.time.hour.toString().padLeft(2, '0')}:${t.time.minute.toString().padLeft(2, '0')}';

    final bool isStatusEntry = t.vesselStatusNote != null;
    final String entryLabel;
    if (isStatusEntry) {
      entryLabel = 'SCHIFFSSTATUS';
    } else if (total == 1) {
      entryLabel = 'EINTRAG';
    } else if (index == 0) {
      entryLabel = 'ABFAHRT';
    } else if (index == total - 1) {
      entryLabel = 'ANKUNFT';
    } else {
      entryLabel = 'VERLAUF';
    }

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        border: Border.all(
            color: cs.outlineVariant.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Time + label + action icons
          Row(
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
                      size: 16, color: cs.primary),
                ),
              ],
              const Spacer(),
              Text(
                entryLabel,
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                  color: cs.secondary,
                ),
              ),
              const SizedBox(width: 12),
              GestureDetector(
                onTap: () => _editTimelineEntry(entry, t),
                child: Icon(Icons.edit_outlined,
                    size: 16, color: cs.outline),
              ),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: () => _deleteTimelineEntry(entry, t),
                child: Icon(Icons.close,
                    size: 16, color: cs.outline),
              ),
            ],
          ),
            // Remarks
            if (t.remarks?.isNotEmpty == true) ...[
              const SizedBox(height: 8),
              Text(
                t.remarks!,
                style: GoogleFonts.inter(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface,
                ),
              ),
            ],
            // Vessel status note (auto-generated)
            if (t.vesselStatusNote != null) ...[
              const SizedBox(height: 8),
              Text(
                t.vesselStatusNote!,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: cs.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
            ],
            // Continuous data text
            if (t.course != null ||
                t.speed != null ||
                t.wind != null ||
                t.sea != null ||
                t.weather != null ||
                t.grossState != null ||
                t.fockState != null ||
                t.motorOn != null) ...[
              const SizedBox(height: 8),
              Text(
                [
                  if (t.course != null)
                    'Kurs: ${t.course!.toStringAsFixed(0)}°',
                  if (t.speed != null)
                    'Fahrt: ${t.speed!.toStringAsFixed(1)} kn',
                  if (t.wind != null) 'Wind: ${t.wind!}',
                  if (t.sea != null) 'See: ${t.sea!}',
                  if (t.weather != null) 'Wetter: ${t.weather!}',
                  if (t.grossState != null) 'Gross: ${t.grossState!}',
                  if (t.fockState != null) 'Fock: ${t.fockState!}',
                  if (t.motorOn != null)
                    'Motor: ${t.motorOn! ? 'An' : 'Aus'}',
                ].join(' · '),
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: cs.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
            ],
          ],
        ),
    );
  }

  // ── Photo strip ───────────────────────────────────────────────────
  Widget _buildPhotoStrip(DayEntry entry, ColorScheme cs) {
    final hasPhotos = entry.photos.isNotEmpty || _deletingPhotos.isNotEmpty;
    final allPaths = [
      ...List<String>.from(entry.photos),
      ..._deletingPhotos.where((p) => !entry.photos.contains(p)),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'FOTOS',
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5,
                color: cs.secondary,
              ),
            ),
            if (hasPhotos) ...[
              const Spacer(),
              GestureDetector(
                onTap: () => _addPhotos(entry),
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: cs.surfaceContainer,
                  ),
                  child: Icon(Icons.add_a_photo_outlined, size: 20, color: cs.secondary),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 10),
        if (hasPhotos)
          SizedBox(
            height: 96,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final path in allPaths) ...[
                  _photoThumbnail(entry, path, cs),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          )
        else
          _emptyStateButton(
            Icons.add_a_photo_outlined,
            'Fotos hinzufügen…',
            () => _addPhotos(entry),
            cs,
          ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _photoThumbnail(DayEntry entry, String storagePath, ColorScheme cs) {
    final isDeleting = _deletingPhotos.contains(storagePath);

    if (isDeleting) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          width: 88,
          height: 88,
          child: Container(
            color: cs.surfaceContainerHighest,
            child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ),
        ),
      );
    }

    return FutureBuilder<File?>(
      future: PhotoService.localFile(storagePath),
      builder: (context, snap) {
        return Stack(
          children: [
            GestureDetector(
              onTap: () { if (snap.data != null) _viewPhoto(snap.data!); },
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 88,
                  height: 88,
                  child: switch (snap.connectionState) {
                    ConnectionState.done when snap.data != null =>
                      Image.file(snap.data!, fit: BoxFit.cover),
                    ConnectionState.done =>
                      Container(
                        color: cs.errorContainer,
                        child: Icon(Icons.broken_image_outlined,
                            color: cs.onErrorContainer),
                      ),
                    _ => Container(
                        color: cs.surfaceContainerHighest,
                        child: const Center(
                            child: CircularProgressIndicator(strokeWidth: 2)),
                      ),
                  },
                ),
              ),
            ),
            Positioned(
              top: 3,
              right: 3,
              child: GestureDetector(
                onTap: () => _deletePhoto(entry, storagePath),
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: cs.errorContainer.withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(Icons.close, size: 14, color: cs.onErrorContainer),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _addPhotos(DayEntry entry) async {
    final day = DateTime(widget.year, widget.month, widget.day);
    final paths = await PhotoService.pickAndUpload(day);
    if (!mounted || paths.isEmpty) return;
    entry.photos.addAll(paths);
    context.read<HomeRepository>().saveEntry(entry);
  }

  void _deletePhoto(DayEntry entry, String storagePath) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return AlertDialog(
          backgroundColor: cs.surfaceContainerHigh,
          titleTextStyle: TextStyle(
              color: cs.onSurface,
              fontSize: 18,
              fontWeight: FontWeight.w600),
          title: const Text('Foto löschen?'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text('Abbrechen', style: TextStyle(color: cs.primary))),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Löschen')),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;
    setState(() => _deletingPhotos.add(storagePath));
    entry.photos.remove(storagePath);
    context.read<HomeRepository>().saveEntry(entry);
    await PhotoService.delete(storagePath);
    if (mounted) setState(() => _deletingPhotos.remove(storagePath));
  }

  void _viewPhoto(File file) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: EdgeInsets.zero,
        child: GestureDetector(
          onTap: () => Navigator.pop(context),
          child: InteractiveViewer(
            child: Image.file(file),
          ),
        ),
      ),
    );
  }

  // ── Vessel Status ─────────────────────────────────────────────────
  Widget _buildVesselStatus(DayEntry entry, ColorScheme cs) {
    final isDark = cs.brightness == Brightness.dark;
    final cardBg = isDark ? cs.tertiaryContainer : cs.tertiary;
    final cardFg = isDark ? cs.onTertiaryContainer : cs.onTertiary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'SCHIFFSSTATUS',
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5,
                color: cs.secondary,
              ),
            ),
            const Spacer(),
            GestureDetector(
              onTap: () => _editVesselStatus(entry),
              child: Row(
                children: [
                  Icon(Icons.edit, size: 16, color: cs.secondary),
                  const SizedBox(width: 4),
                  Text(
                    'AKTUALISIEREN',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.5,
                      color: cs.secondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(12),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              Positioned(
                top: 0,
                right: 0,
                child: Opacity(
                  opacity: 0.10,
                  child: Icon(Icons.water_drop,
                      size: 80, color: cardFg),
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _vesselStatCell(
                            'MOTORÖL', entry.oilLevel, Icons.check_circle, cs, cardFg),
                      ),
                      const SizedBox(width: 20),
                      Expanded(
                        child: _vesselStatCell('KRAFTSTOFF', entry.fuelLevel,
                            Icons.local_gas_station, cs, cardFg),
                      ),
                    ],
                  ),
                  Divider(
                    color: cardFg.withValues(alpha: 0.15),
                    height: 24,
                    thickness: 1,
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'KIEL',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.5,
                          color: cardFg.withValues(alpha: 0.70),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          KeelIcon(
                            size: 28,
                            color: entry.keelDown == null
                                ? cardFg.withValues(alpha: 0.35)
                                : cardFg,
                            keelDown: entry.keelDown,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            entry.keelDown == null
                                ? '—'
                                : (entry.keelDown! ? 'UNTEN' : 'OBEN'),
                            style: GoogleFonts.newsreader(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: entry.keelDown == null
                                  ? cardFg.withValues(alpha: 0.45)
                                  : cardFg,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _vesselStatCell(
      String label, int? level, IconData icon, ColorScheme cs, Color onCard) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.5,
            color: onCard.withValues(alpha: 0.70),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Icon(icon, color: onCard.withValues(alpha: 0.75), size: 20),
            const SizedBox(width: 8),
            Text(
              level != null ? '$level%' : '—',
              style: GoogleFonts.newsreader(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: level != null ? onCard : onCard.withValues(alpha: 0.54),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: Stack(
            children: [
              Container(height: 8, color: onCard.withValues(alpha: 0.20)),
              if (level != null)
                FractionallySizedBox(
                  widthFactor: level / 100,
                  child: Container(height: 8, color: cs.secondaryFixed),
                ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label == 'KRAFTSTOFF' ? 'LEER' : 'MIN',
              style: GoogleFonts.inter(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
                color: onCard.withValues(alpha: 0.50),
              ),
            ),
            Text(
              'VOLL',
              style: GoogleFonts.inter(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
                color: onCard.withValues(alpha: 0.50),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── Empty state helper ────────────────────────────────────────────
  Widget _emptyStateButton(
      IconData icon, String label, VoidCallback onTap, ColorScheme cs) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding:
            const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
        decoration: BoxDecoration(
          border: Border.all(color: cs.outlineVariant, width: 1.5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: cs.onSurfaceVariant, size: 22),
            const SizedBox(width: 8),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 15,
                fontStyle: FontStyle.italic,
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Map ──────────────────────────────────────────────────────────
  Widget _buildMap(DayEntry entry, DailyTrack? track) {
    if (track == null || track.points.isEmpty) return const SizedBox();

    final cs = Theme.of(context).colorScheme;
    final provider = context.watch<ThemeProvider>();
    final filterSettings = provider.filterSettings;
    final showRawTrack = provider.showRawTrack;
    final display    = buildDisplayModel(track.points, settings: filterSettings);
    final correlated = correlateTimelineWithTrack(entry.timeline, track.points);

    final startPoint = display.firstMovingPoint ?? track.points.first;
    final endPoint   = display.lastMovingPoint  ?? track.points.last;

    final cleanedLatLngs =
        display.movingPoints().map((p) => LatLng(p.lat, p.lon)).toList();

    // Bounding box covers all rendered coords + stop centroids
    final boundsLatLngs = [
      for (final s in display.segments)
        if (s.kind != SegmentKind.teleportBreak)
          ...s.points.map((p) => LatLng(p.lat, p.lon)),
      for (final s in display.stops) LatLng(s.lat, s.lon),
    ];
    final fitLatLngs = boundsLatLngs.isNotEmpty
        ? boundsLatLngs
        : track.points.map((p) => LatLng(p.lat, p.lon)).toList();
    final trackBounds = fitLatLngs.isNotEmpty ? LatLngBounds.fromPoints(fitLatLngs) : null;

    final startStop = display.startStop;
    final endStop   = display.endStop;
    final startPos  = startStop != null
        ? LatLng(startStop.lat, startStop.lon)
        : LatLng(startPoint.lat, startPoint.lon);
    final endPos    = endStop != null
        ? LatLng(endStop.lat, endStop.lon)
        : LatLng(endPoint.lat, endPoint.lon);

    final departureBearing = cleanedLatLngs.length >= 2
        ? _dayDetailDepartureBearing(cleanedLatLngs, startPos) : 0.0;
    final arrivalBearing = cleanedLatLngs.length >= 2
        ? _dayDetailArrivalBearing(cleanedLatLngs, endPos) : 0.0;
    final startTimeStr = DateFormat('HH:mm').format(startPoint.time.toLocal());
    final endTimeStr   = DateFormat('HH:mm').format(endPoint.time.toLocal());

    // Stop halos: two concentric circles per stop
    final anchorCircles = <CircleMarker>[];
    for (final stop in display.stops) {
      anchorCircles.add(CircleMarker(
        point: LatLng(stop.lat, stop.lon),
        radius: stop.r95M,
        useRadiusInMeter: true,
        color: cs.primary.withValues(alpha: 0.07),
      ));
      anchorCircles.add(CircleMarker(
        point: LatLng(stop.lat, stop.lon),
        radius: stop.cep50M,
        useRadiusInMeter: true,
        color: cs.primary.withValues(alpha: 0.22),
        borderStrokeWidth: 1.5,
        borderColor: cs.primary.withValues(alpha: 0.50),
      ));
    }

    // Uncertainty bands: translucent blue corridor per moving segment.
    // Gated to zoom > 15 by _ZoomAwareUncertaintyLayer (sub-pixel at route zoom).
    // Fixed blue regardless of theme — reads as "confidence", not alarm.
    final uncertaintyPolygons = display.uncertaintyBands()
        .map((ring) => Polygon(
              points: ring.map((c) => LatLng(c.$1, c.$2)).toList(),
              color: const Color(0x1A42A5F5), // Blue 400 at ~10 %
              borderStrokeWidth: 0,
            ))
        .toList();

    final trackPolylines = <Polyline>[];
    for (final seg in display.segments) {
      if (seg.kind == SegmentKind.moving && seg.points.length >= 2) {
        trackPolylines.add(Polyline(
          points: seg.points.map((p) => LatLng(p.lat, p.lon)).toList(),
          strokeWidth: 4,
          color: cs.primary,
        ));
      } else if ((seg.kind == SegmentKind.stopEntry ||
                  seg.kind == SegmentKind.stopExit) &&
                 seg.points.length >= 2) {
        trackPolylines.add(Polyline(
          points: seg.points.map((p) => LatLng(p.lat, p.lon)).toList(),
          strokeWidth: 2.5,
          color: cs.primary.withValues(alpha: 0.40),
        ));
      }
      // teleportBreak: no polyline drawn — gap is the visual signal
    }

    final timelineMarkers = correlated.map((pair) {
      final t = pair.$1;
      final p = pair.$2;
      return Marker(
        point: LatLng(p.lat, p.lon),
        width: 20,
        height: 20,
        alignment: Alignment.center,
        child: Tooltip(
          richMessage: TextSpan(text: _buildEntryTooltip(t)),
          preferBelow: false,
          triggerMode: TooltipTriggerMode.tap,
          showDuration: const Duration(seconds: 5),
          waitDuration: Duration.zero,
          child: Center(
            child: Container(
              width: 11,
              height: 11,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: cs.surface,
                border: Border.all(color: cs.primary, width: 2.5),
              ),
            ),
          ),
        ),
      );
    }).toList();

    final timeWaypoints = _sampleHourlyPoints(display.movingPoints()).map((p) =>
      Marker(
        point: LatLng(p.lat, p.lon),
        width: 20,
        height: 20,
        alignment: Alignment.center,
        child: Tooltip(
          message: DateFormat('HH:mm').format(p.time.toLocal()),
          preferBelow: false,
          triggerMode: _isTouchPlatform ? TooltipTriggerMode.tap : TooltipTriggerMode.longPress,
          showDuration: _isTouchPlatform ? const Duration(seconds: 4) : const Duration(milliseconds: 1500),
          waitDuration: _isTouchPlatform ? Duration.zero : const Duration(milliseconds: 400),
          child: Center(
            child: Container(
              width: 11,
              height: 11,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: cs.primary.withValues(alpha: 0.12),
                border: Border.all(
                  color: cs.primary.withValues(alpha: 0.60),
                  width: 2.5,
                ),
              ),
            ),
          ),
        ),
      ),
    ).toList();

    final midStopMarkers = [
      for (final stop in display.stops.where((s) => s.kind == AnchorKind.mid))
        Marker(
          point: LatLng(stop.lat, stop.lon),
          width: 32,
          height: 32,
          alignment: Alignment.center,
          child: Tooltip(
            message: _fmtDur(stop.minutes),
            triggerMode: _isTouchPlatform ? TooltipTriggerMode.tap : TooltipTriggerMode.longPress,
            showDuration: _isTouchPlatform ? const Duration(seconds: 4) : const Duration(milliseconds: 1500),
            waitDuration: _isTouchPlatform ? Duration.zero : const Duration(milliseconds: 400),
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.85),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.5),
                boxShadow: [BoxShadow(
                  color: Colors.black.withValues(alpha: 0.20),
                  blurRadius: 3, offset: const Offset(0, 1))],
              ),
              child: Icon(
                stop.minutes >= 30 ? Icons.anchor : Icons.schedule,
                size: 14,
                color: Colors.white,
              ),
            ),
          ),
        ),
    ];

    final markers = <Marker>[
      ...timeWaypoints,
      ...timelineMarkers,
      ...midStopMarkers,
      // ── Departure: label to the left, arrow at the coordinate ───────
      Marker(
        point: startPos,
        width: 82,
        height: 22,
        alignment: Alignment.centerRight,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _trackLabel(startTimeStr, cs),
            const SizedBox(width: 5),
            Transform.rotate(
              angle: departureBearing,
              child: _trackArrow(cs.primary),
            ),
          ],
        ),
      ),
      // ── Arrival: arrow at the coordinate, label to the right ────────
      Marker(
        point: endPos,
        width: 82,
        height: 22,
        alignment: Alignment.centerLeft,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Transform.rotate(
              angle: arrivalBearing,
              child: _trackArrow(cs.primary),
            ),
            const SizedBox(width: 5),
            _trackLabel(endTimeStr, cs),
          ],
        ),
      ),
    ];

    if (_droppedMarkerLatLng != null) {
      markers.add(Marker(
        point: _droppedMarkerLatLng!,
        width: 20,
        height: 20,
        alignment: Alignment.center,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            _markerDismissTimer?.cancel();
            setState(() { _droppedMarkerLatLng = null; _droppedMarkerLabel = null; });
          },
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Container(
                width: 11, height: 11,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: cs.surface,
                  border: Border.all(color: cs.primary, width: 2.5),
                ),
              ),
              if (_droppedMarkerLabel != null)
                Positioned(
                  left: 16, top: 3,
                  child: IgnorePointer(child: _trackLabel(_droppedMarkerLabel!, cs)),
                ),
            ],
          ),
        ),
      ));
    }

    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCameraFit: trackBounds != null
                ? CameraFit.bounds(bounds: trackBounds, padding: const EdgeInsets.all(40))
                : null,
            onTap: (_, latLng) {
              final nearest =
                  _findNearestTrackPoint(latLng, track.points);
              if (nearest == null) return;
              _dropMarker(
                LatLng(nearest.lat, nearest.lon),
                DateFormat('HH:mm').format(nearest.time.toLocal()),
              );
            },
          ),
          children: [
            TileLayer(
              urlTemplate: _satelliteView
                  ? 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}'
                  : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.logbook.app',
            ),
            _ZoomAwareUncertaintyLayer(polygons: uncertaintyPolygons),
            if (showRawTrack) _ZoomAwareRawTrackLayer(rawPoints: display.rawMovingPoints),
            _ZoomAwareCircleLayer(circles: anchorCircles),
            PolylineLayer(polylines: trackPolylines, cullingMargin: null, simplificationTolerance: 0),
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
                  TextSourceAttribution(
                      '© OpenStreetMap contributors', onTap: () async {
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
        // Map controls — zoom + center on macOS, satellite always
        Positioned(
          right: 10,
          bottom: 10,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (defaultTargetPlatform == TargetPlatform.macOS) ...[
                _smallMapBtn(Icons.add, () => _mapController.move(
                  _mapController.camera.center,
                  _mapController.camera.zoom + 1,
                )),
                const SizedBox(height: 6),
                _smallMapBtn(Icons.remove, () => _mapController.move(
                  _mapController.camera.center,
                  _mapController.camera.zoom - 1,
                )),
                const SizedBox(height: 6),
                _smallMapBtn(Icons.explore, () {
                  if (fitLatLngs.isNotEmpty) {
                    _mapController.fitCamera(CameraFit.bounds(
                      bounds: LatLngBounds.fromPoints(fitLatLngs),
                      padding: const EdgeInsets.all(32),
                    ));
                  }
                }),
                const SizedBox(height: 6),
              ],
              FloatingActionButton.small(
                heroTag: 'detail_fullscreen_button',
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => _DayMapFullScreen(
                      entry: entry,
                      track: track,
                      filterSettings: context.read<ThemeProvider>().filterSettings,
                      initialSatellite: _satelliteView,
                      showRawTrack: context.read<ThemeProvider>().showRawTrack,
                    ),
                  ),
                ),
                tooltip: 'Vollbild',
                child: const Icon(Icons.fullscreen),
              ),
              const SizedBox(height: 6),
              FloatingActionButton.small(
                heroTag: 'detail_satellite_button',
                onPressed: () =>
                    setState(() => _satelliteView = !_satelliteView),
                tooltip:
                    _satelliteView ? 'Kartenansicht' : 'Satellitenansicht',
                child: Icon(_satelliteView
                    ? Icons.map_outlined
                    : Icons.satellite_alt),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Edit dialogs ──────────────────────────────────────────────────
  void _editNotes(DayEntry entry) async {
    final result = await showDialog<String>(
      context: context,
      builder: (_) => _EditTextDialog(
        title: 'Tagebucheintrag',
        initialText: entry.notes,
        hintText: 'Notizen für diesen Tag…',
      ),
    );
    if (!mounted || result == null) return;
    setState(() {
      entry.notes = result.trim().isEmpty ? null : result.trim();
      context.read<HomeRepository>().saveEntry(entry);
    });
  }

  void _changeDate(DayEntry entry) async {
    final current = DateTime(widget.year, widget.month, widget.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      locale: const Locale('de', 'CH'),
    );
    if (!mounted || picked == null) return;
    final newDate = DateTime(picked.year, picked.month, picked.day);
    if (newDate == current) return;

    // If a GPX track is present, warn if it belongs to a different day.
    if (entry.track.isNotEmpty) {
      final counts = <DateTime, int>{};
      for (final p in entry.track) {
        final d = DateTime(p.time.toLocal().year, p.time.toLocal().month,
            p.time.toLocal().day);
        counts[d] = (counts[d] ?? 0) + 1;
      }
      final dominantDate =
          counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
      if (dominantDate != newDate) {
        final proceed = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Falsches Datum?'),
            content: Text(
              'Der GPX-Track enthält hauptsächlich Daten vom '
              '${DateFormat('d. MMMM yyyy', 'de_CH').format(dominantDate)}, '
              'nicht vom ${DateFormat('d. MMMM yyyy', 'de_CH').format(newDate)}.\n\n'
              'Trotzdem verschieben?',
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Abbrechen')),
              TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Trotzdem verschieben')),
            ],
          ),
        );
        if (!mounted || proceed != true) return;
      }
    }

    final repo = context.read<HomeRepository>();
    final ok = await repo.changeEntryDate(current, newDate);
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Für dieses Datum existiert bereits ein Eintrag.')));
      return;
    }
    context.go('/day/${newDate.year}/${newDate.month}/${newDate.day}');
  }

  void _startEditRoute(DayEntry entry) {
    _fromHarborCtrl.text = entry.fromHarbor ?? '';
    _toHarborCtrl.text = entry.toHarbor ?? '';
    setState(() => _editingRoute = true);
  }

  void _saveRoute(DayEntry entry) {
    setState(() {
      entry.fromHarbor = _fromHarborCtrl.text.trim().isEmpty
          ? null
          : _fromHarborCtrl.text.trim();
      entry.toHarbor = _toHarborCtrl.text.trim().isEmpty
          ? null
          : _toHarborCtrl.text.trim();
      context.read<HomeRepository>().saveEntry(entry);
      _editingRoute = false;
    });
  }

  void _editVesselStatus(DayEntry entry) async {
    int oilVal = entry.oilLevel ?? 50;
    int fuelVal = entry.fuelLevel ?? 50;
    bool? keelVal = entry.keelDown;
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          final cs = Theme.of(ctx).colorScheme;
          return AlertDialog(
            title: Text(
              'Schiffsstatus',
              style: GoogleFonts.newsreader(
                  fontSize: 18, fontWeight: FontWeight.w600,
                  color: cs.onSurface),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Motoröl', style: TextStyle(color: cs.onSurface)),
                    Text('$oilVal%',
                        style: TextStyle(
                            fontWeight: FontWeight.w600, color: cs.onSurface)),
                  ],
                ),
                Slider(
                  value: oilVal.toDouble(),
                  min: 0,
                  max: 100,
                  divisions: 20,
                  onChanged: (v) => setS(() => oilVal = v.round()),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Kraftstoff', style: TextStyle(color: cs.onSurface)),
                    Text('$fuelVal%',
                        style: TextStyle(
                            fontWeight: FontWeight.w600, color: cs.onSurface)),
                  ],
                ),
                Slider(
                  value: fuelVal.toDouble(),
                  min: 0,
                  max: 100,
                  divisions: 20,
                  onChanged: (v) => setS(() => fuelVal = v.round()),
                ),
                const Divider(height: 24),
                Row(
                  children: [
                    Text('Kiel', style: TextStyle(color: cs.onSurface)),
                    const Spacer(),
                    Text(
                      keelVal == null ? '—' : (keelVal! ? 'Unten' : 'Oben'),
                      style: TextStyle(
                          fontWeight: FontWeight.w600, color: cs.onSurface),
                    ),
                    const SizedBox(width: 8),
                    Switch(
                      value: keelVal ?? false,
                      onChanged: (v) => setS(() => keelVal = v),
                    ),
                  ],
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Abbrechen'),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.pop(ctx, true),
                icon: const Icon(Icons.anchor, size: 18),
                label: const Text('Speichern'),
              ),
            ],
          );
        },
      ),
    );
    if (!mounted || saved != true) return;
    final oldOil = entry.oilLevel;
    final oldFuel = entry.fuelLevel;
    final oldKeel = entry.keelDown;
    final now = DateTime.now();
    final entryTime = DateTime(widget.year, widget.month, widget.day, now.hour, now.minute);
    setState(() {
      entry.oilLevel = oilVal;
      entry.fuelLevel = fuelVal;
      entry.keelDown = keelVal;
      if (oilVal != oldOil || fuelVal != oldFuel) {
        entry.timeline.add(TimelineEntry(
          time: entryTime,
          vesselStatusNote: 'Motoröl: $oilVal% · Kraftstoff: $fuelVal%',
        ));
      }
      if (keelVal != oldKeel && keelVal != null) {
        entry.timeline.add(TimelineEntry(
          time: entryTime,
          vesselStatusNote: keelVal! ? 'Kiel: Unten' : 'Kiel: Oben',
        ));
      }
      entry.timeline.sort((a, b) => a.time.compareTo(b.time));
      context.read<HomeRepository>().saveEntry(entry);
    });
  }

  // ── Crew helpers ──────────────────────────────────────────────────
  void _addCrewMember(DayEntry entry) async {
    final member = await showDialog<CrewMember>(
      context: context,
      builder: (_) => const AddCrewMemberDialog(),
    );
    if (!mounted || member == null) return;
    setState(() {
      entry.crew.add(member);
      context.read<HomeRepository>().saveEntry(entry);
    });
  }

  void _editCrewMember(DayEntry entry, int index) async {
    final member = entry.crew[index];
    final updated = await showDialog<CrewMember>(
      context: context,
      builder: (_) => AddCrewMemberDialog(
        initialMember: member,
        onDelete: () => _removeCrewMember(entry, member),
      ),
    );
    if (!mounted || updated == null) return;
    setState(() {
      final i = entry.crew.indexOf(member);
      if (i != -1) entry.crew[i] = updated;
      context.read<HomeRepository>().saveEntry(entry);
    });
  }

  void _removeCrewMember(DayEntry entry, CrewMember member) {
    setState(() {
      entry.crew.remove(member);
      context.read<HomeRepository>().saveEntry(entry);
    });
  }

  // ── Timeline mutations ────────────────────────────────────────────
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
    final index = entry.timeline.indexOf(t);
    setState(() {
      entry.timeline.remove(t);
      final repo = context.read<HomeRepository>();
      repo.syncKeelFromTimeline(entry);
      repo.saveEntry(entry);
    });
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: const Text('Logeintrag gelöscht'),
        action: SnackBarAction(
          label: 'Rückgängig',
          onPressed: () {
            if (!mounted) return;
            setState(() {
              entry.timeline.insert(index.clamp(0, entry.timeline.length), t);
              entry.timeline.sort((a, b) => a.time.compareTo(b.time));
              final repo = context.read<HomeRepository>();
              repo.syncKeelFromTimeline(entry);
              repo.saveEntry(entry);
            });
          },
        ),
      ));
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
        final repo = context.read<HomeRepository>();
        repo.syncKeelFromTimeline(entry);
        repo.saveEntry(entry);
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Logeintrag aktualisiert')));
  }

  // ── GPX ───────────────────────────────────────────────────────────
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
      final path = picked.path;
      if (path == null) return;
      preview = await GpxParser().parse(File(path));
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

  void _exportGpx(DailyTrack track, DateTime day) async {
    final filterSettings = context.read<ThemeProvider>().filterSettings;
    final vesselName    = context.read<ThemeProvider>().vesselName;
    final display = buildDisplayModel(track.points, settings: filterSettings);
    final gpxStr  = buildGpxExport(
      rawPoints:  track.points,
      display:    display,
      date:       day,
      vesselName: vesselName,
    );
    final bytes    = utf8.encode(gpxStr);
    final fileName = 'logbuch_${DateFormat('yyyy-MM-dd').format(day)}.gpx';

    final result = await FilePicker.saveFile(
      dialogTitle:       'GPX exportieren',
      fileName:          fileName,
      type:              FileType.custom,
      allowedExtensions: ['gpx'],
      bytes:             Uint8List.fromList(bytes),
    );

    if (mounted && result != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('GPX exportiert.')),
      );
    }
  }

  void _exportPdf(DayEntry entry, DailyStats? stats, DailyTrack? track) async {
    final p = context.read<ThemeProvider>();
    final filteredPoints = track != null
        ? buildDisplayModel(track.points, settings: p.filterSettings).allPoints()
        : const <TrackPoint>[];
    final photoBytes = <Uint8List>[];
    for (final path in entry.photos) {
      final file = await PhotoService.localFile(path);
      if (file != null) photoBytes.add(await file.readAsBytes());
    }
    final bytes = await buildVoyagePdf(
      entry:       entry,
      stats:       stats,
      vesselName:  p.vesselName,
      trackPoints: filteredPoints,
      photoBytes:  photoBytes,
    );
    final fileName =
        'logbuch_${DateFormat('yyyy-MM-dd').format(entry.date)}.pdf';
    await Printing.sharePdf(bytes: bytes, filename: fileName);
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
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return AlertDialog(
          title: Text('Tag löschen?', style: TextStyle(color: cs.onSurface)),
          content: Text(
            'Alle Daten für den $dateLabel werden unwiderruflich gelöscht, '
            'inklusive Logeinträge und GPX-Track.',
            style: TextStyle(color: cs.onSurface),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Abbrechen')),
            TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text('Löschen', style: TextStyle(color: cs.error))),
          ],
        );
      },
    );
    if (!mounted || confirmed != true) return;
    await repo.removeEntry(day);
    if (!mounted) return;
    context.go('/');
  }

  // ── Map helpers ───────────────────────────────────────────────────
  void _dropMarker(LatLng pos, String label) {
    _markerDismissTimer?.cancel();
    setState(() {
      _droppedMarkerLatLng = pos;
      _droppedMarkerLabel = label;
    });
    _markerDismissTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) {
        setState(() {
          _droppedMarkerLatLng = null;
          _droppedMarkerLabel = null;
        });
      }
    });
  }

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

  Widget _gpxUploadIcon() {
    return SizedBox(
      width: 26,
      height: 26,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Icon(Icons.file_upload_outlined, size: 22, color: Theme.of(context).colorScheme.onSurface),
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

  Widget _smallMapBtn(IconData icon, VoidCallback onTap) {
    final cs = Theme.of(context).colorScheme;
    return FloatingActionButton.small(
      heroTag: icon.codePoint,
      onPressed: onTap,
      backgroundColor: cs.surfaceContainerLowest,
      foregroundColor: cs.primary,
      elevation: 2,
      child: Icon(icon, size: 18),
    );
  }

  // ── Map marker helpers ────────────────────────────────────────────

  Widget _trackArrow(Color color) => Container(
        width: 15,
        height: 15,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.85),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 1.5),
        ),
        alignment: Alignment.center,
        child: const Icon(Icons.arrow_upward, color: Colors.white, size: 8),
      );

  Widget _trackLabel(String text, ColorScheme cs) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        decoration: BoxDecoration(
          color: cs.primary.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          text,
          style: GoogleFonts.inter(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      );

}

// ── File-level geometry helpers (used by both day-detail and fullscreen) ──────

double _trackBearing(LatLng from, LatLng to) {
  final lat1 = from.latitude  * pi / 180;
  final lat2 = to.latitude    * pi / 180;
  final dLon = (to.longitude - from.longitude) * pi / 180;
  final y = sin(dLon) * cos(lat2);
  final x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon);
  return atan2(y, x);
}

double _distM(LatLng a, LatLng b) {
  const r   = 6371000.0;
  final lat1 = a.latitude  * pi / 180;
  final lat2 = b.latitude  * pi / 180;
  final dLat = (b.latitude  - a.latitude)  * pi / 180;
  final dLon = (b.longitude - a.longitude) * pi / 180;
  final s = sin(dLat / 2) * sin(dLat / 2) +
      cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2);
  return r * 2 * atan2(sqrt(s), sqrt(1 - s));
}

double _dayDetailDepartureBearing(List<LatLng> pts, LatLng origin) {
  if (pts.length < 2) return 0;
  const targetM = 500.0;
  double cum = 0;
  for (int i = 1; i < pts.length; i++) {
    cum += _distM(pts[i - 1], pts[i]);
    if (cum >= targetM) return _trackBearing(origin, pts[i]);
  }
  double maxD = 0; int farIdx = 1;
  for (int i = 1; i < pts.length; i++) {
    final d = _distM(origin, pts[i]);
    if (d > maxD) { maxD = d; farIdx = i; }
  }
  return _trackBearing(origin, pts[farIdx]);
}

double _dayDetailArrivalBearing(List<LatLng> pts, LatLng destination) {
  if (pts.length < 2) return 0;
  const targetM = 500.0;
  double cum = 0;
  for (int i = pts.length - 2; i >= 0; i--) {
    cum += _distM(pts[i], pts[i + 1]);
    if (cum >= targetM) return _trackBearing(pts[i], destination);
  }
  double maxD = 0; int farIdx = 0;
  for (int i = 0; i < pts.length - 1; i++) {
    final d = _distM(pts[i], destination);
    if (d > maxD) { maxD = d; farIdx = i; }
  }
  return _trackBearing(pts[farIdx], destination);
}

// ── Full-screen map for a single day ──────────────────────────────────────────

class _DayMapFullScreen extends StatefulWidget {
  final DayEntry entry;
  final DailyTrack track;
  final FilterSettings filterSettings;
  final bool initialSatellite;
  final bool showRawTrack;

  const _DayMapFullScreen({
    required this.entry,
    required this.track,
    required this.filterSettings,
    required this.initialSatellite,
    required this.showRawTrack,
  });

  @override
  State<_DayMapFullScreen> createState() => _DayMapFullScreenState();
}

class _DayMapFullScreenState extends State<_DayMapFullScreen> {
  final MapController _mapController = MapController();
  late bool _satelliteView;
  LatLng? _droppedMarkerLatLng;
  String? _droppedMarkerLabel;
  Timer? _markerDismissTimer;

  @override
  void initState() {
    super.initState();
    _satelliteView = widget.initialSatellite;
  }

  @override
  void dispose() {
    _markerDismissTimer?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  void _dropMarker(LatLng pos, String label) {
    _markerDismissTimer?.cancel();
    setState(() {
      _droppedMarkerLatLng = pos;
      _droppedMarkerLabel  = label;
    });
    _markerDismissTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() { _droppedMarkerLatLng = null; _droppedMarkerLabel = null; });
    });
  }

  TrackPoint? _findNearest(LatLng tap, List<TrackPoint> points) {
    if (points.isEmpty) return null;
    TrackPoint? best;
    double minDq = double.infinity;
    for (final p in points) {
      final dq = (p.lat - tap.latitude) * (p.lat - tap.latitude) +
                 (p.lon - tap.longitude) * (p.lon - tap.longitude);
      if (dq < minDq) { minDq = dq; best = p; }
    }
    return best;
  }

  Widget _trackArrow(Color color) => Container(
    width: 15, height: 15,
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.85),
      shape: BoxShape.circle,
      border: Border.all(color: Colors.white, width: 1.5),
    ),
    alignment: Alignment.center,
    child: const Icon(Icons.arrow_upward, color: Colors.white, size: 8),
  );

  Widget _trackLabel(String text, ColorScheme cs) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
    decoration: BoxDecoration(
      color: cs.primary.withValues(alpha: 0.85),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(text, style: GoogleFonts.inter(
      fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white)),
  );

  Widget _mapBtn(IconData icon, VoidCallback onTap, ColorScheme cs) =>
    FloatingActionButton.small(
      heroTag: 'fs_${icon.codePoint}',
      onPressed: onTap,
      backgroundColor: cs.surfaceContainerLowest,
      foregroundColor: cs.primary,
      elevation: 2,
      child: Icon(icon, size: 18),
    );

  @override
  Widget build(BuildContext context) {
    final cs    = Theme.of(context).colorScheme;
    final track = widget.track;
    final entry = widget.entry;

    final display    = buildDisplayModel(track.points, settings: widget.filterSettings);
    final correlated = correlateTimelineWithTrack(entry.timeline, track.points);

    final startPoint = display.firstMovingPoint ?? track.points.first;
    final endPoint   = display.lastMovingPoint  ?? track.points.last;
    final cleanedLatLngs = display.movingPoints().map((p) => LatLng(p.lat, p.lon)).toList();
    final boundsLatLngs = [
      for (final s in display.segments)
        if (s.kind != SegmentKind.teleportBreak)
          ...s.points.map((p) => LatLng(p.lat, p.lon)),
      for (final s in display.stops) LatLng(s.lat, s.lon),
    ];
    final fitLatLngs = boundsLatLngs.isNotEmpty
        ? boundsLatLngs
        : track.points.map((p) => LatLng(p.lat, p.lon)).toList();
    final trackBounds = fitLatLngs.isNotEmpty ? LatLngBounds.fromPoints(fitLatLngs) : null;

    final startStop = display.startStop;
    final endStop   = display.endStop;
    final startPos  = startStop != null ? LatLng(startStop.lat, startStop.lon) : LatLng(startPoint.lat, startPoint.lon);
    final endPos    = endStop   != null ? LatLng(endStop.lat,   endStop.lon)   : LatLng(endPoint.lat,   endPoint.lon);

    final departureBearing = cleanedLatLngs.length >= 2 ? _dayDetailDepartureBearing(cleanedLatLngs, startPos) : 0.0;
    final arrivalBearing   = cleanedLatLngs.length >= 2 ? _dayDetailArrivalBearing(cleanedLatLngs, endPos) : 0.0;
    final startTimeStr = DateFormat('HH:mm').format(startPoint.time.toLocal());
    final endTimeStr   = DateFormat('HH:mm').format(endPoint.time.toLocal());

    final anchorCircles = <CircleMarker>[];
    for (final stop in display.stops) {
      anchorCircles.add(CircleMarker(point: LatLng(stop.lat, stop.lon), radius: stop.r95M, useRadiusInMeter: true, color: cs.primary.withValues(alpha: 0.07)));
      anchorCircles.add(CircleMarker(point: LatLng(stop.lat, stop.lon), radius: stop.cep50M, useRadiusInMeter: true,
          color: cs.primary.withValues(alpha: 0.22), borderStrokeWidth: 1.5, borderColor: cs.primary.withValues(alpha: 0.50)));
    }

    final fsUncertaintyPolygons = display.uncertaintyBands()
        .map((ring) => Polygon(
              points: ring.map((c) => LatLng(c.$1, c.$2)).toList(),
              color: const Color(0x1A42A5F5),
              borderStrokeWidth: 0,
            ))
        .toList();

    final fsTrackPolylines = <Polyline>[];
    for (final seg in display.segments) {
      if (seg.kind == SegmentKind.moving && seg.points.length >= 2) {
        fsTrackPolylines.add(Polyline(
          points: seg.points.map((p) => LatLng(p.lat, p.lon)).toList(),
          strokeWidth: 4,
          color: cs.primary,
        ));
      } else if ((seg.kind == SegmentKind.stopEntry ||
                  seg.kind == SegmentKind.stopExit) &&
                 seg.points.length >= 2) {
        fsTrackPolylines.add(Polyline(
          points: seg.points.map((p) => LatLng(p.lat, p.lon)).toList(),
          strokeWidth: 2.5,
          color: cs.primary.withValues(alpha: 0.40),
        ));
      }
    }

    final timelineMarkers = correlated.map((pair) {
      final t = pair.$1; final p = pair.$2;
      return Marker(
        point: LatLng(p.lat, p.lon), width: 20, height: 20, alignment: Alignment.center,
        child: Tooltip(
          richMessage: TextSpan(text: _buildEntryTooltip(t)),
          preferBelow: false,
          triggerMode: TooltipTriggerMode.tap,
          showDuration: const Duration(seconds: 5),
          waitDuration: Duration.zero,
          child: Center(child: Container(
            width: 11, height: 11,
            decoration: BoxDecoration(shape: BoxShape.circle, color: cs.surface, border: Border.all(color: cs.primary, width: 2.5)),
          )),
        ),
      );
    }).toList();

    final fsTimeWaypoints = _sampleHourlyPoints(display.movingPoints()).map((p) =>
      Marker(
        point: LatLng(p.lat, p.lon), width: 20, height: 20, alignment: Alignment.center,
        child: Tooltip(
          message: DateFormat('HH:mm').format(p.time.toLocal()),
          preferBelow: false,
          triggerMode: _isTouchPlatform ? TooltipTriggerMode.tap : TooltipTriggerMode.longPress,
          showDuration: _isTouchPlatform ? const Duration(seconds: 4) : const Duration(milliseconds: 1500),
          waitDuration: _isTouchPlatform ? Duration.zero : const Duration(milliseconds: 400),
          child: Center(
            child: Container(
              width: 11, height: 11,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: cs.primary.withValues(alpha: 0.12),
                border: Border.all(color: cs.primary.withValues(alpha: 0.60), width: 2.5),
              ),
            ),
          ),
        ),
      ),
    ).toList();

    final fsMidStopMarkers = [
      for (final stop in display.stops.where((s) => s.kind == AnchorKind.mid))
        Marker(
          point: LatLng(stop.lat, stop.lon),
          width: 32,
          height: 32,
          alignment: Alignment.center,
          child: Tooltip(
            message: _fmtDur(stop.minutes),
            triggerMode: _isTouchPlatform ? TooltipTriggerMode.tap : TooltipTriggerMode.longPress,
            showDuration: _isTouchPlatform ? const Duration(seconds: 4) : const Duration(milliseconds: 1500),
            waitDuration: _isTouchPlatform ? Duration.zero : const Duration(milliseconds: 400),
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.85),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.5),
                boxShadow: [BoxShadow(
                  color: Colors.black.withValues(alpha: 0.20),
                  blurRadius: 3, offset: const Offset(0, 1))],
              ),
              child: Icon(
                stop.minutes >= 30 ? Icons.anchor : Icons.schedule,
                size: 14,
                color: Colors.white,
              ),
            ),
          ),
        ),
    ];

    final markers = <Marker>[
      ...fsTimeWaypoints,
      ...timelineMarkers,
      ...fsMidStopMarkers,
      Marker(
        point: startPos, width: 82, height: 22, alignment: Alignment.centerRight,
        child: Row(mainAxisAlignment: MainAxisAlignment.end, crossAxisAlignment: CrossAxisAlignment.center, children: [
          _trackLabel(startTimeStr, cs), const SizedBox(width: 5),
          Transform.rotate(angle: departureBearing, child: _trackArrow(cs.primary)),
        ]),
      ),
      Marker(
        point: endPos, width: 82, height: 22, alignment: Alignment.centerLeft,
        child: Row(mainAxisAlignment: MainAxisAlignment.start, crossAxisAlignment: CrossAxisAlignment.center, children: [
          Transform.rotate(angle: arrivalBearing, child: _trackArrow(cs.primary)),
          const SizedBox(width: 5), _trackLabel(endTimeStr, cs),
        ]),
      ),
    ];

    if (_droppedMarkerLatLng != null) {
      markers.add(Marker(
        point: _droppedMarkerLatLng!,
        width: 20,
        height: 20,
        alignment: Alignment.center,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            _markerDismissTimer?.cancel();
            setState(() { _droppedMarkerLatLng = null; _droppedMarkerLabel = null; });
          },
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Container(
                width: 11, height: 11,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: cs.surface,
                  border: Border.all(color: cs.primary, width: 2.5),
                ),
              ),
              if (_droppedMarkerLabel != null)
                Positioned(
                  left: 16, top: 3,
                  child: IgnorePointer(child: _trackLabel(_droppedMarkerLabel!, cs)),
                ),
            ],
          ),
        ),
      ));
    }

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: Padding(
          padding: const EdgeInsets.all(8),
          child: FloatingActionButton.small(
            heroTag: 'fs_close',
            onPressed: () => Navigator.pop(context),
            backgroundColor: cs.surfaceContainerLowest.withValues(alpha: 0.9),
            foregroundColor: cs.primary,
            elevation: 2,
            child: const Icon(Icons.fullscreen_exit, size: 20),
          ),
        ),
      ),
      body: Stack(children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCameraFit: trackBounds != null
                ? CameraFit.bounds(bounds: trackBounds, padding: const EdgeInsets.all(60))
                : null,
            onTap: (_, latLng) {
              final nearest = _findNearest(latLng, track.points);
              if (nearest == null) return;
              _dropMarker(LatLng(nearest.lat, nearest.lon),
                  DateFormat('HH:mm').format(nearest.time.toLocal()));
            },
          ),
          children: [
            TileLayer(
              urlTemplate: _satelliteView
                  ? 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}'
                  : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.logbook.app',
            ),
            _ZoomAwareUncertaintyLayer(polygons: fsUncertaintyPolygons),
            if (widget.showRawTrack) _ZoomAwareRawTrackLayer(rawPoints: display.rawMovingPoints),
            _ZoomAwareCircleLayer(circles: anchorCircles),
            PolylineLayer(polylines: fsTrackPolylines, cullingMargin: null, simplificationTolerance: 0),
            MarkerLayer(markers: markers),
            RichAttributionWidget(attributions: [
              if (_satelliteView)
                TextSourceAttribution('© Esri World Imagery', onTap: () async {
                  final uri = Uri.parse('https://www.esri.com');
                  if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
                })
              else
                TextSourceAttribution('© OpenStreetMap contributors', onTap: () async {
                  final uri = Uri.parse('https://www.openstreetmap.org/copyright');
                  if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
                }),
            ]),
          ],
        ),
        Positioned(
          right: 10, bottom: 10,
          child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            if (defaultTargetPlatform == TargetPlatform.macOS) ...[
              _mapBtn(Icons.add, () => _mapController.move(_mapController.camera.center, _mapController.camera.zoom + 1), cs),
              const SizedBox(height: 6),
              _mapBtn(Icons.remove, () => _mapController.move(_mapController.camera.center, _mapController.camera.zoom - 1), cs),
              const SizedBox(height: 6),
              _mapBtn(Icons.explore, () {
                if (fitLatLngs.isNotEmpty) {
                  _mapController.fitCamera(CameraFit.bounds(bounds: LatLngBounds.fromPoints(fitLatLngs), padding: const EdgeInsets.all(60)));
                }
              }, cs),
              const SizedBox(height: 6),
            ],
            FloatingActionButton.small(
              heroTag: 'fs_satellite',
              onPressed: () => setState(() => _satelliteView = !_satelliteView),
              tooltip: _satelliteView ? 'Kartenansicht' : 'Satellitenansicht',
              child: Icon(_satelliteView ? Icons.map_outlined : Icons.satellite_alt),
            ),
          ]),
        ),
      ]),
    );
  }
}

// ── Shared map helpers ────────────────────────────────────────────────────────

/// Full timeline entry as a multi-line tooltip string.
String _buildEntryTooltip(TimelineEntry t) {
  final buf = StringBuffer(DateFormat('HH:mm').format(t.time.toLocal()));

  final nav = <String>[];
  if (t.course != null) nav.add('Kurs: ${t.course!.toStringAsFixed(0)}°');
  if (t.speed  != null) nav.add('Fahrt: ${t.speed!.toStringAsFixed(1)} kn');
  if (nav.isNotEmpty) buf.write('\n${nav.join(' · ')}');

  final cond = <String>[];
  if (t.wind?.isNotEmpty    == true) cond.add('Wind: ${t.wind!}');
  if (t.sea?.isNotEmpty     == true) cond.add('See: ${t.sea!}');
  if (t.weather?.isNotEmpty == true) cond.add('Wetter: ${t.weather!}');
  if (cond.isNotEmpty) buf.write('\n${cond.join(' · ')}');

  final sails = <String>[];
  if (t.grossState?.isNotEmpty == true) sails.add('Gross: ${t.grossState}');
  if (t.fockState?.isNotEmpty  == true) sails.add('Fock: ${t.fockState}');
  if (t.motorOn  != null) sails.add('Motor: ${t.motorOn!  ? 'An'    : 'Aus'}');
  if (t.keelDown != null) sails.add('Kiel: ${t.keelDown! ? 'Unten' : 'Oben'}');
  if (sails.isNotEmpty) buf.write('\n${sails.join(' · ')}');

  if (t.remarks?.isNotEmpty          == true) buf.write('\n${t.remarks}');
  if (t.vesselStatusNote?.isNotEmpty == true) buf.write('\n${t.vesselStatusNote}');

  return buf.toString();
}

/// True on native iOS/Android; false on web and desktop.
/// Used to select tooltip trigger mode: tap on touch, hover+longPress on desktop.
bool get _isTouchPlatform =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.iOS ||
     defaultTargetPlatform == TargetPlatform.android);

/// Returns one representative TrackPoint per clock-hour, skipping the first
/// and last 20 minutes of the track to avoid overlapping start/end markers.
List<TrackPoint> _sampleHourlyPoints(List<TrackPoint> pts) {
  if (pts.length < 2) return [];
  final first = pts.first.time;
  final last  = pts.last.time;
  const minGap = Duration(minutes: 20);
  final result = <TrackPoint>[];
  DateTime? lastBucket;
  for (final p in pts) {
    if (p.time.difference(first).abs() < minGap) continue;
    if (last.difference(p.time).abs() < minGap) continue;
    final l = p.time.toLocal();
    final bucket = DateTime(l.year, l.month, l.day, l.hour);
    if (lastBucket == null || bucket.isAfter(lastBucket)) {
      result.add(p);
      lastBucket = bucket;
    }
  }
  return result;
}

String _fmtDur(double minutes) {
  final m = minutes.round();
  return m >= 60 ? '${m ~/ 60}h ${m % 60}m' : '${m}m';
}

/// Shows the GPS accuracy rings (CEP50 / R95) only at harbour zoom (> 15).
/// flutter_map propagates MapCamera via InheritedWidget, so this widget
/// rebuilds automatically whenever the camera zoom changes.
class _ZoomAwareCircleLayer extends StatelessWidget {
  final List<CircleMarker> circles;
  const _ZoomAwareCircleLayer({required this.circles});

  @override
  Widget build(BuildContext context) {
    if (circles.isEmpty) return const SizedBox.shrink();
    final zoom = MapCamera.of(context).zoom;
    if (zoom <= 15) return const SizedBox.shrink();
    return CircleLayer(circles: circles);
  }
}

/// Shows the ±GPS uncertainty corridor only at harbour/detail zoom (> 15).
/// At route zoom the band is sub-pixel and would only hurt performance.
/// Fixed blue colour regardless of theme — reads as "confidence", not alarm.
class _ZoomAwareUncertaintyLayer extends StatelessWidget {
  final List<Polygon> polygons;
  const _ZoomAwareUncertaintyLayer({required this.polygons});

  @override
  Widget build(BuildContext context) {
    if (polygons.isEmpty) return const SizedBox.shrink();
    if (MapCamera.of(context).zoom <= 15) return const SizedBox.shrink();
    return PolygonLayer(polygons: polygons);
  }
}

/// Shows the raw (unfiltered) GPS fixes only at harbour/detail zoom (> 15),
/// as faint blue texture inside the uncertainty band — not a competing line.
/// At route zoom two overlapping tracks just look like a mess.
class _ZoomAwareRawTrackLayer extends StatelessWidget {
  final List<TrackPoint> rawPoints;
  const _ZoomAwareRawTrackLayer({required this.rawPoints});

  static const _rawColor = Color(0x3342A5F5); // Blue 400 at ~20 %

  @override
  Widget build(BuildContext context) {
    if (rawPoints.isEmpty) return const SizedBox.shrink();
    if (MapCamera.of(context).zoom <= 15) return const SizedBox.shrink();
    return PolylineLayer(
      polylines: [
        for (final seg in splitTrackSegments(rawPoints))
          if (seg.length >= 2)
            Polyline(
              points: seg.map((p) => LatLng(p.lat, p.lon)).toList(),
              strokeWidth: 1.0,
              color: _rawColor,
            ),
      ],
      cullingMargin: null,
      simplificationTolerance: 0,
    );
  }
}

// ── Keel icon ─────────────────────────────────────────────────────────────────


// ── Reusable multiline-text edit dialog ───────────────────────────────────────
//
// Owns its TextEditingController so disposal is always tied to the widget
// lifecycle — avoids "controller used after dispose" when the dialog builder
// is invoked one final time during the closing animation.
class _EditTextDialog extends StatefulWidget {
  final String title;
  final String? initialText;
  final String hintText;

  const _EditTextDialog({
    required this.title,
    this.initialText,
    required this.hintText,
  });

  @override
  State<_EditTextDialog> createState() => _EditTextDialogState();
}

class _EditTextDialogState extends State<_EditTextDialog> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialText ?? '');
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text(
        widget.title,
        style: GoogleFonts.newsreader(fontSize: 18, fontWeight: FontWeight.w600),
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: TextField(
          controller: _ctrl,
          minLines: 8,
          maxLines: 14,
          keyboardType: TextInputType.multiline,
          autofocus: true,
          style: TextStyle(color: cs.onSurface),
          decoration: InputDecoration(
            hintText: widget.hintText,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            contentPadding: const EdgeInsets.all(12),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Abbrechen'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.pop(context, _ctrl.text),
          icon: const Icon(Icons.anchor, size: 18),
          label: const Text('Speichern'),
        ),
      ],
    );
  }
}
