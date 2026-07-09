import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../app/theme/theme_extensions.dart';
import '../../settings/domain/theme_provider.dart';
import '../domain/timeline_entry.dart';
import '../domain/vessel_equipment.dart';
import '../utils/sail_state_utils.dart';
import '../../../l10n/l10n_extension.dart';

/// Return value from [AddTimelineEntryDialog].
/// [amendmentReason] is non-null only when [isAmendment] was true and the
/// user typed a reason; it is always null for new entries.
class AddTimelineEntryResult {
  final TimelineEntry entry;
  final String? amendmentReason;
  const AddTimelineEntryResult(this.entry, {this.amendmentReason});
}

/// Rejects keystrokes that would make the course field exceed 359 (degrees).
class _CourseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    if (newValue.text.isEmpty) return newValue;
    final v = int.tryParse(newValue.text);
    if (v == null || v > 359) return oldValue;
    return newValue;
  }
}

/// Fullscreen dialog for adding a new timeline log entry or editing an
/// existing one: time, course/speed, wind/sea/weather, sail/motor/keel
/// state, and free-text remarks. When [isAmendment] is true (editing a past
/// day's entry) it also collects an amendment reason and returns it
/// alongside the entry via [AddTimelineEntryResult].
class AddTimelineEntryDialog extends StatefulWidget {
  final DateTime day;
  final TimelineEntry? initialEntry;
  final VoidCallback? onDelete;
  /// When true the dialog shows a "Reason for amendment" field and titles
  /// itself accordingly. Should be set whenever editing an entry from a
  /// past day (not today).
  final bool isAmendment;

  const AddTimelineEntryDialog({
    super.key,
    required this.day,
    this.initialEntry,
    this.onDelete,
    this.isAmendment = false,
  });

  @override
  State<AddTimelineEntryDialog> createState() => _AddTimelineEntryDialogState();
}

class _AddTimelineEntryDialogState extends State<AddTimelineEntryDialog> {
  late TimeOfDay selectedTime;

  final courseCtrl       = TextEditingController();
  final speedCtrl        = TextEditingController();
  final windStrengthCtrl = TextEditingController();
  final seaCtrl          = TextEditingController();
  final weatherCtrl      = TextEditingController();
  final remarksCtrl      = TextEditingController();
  final amendmentReasonCtrl = TextEditingController();

  String  _windDir  = 'N';
  final Map<String, String?> _slotState = {};

  // How many active equipment slots (in configured order) get their full
  // chip row shown at all times; every slot beyond that — sails, motor,
  // keel alike — collapses to a one-line summary that expands on tap, so
  // the dialog stays short regardless of how much equipment is configured.
  // 0 means every slot folds; the current value shown when opening an entry
  // (main/jib's last picked state, motor on/off, keel up/down) is still
  // visible at a glance on the collapsed summary line, so nothing is hidden
  // — folding only costs a tap when you're about to *change* a value.
  //
  // To revert to "always show the first N slots expanded": set this back to
  // that N — no other changes needed. To remove the feature entirely,
  // delete this constant, _expandedSlotKeys, and _collapsibleSlotRow, and go
  // back to rendering every entry in activeSlots the way the always-expanded
  // ones are rendered below.
  static const _alwaysExpandedSlotCount = 0;
  final Set<String> _expandedSlotKeys = {};

  /// True for [slot]s that always get a full expanded chip row, regardless
  /// of [_expandedSlotKeys] — the first [_alwaysExpandedSlotCount] slots in
  /// [activeSlots] order.
  // indexOf's *position* is compared against a threshold that's currently 0
  // but meant to be raised again later; a literal contains() check would
  // only work for this one value.
  bool _isAlwaysExpanded(EquipmentSlot slot, List<EquipmentSlot> activeSlots) =>
      activeSlots.indexOf(slot) < _alwaysExpandedSlotCount; // ignore: prefer_contains

