import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../domain/timeline_entry.dart';

class AddTimelineEntryDialog extends StatefulWidget {
  final DateTime day;
  final TimelineEntry? initialEntry;
  final TimelineEntry? prefillEntry;

  const AddTimelineEntryDialog({
    super.key,
    required this.day,
    this.initialEntry,
    this.prefillEntry,
  });

  @override
  State<AddTimelineEntryDialog> createState() => _AddTimelineEntryDialogState();
}

class _AddTimelineEntryDialogState extends State<AddTimelineEntryDialog> {
  late TimeOfDay selectedTime;

  final courseCtrl  = TextEditingController();
  final speedCtrl   = TextEditingController();
  final windCtrl    = TextEditingController();
  final seaCtrl     = TextEditingController();
  final weatherCtrl = TextEditingController();
  final remarksCtrl = TextEditingController();

  String? _grossState;
  String? _fockState;
  bool?   _motorOn;

  static const _grossOptions = ['Voll Gesetzt', '1. Reff', '2. Reff', 'Niedergeholt'];
  static const _fockOptions  = ['Voll Gesetzt', '1. Reff', '2. Reff', 'Eingerollt'];

  @override
  void initState() {
    super.initState();
    final src = widget.initialEntry ?? widget.prefillEntry;
    if (widget.initialEntry != null) {
      selectedTime     = TimeOfDay.fromDateTime(widget.initialEntry!.time);
      courseCtrl.text  = widget.initialEntry!.course?.toString() ?? '';
      speedCtrl.text   = widget.initialEntry!.speed?.toString() ?? '';
      windCtrl.text    = widget.initialEntry!.wind ?? '';
      seaCtrl.text     = widget.initialEntry!.sea ?? '';
      weatherCtrl.text = widget.initialEntry!.weather ?? '';
      remarksCtrl.text = widget.initialEntry!.remarks ?? '';
    } else {
      selectedTime = TimeOfDay.now();
    }
    if (src != null) {
      _grossState = src.grossState;
      _fockState  = src.fockState;
      _motorOn    = src.motorOn;
    }
  }

