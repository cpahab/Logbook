import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:geolocator/geolocator.dart';

import '../data/home_repository.dart';
import '../domain/day_entry.dart';
import '../domain/daily_track.dart';
import '../domain/timeline_entry.dart';
import '../domain/track_point.dart';
import '../domain/crew_member.dart';
import '../domain/timeline_amendment.dart';
import '../domain/vessel_equipment.dart';
import '../widgets/add_timeline_entry_dialog.dart';
import '../widgets/add_crew_member_dialog.dart';
import '../widgets/crew_picker_sheet.dart';
import '../widgets/keel_icon.dart';
import '../../../core/services/gps_consent_service.dart';
import '../../../core/utils/coordinate_format.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/nav_bar.dart';
import '../../../core/widgets/reorderable_list_card.dart';
import '../../../core/widgets/undo_delete_snackbar.dart';
import '../utils/bearing_utils.dart';
import '../utils/compute_daily_stats.dart';
import '../widgets/day_detail_display_helpers.dart';
import '../widgets/edit_text_dialog.dart';
import '../widgets/edit_vessel_status_dialog.dart';
import '../widgets/entry_tooltip.dart';
import '../widgets/map_layers.dart';
import '../widgets/map_capture.dart';
import '../widgets/map_render_helpers.dart';
import 'day_map_fullscreen.dart';
import 'positions_only_map_fullscreen.dart';
import '../utils/filter_settings.dart';
import '../utils/gpx_parser.dart';
import '../utils/track_correlation.dart';
import '../utils/gpx_exporter.dart';
import '../utils/pdf_exporter.dart';
import '../utils/sail_state_utils.dart';
import '../utils/photo_service.dart';
import '../utils/trim_track.dart';
import '../../tracks/data/track_computation_cache.dart';
import '../../settings/domain/theme_provider.dart';
import '../../../l10n/l10n_extension.dart';
import '../../../core/constants/map_config.dart';
import '../../../core/widgets/progress_snackbar.dart';
import '../../../app/route_names.dart';
import '../../../app/theme/theme_extensions.dart';