  static const _windDirs = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];

  @override
  void initState() {
    super.initState();
    if (widget.initialEntry != null) {
      final e = widget.initialEntry!;
      selectedTime     = TimeOfDay.fromDateTime(e.time);
      courseCtrl.text  = e.course?.toString() ?? '';
      speedCtrl.text   = e.speed?.toString() ?? '';
      _parseWind(e.wind);
      seaCtrl.text     = e.sea ?? '';
      weatherCtrl.text = e.weather ?? '';
      remarksCtrl.text = e.remarks ?? '';

      // New fields (null on entries created before this feature).
      _slotState['slot1']  = e.slot1State;
      _slotState['slot2']  = e.slot2State;
      _slotState['slot3']  = e.slot3State;
      _slotState['slot4']  = e.slot4State;
      _slotState['slot5']  = e.slot5State;
      _slotState['slot6']  = e.slot6State;
      _slotState['slot7']  = e.slot7State;
      _slotState['slot8']  = e.slot8State;
      _slotState['slot9']  = e.slot9State;
      _slotState['slot10'] = e.slot10State;
      _slotState['slot11'] = e.slot11State;
      _slotState['slot12'] = e.slot12State;
    } else {
      selectedTime = TimeOfDay.now();
    }
  }

  bool _legacyFallbackApplied = false;

  /// Applies the legacy sentinel/bool → text fallback for pre-migration
  /// entries. This needs `context.l10n` (an InheritedWidget lookup), which
  /// Flutter forbids resolving before initState() completes — so it lives
  /// here instead, per Flutter's own guidance: "initialization based on
  /// inherited widgets can be placed in the didChangeDependencies method".
  /// Guarded to run once, since didChangeDependencies can fire again later
  /// (e.g. a locale switch while the dialog is open) and must not clobber
  /// edits the user has since made.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_legacyFallbackApplied) return;
    _legacyFallbackApplied = true;
    final e = widget.initialEntry;
    if (e == null) return;

    // Legacy fallback: if the new sail slots are null, derive from old
    // sentinel/bool fields so pre-migration entries don't look empty.
    final legacyGross = normalizeSailState(e.grossState);
    final legacyFock  = normalizeSailState(e.fockState);
    if (_slotState['slot1'] == null && legacyGross != null) {
      _slotState['slot1'] = _sailLabel(legacyGross);
    }
    if (_slotState['slot2'] == null && legacyFock != null) {
      _slotState['slot2'] = _sailLabel(legacyFock);
    }
    if (_slotState['slot11'] == null && e.motorOn != null) {
      _slotState['slot11'] = e.motorOn! ? context.l10n.on : context.l10n.off;
    }
    if (_slotState['slot12'] == null && e.keelDown != null) {
      _slotState['slot12'] =
          e.keelDown! ? context.l10n.vesselKeelDown : context.l10n.vesselKeelUp;
    }
  }

  /// Parses "SW 12 kn" into [_windDir] ("SW") and [windStrengthCtrl] ("12"),
  /// tolerating German "NO"/"SO" direction abbreviations.
  void _parseWind(String? wind) {
    if (wind == null || wind.isEmpty) return;
    final parts = wind.trim().split(RegExp(r'\s+'));
    for (final part in parts) {
      final up = part.toUpperCase()
          .replaceAll('NO', 'NE')
          .replaceAll('SO', 'SE');
      if (_windDirs.contains(up)) {
        _windDir = up;
      } else {
        final num = part.replaceAll(RegExp(r'[^0-9.]'), '');
        if (num.isNotEmpty) windStrengthCtrl.text = num;
      }
    }
  }

  @override
  void dispose() {
    courseCtrl.dispose();
    speedCtrl.dispose();
    windStrengthCtrl.dispose();
    amendmentReasonCtrl.dispose();
    seaCtrl.dispose();
    weatherCtrl.dispose();
    remarksCtrl.dispose();
    super.dispose();
  }

  /// Builds a [TimelineEntry] from the form fields and pops the dialog with
  /// the result (plus an amendment reason, if this is an amendment and one
  /// was entered).
  void _submit() {
    final dt = DateTime(widget.day.year, widget.day.month, widget.day.day,
        selectedTime.hour, selectedTime.minute);

    // Combine wind direction + strength into one string
    String? wind;
    final strength = windStrengthCtrl.text.trim();
    if (strength.isNotEmpty) {
      wind = '$_windDir $strength kn';
    }

    final now = DateTime.now();
    final entry = TimelineEntry(
      time:       dt,
      course:     _parseDouble(courseCtrl.text),
      speed:      _parseDouble(speedCtrl.text),
      wind:       wind,
      sea:        seaCtrl.text.isEmpty     ? null : seaCtrl.text,
      weather:    weatherCtrl.text.isEmpty ? null : weatherCtrl.text,
      remarks:    remarksCtrl.text.isEmpty ? null : remarksCtrl.text,
      slot1State:  _slotState['slot1'],
      slot2State:  _slotState['slot2'],
      slot3State:  _slotState['slot3'],
      slot4State:  _slotState['slot4'],
      slot5State:  _slotState['slot5'],
      slot6State:  _slotState['slot6'],
      slot7State:  _slotState['slot7'],
      slot8State:  _slotState['slot8'],
      slot9State:  _slotState['slot9'],
      slot10State: _slotState['slot10'],
      slot11State: _slotState['slot11'],
      slot12State: _slotState['slot12'],
      // Legacy fields: preserve on edits of old entries so their data isn't
      // erased; new entries leave these null.
      grossState: widget.initialEntry?.grossState,
      fockState:  widget.initialEntry?.fockState,
      motorOn:    widget.initialEntry?.motorOn,
      keelDown:   widget.initialEntry?.keelDown,
      // Preserve original createdAt on edits; set it now for new entries.
      createdAt:  widget.initialEntry?.createdAt ?? now,
      updatedAt:  widget.initialEntry != null ? now : null,
    );
    final reason = amendmentReasonCtrl.text.trim();
    Navigator.pop(
      context,
      AddTimelineEntryResult(
        entry,
        amendmentReason: widget.isAmendment && reason.isNotEmpty ? reason : null,
      ),
    );
  }

  /// Parses [s] as a double, accepting a comma as the decimal separator
  /// (German locale input); returns null for empty/unparseable input.
  double? _parseDouble(String s) {
    if (s.trim().isEmpty) return null;
    return double.tryParse(s.replaceAll(',', '.'));
  }

  @override
  Widget build(BuildContext context) {
    final cs     = Theme.of(context).colorScheme;
    final l10n   = context.l10n;
    final isEdit = widget.initialEntry != null;
    final activeSlots = context.read<ThemeProvider>().vesselEquipment.activeSlots;

    return Dialog.fullscreen(
      child: Scaffold(
        backgroundColor: cs.surface,
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context, null),
          ),
          title: Text(
            widget.isAmendment ? l10n.amendmentDialogTitle
                : isEdit ? l10n.entryDialogTitleEdit
                : l10n.entryDialogTitleNew,
            style: Theme.of(context).textTheme.dialogTitle.copyWith(
              color: cs.primary,
            ),
          ),
        ),
        body: Stack(
          children: [
            // Background watermark compass
            Positioned(
              bottom: -50,
              right: -50,
              child: Icon(Icons.explore,
                  size: 300,
                  color: cs.primary.withValues(alpha: 0.03)),
            ),
            SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── 1. Chronometrie ─────────────────────────────────
                  _sectionHeader(Icons.schedule, l10n.entryDialogSectionTime, cs),
                  const SizedBox(height: 8),
                  _plainCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _labelSm(l10n.entryDialogTimeLabel, cs),
                        const SizedBox(height: 4),
                        GestureDetector(
                          onTap: () async {
                            final t = await showTimePicker(
                                context: context, initialTime: selectedTime);
                            if (t != null) setState(() => selectedTime = t);
                          },
                          child: Text(
                            selectedTime.format(context),
                            style: Theme.of(context).textTheme.fieldValueCompact.copyWith(
                              color: cs.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    cs: cs,
                  ),

                  // ── end 1. Chronometrie ──

                  const SizedBox(height: 16),
                  // ── 2. Navigation ────────────────────────────────────
                  _sectionHeader(Icons.explore, l10n.entryDialogSectionNav, cs),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _navCard(
                          label: l10n.entryDialogCourseLabel,
                          unit: 'deg',
                          controller: courseCtrl,
                          placeholder: '000',
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                                RegExp(r'[0-9]')),
                            _CourseFormatter(),
                          ],
                          cs: cs,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _navCard(
                          label: l10n.entryDialogSpeedLabel,
                          unit: 'kn',
                          controller: speedCtrl,
                          placeholder: '0.0',
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                                RegExp(r'[0-9.,]')),
                          ],
                          cs: cs,
                        ),
                      ),
                    ],
                  ),

                  // ── end 2. Navigation ──

                  const SizedBox(height: 16),
                  // ── 3. Umgebung ──────────────────────────────────────
                  _sectionHeader(Icons.air, l10n.entryDialogSectionEnv, cs),
                  const SizedBox(height: 8),
                  // Wind: direction + strength
                  _plainCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _labelSm(l10n.entryDialogWindLabel, cs),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            // Direction dropdown
                            Expanded(
                              child: Container(
                                height: 44,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12),
                                decoration: BoxDecoration(
                                  color: cs.surfaceContainerLow,
                                  border: Border.all(color: cs.outlineVariant),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<String>(
                                    value: _windDir,
                                    isExpanded: true,
                                    style: Theme.of(context).textTheme.fieldValueCompact.copyWith(
                                        color: cs.primary),
                                    items: _windDirs
                                        .map((d) => DropdownMenuItem(
                                              value: d,
                                              child: Text(d,
                                                  style: Theme.of(context).textTheme.fieldValueCompact.copyWith(
                                                      color: cs.onSurface)),
                                            ))
                                        .toList(),
                                    onChanged: (v) {
                                      if (v != null) {
                                        setState(() => _windDir = v);
                                      }
                                    },
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            // Strength input
                            Expanded(
                              child: Container(
                                height: 44,
                                decoration: BoxDecoration(
                                  color: cs.surfaceContainerLow,
                                  border: Border.all(color: cs.outlineVariant),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: TextField(
                                        controller: windStrengthCtrl,
                                        style: Theme.of(context).textTheme.fieldValueCompact.copyWith(
                                            color: cs.primary),
                                        decoration: InputDecoration(
                                          border: InputBorder.none,
                                          isDense: true,
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                                  horizontal: 12,
                                                  vertical: 12),
                                          hintText: '0',
                                          hintStyle: Theme.of(context).textTheme.fieldHintCompact.copyWith(
                                              color: cs.outline),
                                        ),
                                        keyboardType: TextInputType.number,
                                        textInputAction: TextInputAction.next,
                                        inputFormatters: [
                                          FilteringTextInputFormatter
                                              .digitsOnly,
                                        ],
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.only(right: 12),
                                      child: Text('kn',
                                          style: Theme.of(context).textTheme.labelSmall!.copyWith(
                                              letterSpacing: 0.5,
                                              color: cs.mutedLabel)),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    cs: cs,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _plainCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _labelSm(l10n.entryDialogSeaLabel, cs),
                              const SizedBox(height: 4),
                              _bareTextField(seaCtrl, l10n.entryDialogSeaHint, cs),
                            ],
                          ),
                          cs: cs,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _plainCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _labelSm(l10n.entryDialogWeatherLabel, cs),
                              const SizedBox(height: 4),
                              _bareTextField(weatherCtrl, l10n.entryDialogWeatherHint, cs),
                            ],
                          ),
                          cs: cs,
                        ),
                      ),
                    ],
                  ),

                  // ── end 3. Umgebung ──

                  if (activeSlots.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    // ── 4. Ausrüstung ────────────────────────────────────
                    _sectionHeader(Icons.sailing, l10n.entryDialogSectionSails, cs),
                    const SizedBox(height: 8),
                    // Sails, motor, and keel are visually distinct kinds of
                    // equipment, so each gets its own card instead of one
                    // long shared block.
                    if (_sailSlots(activeSlots).isNotEmpty) ...[
                      _equipmentCard(_sailSlots(activeSlots), activeSlots, cs),
                      const SizedBox(height: 10),
                    ],
                    if (_motorSlot(activeSlots) != null) ...[
                      _equipmentCard([_motorSlot(activeSlots)!], activeSlots, cs),
                      const SizedBox(height: 10),
                    ],
                    if (_keelSlot(activeSlots) != null)
                      _equipmentCard([_keelSlot(activeSlots)!], activeSlots, cs),
                    // ── end 4. Ausrüstung ──
                  ],

                  const SizedBox(height: 16),
                  // ── 5. Bemerkungen ───────────────────────────────────
                  _sectionHeader(Icons.edit_note, l10n.entryDialogSectionRemarks, cs),
                  const SizedBox(height: 8),
                  _plainCard(
                    child: TextField(
                      controller: remarksCtrl,
                      style: Theme.of(context).textTheme.fieldHintCompact.copyWith(
                        fontStyle: FontStyle.italic,
                        color: cs.primary,
                      ),
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                        hintText: l10n.entryDialogRemarksHint,
                        hintStyle: Theme.of(context).textTheme.fieldHintCompact.copyWith(
                          fontStyle: FontStyle.italic,
                          color: cs.onSurface.withValues(alpha: 0.3),
                        ),
                      ),
                      minLines: 2,
                      maxLines: null,
                      keyboardType: TextInputType.multiline,
                      textInputAction: TextInputAction.newline,
                    ),
                    cs: cs,
                  ),
                  // ── end 5. Bemerkungen ──

                  // ── Amendment reason (past entries only) ─────────────
                  if (widget.isAmendment) ...[
                    const SizedBox(height: 16),
                    _sectionHeader(Icons.history, l10n.amendmentReasonLabel, cs),
                    const SizedBox(height: 8),
                    _plainCard(
                      cs: cs,
                      child: TextField(
                        controller: amendmentReasonCtrl,
                        style: Theme.of(context).textTheme.fieldValueCompact.copyWith(
                          color: cs.onSurface,
                        ),
                        decoration: InputDecoration(
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                          hintText: l10n.amendmentReasonHint,
                          hintStyle: Theme.of(context).textTheme.fieldHintCompact.copyWith(
                            color: cs.onSurface.withValues(alpha: 0.3),
                          ),
                        ),
                        maxLines: 2,
                        keyboardType: TextInputType.multiline,
                        textInputAction: TextInputAction.newline,
                      ),
                    ),
                  ],
                  // ── end Amendment reason ──

                  const SizedBox(height: 20),
                  // ── Actions ──────────────────────────────────────────
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: FilledButton.icon(
                      onPressed: _submit,
                      style: FilledButton.styleFrom(
                        backgroundColor: cs.primary,
                        foregroundColor: cs.onPrimary,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        textStyle: Theme.of(context).textTheme.fieldValueCompact,
                      ),
                      icon: const Icon(Icons.anchor, size: 20),
                      label: Text(isEdit ? l10n.saveChanges : l10n.entryDialogSubmitNew),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context, null),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: cs.primary,
                        side: BorderSide(
                            color: cs.primary.withValues(alpha: 0.25)),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        textStyle: Theme.of(context).textTheme.fieldValueCompact,
                      ),
                      child: Text(l10n.cancel),
                    ),
                  ),
                  if (isEdit && widget.onDelete != null) ...[
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: TextButton.icon(
                        onPressed: () {
                          Navigator.pop(context, null);
                          widget.onDelete!.call();
                        },
                        icon: Icon(Icons.delete_outline,
                            size: 18, color: cs.error),
                        label: Text(l10n.dayDeleteLogEntry),
                        style: TextButton.styleFrom(
                          foregroundColor: cs.error,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          textStyle: Theme.of(context).textTheme.fieldValueCompact,
                        ),
                      ),
                    ),
                  ],
                  // ── end Actions ──
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Small-caps eyebrow label with a leading icon, above each form section.
  Widget _sectionHeader(IconData icon, String label, ColorScheme cs) {
    return Row(
      children: [
        Icon(icon, size: 20, color: cs.primary),
        const SizedBox(width: 8),
        Text(
          label.toUpperCase(),
          style: Theme.of(context).textTheme.labelSmall!.copyWith(
            color: cs.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  /// Bordered card shell wrapping one field (or group of fields).
  Widget _plainCard({required Widget child, required ColorScheme cs}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
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
      child: child,
    );
  }

  /// A [_plainCard] specialized for one numeric field (course/speed): label,
  /// bare number input, and a trailing unit suffix on one baseline.
  Widget _navCard({
    required String label,
    required String unit,
    required TextEditingController controller,
    required String placeholder,
    required TextInputType keyboardType,
    required List<TextInputFormatter> inputFormatters,
    required ColorScheme cs,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
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
          _labelSm(label, cs),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  style: Theme.of(context).textTheme.fieldValueCompact.copyWith(
                    color: cs.primary,
                  ),
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                    hintText: placeholder,
                    hintStyle: Theme.of(context).textTheme.fieldValueCompact.copyWith(
                      color: cs.outline,
                    ),
                  ),
                  keyboardType: keyboardType,
                  inputFormatters: inputFormatters,
                  textInputAction: TextInputAction.next,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                unit,
                style: Theme.of(context).textTheme.unitLabel.copyWith(
                  color: cs.mutedLabel,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Borderless text input styled to sit flush inside a [_plainCard].
  Widget _bareTextField(
      TextEditingController ctrl, String hint, ColorScheme cs) {
    return TextField(
      controller: ctrl,
      style: Theme.of(context).textTheme.fieldValueCompact.copyWith(color: cs.primary),
      decoration: InputDecoration(
        border: InputBorder.none,
        isDense: true,
        contentPadding: EdgeInsets.zero,
        hintText: hint,
        hintStyle: Theme.of(context).textTheme.fieldHintCompact.copyWith(color: cs.outline),
      ),
      textInputAction: TextInputAction.next,
    );
  }

  /// Localized display label for a `sail:` sentinel value.
  String _sailLabel(String sentinel) {
    final l10n = context.l10n;
    return switch (sentinel) {
      'sail:full'    => l10n.sailFull,
      'sail:reef1'   => l10n.sailReef1,
      'sail:reef2'   => l10n.sailReef2,
      'sail:lowered' => l10n.sailLowered,
      'sail:furled'  => l10n.sailFurled,
      _              => sentinel,
    };
  }

  /// Active slots that are neither motor (slot11) nor keel (slot12) — i.e.
  /// every configured sail, in slot order.
  List<EquipmentSlot> _sailSlots(List<EquipmentSlot> activeSlots) =>
      activeSlots.where((s) => s.key != 'slot11' && s.key != 'slot12').toList();

  EquipmentSlot? _motorSlot(List<EquipmentSlot> activeSlots) =>
      activeSlots.where((s) => s.key == 'slot11').firstOrNull;

  EquipmentSlot? _keelSlot(List<EquipmentSlot> activeSlots) =>
      activeSlots.where((s) => s.key == 'slot12').firstOrNull;

  /// A card holding one or more equipment [slots] (sails, or the single
  /// motor/keel slot), each rendered via [_equipmentSlotRow]. [activeSlots]
  /// is the full list — passed through so [_isAlwaysExpanded]'s position
  /// check stays correct regardless of which slots end up in this card.
  Widget _equipmentCard(
      List<EquipmentSlot> slots, List<EquipmentSlot> activeSlots, ColorScheme cs) {
    return _plainCard(
      cs: cs,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (int i = 0; i < slots.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            _equipmentSlotRow(slots[i], activeSlots, cs),
          ],
        ],
      ),
    );
  }

  /// One equipment slot's row: the full label+chips block if
  /// [_isAlwaysExpanded], otherwise the folded [_collapsibleSlotRow].
  Widget _equipmentSlotRow(
      EquipmentSlot slot, List<EquipmentSlot> activeSlots, ColorScheme cs) {
    if (!_isAlwaysExpanded(slot, activeSlots)) {
      return _collapsibleSlotRow(slot: slot, cs: cs);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _labelSm(slot.label, cs),
        const SizedBox(height: 6),
        _equipmentChips(
          slot: slot,
          selected: _slotState[slot.key],
          onSelect: (v) => setState(() => _slotState[slot.key] = v),
          cs: cs,
        ),
      ],
    );
  }

  /// Row of tappable state chips for one configurable equipment [slot] (one
  /// state can be selected at a time; tapping the already-selected one
  /// clears it).
  Widget _equipmentChips({
    required EquipmentSlot slot,
    required String? selected,
    required ValueChanged<String?> onSelect,
    required ColorScheme cs,
  }) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: slot.states
          .map((state) => _stateChip(
                state,
                selected == state,
                () => onSelect(selected == state ? null : state),
                cs,
              ))
          .toList(),
    );
  }

  /// Space-saving alternative to the always-expanded label+chips block above,
  /// used for any slot where [_isAlwaysExpanded] is false. Collapsed,
  /// it's a single tappable line showing the slot's name and current
  /// selection (or a muted dash); tapping it reveals the full [_equipmentChips]
  /// row, which collapses itself again as soon as a state is picked.
  Widget _collapsibleSlotRow({required EquipmentSlot slot, required ColorScheme cs}) {
    final expanded = _expandedSlotKeys.contains(slot.key);
    final selected = _slotState[slot.key];

    if (!expanded) {
      return GestureDetector(
        onTap: () => setState(() => _expandedSlotKeys.add(slot.key)),
        child: Row(
          children: [
            Expanded(
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(
                    text: '${slot.label}: ',
                    style: Theme.of(context).textTheme.microLabel.copyWith(color: cs.mutedLabel),
                  ),
                  TextSpan(
                    text: selected ?? '—',
                    style: Theme.of(context).textTheme.chipLabel.copyWith(
                      color: selected == null ? cs.outline : cs.onSurface,
                    ),
                  ),
                ]),
              ),
            ),
            Icon(Icons.expand_more, size: 18, color: cs.outlineVariant),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () => setState(() => _expandedSlotKeys.remove(slot.key)),
          child: Row(
            children: [
              Expanded(child: _labelSm(slot.label, cs)),
              Icon(Icons.expand_less, size: 18, color: cs.outlineVariant),
            ],
          ),
        ),
        const SizedBox(height: 6),
        _equipmentChips(
          slot: slot,
          selected: selected,
          onSelect: (v) => setState(() {
            _slotState[slot.key] = v;
            _expandedSlotKeys.remove(slot.key);
          }),
          cs: cs,
        ),
      ],
    );
  }

  /// A single toggleable pill chip, used for sail state, motor on/off, and
  /// keel up/down.
  Widget _stateChip(
      String label, bool isSelected, VoidCallback onTap, ColorScheme cs) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? cs.primary : cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(99),
          border: Border.all(
            color: isSelected ? cs.primary : cs.outlineVariant,
          ),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.chipLabel.copyWith(
            color: isSelected ? cs.onPrimary : cs.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  /// Small muted field label above a form field.
  Widget _labelSm(String text, ColorScheme cs) {
    return Text(
      text,
      style: Theme.of(context).textTheme.microLabel.copyWith(
        color: cs.mutedLabel,
      ),
    );
  }
}