  @override
  void dispose() {
    courseCtrl.dispose();
    speedCtrl.dispose();
    windCtrl.dispose();
    seaCtrl.dispose();
    weatherCtrl.dispose();
    remarksCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs     = Theme.of(context).colorScheme;
    final isEdit = widget.initialEntry != null;

    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      title: Text(
        isEdit ? 'Eintrag bearbeiten' : 'Neuer Eintrag',
        style: GoogleFonts.newsreader(fontSize: 22, fontWeight: FontWeight.w500),
      ),
      contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Zeit ───────────────────────────────────────────────
            Row(
              children: [
                Icon(Icons.access_time, size: 18, color: cs.onSurfaceVariant),
                const SizedBox(width: 8),
                TextButton(
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: () async {
                    final t = await showTimePicker(
                        context: context, initialTime: selectedTime);
                    if (t != null) setState(() => selectedTime = t);
                  },
                  child: Text(
                    selectedTime.format(context),
                    style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: cs.primary),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // ── Navigation ─────────────────────────────────────────
            _sectionLabel('Navigation', cs),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(child: _textField(courseCtrl, 'Kurs (°)',
                    keyboardType: TextInputType.number)),
                const SizedBox(width: 12),
                Expanded(child: _textField(speedCtrl, 'Fahrt (kn)',
                    keyboardType: TextInputType.number)),
              ],
            ),
            const SizedBox(height: 8),
            _textField(windCtrl, 'Wind'),
            const SizedBox(height: 8),
            _textField(seaCtrl, 'See'),
            const SizedBox(height: 8),
            _textField(weatherCtrl, 'Wetter'),
            const SizedBox(height: 12),

            // ── Segel ──────────────────────────────────────────────
            _sectionLabel('Segel', cs),
            const SizedBox(height: 6),
            _sailDropdown('Gross', _grossState, _grossOptions,
                (v) => setState(() => _grossState = v), cs),
            const SizedBox(height: 8),
            _sailDropdown('Fock', _fockState, _fockOptions,
                (v) => setState(() => _fockState = v), cs),
            const SizedBox(height: 12),

            // ── Motor ──────────────────────────────────────────────
            _sectionLabel('Motor', cs),
            const SizedBox(height: 6),
            _motorRow(_motorOn, (v) => setState(() => _motorOn = v), cs),
            const SizedBox(height: 12),

            // ── Bemerkungen ────────────────────────────────────────
            _sectionLabel('Bemerkungen', cs),
            const SizedBox(height: 6),
            _textField(remarksCtrl, '', maxLines: 2),
            const SizedBox(height: 8),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(isEdit ? 'Speichern' : 'Hinzufügen'),
        ),
      ],
    );
  }

  void _submit() {
    final dt = DateTime(widget.day.year, widget.day.month, widget.day.day,
        selectedTime.hour, selectedTime.minute);
    Navigator.pop(
      context,
      TimelineEntry(
        time:       dt,
        course:     _parseDouble(courseCtrl.text),
        speed:      _parseDouble(speedCtrl.text),
        wind:       windCtrl.text.isEmpty    ? null : windCtrl.text,
        sea:        seaCtrl.text.isEmpty     ? null : seaCtrl.text,
        weather:    weatherCtrl.text.isEmpty ? null : weatherCtrl.text,
        remarks:    remarksCtrl.text.isEmpty ? null : remarksCtrl.text,
        grossState: _grossState,
        fockState:  _fockState,
        motorOn:    _motorOn,
      ),
    );
  }

  // ── Widgets ──────────────────────────────────────────────────────

  Widget _sectionLabel(String label, ColorScheme cs) => Text(
        label,
        style: GoogleFonts.inter(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
            color: cs.onSurfaceVariant),
      );

  Widget _textField(TextEditingController ctrl, String label,
      {TextInputType? keyboardType, int maxLines = 1}) {
    return TextField(
      controller: ctrl,
      decoration: InputDecoration(
        labelText: label.isEmpty ? null : label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
      keyboardType: keyboardType,
      maxLines: maxLines,
      textInputAction:
          maxLines > 1 ? TextInputAction.newline : TextInputAction.next,
    );
  }

  /// Compact dropdown for sail state. A clear button appears when a value
  /// is selected so the field can be reset to empty.
  Widget _sailDropdown(String label, String? current, List<String> options,
      ValueChanged<String?> onChanged, ColorScheme cs) {
    return Row(
      children: [
        SizedBox(
          width: 44,
          child: Text(label,
              style:
                  GoogleFonts.inter(fontSize: 13, color: cs.onSurface)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              border: Border.all(color: cs.outline),
              borderRadius: BorderRadius.circular(10),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: current,
                isExpanded: true,
                hint: const SizedBox.shrink(),
                style: GoogleFonts.inter(fontSize: 13, color: Colors.black),
                items: options
                    .map((opt) => DropdownMenuItem(
                          value: opt,
                          child: Text(opt,
                              style: GoogleFonts.inter(fontSize: 13)),
                        ))
                    .toList(),
                onChanged: onChanged,
              ),
            ),
          ),
        ),
        if (current != null) ...[
          const SizedBox(width: 4),
          GestureDetector(
            onTap: () => onChanged(null),
            child: Icon(Icons.close, size: 18, color: cs.onSurfaceVariant),
          ),
        ] else
          const SizedBox(width: 22), // keep layout stable
      ],
    );
  }

  /// Two chips: An and Aus. Tapping the active one deselects it.
  Widget _motorRow(bool? value, ValueChanged<bool?> onChanged, ColorScheme cs) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _chip('An',  value == true,
            () => onChanged(value == true ? null : true), cs),
        const SizedBox(width: 6),
        _chip('Aus', value == false,
            () => onChanged(value == false ? null : false), cs),
      ],
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap,
      ColorScheme cs) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? cs.primary : cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: selected ? cs.onPrimary : cs.onSurfaceVariant),
        ),
      ),
    );
  }

  double? _parseDouble(String s) {
    if (s.trim().isEmpty) return null;
    return double.tryParse(s.replaceAll(',', '.'));
  }
}
