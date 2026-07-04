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
import '../domain/timeline_amendment.dart';
import '../widgets/add_timeline_entry_dialog.dart';
import '../widgets/add_crew_member_dialog.dart';
import '../widgets/crew_picker_sheet.dart';
import '../widgets/keel_icon.dart';
import '../widgets/nav_bar.dart';
import '../utils/compute_daily_stats.dart';
import '../utils/filter_settings.dart';
import '../utils/gpx_parser.dart';
import '../utils/track_correlation.dart';
import '../utils/gpx_exporter.dart';
import '../utils/pdf_exporter.dart';
import '../utils/sail_state_utils.dart';
import '../utils/photo_service.dart';
import '../utils/trim_track.dart';
import '../../settings/domain/theme_provider.dart';
import '../../../l10n/l10n_extension.dart';
import '../../../l10n/app_localizations.dart';
import '../../../core/constants/map_config.dart';
import '../../../app/theme/theme_extensions.dart';


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
  // Detects crew notes stored with either the new sentinel ('crew:') or the
  // legacy format ('Besatzung: ') so Firestore entries written before the
  // sentinel rename continue to render correctly.
  static bool _isCrewNote(String? note) =>
      note?.startsWith('crew:') == true ||
      note?.startsWith('Besatzung: ') == true;

  // Returns the display string for a crew note, stripping the sentinel prefix
  // and prepending a localisation-ready display label.
  // New format: 'crew:role=0:Alice · Bob' → 'Crew: Alice (Skipper) · Bob'
  // Legacy format: 'crew:Alice (Skipper) · Bob' — passes through verbatim after stripping prefix.
  static String _crewNoteDisplay(String note, String crewLabel, String skipperLabel) {
    if (note.startsWith('crew:')) {
      final body = note.substring(5).split(' · ').map((part) {
        if (part.startsWith('role=0:')) return '${part.substring(7)} ($skipperLabel)';
        return part;
      }).join(' · ');
      return '$crewLabel: $body';
    }
    return note; // legacy format already begins with 'Besatzung: '
  }

  // Parses a vessel-status sentinel note (`vs:oil=75,fuel=60`, `vs:keel=down`)
  // and returns a localised display string. Legacy notes (no `vs:` prefix) are
  // returned verbatim so old Firestore documents continue to display correctly.
  static String _sailStateDisplay(String s, AppLocalizations l10n) => switch (s) {
    'sail:full'    => l10n.sailFull,
    'sail:reef1'   => l10n.sailReef1,
    'sail:reef2'   => l10n.sailReef2,
    'sail:lowered' => l10n.sailLowered,
    'sail:furled'  => l10n.sailFurled,
    _              => s, // legacy German text — display verbatim
  };

  static String _vesselStatusDisplay(String note, AppLocalizations l10n) =>
      parseVesselStatus(
        note,
        oilLabel:       (pct) => '${l10n.vesselOilLabel}: $pct%',
        fuelLabel:      (pct) => '${l10n.vesselFuelLabel}: $pct%',
        keelDownLabel:  l10n.vesselKeelDown,
        keelUpLabel:    l10n.vesselKeelUp,
        keelFieldLabel: l10n.entryDialogKeelLabel,
      );

  bool get _isToday {
    final now = DateTime.now();
    return widget.year == now.year &&
        widget.month == now.month &&
        widget.day == now.day;
  }

  final MapController _mapController = MapController();
  bool _satelliteView = false;
  LatLng? _droppedMarkerLatLng;
  String? _droppedMarkerLabel;
  Timer? _markerDismissTimer;
  bool _editingRoute = false;
  final Set<String> _deletingPhotos = {};
  bool _importingPhotos = false;
  bool _crewEditing = false;
  List<CrewMember>? _pendingCrew;
  final _fromHarborCtrl = TextEditingController();
  final _toHarborCtrl = TextEditingController();
  final _fromHarborFocus = FocusNode();
  final _toHarborFocus = FocusNode();
  @override
  void initState() {
    super.initState();
    if (widget.openAddDialog) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _addTimelineEntry(context);
      });
    }
    // Save as soon as focus leaves both route fields, not just on explicit
    // "Done"/checkmark — otherwise navigating away mid-edit silently
    // discards whatever was typed.
    _fromHarborFocus.addListener(_onRouteFocusChange);
    _toHarborFocus.addListener(_onRouteFocusChange);
  }

  void _onRouteFocusChange() {
    if (_fromHarborFocus.hasFocus || _toHarborFocus.hasFocus) return;
    if (!_editingRoute) return;
    final entry = context
        .read<HomeRepository>()
        .getEntry(DateTime(widget.year, widget.month, widget.day));
    if (entry != null) _saveRoute(entry);
  }

  @override
  void dispose() {
    _markerDismissTimer?.cancel();
    _fromHarborCtrl.dispose();
    _toHarborCtrl.dispose();
    _fromHarborFocus.dispose();
    _toHarborFocus.dispose();
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

    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final localeStr = context.read<ThemeProvider>().localeString;
    final dayName = DateFormat('EEEE', localeStr).format(day);
    final dateStr = DateFormat('d. MMM yyyy', localeStr).format(day);

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
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
              tooltip: l10n.dayMenuOptions,
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
                    Text(l10n.dayMenuChangeDate, style: TextStyle(color: cs.onSurface)),
                  ]),
                ),
                PopupMenuItem<String>(
                  value: 'import_gpx',
                  child: Row(children: [
                    _gpxUploadIcon(),
                    const SizedBox(width: 12),
                    Text(l10n.dayMenuImportGpx, style: TextStyle(color: cs.onSurface)),
                  ]),
                ),
                if (track != null)
                  PopupMenuItem<String>(
                    value: 'export_gpx',
                    child: Row(children: [
                      Icon(Icons.download_outlined, color: cs.onSurface),
                      const SizedBox(width: 12),
                      Text(l10n.dayMenuExportGpx, style: TextStyle(color: cs.onSurface)),
                    ]),
                  ),
                PopupMenuItem<String>(
                  value: 'export_pdf',
                  child: Row(children: [
                    Icon(Icons.picture_as_pdf_outlined, color: cs.onSurface),
                    const SizedBox(width: 12),
                    Text(l10n.dayMenuExportPdf, style: TextStyle(color: cs.onSurface)),
                  ]),
                ),
                if (track != null)
                  const PopupMenuDivider(),
                if (track != null)
                  PopupMenuItem<String>(
                    value: 'delete_gpx',
                    child: Row(children: [
                      Icon(Icons.delete_outline, color: cs.error),
                      const SizedBox(width: 12),
                      Text(l10n.dayMenuDeleteGpx,
                          style: TextStyle(color: cs.error)),
                    ]),
                  ),
                const PopupMenuDivider(),
                PopupMenuItem<String>(
                  value: 'delete_day',
                  child: Row(children: [
                    Icon(Icons.delete_forever_outlined, color: cs.error),
                    const SizedBox(width: 12),
                    Text(l10n.dayMenuDeleteDay,
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
          ? Center(child: Text(l10n.dayNoEntry))
          : _buildBody(entry, track, stats, filterSettings, cs),
    );
  }

  // ── Body ──────────────────────────────────────────────────────────
  Widget _buildBody(DayEntry entry, DailyTrack? track, DailyStats? stats,
      FilterSettings filterSettings, ColorScheme cs) {
    final corrPoints = track != null
        ? buildDisplayModel(track.points, settings: filterSettings).correlationPoints
        : <TrackPoint>[];
    final correlatedMap = track != null
        ? Map<TimelineEntry, TrackPoint>.fromEntries(
            correlateTimelineWithTrack(entry.timeline, corrPoints)
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
    final tl = Theme.of(context).extension<LogbookTimelineColors>()!;
    final hasText = entry.freeText?.isNotEmpty ?? false;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.l10n.sectionNotes.toUpperCase(),
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
                    color: tl.dividerColor),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: tl.cardShadowColor,
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
            context.l10n.dayAddNotes,
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
        title: context.l10n.sectionNotes,
        initialText: entry.freeText,
        hintText: context.l10n.dayFreeTextHint,
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
    final tl = Theme.of(context).extension<LogbookTimelineColors>()!;
    final hasNotes = entry.notes?.isNotEmpty ?? false;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.l10n.sectionDiary.toUpperCase(),
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
                    color: tl.dividerColor),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: tl.cardShadowColor,
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
            context.l10n.dayAddDiary,
            () => _editNotes(entry),
            cs,
          ),
        const SizedBox(height: 20),
      ],
    );
  }

  // ── Crew List ─────────────────────────────────────────────────────
  Widget _buildCrewList(DayEntry entry, ColorScheme cs) {
    final tl = Theme.of(context).extension<LogbookTimelineColors>()!;
    final displayCrew =
        _crewEditing ? (_pendingCrew ?? <CrewMember>[]) : entry.crew;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Header ──────────────────────────────────────────────────
        Row(
          children: [
            Text(
              context.l10n.sectionCrew.toUpperCase(),
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5,
                color: cs.secondary,
              ),
            ),
            const Spacer(),
            if (_crewEditing) ...[
              Tooltip(
                message: context.l10n.dayAddCrewMember,
                child: GestureDetector(
                  onTap: _addPendingMember,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: cs.surfaceContainer,
                    ),
                    child: Icon(Icons.person_add, size: 20, color: cs.secondary),
                  ),
                ),
              ),
            ] else ...[
              Tooltip(
                message: entry.crew.isEmpty
                    ? context.l10n.dayAddCrewMember
                    : context.l10n.dayEditCrew,
                child: GestureDetector(
                  onTap: entry.crew.isEmpty
                      ? () => _addCrewMember(entry)
                      : _enterCrewEditMode,
                  child: Row(
                    children: [
                      Icon(
                        entry.crew.isEmpty ? Icons.person_add : Icons.edit,
                        size: 16,
                        color: cs.secondary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        entry.crew.isEmpty ? context.l10n.add.toUpperCase() : context.l10n.change.toUpperCase(),
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
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        // ── Crew body ────────────────────────────────────────────────
        if (displayCrew.isNotEmpty)
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: cs.surfaceContainerLowest,
              border: Border.all(
                  color: tl.dividerColor),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: tl.cardShadowColor,
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: _crewEditing
                ? ReorderableListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    buildDefaultDragHandles: false,
                    padding: const EdgeInsets.all(12),
                    onReorderItem: _reorderPending,
                    proxyDecorator: (child, index, animation) => Material(
                      elevation: 4,
                      color: cs.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(8),
                      child: child,
                    ),
                    itemCount: displayCrew.length,
                    itemBuilder: (context, i) {
                      final member = displayCrew[i];
                      final isFirst = i == 0;
                      final isLast = i == displayCrew.length - 1;
                      return Column(
                        key: ValueKey(member.name),
                        children: [
                          _buildCrewRow(
                            member: member,
                            isFirst: isFirst,
                            cs: cs,
                            editing: true,
                            index: i,
                            onTap: () => _editPendingMember(i),
                          ),
                          if (!isLast)
                            Divider(
                              color: tl.dividerColor,
                              height: 16,
                            ),
                        ],
                      );
                    },
                  )
                : Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: displayCrew.asMap().entries.map((e) {
                        final isFirst = e.key == 0;
                        final isLast = e.key == displayCrew.length - 1;
                        return Column(
                          key: ValueKey(e.value.name),
                          children: [
                            _buildCrewRow(
                              member: e.value,
                              isFirst: isFirst,
                              cs: cs,
                              editing: false,
                              index: e.key,
                            ),
                            if (!isLast)
                              Divider(
                                color:
                                    tl.dividerColor,
                                height: 16,
                              ),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
          )
        else if (_crewEditing)
          _emptyStateButton(
            Icons.groups,
            context.l10n.dayAddCrewMember,
            _addPendingMember,
            cs,
          )
        else
          _emptyStateButton(
            Icons.groups,
            context.l10n.dayAddCrew,
            () => _addCrewMember(entry),
            cs,
          ),
        // ── Edit mode commit / cancel ───────────────────────────────
        if (_crewEditing) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _cancelCrewChanges,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: cs.secondary,
                    side: BorderSide(
                        color: cs.secondary.withValues(alpha: 0.3)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    textStyle: GoogleFonts.inter(
                        fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  child: Text(context.l10n.cancel),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  onPressed: () => _commitCrewChanges(entry),
                  style: FilledButton.styleFrom(
                    backgroundColor: cs.secondary,
                    foregroundColor: cs.onSecondary,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    textStyle: GoogleFonts.inter(
                        fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  child: Text(context.l10n.apply),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildCrewRow({
    required CrewMember member,
    required bool isFirst,
    required ColorScheme cs,
    required bool editing,
    required int index,
    VoidCallback? onTap,
  }) {
    return Row(
      children: [
        if (editing) ...[
          ReorderableDragStartListener(
            index: index,
            child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Icon(Icons.drag_handle,
                  size: 20, color: cs.outline.withValues(alpha: 0.4)),
            ),
          ),
        ],
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: cs.surfaceContainerHigh,
            ),
            child: Icon(Icons.person, color: cs.primary, size: 22),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: GestureDetector(
            onTap: onTap,
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
                Text(
                  isFirst ? context.l10n.labelSkipper.toUpperCase() : context.l10n.labelCrewRole.toUpperCase(),
                  style: GoogleFonts.inter(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                    color: isFirst ? cs.primary : cs.outline,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (editing && onTap != null)
          GestureDetector(
            onTap: onTap,
            child: Icon(Icons.chevron_right, size: 18, color: cs.outlineVariant),
          ),
      ],
    );
  }

  // ── Route & Map ───────────────────────────────────────────────────
  Widget _buildRouteMap(
      DayEntry entry, DailyTrack? track, DailyStats? stats, ColorScheme cs) {
    final tl = Theme.of(context).extension<LogbookTimelineColors>()!;
    final hasTrack = track != null && track.points.isNotEmpty;
    final fromH = entry.fromHarbor?.isNotEmpty ?? false;
    final toH = entry.toHarbor?.isNotEmpty ?? false;
    final routeLabel = (fromH || toH)
        ? [if (fromH) entry.fromHarbor!, if (toH) entry.toHarbor!].join(' → ')
        : null;
    final div = BorderSide(color: tl.dividerColor);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.l10n.sectionRoute.toUpperCase(),
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
                  color: tl.dividerColor),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: tl.cardShadowColor,
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
                                    focusNode: _fromHarborFocus,
                                    autofocus: true,
                                    decoration: InputDecoration(
                                      hintText: context.l10n.dayDeparturePort,
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
                                    focusNode: _toHarborFocus,
                                    decoration: InputDecoration(
                                      hintText: context.l10n.dayDestinationPort,
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
                            Tooltip(
                              message: context.l10n.daySaveRoute,
                              child: GestureDetector(
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
                                          context.l10n.dayCaptureRoute,
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
                                  context.l10n.dayAddGpxTrack,
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
    final tl = Theme.of(context).extension<LogbookTimelineColors>()!;
    final div = BorderSide(color: tl.dividerColor);

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
                      context.l10n.statDistance.toUpperCase(), '${stats.distanceNm.toStringAsFixed(1)} NM', cs),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: _statCell(
                      context.l10n.statAvgSpeed, '${stats.avgOverGroundKn.toStringAsFixed(1)} kn', cs),
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
                          context.l10n.statAvgSpeedUnderway, '${stats.avgMakingWayKn.toStringAsFixed(1)} kn', cs),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: _statCell(
                          context.l10n.statMax.toUpperCase(), '${stats.maxSpeedKn.toStringAsFixed(1)} kn', cs),
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
              context.l10n.sectionLogEntries.toUpperCase(),
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5,
                color: cs.secondary,
              ),
            ),
            const Spacer(),
            Tooltip(
              message: context.l10n.dayAddLogEntry,
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
            context.l10n.dayFirstLogEntry,
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
    final tl = Theme.of(context).extension<LogbookTimelineColors>()!;
    final timeStr =
        '${t.time.hour.toString().padLeft(2, '0')}:${t.time.minute.toString().padLeft(2, '0')}';

    final bool isCrewEntry = _isCrewNote(t.vesselStatusNote);
    final bool isStatusEntry = t.vesselStatusNote != null && !isCrewEntry;
    final String entryLabel;
    if (isCrewEntry) {
      entryLabel = context.l10n.dataCrewNote.toUpperCase();
    } else if (isStatusEntry) {
      entryLabel = context.l10n.sectionVesselStatus.toUpperCase();
    } else if (total == 1) {
      entryLabel = context.l10n.labelEntry.toUpperCase();
    } else if (index == 0) {
      entryLabel = context.l10n.labelDeparture.toUpperCase();
    } else if (index == total - 1) {
      entryLabel = context.l10n.labelArrival.toUpperCase();
    } else {
      entryLabel = context.l10n.labelProgress.toUpperCase();
    }

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        border: Border.all(
            color: tl.dividerColor),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: tl.cardShadowColor,
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Label + time + action icons
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  entryLabel,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5,
                    color: cs.secondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Entry-type icon — tappable to snap map when GPS data exists.
                  GestureDetector(
                    onTap: trackedPoint != null
                        ? () => _mapController.move(
                              LatLng(trackedPoint.lat, trackedPoint.lon),
                              14,
                            )
                        : null,
                    child: Icon(
                      isCrewEntry
                          ? Icons.groups_outlined
                          : isStatusEntry
                              ? Icons.sailing
                              : Icons.schedule,
                      size: 16,
                      color:
                          trackedPoint != null ? cs.primary : cs.outlineVariant,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    timeStr,
                    style: GoogleFonts.newsreader(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: cs.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Tooltip(
                    message: context.l10n.dayEditLogEntry,
                    child: GestureDetector(
                      onTap: () => _editTimelineEntry(entry, t),
                      child: Icon(Icons.edit_outlined,
                          size: 16, color: cs.outline),
                    ),
                  ),
                ],
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
                isCrewEntry
                    ? _crewNoteDisplay(t.vesselStatusNote!, context.l10n.dataCrewNote, context.l10n.labelSkipper)
                    : _vesselStatusDisplay(t.vesselStatusNote!, context.l10n),
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
                    '${context.l10n.dataCourse}: ${t.course!.toStringAsFixed(0)}°',
                  if (t.speed != null)
                    '${context.l10n.dataSpeed}: ${t.speed!.toStringAsFixed(1)} kn',
                  if (t.wind != null) '${context.l10n.dataWind}: ${t.wind!}',
                  if (t.sea != null) '${context.l10n.dataSea}: ${t.sea!}',
                  if (t.weather != null) '${context.l10n.dataWeather}: ${t.weather!}',
                  if (t.grossState != null) '${context.l10n.dataMainSail}: ${_sailStateDisplay(t.grossState!, context.l10n)}',
                  if (t.fockState != null) '${context.l10n.dataJibSail}: ${_sailStateDisplay(t.fockState!, context.l10n)}',
                  if (t.motorOn != null)
                    '${context.l10n.dataMotor}: ${t.motorOn! ? context.l10n.on : context.l10n.off}',
                ].join(' · '),
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: cs.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
            ],
            // Amendment history badge
            if (t.amendments.isNotEmpty) ...[
              const SizedBox(height: 8),
              Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.5)),
              const SizedBox(height: 6),
              _buildAmendmentBadge(t, cs),
            ],
          ],
        ),
    );
  }



  Widget _buildAmendmentBadge(TimelineEntry t, ColorScheme cs) {
    final l10n = context.l10n;
    final count = t.amendments.length;
    final last = t.amendments.last;
    final dateStr = DateFormat('d MMM', context.read<ThemeProvider>().localeString)
        .format(last.amendedAt);
    final label = count == 1
        ? l10n.amendmentBadgeSingle(dateStr)
        : l10n.amendmentBadgeMultiple(count, dateStr);

    return GestureDetector(
      onTap: () => _showAmendmentHistory(t, cs),
      child: Row(
        children: [
          Icon(Icons.history, size: 13, color: cs.outline),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
                color: cs.outline,
              ),
            ),
          ),
          Icon(Icons.chevron_right, size: 14, color: cs.outlineVariant),
        ],
      ),
    );
  }

  void _showAmendmentHistory(TimelineEntry t, ColorScheme cs) {
    final l10n = context.l10n;
    final locale = context.read<ThemeProvider>().localeString;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) {
        // Entries displayed newest-first: current state at top, then
        // intermediate amendments (newest to second-oldest). The oldest
        // snapshot is shown separately at the bottom as "Original entry"
        // to avoid duplicating it in both the list and the special row.
        final entries = [
          (amendedAt: null as DateTime?, reason: null as String?, isOriginal: false, isCurrent: true,
            snapshot: t),
          ...t.amendments.reversed.skip(1).map((a) => (
            amendedAt: a.amendedAt, reason: a.reason, isOriginal: false, isCurrent: false,
            snapshot: a)),
        ];
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.5,
          maxChildSize: 0.9,
          builder: (_, controller) => Column(
            children: [
              const SizedBox(height: 8),
              Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: cs.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  l10n.amendmentHistoryTitle,
                  style: GoogleFonts.newsreader(
                    fontSize: 20, fontWeight: FontWeight.w600,
                    fontStyle: FontStyle.italic, color: cs.primary,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView.separated(
                  controller: controller,
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  itemCount: entries.length + 1, // +1 for original label
                  separatorBuilder: (_, _) => Divider(
                    color: cs.outlineVariant.withValues(alpha: 0.5), height: 24),
                  itemBuilder: (_, i) {
                    if (i == entries.length) {
                      // Original entry (oldest amendment's snapshot)
                      final orig = t.amendments.first;
                      return _amendmentSnapshotTile(
                        label: l10n.amendmentOriginal,
                        dateStr: DateFormat('d MMM yyyy · HH:mm', locale).format(orig.amendedAt),
                        reason: null,
                        time: orig.time,
                        course: orig.course,
                        speed: orig.speed,
                        wind: orig.wind,
                        sea: orig.sea,
                        weather: orig.weather,
                        remarks: orig.remarks,
                        cs: cs,
                        isOriginal: true,
                      );
                    }
                    final e = entries[i];
                    if (e.isCurrent) {
                      return _amendmentSnapshotTile(
                        label: l10n.amendmentCurrent,
                        dateStr: t.updatedAt != null
                            ? DateFormat('d MMM yyyy · HH:mm', locale).format(t.updatedAt!)
                            : '',
                        reason: null,
                        time: t.time,
                        course: t.course,
                        speed: t.speed,
                        wind: t.wind,
                        sea: t.sea,
                        weather: t.weather,
                        remarks: t.remarks,
                        cs: cs,
                        isOriginal: false,
                      );
                    }
                    final a = t.amendments.reversed.toList()[i - 1];
                    return _amendmentSnapshotTile(
                      label: DateFormat('d MMM yyyy · HH:mm', locale).format(a.amendedAt),
                      dateStr: '',
                      reason: a.reason ?? l10n.amendmentNoReason,
                      time: a.time,
                      course: a.course,
                      speed: a.speed,
                      wind: a.wind,
                      sea: a.sea,
                      weather: a.weather,
                      remarks: a.remarks,
                      cs: cs,
                      isOriginal: false,
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _amendmentSnapshotTile({
    required String label,
    required String dateStr,
    required String? reason,
    required DateTime time,
    required double? course,
    required double? speed,
    required String? wind,
    required String? sea,
    required String? weather,
    required String? remarks,
    required ColorScheme cs,
    required bool isOriginal,
  }) {
    final timeStr =
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    final details = [
      if (course != null) 'COG ${course.toStringAsFixed(0)}°',
      if (speed != null) '${speed.toStringAsFixed(1)} kn',
      ?wind,
      ?sea,
      ?weather,
    ].join(' · ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 11, fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
                color: isOriginal ? cs.outline : cs.secondary,
              ),
            ),
            if (dateStr.isNotEmpty) ...[
              const SizedBox(width: 8),
              Text(dateStr,
                style: GoogleFonts.inter(fontSize: 11, color: cs.outline)),
            ],
          ],
        ),
        const SizedBox(height: 4),
        Text(
          timeStr,
          style: GoogleFonts.newsreader(
            fontSize: 20, fontWeight: FontWeight.w500,
            color: isOriginal ? cs.outline : cs.primary,
          ),
        ),
        if (details.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(details,
            style: GoogleFonts.inter(fontSize: 13, color: cs.onSurfaceVariant)),
        ],
        if (remarks?.isNotEmpty == true) ...[
          const SizedBox(height: 2),
          Text(remarks!,
            style: GoogleFonts.inter(
              fontSize: 13, fontStyle: FontStyle.italic, color: cs.onSurface)),
        ],
        if (reason != null) ...[
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: cs.surfaceContainerLow,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              reason,
              style: GoogleFonts.inter(fontSize: 12, color: cs.onSurfaceVariant),
            ),
          ),
        ],
      ],
    );
  }

  // ── Photo gallery ─────────────────────────────────────────────────
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
              context.l10n.sectionPhotos.toUpperCase(),
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5,
                color: cs.secondary,
              ),
            ),
            if (hasPhotos) ...[
              const Spacer(),
              if (_importingPhotos)
                SizedBox(
                  width: 28, height: 28,
                  child: CircularProgressIndicator(strokeWidth: 2, color: cs.secondary),
                )
              else
                Tooltip(
                  message: context.l10n.dayAddPhotosTooltip,
                  child: GestureDetector(
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
                ),
            ],
          ],
        ),
        const SizedBox(height: 10),
        if (hasPhotos)
          _buildPhotoGallery(allPaths, entry, cs)
        else if (_importingPhotos)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              border: Border.all(color: cs.outlineVariant, width: 1.5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                SizedBox(
                  width: 20, height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: cs.secondary),
                ),
                const SizedBox(height: 8),
                Text(
                  context.l10n.dayImportingPhotos,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontStyle: FontStyle.italic,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          )
        else
          _emptyStateButton(
            Icons.add_a_photo_outlined,
            context.l10n.dayAddPhotosEmpty,
            () => _addPhotos(entry),
            cs,
          ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildPhotoGallery(List<String> paths, DayEntry entry, ColorScheme cs) {
    const h = 200.0;

    // Single photo: full width, contain so the whole image is visible
    if (paths.length == 1) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 220,
          width: double.infinity,
          color: cs.surfaceContainerHighest,
          child: _photoCell(entry, paths[0], cs, h: 220, single: true),
        ),
      );
    }

    // Multiple: horizontal scroll, each tile naturally wide for its aspect ratio
    return SizedBox(
      height: h,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        itemCount: paths.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) => _photoCell(entry, paths[i], cs, h: h),
      ),
    );
  }

  Widget _photoCell(
    DayEntry entry,
    String storagePath,
    ColorScheme cs, {
    required double h,
    bool single = false,
  }) {
    if (_deletingPhotos.contains(storagePath)) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(single ? 0 : 10),
        child: SizedBox(
          width: single ? double.infinity : 120,
          height: h,
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
        final file = snap.data;
        final done = snap.connectionState == ConnectionState.done;

        Widget image;
        if (!done) {
          image = SizedBox(
            width: single ? double.infinity : 120,
            height: h,
            child: Container(
              color: cs.surfaceContainerHighest,
              child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          );
        } else if (file == null) {
          image = SizedBox(
            width: single ? double.infinity : 120,
            height: h,
            child: Container(
              color: cs.errorContainer,
              child: Icon(Icons.broken_image_outlined, color: cs.onErrorContainer),
            ),
          );
        } else if (single) {
          // Full-width: contain so complete photo is visible
          image = GestureDetector(
            onTap: () => _viewPhoto(file),
            child: SizedBox.expand(
              child: Image.file(file, fit: BoxFit.contain),
            ),
          );
        } else {
          // Strip tile: scale to height, natural width — no cropping
          image = GestureDetector(
            onTap: () => _viewPhoto(file),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.file(file, height: h, fit: BoxFit.fitHeight),
            ),
          );
        }

        return Stack(
          children: [
            image,
            Positioned(
              top: 8,
              right: 8,
              child: GestureDetector(
                onTap: () => _deletePhoto(entry, storagePath),
                child: Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: cs.errorContainer.withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(Icons.close, size: 15, color: cs.onErrorContainer),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _addPhotos(DayEntry entry) async {
    if (_importingPhotos) return;
    setState(() => _importingPhotos = true);
    final logbookId = context.read<ValueNotifier<String?>>().value;
    if (logbookId == null) {
      setState(() => _importingPhotos = false);
      return;
    }
    final day = DateTime(widget.year, widget.month, widget.day);
    try {
      final paths = await PhotoService.pickAndUpload(day, logbookId);
      if (!mounted || paths.isEmpty) return;
      // Re-fetch: a Firestore sync may have replaced the entry object in the
      // Hive box during the await, making the original reference invalid.
      final repo = context.read<HomeRepository>();
      final fresh = repo.getEntry(day) ?? entry;
      fresh.photos.addAll(paths);
      repo.saveEntry(fresh);
    } finally {
      if (mounted) setState(() => _importingPhotos = false);
    }
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
          title: Text(ctx.l10n.dayDeletePhoto),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(ctx.l10n.cancel, style: TextStyle(color: cs.primary))),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(ctx.l10n.delete)),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;
    setState(() => _deletingPhotos.add(storagePath));
    // Re-fetch: a Firestore sync or a prior concurrent delete may have replaced
    // the entry object in the Hive box while the dialog was open.
    final repo = context.read<HomeRepository>();
    final day = DateTime(widget.year, widget.month, widget.day);
    final fresh = repo.getEntry(day) ?? entry;
    fresh.photos.remove(storagePath);
    repo.saveEntry(fresh);
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
              context.l10n.sectionVesselStatus.toUpperCase(),
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5,
                color: cs.secondary,
              ),
            ),
            const Spacer(),
            Tooltip(
              message: context.l10n.dayUpdateVesselStatus,
              child: GestureDetector(
                onTap: () => _editVesselStatus(entry),
                child: Row(
                  children: [
                    Icon(Icons.edit, size: 16, color: cs.secondary),
                    const SizedBox(width: 4),
                    Text(
                      context.l10n.update.toUpperCase(),
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
                            context.l10n.vesselOilLabel.toUpperCase(), entry.oilLevel, Icons.opacity, cs, cardFg),
                      ),
                      const SizedBox(width: 20),
                      Expanded(
                        child: _vesselStatCell(context.l10n.vesselFuelLabel.toUpperCase(), entry.fuelLevel,
                            Icons.local_gas_station, cs, cardFg, isFuel: true),
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
                        context.l10n.entryDialogKeelLabel.toUpperCase(),
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
                                : (entry.keelDown! ? context.l10n.vesselKeelDown.toUpperCase() : context.l10n.vesselKeelUp.toUpperCase()),
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
      String label, int? level, IconData icon, ColorScheme cs, Color onCard, {bool isFuel = false}) {
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
              context.l10n.vesselEmptyLabel.toUpperCase(),
              style: GoogleFonts.inter(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
                color: onCard.withValues(alpha: 0.50),
              ),
            ),
            Text(
              context.l10n.vesselFullLabel.toUpperCase(),
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
    final correlated = correlateTimelineWithTrack(entry.timeline, display.correlationPoints);

    final startPoint = display.firstMovingPoint ?? track.points.first;
    final endPoint   = display.lastMovingPoint  ?? track.points.last;

    final cleanedLatLngs =
        display.movingPoints().map((p) => LatLng(p.lat, p.lon)).toList();

    // Bounding box covers all rendered coords + stop centroids
    final boundsLatLngs = [
      for (final s in display.segments)
        if (s.kind != SegmentKind.teleportBreak)
          for (final p in s.points)
            if (p.lat.isFinite && p.lon.isFinite) LatLng(p.lat, p.lon),
      for (final s in display.stops)
        if (s.lat.isFinite && s.lon.isFinite) LatLng(s.lat, s.lon),
    ];
    final fitLatLngs = boundsLatLngs.isNotEmpty
        ? boundsLatLngs
        : track.points
            .where((p) => p.lat.isFinite && p.lon.isFinite)
            .map((p) => LatLng(p.lat, p.lon))
            .toList();
    final trackBounds = fitLatLngs.isNotEmpty ? LatLngBounds.fromPoints(fitLatLngs) : null;

    final startStop = display.startStop;
    final endStop   = display.endStop;
    final endPositionReliable = display.endPositionReliable;
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
    // Effective departure/arrival (from windowed speed) rather than the raw/
    // segment-based start/endPoint time, which can read hours off when a
    // genuine stop's GPS scatter was too wide to pass stop validation — see
    // the doc comments on DisplayModel.departureTime/arrivalTime.
    final departurePrecision = display.departurePrecision;
    final startTimeStr = switch (departurePrecision) {
      TimePrecision.unknown => '—',
      TimePrecision.estimated =>
        '~ ${DateFormat('HH:mm').format((display.departureTime ?? startPoint.time).toLocal())}',
      TimePrecision.precise =>
        DateFormat('HH:mm').format((display.departureTime ?? startPoint.time).toLocal()),
    };
    final endTimeStr = (endPositionReliable ? '' : '~ ') +
        DateFormat('HH:mm').format((display.arrivalTime ?? endPoint.time).toLocal());

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
    final trackColor = _satelliteView ? cs.secondaryFixed : cs.primary;
    for (final seg in display.segments) {
      if (seg.kind == SegmentKind.moving && seg.points.length >= 2) {
        trackPolylines.add(Polyline(
          points: seg.points.map((p) => LatLng(p.lat, p.lon)).toList(),
          strokeWidth: 4,
          color: trackColor,
          borderStrokeWidth: _satelliteView ? 1.5 : 0,
          borderColor: Colors.black.withValues(alpha: 0.45),
        ));
      } else if ((seg.kind == SegmentKind.stopEntry ||
                  seg.kind == SegmentKind.stopExit) &&
                 seg.points.length >= 2) {
        trackPolylines.add(Polyline(
          points: seg.points.map((p) => LatLng(p.lat, p.lon)).toList(),
          strokeWidth: 2.5,
          color: trackColor.withValues(alpha: 0.50),
          borderStrokeWidth: _satelliteView ? 1.0 : 0,
          borderColor: Colors.black.withValues(alpha: 0.35),
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
        // GestureDetector absorbs the tap so the map's onTap does not also
        // fire (which would show only the time). _dropMarker shows the full
        // entry data instead.
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _dropMarker(
            LatLng(p.lat, p.lon),
            _buildEntryTooltip(t, context.l10n),
          ),
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
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _dropMarker(
            LatLng(p.lat, p.lon),
            DateFormat('HH:mm').format(p.time.toLocal()),
          ),
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
      // Only a validated start stop gives a real position/bearing — estimated
      // and unknown departures still show a time (or "—"), but with a
      // GPS-uncertain icon and a tooltip explaining why, instead of a
      // directional arrow implying false precision.
      Marker(
        point: startPos,
        width: 82,
        height: 22,
        alignment: Alignment.centerRight,
        child: Tooltip(
          message: switch (departurePrecision) {
            TimePrecision.precise => '',
            TimePrecision.estimated => context.l10n.departureTimeEstimatedTooltip,
            TimePrecision.unknown => context.l10n.departureTimeUnknownTooltip,
          },
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _trackLabel(startTimeStr, cs),
              const SizedBox(width: 5),
              departurePrecision == TimePrecision.precise
                  ? Transform.rotate(
                      angle: departureBearing,
                      child: _trackArrow(cs.primary),
                    )
                  : _trackArrow(cs.primary, icon: Icons.gps_not_fixed),
            ],
          ),
        ),
      ),
      // ── Arrival: arrow at the coordinate, label to the right ────────
      // When no end stop was validated, endPos is just wherever GPS logging
      // trailed off, not a real berth — show a GPS-uncertain icon instead of
      // a directional arrow, and let the tooltip explain why.
      Marker(
        point: endPos,
        width: 82,
        height: 22,
        alignment: Alignment.centerLeft,
        child: Tooltip(
          message: endPositionReliable
              ? ''
              : context.l10n.arrivalTimeUncertainTooltip,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              endPositionReliable
                  ? Transform.rotate(
                      angle: arrivalBearing,
                      child: _trackArrow(cs.primary),
                    )
                  : _trackArrow(cs.primary, icon: Icons.gps_not_fixed),
              const SizedBox(width: 5),
              _trackLabel(endTimeStr, cs),
            ],
          ),
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
              urlTemplate: _satelliteView ? kSatelliteUrl : kBaseTileUrl,
              userAgentPackageName: 'com.logbook.app',
              // Keep more of the surrounding tile grid loaded across a
              // pan/zoom transition so fewer tiles need a fresh fetch right
              // when the gesture ends (default is 2).
              keepBuffer: 4,
              // Default is `.none`, which never retries a tile that failed
              // once (transient network blip, tile-server rate limit) — it
              // stays blank until this whole map widget is rebuilt. Evicting
              // once it scrolls out of view lets it be re-fetched next time
              // it's needed.
              evictErrorTileStrategy: EvictErrorTileStrategy.notVisibleRespectMargin,
              errorTileCallback: kDebugMode
                  ? (tile, error, stackTrace) =>
                      debugPrint('[Map] tile ${tile.coordinates} failed to load: $error')
                  : null,
              // Fade-in on arrival is TileLayer's default (tileDisplay:
              // TileDisplay.fadeIn()); this only overrides the tile that
              // failed to load, in place of a blank grey square.
              tileBuilder: (context, tileWidget, tile) => tile.loadError
                  ? Container(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      child: const Icon(Icons.map_outlined, size: 20),
                    )
                  : tileWidget,
            ),
            _ZoomAwareUncertaintyLayer(polygons: uncertaintyPolygons),
            _ZoomAwareCircleLayer(circles: anchorCircles),
            PolylineLayer(polylines: trackPolylines, cullingMargin: null, simplificationTolerance: 0),
            if (showRawTrack) _ZoomAwareRawTrackLayer(rawPoints: display.rawMovingPoints),
            MarkerLayer(markers: markers),
            RichAttributionWidget(
              attributions: [
                TextSourceAttribution('MapTiler', onTap: () async {
                  final uri = Uri.parse('https://www.maptiler.com/copyright/');
                  if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
                }),
                if (!_satelliteView)
                  TextSourceAttribution('OpenStreetMap contributors', onTap: () async {
                    final uri = Uri.parse('https://www.openstreetmap.org/copyright');
                    if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
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
                tooltip: context.l10n.tracksFullscreen,
                child: const Icon(Icons.fullscreen),
              ),
              const SizedBox(height: 6),
              FloatingActionButton.small(
                heroTag: 'detail_satellite_button',
                onPressed: () =>
                    setState(() => _satelliteView = !_satelliteView),
                tooltip: _satelliteView
                    ? context.l10n.tracksMapView
                    : context.l10n.tracksSatelliteView,
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
        title: context.l10n.sectionDiary,
        initialText: entry.notes,
        hintText: context.l10n.dayDiaryHint,
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
      locale: context.read<ThemeProvider>().materialLocale,
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
        final locStr = context.read<ThemeProvider>().localeString;
        final proceed = await showDialog<bool>(
          context: context,
          builder: (ctx) {
            final cs = Theme.of(ctx).colorScheme;
            return AlertDialog(
              backgroundColor: cs.surface,
              surfaceTintColor: Colors.transparent,
              titleTextStyle: TextStyle(color: cs.onSurface, fontSize: 18, fontWeight: FontWeight.w600),
              contentTextStyle: TextStyle(color: cs.onSurfaceVariant, fontSize: 14),
              title: Text(context.l10n.dayChangeDateTitle),
              content: Text(context.l10n.dayChangeDateContent(
                DateFormat('d. MMMM yyyy', locStr).format(dominantDate),
                DateFormat('d. MMMM yyyy', locStr).format(newDate),
              )),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: Text(context.l10n.cancel)),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: Text(context.l10n.dayChangeDateConfirm)),
              ],
            );
          },
        );
        if (!mounted || proceed != true) return;
      }
    }

    final repo = context.read<HomeRepository>();
    final ok = await repo.changeEntryDate(current, newDate);
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(context.l10n.dayDateExistsError)));
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
              context.l10n.vesselStatusTitle,
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
                    Text(context.l10n.vesselOilLabel, style: TextStyle(color: cs.onSurface)),
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
                    Text(context.l10n.vesselFuelLabel, style: TextStyle(color: cs.onSurface)),
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
                    Text(context.l10n.entryDialogKeelLabel, style: TextStyle(color: cs.onSurface)),
                    const Spacer(),
                    Text(
                      keelVal == null ? '—' : (keelVal! ? context.l10n.vesselKeelDown : context.l10n.vesselKeelUp),
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
                child: Text(context.l10n.cancel),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.pop(ctx, true),
                icon: const Icon(Icons.anchor, size: 18),
                label: Text(context.l10n.saveChanges),
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
          vesselStatusNote: 'vs:oil=$oilVal,fuel=$fuelVal',
        ));
      }
      if (keelVal != oldKeel && keelVal != null) {
        entry.timeline.add(TimelineEntry(
          time: entryTime,
          vesselStatusNote: keelVal! ? 'vs:keel=down' : 'vs:keel=up',
        ));
      }
      entry.timeline.sort((a, b) => a.time.compareTo(b.time));
      context.read<HomeRepository>().saveEntry(entry);
    });
  }

  // ── Crew helpers ──────────────────────────────────────────────────

  // Direct add (locked mode, empty list — saves immediately).
  void _addCrewMember(DayEntry entry) async {
    final repo = context.read<HomeRepository>();
    final day = DateTime(widget.year, widget.month, widget.day);
    final alreadyAdded = entry.crew.map((m) => m.name).toSet();

    CrewMember? member;
    final availableRoster =
        repo.roster.where((m) => !alreadyAdded.contains(m.name)).toList();

    if (availableRoster.isEmpty) {
      member = await showDialog<CrewMember>(
        context: context,
        builder: (_) => const AddCrewMemberDialog(),
      );
      if (member != null) repo.saveRosterMember(member);
    } else {
      member = await showModalBottomSheet<CrewMember>(
        context: context,
        isScrollControlled: true,
        useRootNavigator: true,
        builder: (_) => CrewPickerSheet(repo: repo, excludeNames: alreadyAdded),
      );
    }

    if (!mounted || member == null) return;
    final fresh = repo.getEntry(day) ?? entry;
    fresh.crew.add(member);
    if (fresh.timeline.isNotEmpty) {
      final now = DateTime.now();
      final ts = DateTime(widget.year, widget.month, widget.day, now.hour, now.minute);
      fresh.timeline.add(TimelineEntry(
          time: ts, vesselStatusNote: HomeRepository.buildCrewNote(fresh.crew)));
      fresh.timeline.sort((a, b) => a.time.compareTo(b.time));
    }
    repo.saveEntry(fresh);
  }

  // Activate edit mode (locked → editing, non-empty crew only).
  void _enterCrewEditMode() {
    final day = DateTime(widget.year, widget.month, widget.day);
    final entry = context.read<HomeRepository>().getEntry(day);
    if (entry == null) return;
    setState(() {
      _crewEditing = true;
      _pendingCrew = entry.crew
          .map((m) => CrewMember(
                name: m.name,
                bloodType: m.bloodType,
                allergies: m.allergies,
                conditions: m.conditions,
                remarks: m.remarks,
                id: m.id,
                personalEpirb: m.personalEpirb,
              ))
          .toList();
    });
  }

  void _cancelCrewChanges() {
    setState(() {
      _crewEditing = false;
      _pendingCrew = null;
    });
  }

  void _commitCrewChanges(DayEntry entry) {
    if (_pendingCrew == null) return;
    final repo = context.read<HomeRepository>();
    final day = DateTime(widget.year, widget.month, widget.day);
    final fresh = repo.getEntry(day) ?? entry;

    fresh.crew = List<CrewMember>.from(_pendingCrew!);

    if (fresh.timeline.isNotEmpty && fresh.crew.isNotEmpty) {
      final now = DateTime.now();
      final ts = DateTime(
          widget.year, widget.month, widget.day, now.hour, now.minute);
      final note = HomeRepository.buildCrewNote(fresh.crew);
      fresh.timeline.add(TimelineEntry(time: ts, vesselStatusNote: note));
      fresh.timeline.sort((a, b) => a.time.compareTo(b.time));
    }

    repo.saveEntry(fresh);
    setState(() {
      _crewEditing = false;
      _pendingCrew = null;
    });
  }

  // Pending-crew add (edit mode — buffers to _pendingCrew).
  void _addPendingMember() async {
    if (_pendingCrew == null) return;
    final repo = context.read<HomeRepository>();
    final alreadyAdded = _pendingCrew!.map((m) => m.name).toSet();
    final available =
        repo.roster.where((m) => !alreadyAdded.contains(m.name)).toList();

    CrewMember? member;
    if (available.isEmpty) {
      member = await showDialog<CrewMember>(
        context: context,
        builder: (_) => const AddCrewMemberDialog(),
      );
      if (member != null) repo.saveRosterMember(member);
    } else {
      member = await showModalBottomSheet<CrewMember>(
        context: context,
        isScrollControlled: true,
        useRootNavigator: true,
        builder: (_) => CrewPickerSheet(repo: repo, excludeNames: alreadyAdded),
      );
    }

    if (!mounted || member == null) return;
    setState(() => _pendingCrew!.add(member!));
  }

  void _editPendingMember(int index) async {
    if (_pendingCrew == null || index >= _pendingCrew!.length) return;
    final member = _pendingCrew![index];
    final updated = await showDialog<CrewMember>(
      context: context,
      builder: (_) => AddCrewMemberDialog(
        initialMember: member,
        onDelete: () => _removePendingMember(member),
      ),
    );
    if (!mounted || updated == null) return;
    // AddCrewMemberDialog always builds a fresh CrewMember with no id, so the
    // link to this person's roster record must be carried over explicitly —
    // otherwise saving would silently create a disconnected duplicate.
    updated.id = member.id;
    context.read<HomeRepository>().saveEditedRosterMember(updated);
    setState(() {
      final i = _pendingCrew!.indexWhere((m) => m.name == member.name);
      if (i != -1) _pendingCrew![i] = updated;
    });
  }

  Future<bool> _removePendingMember(CrewMember member) async {
    setState(() => _pendingCrew?.remove(member));
    return true;
  }

  void _reorderPending(int oldIndex, int newIndex) {
    setState(() {
      if (_pendingCrew == null) return;
      final m = _pendingCrew!.removeAt(oldIndex);
      _pendingCrew!.insert(newIndex, m);
    });
  }

  // ── Timeline mutations ────────────────────────────────────────────
  void _addTimelineEntry(BuildContext context) async {
    final repo = context.read<HomeRepository>();
    final day = DateTime(widget.year, widget.month, widget.day);
    final result = await showDialog<AddTimelineEntryResult>(
      context: context,
      builder: (_) => AddTimelineEntryDialog(day: day),
    );
    if (!mounted || result == null) return;
    repo.addTimelineEntry(day, result.entry);
  }

  void _deleteTimelineEntry(DayEntry entry, TimelineEntry t) {
    final index = entry.timeline.indexOf(t);
    setState(() {
      entry.timeline.remove(t);
      final repo = context.read<HomeRepository>();
      repo.syncKeelFromTimeline(entry);
      repo.saveEntry(entry);
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(context.l10n.dayEntryDeleted),
      action: SnackBarAction(
        label: context.l10n.dayUndo,
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
    final isAmendment = !_isToday;
    final result = await showDialog<AddTimelineEntryResult>(
      context: context,
      builder: (_) => AddTimelineEntryDialog(
        day: day,
        initialEntry: t,
        isAmendment: isAmendment,
        onDelete: () => _deleteTimelineEntry(entry, t),
      ),
    );
    if (!mounted || result == null) return;
    final updated = result.entry;
    // For past-day edits, snapshot the previous state as an amendment.
    if (isAmendment) {
      final snapshot = TimelineAmendment.fromSnapshot(
        amendedAt: DateTime.now(),
        reason: result.amendmentReason,
        time: t.time,
        course: t.course,
        speed: t.speed,
        wind: t.wind,
        sea: t.sea,
        weather: t.weather,
        remarks: t.remarks,
        grossState: t.grossState,
        fockState: t.fockState,
        motorOn: t.motorOn,
        keelDown: t.keelDown,
      );
      updated.amendments
        ..addAll(t.amendments) // carry forward prior amendments
        ..add(snapshot);
    }
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
        SnackBar(content: Text(context.l10n.dayEntryUpdated)));
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
      preview = GpxParser().parseBytes(bytes).points;
    } else {
      final path = picked.path;
      if (path == null) return;
      preview = (await GpxParser().parse(File(path))).points;
    }

    if (!mounted) return;

    if (preview.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(context.l10n.dayGpxNoWaypoints)));
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
      final locStr = context.read<ThemeProvider>().localeString;
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) {
          final cs = Theme.of(ctx).colorScheme;
          return AlertDialog(
            backgroundColor: cs.surface,
            surfaceTintColor: Colors.transparent,
            titleTextStyle: TextStyle(color: cs.onSurface, fontSize: 18, fontWeight: FontWeight.w600),
            contentTextStyle: TextStyle(color: cs.onSurfaceVariant, fontSize: 14),
            title: Text(context.l10n.dayChangeDateTitle),
            content: Text(
              context.l10n.dayGpxWrongDateContent(
                DateFormat('d. MMMM yyyy', locStr).format(dominantDate),
                DateFormat('d. MMMM yyyy', locStr).format(targetDate),
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text(context.l10n.cancel)),
              FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: Text(context.l10n.dayGpxImportConfirm)),
            ],
          );
        },
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
        content: Text(context.l10n.dayGpxImported(
            DateFormat('d. MMMM yyyy', context.read<ThemeProvider>().localeString).format(day)))));
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
        SnackBar(content: Text(context.l10n.dayGpxExported)),
      );
    }
  }

  void _exportPdf(DayEntry entry, DailyStats? stats, DailyTrack? track) async {
    final p = context.read<ThemeProvider>();
    final l10n = context.l10n;
    final filteredPoints = track != null
        ? buildDisplayModel(track.points, settings: p.filterSettings).allPoints()
        : const <TrackPoint>[];
    final photoBytes = <Uint8List>[];
    for (final path in entry.photos) {
      final file = await PhotoService.localFile(path);
      if (file != null) photoBytes.add(await file.readAsBytes());
    }
    final pdfStrings = PdfStrings(
      voyageLog:     l10n.pdfVoyageLog,
      notes:         l10n.pdfNotes,
      date:          l10n.pdfDate,
      distance:      l10n.pdfDistance,
      avgSpeed:      l10n.pdfAvgSpeed,
      max:           l10n.pdfMax,
      duration:      l10n.pdfDuration,
      stops:         l10n.pdfStops,
      statistics:    l10n.pdfStatistics,
      crew:          l10n.pdfCrew,
      skipper:       l10n.pdfSkipper,
      crewMember:    l10n.pdfCrewMember,
      logEntries:    l10n.pdfLogEntries,
      timeCol:       l10n.pdfTimeCol,
      courseCol:     l10n.pdfCourseCol,
      windCol:       l10n.pdfWindCol,
      seaCol:        l10n.pdfSeaCol,
      motorCol:      l10n.pdfMotorCol,
      sailsCol:      l10n.pdfSailsCol,
      remarksCol:    l10n.pdfRemarksCol,
      motorOn:       l10n.pdfMotorOn,
      motorOff:      l10n.pdfMotorOff,
      trackMap:      l10n.pdfTrackMap,
      locale:        l10n.pdfLocale,
      passageTo:     l10n.pdfPassageTo,
      departureFrom: l10n.pdfDepartureFrom,
      pageOf:        l10n.pdfPageOf,
    );
    final bytes = await buildVoyagePdf(
      entry:       entry,
      stats:       stats,
      vesselName:  p.vesselName,
      strings:     pdfStrings,
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
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return AlertDialog(
          backgroundColor: cs.surface,
          surfaceTintColor: Colors.transparent,
          titleTextStyle: TextStyle(color: cs.onSurface, fontSize: 18, fontWeight: FontWeight.w600),
          contentTextStyle: TextStyle(color: cs.onSurfaceVariant, fontSize: 14),
          title: Text(context.l10n.dayGpxDeleteTitle),
          content: Text(context.l10n.dayGpxDeleteContent),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(context.l10n.cancel)),
            FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor: cs.error,
                    foregroundColor: cs.onError),
                onPressed: () => Navigator.pop(context, true),
                child: Text(context.l10n.delete)),
          ],
        );
      },
    );
    if (!mounted || shouldDelete != true) return;
    await repo.removeGpx(day);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.dayGpxRemoved)));
  }

  void _deleteDay() async {
    final repo = context.read<HomeRepository>();
    final day = DateTime(widget.year, widget.month, widget.day);
    final dateLabel =
        DateFormat('d. MMMM yyyy', context.read<ThemeProvider>().localeString).format(day);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return AlertDialog(
          title: Text(context.l10n.dayDeleteTitle, style: TextStyle(color: cs.onSurface)),
          content: Text(
            context.l10n.dayDeleteContent(dateLabel),
            style: TextStyle(color: cs.onSurface),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(context.l10n.cancel)),
            FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor: cs.error,
                    foregroundColor: cs.onError),
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(context.l10n.delete)),
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

  Widget _trackArrow(Color color, {IconData icon = Icons.arrow_upward}) => Container(
        width: 15,
        height: 15,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.85),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 1.5),
        ),
        alignment: Alignment.center,
        child: Icon(icon, color: Colors.white, size: 8),
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

  Widget _trackArrow(Color color, {IconData icon = Icons.arrow_upward}) => Container(
    width: 15, height: 15,
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.85),
      shape: BoxShape.circle,
      border: Border.all(color: Colors.white, width: 1.5),
    ),
    alignment: Alignment.center,
    child: Icon(icon, color: Colors.white, size: 8),
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
    final correlated = correlateTimelineWithTrack(entry.timeline, display.correlationPoints);

    final startPoint = display.firstMovingPoint ?? track.points.first;
    final endPoint   = display.lastMovingPoint  ?? track.points.last;
    final cleanedLatLngs = display.movingPoints().map((p) => LatLng(p.lat, p.lon)).toList();
    final boundsLatLngs = [
      for (final s in display.segments)
        if (s.kind != SegmentKind.teleportBreak)
          for (final p in s.points)
            if (p.lat.isFinite && p.lon.isFinite) LatLng(p.lat, p.lon),
      for (final s in display.stops)
        if (s.lat.isFinite && s.lon.isFinite) LatLng(s.lat, s.lon),
    ];
    final fitLatLngs = boundsLatLngs.isNotEmpty
        ? boundsLatLngs
        : track.points
            .where((p) => p.lat.isFinite && p.lon.isFinite)
            .map((p) => LatLng(p.lat, p.lon))
            .toList();
    final trackBounds = fitLatLngs.isNotEmpty ? LatLngBounds.fromPoints(fitLatLngs) : null;

    final startStop = display.startStop;
    final endStop   = display.endStop;
    final endPositionReliable = display.endPositionReliable;
    final startPos  = startStop != null ? LatLng(startStop.lat, startStop.lon) : LatLng(startPoint.lat, startPoint.lon);
    final endPos    = endStop   != null ? LatLng(endStop.lat,   endStop.lon)   : LatLng(endPoint.lat,   endPoint.lon);

    final departureBearing = cleanedLatLngs.length >= 2 ? _dayDetailDepartureBearing(cleanedLatLngs, startPos) : 0.0;
    final arrivalBearing   = cleanedLatLngs.length >= 2 ? _dayDetailArrivalBearing(cleanedLatLngs, endPos) : 0.0;
    // Effective departure/arrival (from windowed speed) rather than the raw/
    // segment-based start/endPoint time — see the doc comments on
    // DisplayModel.departureTime/arrivalTime.
    final departurePrecision = display.departurePrecision;
    final startTimeStr = switch (departurePrecision) {
      TimePrecision.unknown => '—',
      TimePrecision.estimated =>
        '~ ${DateFormat('HH:mm').format((display.departureTime ?? startPoint.time).toLocal())}',
      TimePrecision.precise =>
        DateFormat('HH:mm').format((display.departureTime ?? startPoint.time).toLocal()),
    };
    final endTimeStr = (endPositionReliable ? '' : '~ ') +
        DateFormat('HH:mm').format((display.arrivalTime ?? endPoint.time).toLocal());

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
    final fsTrackColor = _satelliteView ? cs.secondaryFixed : cs.primary;
    for (final seg in display.segments) {
      if (seg.kind == SegmentKind.moving && seg.points.length >= 2) {
        fsTrackPolylines.add(Polyline(
          points: seg.points.map((p) => LatLng(p.lat, p.lon)).toList(),
          strokeWidth: 4,
          color: fsTrackColor,
          borderStrokeWidth: _satelliteView ? 1.5 : 0,
          borderColor: Colors.black.withValues(alpha: 0.45),
        ));
      } else if ((seg.kind == SegmentKind.stopEntry ||
                  seg.kind == SegmentKind.stopExit) &&
                 seg.points.length >= 2) {
        fsTrackPolylines.add(Polyline(
          points: seg.points.map((p) => LatLng(p.lat, p.lon)).toList(),
          strokeWidth: 2.5,
          color: fsTrackColor.withValues(alpha: 0.50),
          borderStrokeWidth: _satelliteView ? 1.0 : 0,
          borderColor: Colors.black.withValues(alpha: 0.35),
        ));
      }
    }

    final timelineMarkers = correlated.map((pair) {
      final t = pair.$1; final p = pair.$2;
      return Marker(
        point: LatLng(p.lat, p.lon), width: 20, height: 20, alignment: Alignment.center,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _dropMarker(
            LatLng(p.lat, p.lon),
            _buildEntryTooltip(t, context.l10n),
          ),
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
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _dropMarker(
            LatLng(p.lat, p.lon),
            DateFormat('HH:mm').format(p.time.toLocal()),
          ),
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
        child: Tooltip(
          message: switch (departurePrecision) {
            TimePrecision.precise => '',
            TimePrecision.estimated => context.l10n.departureTimeEstimatedTooltip,
            TimePrecision.unknown => context.l10n.departureTimeUnknownTooltip,
          },
          child: Row(mainAxisAlignment: MainAxisAlignment.end, crossAxisAlignment: CrossAxisAlignment.center, children: [
            _trackLabel(startTimeStr, cs), const SizedBox(width: 5),
            departurePrecision == TimePrecision.precise
                ? Transform.rotate(angle: departureBearing, child: _trackArrow(cs.primary))
                : _trackArrow(cs.primary, icon: Icons.gps_not_fixed),
          ]),
        ),
      ),
      Marker(
        point: endPos, width: 82, height: 22, alignment: Alignment.centerLeft,
        child: Tooltip(
          message: endPositionReliable ? '' : context.l10n.arrivalTimeUncertainTooltip,
          child: Row(mainAxisAlignment: MainAxisAlignment.start, crossAxisAlignment: CrossAxisAlignment.center, children: [
            endPositionReliable
                ? Transform.rotate(angle: arrivalBearing, child: _trackArrow(cs.primary))
                : _trackArrow(cs.primary, icon: Icons.gps_not_fixed),
            const SizedBox(width: 5), _trackLabel(endTimeStr, cs),
          ]),
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
              urlTemplate: _satelliteView ? kSatelliteUrl : kBaseTileUrl,
              userAgentPackageName: 'com.logbook.app',
              // Keep more of the surrounding tile grid loaded across a
              // pan/zoom transition so fewer tiles need a fresh fetch right
              // when the gesture ends (default is 2).
              keepBuffer: 4,
              // Default is `.none`, which never retries a tile that failed
              // once (transient network blip, tile-server rate limit) — it
              // stays blank until this whole map widget is rebuilt. Evicting
              // once it scrolls out of view lets it be re-fetched next time
              // it's needed.
              evictErrorTileStrategy: EvictErrorTileStrategy.notVisibleRespectMargin,
              errorTileCallback: kDebugMode
                  ? (tile, error, stackTrace) =>
                      debugPrint('[Map] tile ${tile.coordinates} failed to load: $error')
                  : null,
              // Fade-in on arrival is TileLayer's default (tileDisplay:
              // TileDisplay.fadeIn()); this only overrides the tile that
              // failed to load, in place of a blank grey square.
              tileBuilder: (context, tileWidget, tile) => tile.loadError
                  ? Container(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      child: const Icon(Icons.map_outlined, size: 20),
                    )
                  : tileWidget,
            ),
            _ZoomAwareUncertaintyLayer(polygons: fsUncertaintyPolygons),
            _ZoomAwareCircleLayer(circles: anchorCircles),
            PolylineLayer(polylines: fsTrackPolylines, cullingMargin: null, simplificationTolerance: 0),
            if (widget.showRawTrack) _ZoomAwareRawTrackLayer(rawPoints: display.rawMovingPoints),
            MarkerLayer(markers: markers),
            RichAttributionWidget(attributions: [
              TextSourceAttribution('MapTiler', onTap: () async {
                final uri = Uri.parse('https://www.maptiler.com/copyright/');
                if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
              }),
              if (!_satelliteView)
                TextSourceAttribution('OpenStreetMap contributors', onTap: () async {
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
              tooltip: _satelliteView
                  ? context.l10n.tracksMapView
                  : context.l10n.tracksSatelliteView,
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
String _buildEntryTooltip(TimelineEntry t, AppLocalizations l10n) {
  final buf = StringBuffer(DateFormat('HH:mm').format(t.time.toLocal()));

  final nav = <String>[];
  // Course/speed: strip unit annotation from dialog label (e.g. "Course (°)" → "Course")
  final courseLabel = l10n.entryDialogCourseLabel.split(' ').first;
  final speedLabel  = l10n.entryDialogSpeedLabel.split(' ').first;
  if (t.course != null) nav.add('$courseLabel: ${t.course!.toStringAsFixed(0)}°');
  if (t.speed  != null) nav.add('$speedLabel: ${t.speed!.toStringAsFixed(1)} kn');
  if (nav.isNotEmpty) buf.write('\n${nav.join(' · ')}');

  final cond = <String>[];
  if (t.wind?.isNotEmpty    == true) cond.add('${l10n.entryDialogWindLabel.split(' ').first}: ${t.wind!}');
  if (t.sea?.isNotEmpty     == true) cond.add('${l10n.entryDialogSeaLabel}: ${t.sea!}');
  if (t.weather?.isNotEmpty == true) cond.add('${l10n.entryDialogWeatherLabel}: ${t.weather!}');
  if (cond.isNotEmpty) buf.write('\n${cond.join(' · ')}');

  final sails = <String>[];
  if (t.grossState?.isNotEmpty == true) sails.add('${l10n.dataMainSail}: ${_DayDetailScreenState._sailStateDisplay(t.grossState!, l10n)}');
  if (t.fockState?.isNotEmpty  == true) sails.add('${l10n.dataJibSail}: ${_DayDetailScreenState._sailStateDisplay(t.fockState!, l10n)}');
  if (t.motorOn  != null) sails.add('${l10n.entryDialogMotorLabel}: ${t.motorOn! ? l10n.on : l10n.off}');
  if (t.keelDown != null) sails.add('${l10n.entryDialogKeelLabel}: ${t.keelDown! ? l10n.vesselKeelDown : l10n.vesselKeelUp}');
  if (sails.isNotEmpty) buf.write('\n${sails.join(' · ')}');

  if (t.remarks?.isNotEmpty          == true) buf.write('\n${t.remarks}');
  if (t.vesselStatusNote?.isNotEmpty == true) {
    buf.write('\n${_DayDetailScreenState._vesselStatusDisplay(t.vesselStatusNote!, l10n)}');
  }

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
      backgroundColor: cs.surface,
      surfaceTintColor: Colors.transparent,
      title: Text(
        widget.title,
        style: GoogleFonts.newsreader(fontSize: 18, fontWeight: FontWeight.w600, color: cs.onSurface),
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
          child: Text(context.l10n.cancel),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.pop(context, _ctrl.text),
          icon: const Icon(Icons.anchor, size: 18),
          label: Text(context.l10n.saveChanges),
        ),
      ],
    );
  }
}