/// Full detail view for one calendar day's log entry: crew list, reflection
/// note, photos, GPS route map, timeline (course/speed/wind/sail entries,
/// each correlatable to its GPS position), vessel status, and a free-text
/// narrative. Also hosts the day-level actions menu (change date, import/
/// export GPX, export PDF, delete track/day).
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

  /// Whether this screen's date is the current calendar day — gates
  /// same-day-only affordances like adding a live timeline entry without an
  /// amendment reason.
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
        if (mounted) _addTimelineEntry();
      });
    }
    // Save as soon as focus leaves both route fields, not just on explicit
    // "Done"/checkmark — otherwise navigating away mid-edit silently
    // discards whatever was typed.
    _fromHarborFocus.addListener(_onRouteFocusChange);
    _toHarborFocus.addListener(_onRouteFocusChange);
  }

  /// Persists the in-progress route (from/to harbor) edit once focus leaves
  /// both text fields — the save trigger for [_editingRoute] mode.
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

  // ── Build ──────────────────────────────────────────────────────────
  /// Scaffold: app bar (with the day-actions overflow menu), bottom nav
  /// (FAB adds a new timeline entry), and the scrollable body — or a
  /// "no entry" message if this date has none.
  @override
  Widget build(BuildContext context) {
    final repo = context.watch<HomeRepository>();
    final day = DateTime(widget.year, widget.month, widget.day);
    final entry = repo.getEntry(day);
    final track = repo.dailyTracks[day];

    final filterSettings = context.watch<ThemeProvider>().filterSettings;
    DailyStats? stats;
    if (track != null && track.points.isNotEmpty) {
      stats = TrackComputationCache.get(
        day: day,
        sourcePoints: track.points,
        settings: filterSettings,
      ).stats;
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
          // Usually pushed from the home screen's day list (pop() correctly
          // reveals the existing Home instance with its scroll position and
          // reverses the entrance animation). But GPX-import flows reach
          // this screen via go(), leaving nothing to pop back to — fall
          // back to Home in that case.
          onPressed: () => context.canPop()
              ? context.pop()
              : context.goNamed(AppRoute.home),
        ),
        title: Text(
          '$dayName · $dateStr',
          style: Theme.of(context).textTheme.labelSmall!.copyWith(
            color: cs.primary,
          ),
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          // -- Day-actions overflow menu (change date, GPX/PDF import-export, delete) --
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
                    gpxUploadIcon(context),
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
          // -- end overflow menu --
        ],
      ),
      bottomNavigationBar: AppBottomNav(
        active: NavTab.journal,
        onFabTap: () => _addTimelineEntry(),
        onSelect: (tab) {
          if (tab == NavTab.journal) context.goNamed(AppRoute.home);
          if (tab == NavTab.map) context.pushNamed(AppRoute.tracks);
          if (tab == NavTab.settings) context.pushNamed(AppRoute.settings);
          if (tab == NavTab.safety) context.pushNamed(AppRoute.emergencyManifest);
        },
      ),
      body: entry == null
          ? Center(child: Text(l10n.dayNoEntry))
          : _buildBody(entry, track, stats, filterSettings, cs),
    );
  }

  // ── Body ──────────────────────────────────────────────────────────
  /// Scrollable stack of every section card, in display order: crew, daily
  /// reflection, photos, route map, timeline log, vessel status, free text.
  /// Pre-computes the GPS-correlated position for each timeline entry once
  /// here, shared by every entry card below.
  Widget _buildBody(DayEntry entry, DailyTrack? track, DailyStats? stats,
      FilterSettings filterSettings, ColorScheme cs) {
    final corrPoints = track != null
        ? TrackComputationCache.get(
            day: track.day,
            sourcePoints: track.points,
            settings: filterSettings,
          ).display.correlationPoints
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
            _buildPhotoStrip(entry, cs),
            _buildRouteMap(entry, track, stats, cs),
            _buildLogSection(entry, correlatedMap, cs),
            _buildVesselStatus(entry, cs),
            _buildFreeText(entry, cs),
          ],
        ),
      ),
    );
  }

  // ── Free Text ─────────────────────────────────────────────────────
  /// "Notes" section: a free-text field (distinct from the italic "Diary"
  /// reflection) shown as a tappable card, or an add-button when empty.
  Widget _buildFreeText(DayEntry entry, ColorScheme cs) {
    final tl = cs;
    final hasText = entry.freeText?.isNotEmpty ?? false;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.l10n.sectionNotes.toUpperCase(),
          style: Theme.of(context).textTheme.labelSmall!.copyWith(
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
                style: Theme.of(context).textTheme.bodyMedium!.copyWith(
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

  /// Opens the free-text editor dialog and saves the result.
  void _editFreeText(DayEntry entry) async {
    final result = await showDialog<String>(
      context: context,
      builder: (_) => EditTextDialog(
        title: context.l10n.sectionNotes,
        initialText: entry.freeText,
        hintText: context.l10n.dayFreeTextHint,
      ),
    );
    if (!mounted || result == null) return;
    setState(() {
      entry.freeText = result.trim().isEmpty ? null : result.trim();
      context.read<HomeRepository>().saveEntry(entry, changedFields: {'freeText'});
    });
  }

  // ── Daily Reflection ──────────────────────────────────────────────
  /// "Diary" section: a personal, italicized reflection note shown as a
  /// tappable quoted card, or an add-button when empty.
  Widget _buildReflection(DayEntry entry, ColorScheme cs) {
    final tl = cs;
    final hasNotes = entry.notes?.isNotEmpty ?? false;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.l10n.sectionDiary.toUpperCase(),
          style: Theme.of(context).textTheme.labelSmall!.copyWith(
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
                style: Theme.of(context).textTheme.fieldValueProse.copyWith(fontStyle: FontStyle.italic, height: 1.5, color: cs.onSurface),
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
  /// "Crew" section: read-only list of today's crew, or (in [_crewEditing]
  /// mode) a reorderable, editable list backed by [_pendingCrew] with its
  /// own commit/cancel actions rather than saving on every change.
  Widget _buildCrewList(DayEntry entry, ColorScheme cs) {
    final tl = cs;
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
              style: Theme.of(context).textTheme.labelSmall!.copyWith(
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
                        style: Theme.of(context).textTheme.labelSmall!.copyWith(
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
        // ── end header ──
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
                ? ReorderableListCard<CrewMember>(
                    items: displayCrew,
                    onReorder: _reorderPending,
                    dividerColor: tl.dividerColor,
                    keyOf: (member) => ValueKey(member.name),
                    itemBuilder: (context, member, i) => buildCrewRow(
                      context,
                      member: member,
                      isFirst: i == 0,
                      cs: cs,
                      editing: true,
                      index: i,
                      onTap: () => _editPendingMember(i),
                    ),
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
                            buildCrewRow(
                            context,
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
        // ── end crew body ──
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
                    textStyle: Theme.of(context).textTheme.chipLabel,
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
                    textStyle: Theme.of(context).textTheme.chipLabel,
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

  // ── Route & Map ───────────────────────────────────────────────────
  /// "Route" section: an inline-editable from/to harbor line, plus either
  /// the GPS map + stats grid (if a track exists) or a prompt to import one.
  Widget _buildRouteMap(
      DayEntry entry, DailyTrack? track, DailyStats? stats, ColorScheme cs) {
    final tl = cs;
    final hasTrack = track != null && track.points.isNotEmpty;
    final positioned = entry.timeline
        .where((t) => t.latitude != null && t.longitude != null)
        .toList();
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
          style: Theme.of(context).textTheme.labelSmall!.copyWith(
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
                                      hintStyle: Theme.of(context).textTheme.fieldHintCompact.copyWith(color: cs.onSurfaceVariant),
                                    ),
                                    style: Theme.of(context).textTheme.fieldValueCompact.copyWith(color: cs.onSurface),
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
                                      hintStyle: Theme.of(context).textTheme.fieldHintCompact.copyWith(color: cs.onSurfaceVariant),
                                    ),
                                    style: Theme.of(context).textTheme.fieldValueCompact.copyWith(color: cs.onSurface),
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
                                          style: Theme.of(context).textTheme.fieldValueCompact.copyWith(color: cs.onSurface),
                                          overflow: TextOverflow.ellipsis,
                                        )
                                      : Text(
                                          context.l10n.dayCaptureRoute,
                                          style: Theme.of(context).textTheme.fieldHintCompact.copyWith(fontStyle: FontStyle.italic, color: cs.onSurfaceVariant),
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
                      : (positioned.isNotEmpty
                          ? SizedBox(
                              height: 220,
                              child: _buildPositionsOnlyMap(entry, positioned),
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
                                      style: Theme.of(context).textTheme.fieldHintCompact.copyWith(fontStyle: FontStyle.italic, color: cs.onSurfaceVariant),
                                    ),
                                  ],
                                ),
                              ),
                            )),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  /// 2×2 (or 2×1) stat grid under the map: distance, average speed, and
  /// (when meaningfully different) moving-average and max speed.
  Widget _buildStatsGrid(DailyStats stats, ColorScheme cs) {
    final tl = cs;
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
                  child: statCell(
                      context,
                      context.l10n.statDistance.toUpperCase(), '${stats.distanceNm.toStringAsFixed(1)} nm', cs),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: statCell(context, context.l10n.statDuration,
                      _formatDuration(stats.movingDuration), cs),
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
                      child: statCell(
                      context,
                          context.l10n.statAvgSpeedUnderway, '${stats.avgMakingWayKn.toStringAsFixed(1)} kn', cs),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: statCell(
                      context,
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

  /// Formats a [Duration] as "Xh Ymin" (or just "Ymin" under an hour) —
  /// matches pdf_exporter.dart's identical local `dur()` helper, kept in
  /// sync so the in-app stat and the PDF read the same way.
  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    return h > 0 ? '${h}h ${m}min' : '${m}min';
  }


  // ── Log Section ───────────────────────────────────────────────────
  /// "Log Entries" section: the day's timeline as a vertical spine of cards,
  /// each correlated to a GPS position when [correlatedMap] has one.
  Widget _buildLogSection(DayEntry entry,
      Map<TimelineEntry, TrackPoint> correlatedMap, ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              context.l10n.sectionLogEntries.toUpperCase(),
              style: Theme.of(context).textTheme.labelSmall!.copyWith(
                color: cs.secondary,
              ),
            ),
            const Spacer(),
            Tooltip(
              message: context.l10n.dayAddLogEntry,
              child: GestureDetector(
                onTap: () => _addTimelineEntry(),
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
            () => _addTimelineEntry(),
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

  /// Spine-dot + connector line for one timeline entry, wrapping its
  /// [_buildLogEntryCard].
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

  /// One timeline entry's card: an auto-derived label (Departure/Arrival/
  /// Progress, or Crew/Vessel-status for auto-generated notes), time, tap-to-
  /// snap-map icon, course/speed/wind/sea/weather/sail/motor/keel fields,
  /// remarks, and an amendment-history badge if this entry has been edited.
  Widget _buildLogEntryCard(DayEntry entry, TimelineEntry t, int index,
      int total, TrackPoint? trackedPoint, ColorScheme cs) {
    final tl = cs;
    final timeStr =
        '${t.time.hour.toString().padLeft(2, '0')}:${t.time.minute.toString().padLeft(2, '0')}';

    final bool isCrewEntry = isCrewNote(t.vesselStatusNote);
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
                  style: Theme.of(context).textTheme.labelSmall!.copyWith(
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
                    style: Theme.of(context).textTheme.fieldValueProse.copyWith(color: cs.primary),
                  ),
                  const SizedBox(width: 12),
                  Tooltip(
                    message: context.l10n.dayEditLogEntry,
                    child: GestureDetector(
                      onTap: () => _editTimelineEntry(entry, t),
                      child: Icon(Icons.edit_outlined,
                          size: 16, color: cs.mutedLabel),
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
                style: Theme.of(context).textTheme.fieldValueCompact.copyWith(color: cs.onSurface),
              ),
            ],
            // Vessel status note (auto-generated)
            if (t.vesselStatusNote != null) ...[
              const SizedBox(height: 8),
              Text(
                isCrewEntry
                    ? crewNoteDisplay(t.vesselStatusNote!, context.l10n.dataCrewNote, context.l10n.labelSkipper)
                    : vesselStatusDisplay(t.vesselStatusNote!, context.l10n),
                style: Theme.of(context).textTheme.bodyMedium!.copyWith(
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
                t.temperature != null ||
                t.pressure != null ||
                (t.latitude != null && t.longitude != null) ||
                VesselEquipmentConfig.slotKeys.any((k) => slotValue(t, k) != null)) ...[
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
                  if (t.temperature != null)
                    '${context.l10n.dataTemperature}: ${t.temperature!.toStringAsFixed(1)}°C',
                  if (t.pressure != null)
                    '${context.l10n.dataPressure}: ${t.pressure!.toStringAsFixed(0)} mBar',
                  if (t.latitude != null && t.longitude != null)
                    '${context.l10n.dataPosition}: ${formatDDM(t.latitude!, t.longitude!)}',
                  ...equipmentStatusLines(
                      t, context.read<ThemeProvider>().vesselEquipment.activeSlots),
                ].join(' · '),
                style: Theme.of(context).textTheme.bodyMedium!.copyWith(
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



  /// Small "amended N times, last on ..." tappable line at the bottom of a
  /// log entry card, opening the full [_showAmendmentHistory] sheet.
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
          Icon(Icons.history, size: 13, color: cs.mutedLabel),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.unitLabel.copyWith(fontSize: 11, letterSpacing: 0.3, color: cs.mutedLabel),
            ),
          ),
          Icon(Icons.chevron_right, size: 14, color: cs.outlineVariant),
        ],
      ),
    );
  }

  /// Bottom sheet listing every prior snapshot of [t], newest first: the
  /// current state, each amendment's snapshot (with its reason), and the
  /// original entry at the bottom.
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
                  style: Theme.of(context).textTheme.dialogTitle.copyWith(fontSize: 20, fontWeight: FontWeight.w600, color: cs.primary),
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
                      return amendmentSnapshotTile(context, 
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
                      return amendmentSnapshotTile(context, 
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
                    return amendmentSnapshotTile(context, 
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

  // ── Photo gallery ─────────────────────────────────────────────────
  /// "Photos" section header + gallery (or an add-button/progress indicator
  /// when empty or mid-upload). [_deletingPhotos] paths stay visible (with a
  /// spinner overlay) until their delete actually completes.
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
              style: Theme.of(context).textTheme.labelSmall!.copyWith(
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
                  style: Theme.of(context).textTheme.bodyMedium!.copyWith(
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

  /// Single full-width photo (contain-fit), or a horizontally scrollable
  /// strip of tiles for multiple photos.
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

  /// One photo tile: fetches/decodes the local cache file, shows a spinner
  /// while loading or being deleted, and a delete "×" button overlay.
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
          // Strip tile: scale to height, natural width — no cropping.
          // cacheHeight makes the codec decode (and cache) at roughly the
          // tile's actual physical pixel height instead of the photo's
          // full ~1920px resolution — cacheWidth is left unset so Flutter
          // derives it to preserve aspect ratio automatically.
          final cacheH =
              (h * MediaQuery.devicePixelRatioOf(context)).round();
          image = GestureDetector(
            onTap: () => _viewPhoto(file),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.file(file,
                  height: h, fit: BoxFit.fitHeight, cacheHeight: cacheH),
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

  /// Opens the system photo picker, uploads the selection, and appends the
  /// resulting Storage paths to the entry.
  void _addPhotos(DayEntry entry) async {
    if (_importingPhotos) return;
    setState(() => _importingPhotos = true);
    // null in local mode (no cloud "active logbook" was ever assigned) means
    // the default local logbook — '' is its reserved sentinel, same
    // convention as backup_screen.dart — not "no logbook, abort".
    final logbookId = context.read<ValueNotifier<String?>>().value ?? '';
    final day = DateTime(widget.year, widget.month, widget.day);
    try {
      final paths = await PhotoService.pickAndUpload(day, logbookId);
      if (!mounted || paths.isEmpty) return;
      // Re-fetch: a Firestore sync may have replaced the entry object in the
      // Hive box during the await, making the original reference invalid.
      final repo = context.read<HomeRepository>();
      final fresh = repo.getEntry(day) ?? entry;
      fresh.photos.addAll(paths);
      repo.saveEntry(fresh, changedFields: {'photos'});
    } finally {
      if (mounted) setState(() => _importingPhotos = false);
    }
  }

  /// Confirms, then removes a photo from Storage and the entry's photo list.
  void _deletePhoto(DayEntry entry, String storagePath) async {
    final confirmed = await showConfirmDialog(
      context,
      title: context.l10n.dayDeletePhoto,
      confirmLabel: context.l10n.delete,
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    setState(() => _deletingPhotos.add(storagePath));
    // Re-fetch: a Firestore sync or a prior concurrent delete may have replaced
    // the entry object in the Hive box while the dialog was open.
    final repo = context.read<HomeRepository>();
    final day = DateTime(widget.year, widget.month, widget.day);
    final fresh = repo.getEntry(day) ?? entry;
    fresh.photos.remove(storagePath);
    repo.saveEntry(fresh, changedFields: {'photos'});
    await repo.deletePhoto(storagePath);
    if (mounted) setState(() => _deletingPhotos.remove(storagePath));
  }

  /// Full-screen pinch-to-zoom viewer for one photo; tap to dismiss.
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
  /// "Vessel Status" card: oil/fuel level bars and keel position, on a
  /// tertiary-colored background distinct from the other white/surface cards.
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
              style: Theme.of(context).textTheme.labelSmall!.copyWith(
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
                      style: Theme.of(context).textTheme.labelSmall!.copyWith(
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
                        child: vesselStatCell(context, 
                            context.l10n.vesselOilLabel.toUpperCase(), entry.oilLevel, Icons.opacity, cs, cardFg),
                      ),
                      const SizedBox(width: 20),
                      Expanded(
                        child: vesselStatCell(context, context.l10n.vesselFuelLabel.toUpperCase(), entry.fuelLevel,
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
                        style: Theme.of(context).textTheme.labelSmall!.copyWith(
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
                            style: Theme.of(context).textTheme.fieldValueProse.copyWith(color: entry.keelDown == null
                                  ? cardFg.withValues(alpha: 0.45)
                                  : cardFg),
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
        const SizedBox(height: 20),
      ],
    );
  }

  // ── Empty state helper ────────────────────────────────────────────
  /// Dashed-border "add X" prompt shown when a section has no content yet.
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
            Flexible(
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.fieldHintCompact.copyWith(fontStyle: FontStyle.italic, color: cs.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Map ──────────────────────────────────────────────────────────
  /// The inline preview map embedded in the Route card: track polyline(s),
  /// stop halos, an uncertainty corridor (at close zoom), start/end/hourly
  /// tap-to-inspect markers, and satellite/normal toggle support. Builds a
  /// [DisplayModel] via [TrackComputationCache], which keys on track
  /// identity + filter settings so it recomputes exactly when either
  /// changes between rebuilds, not on every rebuild.
  Widget _buildMap(DayEntry entry, DailyTrack? track) {
    if (track == null || track.points.isEmpty) return const SizedBox();

    final cs = Theme.of(context).colorScheme;
    final provider = context.watch<ThemeProvider>();
    final filterSettings = provider.filterSettings;
    final showRawTrack = provider.showRawTrack;
    final display    = TrackComputationCache.get(
      day: track.day,
      sourcePoints: track.points,
      settings: filterSettings,
    ).display;
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
        ? dayDetailDepartureBearing(cleanedLatLngs, startPos) : 0.0;
    final arrivalBearing = cleanedLatLngs.length >= 2
        ? dayDetailArrivalBearing(cleanedLatLngs, endPos) : 0.0;
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
    // Gated to zoom > 15 by ZoomAwareUncertaintyLayer (sub-pixel at route zoom).
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
            buildEntryTooltip(t, context.l10n,
                context.read<ThemeProvider>().vesselEquipment.activeSlots),
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

    final midStopMarkers = [
      for (final stop in display.stops.where((s) => s.kind == AnchorKind.mid))
        Marker(
          point: LatLng(stop.lat, stop.lon),
          width: 32,
          height: 32,
          alignment: Alignment.center,
          child: Tooltip(
            message: fmtDur(stop.minutes),
            triggerMode: isTouchPlatform ? TooltipTriggerMode.tap : TooltipTriggerMode.longPress,
            showDuration: isTouchPlatform ? const Duration(seconds: 4) : const Duration(milliseconds: 1500),
            waitDuration: isTouchPlatform ? Duration.zero : const Duration(milliseconds: 400),
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
              trackLabel(context, startTimeStr, cs),
              const SizedBox(width: 5),
              departurePrecision == TimePrecision.precise
                  ? Transform.rotate(
                      angle: departureBearing,
                      child: trackArrow(cs.primary),
                    )
                  : trackArrow(cs.primary, icon: Icons.gps_not_fixed),
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
                      child: trackArrow(cs.primary),
                    )
                  : trackArrow(cs.primary, icon: Icons.gps_not_fixed),
              const SizedBox(width: 5),
              trackLabel(context, endTimeStr, cs),
            ],
          ),
        ),
      ),
    ];

    if (_droppedMarkerLatLng != null) {
      markers.add(droppedMarker(
        position: _droppedMarkerLatLng!,
        label: _droppedMarkerLabel,
        context: context,
        cs: cs,
        onDismiss: () {
          _markerDismissTimer?.cancel();
          setState(() { _droppedMarkerLatLng = null; _droppedMarkerLabel = null; });
        },
      ));
    }

    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            maxZoom: kMaxMapZoom,
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
            mapTileLayer(satelliteView: _satelliteView),
            ZoomAwareUncertaintyLayer(polygons: uncertaintyPolygons),
            ZoomAwareCircleLayer(circles: anchorCircles),
            PolylineLayer(polylines: trackPolylines, cullingMargin: null, simplificationTolerance: 0),
            if (showRawTrack) ZoomAwareRawTrackLayer(rawPoints: display.rawMovingPoints),
            MarkerLayer(markers: markers),
            mapAttribution(satelliteView: _satelliteView),
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
                mapZoomButton(Icons.add, () => _mapController.move(
                  _mapController.camera.center,
                  _mapController.camera.zoom + 1,
                ), cs, heroTagPrefix: ''),
                const SizedBox(height: 6),
                mapZoomButton(Icons.remove, () => _mapController.move(
                  _mapController.camera.center,
                  _mapController.camera.zoom - 1,
                ), cs, heroTagPrefix: ''),
                const SizedBox(height: 6),
                mapZoomButton(Icons.explore, () {
                  if (fitLatLngs.isNotEmpty) {
                    _mapController.fitCamera(CameraFit.bounds(
                      bounds: LatLngBounds.fromPoints(fitLatLngs),
                      padding: const EdgeInsets.all(32),
                    ));
                  }
                }, cs, heroTagPrefix: ''),
                const SizedBox(height: 6),
              ],
              FloatingActionButton.small(
                heroTag: 'detail_fullscreen_button',
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => DayMapFullScreen(
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
        // ── end map controls ──
      ],
    );
  }

  /// Simplified inline map for a day with no imported GPX track but ≥1
  /// timeline entry carrying its own auto-captured GPS fix
  /// ([TimelineEntry.latitude]/[longitude]). Shows one pin per such entry,
  /// connected by a polyline (styled like a real track's) once there are
  /// 2+ of them — no stop halos, no uncertainty band, since neither
  /// concept applies to a handful of manually-logged fixes. Zoom/center,
  /// satellite-toggle, and fullscreen controls match the track map's.
  Widget _buildPositionsOnlyMap(DayEntry entry, List<TimelineEntry> positioned) {
    final cs = Theme.of(context).colorScheme;
    final sorted = [...positioned]..sort((a, b) => a.time.compareTo(b.time));
    final points = sorted.map((t) => LatLng(t.latitude!, t.longitude!)).toList();
    final positionsColor = _satelliteView ? cs.secondaryFixed : cs.primary;
    final positionsPolylines = <Polyline>[
      if (points.length >= 2)
        Polyline(
          points: points,
          strokeWidth: 4,
          color: positionsColor,
          borderStrokeWidth: _satelliteView ? 1.5 : 0,
          borderColor: Colors.black.withValues(alpha: 0.45),
        ),
    ];

    final markers = <Marker>[
      for (final t in sorted)
        Marker(
          point: LatLng(t.latitude!, t.longitude!),
          width: 20,
          height: 20,
          alignment: Alignment.center,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _dropMarker(
              LatLng(t.latitude!, t.longitude!),
              buildEntryTooltip(t, context.l10n,
                  context.read<ThemeProvider>().vesselEquipment.activeSlots),
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
        ),
    ];

    if (_droppedMarkerLatLng != null) {
      markers.add(droppedMarker(
        position: _droppedMarkerLatLng!,
        label: _droppedMarkerLabel,
        context: context,
        cs: cs,
        onDismiss: () {
          _markerDismissTimer?.cancel();
          setState(() {
            _droppedMarkerLatLng = null;
            _droppedMarkerLabel = null;
          });
        },
      ));
    }

    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            maxZoom: kMaxMapZoom,
            initialCenter: points.length == 1 ? points.first : const LatLng(0, 0),
            initialZoom: 13,
            initialCameraFit: points.length >= 2
                ? CameraFit.bounds(
                    bounds: LatLngBounds.fromPoints(points),
                    padding: const EdgeInsets.all(40),
                  )
                : null,
          ),
          children: [
            mapTileLayer(satelliteView: _satelliteView),
            PolylineLayer(polylines: positionsPolylines, cullingMargin: null, simplificationTolerance: 0),
            MarkerLayer(markers: markers),
            mapAttribution(satelliteView: _satelliteView),
          ],
        ),
        // Map controls — zoom + center on macOS, satellite + fullscreen always.
        Positioned(
          right: 10,
          bottom: 10,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (defaultTargetPlatform == TargetPlatform.macOS) ...[
                mapZoomButton(Icons.add, () => _mapController.move(
                  _mapController.camera.center,
                  _mapController.camera.zoom + 1,
                ), cs, heroTagPrefix: ''),
                const SizedBox(height: 6),
                mapZoomButton(Icons.remove, () => _mapController.move(
                  _mapController.camera.center,
                  _mapController.camera.zoom - 1,
                ), cs, heroTagPrefix: ''),
                const SizedBox(height: 6),
                mapZoomButton(Icons.explore, () {
                  if (points.length >= 2) {
                    _mapController.fitCamera(CameraFit.bounds(
                      bounds: LatLngBounds.fromPoints(points),
                      padding: const EdgeInsets.all(32),
                    ));
                  } else if (points.isNotEmpty) {
                    _mapController.move(points.first, 13);
                  }
                }, cs, heroTagPrefix: ''),
                const SizedBox(height: 6),
              ],
              FloatingActionButton.small(
                heroTag: 'positions_fullscreen_button',
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PositionsOnlyMapFullScreen(
                      entry: entry,
                      positioned: sorted,
                      initialSatellite: _satelliteView,
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
  /// Opens the diary/reflection editor dialog and saves the result.
  void _editNotes(DayEntry entry) async {
    final result = await showDialog<String>(
      context: context,
      builder: (_) => EditTextDialog(
        title: context.l10n.sectionDiary,
        initialText: entry.notes,
        hintText: context.l10n.dayDiaryHint,
      ),
    );
    if (!mounted || result == null) return;
    setState(() {
      entry.notes = result.trim().isEmpty ? null : result.trim();
      context.read<HomeRepository>().saveEntry(entry, changedFields: {'notes'});
    });
  }

  /// Moves this entry to a newly picked date, warning first if its GPX track
  /// mostly belongs to a different day than the one being moved to.
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
        final proceed = await showConfirmDialog(
          context,
          title: context.l10n.dayChangeDateTitle,
          body: context.l10n.dayChangeDateContent(
            DateFormat('d. MMMM yyyy', locStr).format(dominantDate),
            DateFormat('d. MMMM yyyy', locStr).format(newDate),
          ),
          confirmLabel: context.l10n.dayChangeDateConfirm,
        );
        if (!mounted || !proceed) return;
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
    context.goNamed(AppRoute.dayDetail, pathParameters: {
      'year': '${newDate.year}',
      'month': '${newDate.month}',
      'day': '${newDate.day}',
    });
  }

  /// Loads the current route into the text controllers and enters route-edit mode.
  void _startEditRoute(DayEntry entry) {
    _fromHarborCtrl.text = entry.fromHarbor ?? '';
    _toHarborCtrl.text = entry.toHarbor ?? '';
    setState(() => _editingRoute = true);
  }

  /// Saves the edited from/to harbor fields and exits route-edit mode.
  void _saveRoute(DayEntry entry) {
    setState(() {
      entry.fromHarbor = _fromHarborCtrl.text.trim().isEmpty
          ? null
          : _fromHarborCtrl.text.trim();
      entry.toHarbor = _toHarborCtrl.text.trim().isEmpty
          ? null
          : _toHarborCtrl.text.trim();
      context.read<HomeRepository>().saveEntry(entry,
          changedFields: {'fromHarbor', 'toHarbor'});
      _editingRoute = false;
    });
  }

  /// Shows the oil/fuel-slider + keel-toggle dialog and saves the result.
  void _editVesselStatus(DayEntry entry) async {
    final result = await showEditVesselStatusDialog(
      context,
      initialOil: entry.oilLevel ?? 50,
      initialFuel: entry.fuelLevel ?? 50,
      initialKeel: entry.keelDown,
    );
    if (!mounted || result == null) return;
    final oilVal = result.oil;
    final fuelVal = result.fuel;
    final keelVal = result.keel;
    final oldOil = entry.oilLevel;
    final oldFuel = entry.fuelLevel;
    final oldKeel = entry.keelDown;
    final now = DateTime.now();
    final entryTime = DateTime(widget.year, widget.month, widget.day, now.hour, now.minute);
    setState(() {
      entry.oilLevel = oilVal;
      entry.fuelLevel = fuelVal;
      entry.keelDown = keelVal;
      var timelineTouched = false;
      if (oilVal != oldOil || fuelVal != oldFuel) {
        entry.timeline.add(TimelineEntry(
          time: entryTime,
          vesselStatusNote: 'vs:oil=$oilVal,fuel=$fuelVal',
        ));
        timelineTouched = true;
      }
      if (keelVal != oldKeel && keelVal != null) {
        entry.timeline.add(TimelineEntry(
          time: entryTime,
          vesselStatusNote: keelVal ? 'vs:keel=down' : 'vs:keel=up',
        ));
        timelineTouched = true;
      }
      entry.timeline.sort((a, b) => a.time.compareTo(b.time));
      context.read<HomeRepository>().saveEntry(entry, changedFields: {
        'oilLevel', 'fuelLevel', 'keelDown',
        if (timelineTouched) 'timeline',
      });
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
    final touchedTimeline = fresh.timeline.isNotEmpty;
    if (touchedTimeline) {
      final now = DateTime.now();
      final ts = DateTime(widget.year, widget.month, widget.day, now.hour, now.minute);
      fresh.timeline.add(TimelineEntry(
          time: ts, vesselStatusNote: HomeRepository.buildCrewNote(fresh.crew)));
      fresh.timeline.sort((a, b) => a.time.compareTo(b.time));
    }
    repo.saveEntry(fresh, changedFields: {
      'crew',
      if (touchedTimeline) 'timeline',
    });
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

  /// Discards [_pendingCrew] and exits edit mode without saving.
  void _cancelCrewChanges() {
    setState(() {
      _crewEditing = false;
      _pendingCrew = null;
    });
  }

  /// Saves [_pendingCrew] as the entry's crew list, auto-logging a crew-note
  /// timeline entry if the day already has timeline entries, then exits edit mode.
  void _commitCrewChanges(DayEntry entry) {
    if (_pendingCrew == null) return;
    final repo = context.read<HomeRepository>();
    final day = DateTime(widget.year, widget.month, widget.day);
    final fresh = repo.getEntry(day) ?? entry;

    fresh.crew = List<CrewMember>.from(_pendingCrew!);

    final touchedTimeline = fresh.timeline.isNotEmpty && fresh.crew.isNotEmpty;
    if (touchedTimeline) {
      final now = DateTime.now();
      final ts = DateTime(
          widget.year, widget.month, widget.day, now.hour, now.minute);
      final note = HomeRepository.buildCrewNote(fresh.crew);
      fresh.timeline.add(TimelineEntry(time: ts, vesselStatusNote: note));
      fresh.timeline.sort((a, b) => a.time.compareTo(b.time));
    }

    repo.saveEntry(fresh, changedFields: {
      'crew',
      if (touchedTimeline) 'timeline',
    });
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

  /// Edits the pending-crew member at [index] and saves the change to their
  /// roster record.
  void _editPendingMember(int index) async {
    if (_pendingCrew == null || index >= _pendingCrew!.length) return;
    final member = _pendingCrew![index];
    final updated = await showDialog<CrewMember>(
      context: context,
      builder: (_) => AddCrewMemberDialog(
        initialMember: member,
        deleteLabel: context.l10n.crewButtonRemoveFromDay,
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

  /// Removes [member] from [_pendingCrew]; always succeeds (no confirmation
  /// needed since edit mode itself is cancelable).
  Future<bool> _removePendingMember(CrewMember member) async {
    setState(() => _pendingCrew?.remove(member));
    return true;
  }

  /// Reorders [_pendingCrew] (drag-and-drop in the crew edit list).
  void _reorderPending(int oldIndex, int newIndex) {
    setState(() {
      if (_pendingCrew == null) return;
      final m = _pendingCrew!.removeAt(oldIndex);
      _pendingCrew!.insert(newIndex, m);
    });
  }

  // ── Timeline mutations ────────────────────────────────────────────
  /// Shows the add-timeline-entry dialog and saves the result.
  void _addTimelineEntry() async {
    final repo = context.read<HomeRepository>();
    final day = DateTime(widget.year, widget.month, widget.day);
    final result = await showDialog<AddTimelineEntryResult>(
      context: context,
      builder: (_) => AddTimelineEntryDialog(day: day),
    );
    if (!mounted || result == null) return;
    repo.addTimelineEntry(day, result.entry,
        equipment: context.read<ThemeProvider>().vesselEquipment);
    unawaited(_captureEntryPosition(result.entry, day));
  }

  /// Fire-and-forget: if the device-local "auto-log position" setting is on,
  /// requests a one-time high-accuracy GPS fix (same 15s timeout as the
  /// MAYDAY screen) for the just-created entry [t], then patches it into
  /// whichever timeline currently holds it. Never surfaces an error — this
  /// is a best-effort background enhancement, not a required part of saving
  /// the entry. Editing an existing entry never calls this.
  Future<void> _captureEntryPosition(TimelineEntry t, DateTime day) async {
    if (!context.read<ThemeProvider>().autoLogPositionEnabled) return;
    try {
      await GpsConsentService.requestIfNeeded(context);
      if (!mounted) return;

      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.deniedForever ||
          permission == LocationPermission.denied) {
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      if (!mounted) return;

      final repo = context.read<HomeRepository>();
      // Re-fetch rather than trust a captured reference: the debounced
      // Firestore sync may already have replaced the object graph by the
      // time this GPS fix resolves — see _deleteTimelineEntry.
      final current = repo.getEntry(day);
      if (current == null) return;
      final index = _indexOfTimelineEntry(current.timeline, t);
      if (index == -1) return; // entry was deleted while we were waiting

      setState(() {
        current.timeline[index].latitude = pos.latitude;
        current.timeline[index].longitude = pos.longitude;
        repo.saveEntry(current, changedFields: {'timeline'});
      });
    } catch (_) {
      // Silently swallow: permission errors, timeouts, location-services-off,
      // etc. must never surface for a best-effort background feature.
    }
  }

  /// Finds [t]'s position within [timeline] by reference (the common,
  /// cheap case), falling back to matching `createdAt` (stable across
  /// edits, unlike list position) if a Firestore sync round-trip has
  /// already replaced the object graph with freshly deserialized instances.
  /// Returns -1 if [t] genuinely isn't present.
  int _indexOfTimelineEntry(List<TimelineEntry> timeline, TimelineEntry t) {
    final byReference = timeline.indexOf(t);
    if (byReference != -1) return byReference;
    if (t.createdAt == null) return -1;
    return timeline.indexWhere((e) => e.createdAt == t.createdAt);
  }

  /// Removes [t] from the timeline, offering an "undo" snackbar action that
  /// re-inserts it at its original index.
  void _deleteTimelineEntry(DayEntry entry, TimelineEntry t) {
    final repo = context.read<HomeRepository>();
    final date = entry.date;
    // Re-fetch rather than trust the passed-in `entry`: the debounced
    // Firestore sync (~2s after any edit) always echoes back a freshly
    // deserialized DayEntry that replaces this one in the repository. Saving
    // a stale reference throws HiveError ("This object is currently not in a
    // box"); matching `t` by identity against a fresh object graph also
    // silently fails, hence _indexOfTimelineEntry's createdAt fallback.
    final current = repo.getEntry(date) ?? entry;
    final index = _indexOfTimelineEntry(current.timeline, t);
    if (index == -1) return;
    setState(() {
      current.timeline.removeAt(index);
      repo.saveEntry(current, changedFields: {'timeline'});
    });
    showUndoDeleteSnackBar(
      context,
      message: context.l10n.dayEntryDeleted,
      onUndo: () {
        if (!mounted) return;
        final repo = context.read<HomeRepository>();
        // Staleness risk as noted above, now certain: the 10s snackbar
        // window is always longer than the 2s debounce, so the echo has
        // essentially already landed by the time this fires.
        final current = repo.getEntry(date);
        if (current == null) return;
        setState(() {
          current.timeline.insert(index.clamp(0, current.timeline.length), t);
          current.timeline.sort((a, b) => a.time.compareTo(b.time));
          repo.saveEntry(current, changedFields: {'timeline'});
        });
      },
    );
  }

  /// Opens the edit dialog for [t]; if this is a past day (not today), the
  /// dialog collects an amendment reason and the prior state is snapshotted
  /// into [t.amendments] before being overwritten.
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
        slot1State: t.slot1State,
        slot2State: t.slot2State,
        slot3State: t.slot3State,
        slot4State: t.slot4State,
        slot5State: t.slot5State,
        slot6State: t.slot6State,
        slot7State: t.slot7State,
        slot8State: t.slot8State,
        slot9State: t.slot9State,
        slot10State: t.slot10State,
        slot11State: t.slot11State,
        slot12State: t.slot12State,
        temperature: t.temperature,
        pressure: t.pressure,
      );
      updated.amendments
        ..addAll(t.amendments) // carry forward prior amendments
        ..add(snapshot);
    }
    setState(() {
      final repo = context.read<HomeRepository>();
      // Re-fetch rather than trust the captured `entry`: the dialog above
      // was just awaited for as long as the user took to fill it in, plenty
      // of time for the debounced Firestore sync to have echoed back a
      // fresh DayEntry and replaced this one — see _deleteTimelineEntry for
      // the full explanation of why saving a stale reference throws.
      final current = repo.getEntry(entry.date) ?? entry;
      final index = _indexOfTimelineEntry(current.timeline, t);
      if (index != -1) {
        current.timeline[index] = updated;
        current.timeline.sort((a, b) => a.time.compareTo(b.time));

        final changedFields = {'timeline'};
        final derivedKeel = context
            .read<ThemeProvider>()
            .vesselEquipment
            .keelDownFor(updated.slot12State);
        if (derivedKeel != null && derivedKeel != current.keelDown) {
          current.keelDown = derivedKeel;
          changedFields.add('keelDown');
        }

        repo.saveEntry(current, changedFields: changedFields);
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.dayEntryUpdated)));
  }

  // ── GPX ───────────────────────────────────────────────────────────
  /// Picks a GPX file, previews it to determine its dominant date, warns if
  /// that date doesn't match this screen's day, and imports it.
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
      preview = (await compute(parseGpxBytes, bytes)).points;
    } else {
      final path = picked.path;
      if (path == null) return;
      final bytes = await File(path).readAsBytes();
      preview = (await compute(parseGpxBytes, bytes)).points;
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
      final proceed = await showConfirmDialog(
        context,
        title: context.l10n.dayChangeDateTitle,
        body: context.l10n.dayGpxWrongDateContent(
          DateFormat('d. MMMM yyyy', locStr).format(dominantDate),
          DateFormat('d. MMMM yyyy', locStr).format(targetDate),
        ),
        confirmLabel: context.l10n.dayGpxImportConfirm,
      );
      if (!mounted || !proceed) return;
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

  /// Builds a GPX file from [track] (filtered + raw segments) and opens the
  /// system save-file dialog.
  void _exportGpx(DailyTrack track, DateTime day) async {
    final filterSettings = context.read<ThemeProvider>().filterSettings;
    final vesselName    = context.read<ThemeProvider>().vesselName;
    final display = TrackComputationCache.get(
      day: track.day,
      sourcePoints: track.points,
      settings: filterSettings,
    ).display;
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

  /// Builds the single-day voyage-log PDF (fetching photo bytes first) and
  /// opens the system share sheet.
  void _exportPdf(DayEntry entry, DailyStats? stats, DailyTrack? track) async {
    final p = context.read<ThemeProvider>();
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    showProgressSnackBar(context, l10n.dayExportPdfInProgress);

    try {
      final display = track != null
          ? TrackComputationCache.get(
              day: track.day,
              sourcePoints: track.points,
              settings: p.filterSettings,
            ).display
          : null;
      final filteredPoints = display?.allPoints() ?? const <TrackPoint>[];
      final photoBytes = <Uint8List>[];
      for (final path in entry.photos) {
        final file = await PhotoService.localFile(path);
        if (file != null) photoBytes.add(await file.readAsBytes());
      }
      final pdfStrings = PdfStrings(
        voyageLog:     l10n.pdfVoyageLog,
        notes:         l10n.pdfNotes,
        date:          l10n.pdfDate,
        distance:         l10n.pdfDistance,
        avgSpeedUnderway: l10n.pdfAvgSpeedUnderway,
        max:              l10n.pdfMax,
        duration:      l10n.pdfDuration,
        statistics:    l10n.pdfStatistics,
        crew:          l10n.pdfCrew,
        skipper:       l10n.pdfSkipper,
        crewMember:    l10n.pdfCrewMember,
        logEntries:    l10n.pdfLogEntries,
        timeCol:       l10n.pdfTimeCol,
        courseCol:     l10n.pdfCourseCol,
        windCol:       l10n.pdfWindCol,
        seaCol:        l10n.pdfSeaCol,
        positionCol:   l10n.pdfPositionCol,
        remarksCol:    l10n.pdfRemarksCol,
        trackMap:      l10n.pdfTrackMap,
        locale:        l10n.pdfLocale,
        generatedOn:   l10n.pdfGeneratedOn,
        crewNoteLabel: l10n.dataCrewNote,
        skipperLabel:  l10n.labelSkipper,
        oilLabel:      l10n.vesselOilLabel,
        fuelLabel:     l10n.vesselFuelLabel,
        keelLabel:     l10n.entryDialogKeelLabel,
        keelDownLabel: l10n.vesselKeelDown,
        keelUpLabel:   l10n.vesselKeelUp,
        passageToTemplate:       l10n.pdfPassageTo('\u0000'),
        departureFromTemplate:   l10n.pdfDepartureFrom('\u0000'),
        departureFromAtTemplate: l10n.pdfDepartureFromAt('\u0000', '\u0000'),
        arrivalAtTemplate:       l10n.pdfArrivalAt('\u0000'),
        pageOfTemplate:          l10n.pdfPageOf(-1, -2),
      );
      if (!mounted) return;
      final trackImageBytes = filteredPoints.length >= 2
          ? await captureTrackMapImage(context,
              points: filteredPoints.map((p) => (lat: p.lat, lon: p.lon)).toList(),
              entryPositions: entryMarkerPositions(entry, filteredPoints))
          : await capturePositionsMapImage(context, positionedFixes(entry));
      if (!mounted) return;

      final bytes = await buildVoyagePdf(
        entry:              entry,
        stats:              stats,
        vesselName:         p.vesselName,
        strings:            pdfStrings,
        equipment:          p.vesselEquipment,
        trackImageBytes:    trackImageBytes,
        photoBytes:         photoBytes,
        departureTime:      display?.departureTime,
        departurePrecision: display?.departurePrecision ?? TimePrecision.unknown,
        arrivalTime:        display?.arrivalTime,
        arrivalPrecision:   display?.arrivalPrecision ?? TimePrecision.unknown,
      );

      messenger.hideCurrentSnackBar();
      if (!mounted) return;

      final fileName =
          'logbuch_${DateFormat('yyyy-MM-dd').format(entry.date)}.pdf';
      await Printing.sharePdf(bytes: bytes, filename: fileName);

      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(l10n.dayExportPdfSuccess)));
    } catch (e, st) {
      if (kDebugMode) debugPrint('_exportPdf failed: $e\n$st');
      messenger.hideCurrentSnackBar();
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(l10n.dayExportPdfError)));
    }
  }

  /// Confirms, then deletes this day's GPX track (the day entry itself is kept).
  void _removeGpx() async {
    final repo = context.read<HomeRepository>();
    final day = DateTime(widget.year, widget.month, widget.day);
    final shouldDelete = await showConfirmDialog(
      context,
      title: context.l10n.dayGpxDeleteTitle,
      body: context.l10n.dayGpxDeleteContent,
      confirmLabel: context.l10n.delete,
      destructive: true,
    );
    if (!mounted || !shouldDelete) return;
    await repo.removeGpx(day);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.dayGpxRemoved)));
  }

  /// Confirms, then permanently deletes the entire day entry (and its GPX
  /// track) and navigates back to home.
  void _deleteDay() async {
    final repo = context.read<HomeRepository>();
    final day = DateTime(widget.year, widget.month, widget.day);
    final dateLabel =
        DateFormat('d. MMMM yyyy', context.read<ThemeProvider>().localeString).format(day);
    final confirmed = await showConfirmDialog(
      context,
      title: context.l10n.dayDeleteTitle,
      body: context.l10n.dayDeleteContent(dateLabel),
      confirmLabel: context.l10n.delete,
      destructive: true,
    );
    if (!mounted || !confirmed) return;
    await repo.removeEntry(day);
    if (!mounted) return;
    context.goNamed(AppRoute.home);
  }

  // ── Map helpers ───────────────────────────────────────────────────
  /// Shows a tap-to-inspect marker at [pos] with [label], auto-dismissing
  /// after 5 seconds (or immediately if tapped again).
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

  /// The track point closest to a map tap, by planar (not great-circle)
  /// distance — sufficient at the zoom levels this map is used at.
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

}

// ── Shared map helpers ────────────────────────────────────────────────────────

// ── Keel icon ─────────────────────────────────────────────────────────────────
