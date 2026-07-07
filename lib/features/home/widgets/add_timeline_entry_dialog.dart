import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../app/theme/theme_extensions.dart';
import '../domain/timeline_entry.dart';
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
  String? _grossState;
  String? _fockState;
  bool?   _motorOn;
  bool?   _keelDown;

  static const _windDirs = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];

  static const _grossSentinels = ['sail:full', 'sail:reef1', 'sail:reef2', 'sail:lowered'];
  static const _fockSentinels  = ['sail:full', 'sail:reef1', 'sail:reef2', 'sail:furled'];


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
      _grossState = normalizeSailState(e.grossState);
      _fockState  = normalizeSailState(e.fockState);
      _motorOn    = e.motorOn;
      _keelDown   = e.keelDown;
    } else {
      selectedTime = TimeOfDay.now();
    }
  }

  // Parse "SW 12 kn" → dir="SW", strength="12"
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
      grossState: _grossState,
      fockState:  _fockState,
      motorOn:    _motorOn,
      keelDown:   _keelDown,
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

  double? _parseDouble(String s) {
    if (s.trim().isEmpty) return null;
    return double.tryParse(s.replaceAll(',', '.'));
  }

  @override
  Widget build(BuildContext context) {
    final cs     = Theme.of(context).colorScheme;
    final l10n   = context.l10n;
    final isEdit = widget.initialEntry != null;

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

                  const SizedBox(height: 16),
                  // ── 4. Segel & Motor ─────────────────────────────────
                  _sectionHeader(Icons.sailing, l10n.entryDialogSectionSails, cs),
                  const SizedBox(height: 8),
                  _plainCard(
                    cs: cs,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _labelSm(l10n.entryDialogMainSailLabel, cs),
                        const SizedBox(height: 6),
                        _sailChips(
                          sentinels: _grossSentinels,
                          labelFor: _sailLabel,
                          selected: _grossState,
                          onSelect: (v) => setState(() => _grossState = v),
                          cs: cs,
                        ),
                        const SizedBox(height: 10),
                        _labelSm(l10n.entryDialogJibSailLabel, cs),
                        const SizedBox(height: 6),
                        _sailChips(
                          sentinels: _fockSentinels,
                          labelFor: _sailLabel,
                          selected: _fockState,
                          onSelect: (v) => setState(() => _fockState = v),
                          cs: cs,
                        ),
                        const SizedBox(height: 10),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _labelSm(l10n.entryDialogMotorLabel, cs),
                                  const SizedBox(height: 6),
                                  Row(children: [
                                    _stateChip(l10n.on,  _motorOn == true,
                                        () => setState(() => _motorOn = _motorOn == true  ? null : true),  cs),
                                    const SizedBox(width: 8),
                                    _stateChip(l10n.off, _motorOn == false,
                                        () => setState(() => _motorOn = _motorOn == false ? null : false), cs),
                                  ]),
                                ],
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _labelSm(l10n.entryDialogKeelLabel, cs),
                                  const SizedBox(height: 6),
                                  Row(children: [
                                    _stateChip(l10n.vesselKeelDown, _keelDown == true,
                                        () => setState(() => _keelDown = _keelDown == true  ? null : true),  cs),
                                    const SizedBox(width: 8),
                                    _stateChip(l10n.vesselKeelUp, _keelDown == false,
                                        () => setState(() => _keelDown = _keelDown == false ? null : false), cs),
                                  ]),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

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
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Section header ────────────────────────────────────────────────
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

  // ── Plain card ────────────────────────────────────────────────────
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

  // ── Nav card (plain card with headline-sm number input) ──────────
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

  // ── Bare text field (no border, inside a card) ────────────────────
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

  // ── Sail state chip row ───────────────────────────────────────────
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

  Widget _sailChips({
    required List<String> sentinels,
    required String Function(String) labelFor,
    required String? selected,
    required ValueChanged<String?> onSelect,
    required ColorScheme cs,
  }) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: sentinels
          .map((s) => _stateChip(
                labelFor(s),
                selected == s,
                () => onSelect(selected == s ? null : s),
                cs,
              ))
          .toList(),
    );
  }

  // ── Single selectable chip ────────────────────────────────────────
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

  // ── Label sm ──────────────────────────────────────────────────────
  Widget _labelSm(String text, ColorScheme cs) {
    return Text(
      text,
      style: Theme.of(context).textTheme.microLabel.copyWith(
        color: cs.mutedLabel,
      ),
    );
  }
}
