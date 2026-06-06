import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
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
import '../domain/crew_member.dart';
import '../widgets/add_timeline_entry_dialog.dart';
import '../widgets/add_crew_member_dialog.dart';
import '../widgets/nav_bar.dart';
import '../utils/compute_daily_stats.dart';
import '../utils/gpx_parser.dart';
import '../utils/track_correlation.dart';
import '../utils/trim_track.dart';


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
  bool _satelliteView = false;
  LatLng? _droppedMarkerLatLng;
  bool _isMarkerSheetOpen = false;
  bool _editingRoute = false;
  final _fromHarborCtrl = TextEditingController();
  final _toHarborCtrl = TextEditingController();

  @override
  void dispose() {
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

    DailyStats? stats;
    if (track != null && track.points.isNotEmpty) {
      stats = computeDailyStats(track.points);
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
          '$dayName · $dateStr · LOGBUCHEINTRAG',
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
                if (value == 'delete_gpx') _removeGpx();
                if (value == 'delete_day') _deleteDay();
              },
              itemBuilder: (context) => [
                PopupMenuItem<String>(
                  value: 'change_date',
                  child: Row(children: [
                    const Icon(Icons.calendar_today_outlined),
                    const SizedBox(width: 12),
                    const Text('Datum ändern'),
                  ]),
                ),
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
            _buildReflection(entry, cs),
            _buildFreeText(entry, cs),
            _buildCrewList(entry, cs),
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
    final ctrl = TextEditingController(text: entry.freeText ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Notizen',
          style: GoogleFonts.newsreader(
              fontSize: 18, fontWeight: FontWeight.w600),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: TextField(
            controller: ctrl,
            minLines: 8,
            maxLines: 14,
            keyboardType: TextInputType.multiline,
            autofocus: true,
            decoration: InputDecoration(
              hintText: 'Freie Notizen für diesen Tag…',
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12)),
              contentPadding: const EdgeInsets.all(12),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Abbrechen'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            icon: const Icon(Icons.anchor, size: 18),
            label: const Text('Speichern'),
          ),
        ],
      ),
    );
    ctrl.dispose();
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
      child: Row(
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
                  'Ø FAHRT', '${stats.avgSpeed.toStringAsFixed(1)} kn', cs),
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

  // ── Vessel Status ─────────────────────────────────────────────────
  Widget _buildVesselStatus(DayEntry entry, ColorScheme cs) {
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
            color: cs.tertiary,
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
                      size: 80, color: cs.onTertiary),
                ),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _vesselStatCell(
                        'MOTORÖL', entry.oilLevel, Icons.check_circle, cs),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: _vesselStatCell('KRAFTSTOFF', entry.fuelLevel,
                        Icons.local_gas_station, cs),
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
      String label, int? level, IconData icon, ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.5,
            color: cs.onTertiary.withValues(alpha: 0.70),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Icon(icon, color: cs.secondaryFixed, size: 20),
            const SizedBox(width: 8),
            Text(
              level != null ? '$level%' : '—',
              style: GoogleFonts.newsreader(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: level != null ? cs.onTertiary : cs.onTertiary.withValues(alpha: 0.54),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: Stack(
            children: [
              Container(height: 8, color: cs.tertiaryContainer),
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
                color: cs.onTertiary.withValues(alpha: 0.50),
              ),
            ),
            Text(
              'VOLL',
              style: GoogleFonts.inter(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
                color: cs.onTertiary.withValues(alpha: 0.50),
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
    final trimResult = trimTrackWithAnchors(track.points);
    final polylinePoints =
        track.points.map((p) => LatLng(p.lat, p.lon)).toList();
    final correlated =
        correlateTimelineWithTrack(entry.timeline, track.points);
    final startPoint = track.points.first;
    final endPoint = track.points.last;

    final anchorCircles = <CircleMarker>[];
    for (final anchor in [trimResult.startAnchor, trimResult.endAnchor]) {
      if (anchor == null) continue;
      anchorCircles.add(CircleMarker(
        point: LatLng(anchor.lat, anchor.lon),
        radius: anchor.radiusM * 2.8,
        useRadiusInMeter: true,
        color: cs.primary.withValues(alpha: 0.07),
      ));
      anchorCircles.add(CircleMarker(
        point: LatLng(anchor.lat, anchor.lon),
        radius: anchor.radiusM,
        useRadiusInMeter: true,
        color: cs.primary.withValues(alpha: 0.22),
        borderStrokeWidth: 1.5,
        borderColor: cs.primary.withValues(alpha: 0.50),
      ));
    }

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
        width: 20,
        height: 20,
        child: Container(
          decoration: const BoxDecoration(
              shape: BoxShape.circle, color: Colors.green),
          child: const Icon(Icons.flag, color: Colors.white, size: 12),
        ),
      ),
      Marker(
        point: LatLng(endPoint.lat, endPoint.lon),
        width: 20,
        height: 20,
        child: Container(
          decoration: const BoxDecoration(
              shape: BoxShape.circle, color: Colors.red),
          child: const Icon(Icons.flag, color: Colors.white, size: 12),
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
            final screenOffset = camera.latLngToScreenOffset(_droppedMarkerLatLng!);
            final newOffset = screenOffset + details.delta;
            setState(
                () => _droppedMarkerLatLng = camera.screenOffsetToLatLng(newOffset));
          },
          onPanEnd: (_) {
            final nearest = _findNearestTrackPoint(
                _droppedMarkerLatLng!, track.points);
            if (nearest != null) _showTrackPointBottomSheet(nearest);
          },
          child: const Icon(Icons.place,
              color: Colors.deepOrange, size: 40),
        ),
      ));
    }

    return Stack(
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
            ),
            CircleLayer(circles: anchorCircles),
            PolylineLayer(
              polylines: [
                Polyline(
                  points: polylinePoints,
                  strokeWidth: 4,
                  color: cs.primary,
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
                  if (polylinePoints.isNotEmpty) {
                    _mapController.fitCamera(CameraFit.bounds(
                      bounds: LatLngBounds.fromPoints(polylinePoints),
                      padding: const EdgeInsets.all(32),
                    ));
                  }
                }),
                const SizedBox(height: 6),
              ],
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
    final ctrl = TextEditingController(text: entry.notes ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Tagebucheintrag',
          style: GoogleFonts.newsreader(
              fontSize: 18, fontWeight: FontWeight.w600),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: TextField(
            controller: ctrl,
            minLines: 8,
            maxLines: 14,
            keyboardType: TextInputType.multiline,
            autofocus: true,
            decoration: InputDecoration(
              hintText: 'Notizen für diesen Tag…',
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12)),
              contentPadding: const EdgeInsets.all(12),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Abbrechen'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            icon: const Icon(Icons.anchor, size: 18),
            label: const Text('Speichern'),
          ),
        ],
      ),
    );
    ctrl.dispose();
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
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text(
            'Schiffsstatus',
            style: GoogleFonts.newsreader(
                fontSize: 18, fontWeight: FontWeight.w600),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Motoröl'),
                  Text('$oilVal%',
                      style:
                          const TextStyle(fontWeight: FontWeight.w600)),
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
                  const Text('Kraftstoff'),
                  Text('$fuelVal%',
                      style:
                          const TextStyle(fontWeight: FontWeight.w600)),
                ],
              ),
              Slider(
                value: fuelVal.toDouble(),
                min: 0,
                max: 100,
                divisions: 20,
                onChanged: (v) => setS(() => fuelVal = v.round()),
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
        ),
      ),
    );
    if (!mounted || saved != true) return;
    final oldOil = entry.oilLevel;
    final oldFuel = entry.fuelLevel;
    final changed = oilVal != oldOil || fuelVal != oldFuel;
    setState(() {
      entry.oilLevel = oilVal;
      entry.fuelLevel = fuelVal;
      if (changed) {
        final now = DateTime.now();
        final note = 'Motoröl: $oilVal% · Kraftstoff: $fuelVal%';
        final autoEntry = TimelineEntry(
          time: DateTime(widget.year, widget.month, widget.day,
              now.hour, now.minute),
          vesselStatusNote: note,
        );
        entry.timeline.add(autoEntry);
        entry.timeline.sort((a, b) => a.time.compareTo(b.time));
      }
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
      context.read<HomeRepository>().saveEntry(entry);
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
              context.read<HomeRepository>().saveEntry(entry);
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
        context.read<HomeRepository>().saveEntry(entry);
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
    ).whenComplete(() => setState(() => _isMarkerSheetOpen = false));
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

  void _showEntryDetail(TimelineEntry t) {
    final timeStr =
        '${t.time.hour.toString().padLeft(2, '0')}:${t.time.minute.toString().padLeft(2, '0')}';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: SingleChildScrollView(
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
              _detailRow(Icons.speed, 'Fahrt',
                  '${t.speed!.toStringAsFixed(1)} kn'),
            if (t.wind != null) _detailRow(Icons.air, 'Wind', t.wind!),
            if (t.sea != null)
              _detailRow(Icons.waves, 'See', t.sea!),
            if (t.weather != null)
              _detailRow(
                  Icons.wb_sunny_outlined, 'Wetter', t.weather!),
            if (t.grossState != null)
              _detailRow(Icons.sailing, 'Gross', t.grossState!),
            if (t.fockState != null)
              _detailRow(Icons.sailing, 'Fock', t.fockState!),
            if (t.motorOn != null)
              _detailRow(Icons.directions_boat, 'Motor',
                  t.motorOn! ? 'An' : 'Aus'),
          ],
        ),
        ),   // SingleChildScrollView
      ),     // SafeArea
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
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
          Text(value,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

}
