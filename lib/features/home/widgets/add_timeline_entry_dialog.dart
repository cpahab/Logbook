import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  final courseCtrl      = TextEditingController();
  final speedCtrl       = TextEditingController();
  final windStrengthCtrl = TextEditingController();
  final seaCtrl         = TextEditingController();
  final weatherCtrl     = TextEditingController();
  final remarksCtrl     = TextEditingController();

  String  _windDir  = 'N';
  String? _grossState;
  String? _fockState;
  bool?   _motorOn;

  static const _windDirs    = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
  static const _grossOptions = ['Voll Gesetzt', '1. Reff', '2. Reff', 'Niedergeholt'];
  static const _fockOptions  = ['Voll Gesetzt', '1. Reff', '2. Reff', 'Eingerollt'];

  @override
  void initState() {
    super.initState();
    final src = widget.initialEntry ?? widget.prefillEntry;

    if (widget.initialEntry != null) {
      final e = widget.initialEntry!;
      selectedTime = TimeOfDay.fromDateTime(e.time);
      courseCtrl.text  = e.course?.toString() ?? '';
      speedCtrl.text   = e.speed?.toString() ?? '';
      _parseWind(e.wind);
      seaCtrl.text     = e.sea ?? '';
      weatherCtrl.text = e.weather ?? '';
      remarksCtrl.text = e.remarks ?? '';
    } else {
      selectedTime = TimeOfDay.now();
    }

    if (src != null) {
      _grossState = src.grossState;
      _fockState  = src.fockState;
      _motorOn    = src.motorOn;
      if (widget.initialEntry == null) _parseWind(src.wind);
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

    Navigator.pop(
      context,
      TimelineEntry(
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
    final isEdit = widget.initialEntry != null;

    return Dialog.fullscreen(
      child: Scaffold(
        backgroundColor: cs.surface,
        appBar: AppBar(
          backgroundColor: cs.surface,
          foregroundColor: cs.primary,
          elevation: 0,
          scrolledUnderElevation: 1,
          shadowColor: Colors.black12,
          centerTitle: true,
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context, null),
          ),
          title: Text(
            isEdit ? 'Eintrag bearbeiten' : 'Neuer Eintrag',
            style: GoogleFonts.newsreader(
              fontSize: 22,
              fontStyle: FontStyle.italic,
              fontWeight: FontWeight.w500,
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
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── 1. Chronometrie ─────────────────────────────────
                  _sectionHeader(Icons.schedule, 'Chronometrie', cs),
                  const SizedBox(height: 12),
                  _plainCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _labelSm('UHRZEIT', cs),
                        const SizedBox(height: 6),
                        GestureDetector(
                          onTap: () async {
                            final t = await showTimePicker(
                                context: context, initialTime: selectedTime);
                            if (t != null) setState(() => selectedTime = t);
                          },
                          child: Text(
                            selectedTime.format(context),
                            style: GoogleFonts.newsreader(
                              fontSize: 32,
                              fontWeight: FontWeight.w500,
                              color: cs.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    cs: cs,
                  ),

                  const SizedBox(height: 24),
                  // ── 2. Navigation ────────────────────────────────────
                  _sectionHeader(Icons.explore, 'Navigation', cs),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _accentCard(
                          label: 'KURS (°)',
                          unit: '°',
                          controller: courseCtrl,
                          placeholder: '000',
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                                RegExp(r'[0-9]')),
                          ],
                          cs: cs,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _accentCard(
                          label: 'FAHRT (kn)',
                          unit: 'kts',
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

                  const SizedBox(height: 24),
                  // ── 3. Umgebung ──────────────────────────────────────
                  _sectionHeader(Icons.air, 'Umgebung', cs),
                  const SizedBox(height: 12),
                  // Wind: direction + strength
                  _plainCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _labelSm('WIND RICHTUNG & STÄRKE', cs),
                        const SizedBox(height: 10),
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
                                    style: GoogleFonts.inter(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                        color: cs.primary),
                                    items: _windDirs
                                        .map((d) => DropdownMenuItem(
                                              value: d,
                                              child: Text(d,
                                                  style: GoogleFonts.inter(
                                                      fontSize: 15,
                                                      fontWeight:
                                                          FontWeight.w600,
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
                                        style: GoogleFonts.inter(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w600,
                                            color: cs.primary),
                                        decoration: InputDecoration(
                                          border: InputBorder.none,
                                          isDense: true,
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                                  horizontal: 12,
                                                  vertical: 12),
                                          hintText: '0',
                                          hintStyle: GoogleFonts.inter(
                                              fontSize: 15,
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
                                      child: Text('KN',
                                          style: GoogleFonts.inter(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                              letterSpacing: 0.5,
                                              color: cs.outline)),
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
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _plainCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _labelSm('SEE', cs),
                              const SizedBox(height: 6),
                              _bareTextField(seaCtrl, 'z.B. Leicht', cs),
                            ],
                          ),
                          cs: cs,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _plainCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _labelSm('WETTER', cs),
                              const SizedBox(height: 6),
                              _bareTextField(weatherCtrl, 'z.B. Sonnig', cs),
                            ],
                          ),
                          cs: cs,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),
                  // ── 4. Segel & Motor ─────────────────────────────────
                  _sectionHeader(Icons.sailing, 'Segel & Motor', cs),
                  const SizedBox(height: 12),
                  _plainCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _sailRow('Gross', _grossState, _grossOptions,
                            (v) => setState(() => _grossState = v), cs),
                        const SizedBox(height: 12),
                        _sailRow('Fock', _fockState, _fockOptions,
                            (v) => setState(() => _fockState = v), cs),
                        const SizedBox(height: 12),
                        _labelSm('MOTOR', cs),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            _toggleChip('An', _motorOn == true,
                                () => setState(() => _motorOn =
                                    _motorOn == true ? null : true),
                                cs),
                            const SizedBox(width: 8),
                            _toggleChip('Aus', _motorOn == false,
                                () => setState(() => _motorOn =
                                    _motorOn == false ? null : false),
                                cs),
                          ],
                        ),
                      ],
                    ),
                    cs: cs,
                  ),

                  const SizedBox(height: 24),
                  // ── 5. Bemerkungen ───────────────────────────────────
                  _sectionHeader(Icons.edit_note, 'Bemerkungen', cs),
                  const SizedBox(height: 12),
                  _plainCard(
                    child: TextField(
                      controller: remarksCtrl,
                      style: GoogleFonts.newsreader(
                        fontSize: 18,
                        fontStyle: FontStyle.italic,
                        color: cs.primary,
                      ),
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                        hintText: 'z.B. Beobachtung, Erlebnis…',
                        hintStyle: GoogleFonts.newsreader(
                          fontSize: 18,
                          fontStyle: FontStyle.italic,
                          color: cs.onSurface.withValues(alpha: 0.3),
                        ),
                      ),
                      minLines: 3,
                      maxLines: null,
                      keyboardType: TextInputType.multiline,
                      textInputAction: TextInputAction.newline,
                    ),
                    cs: cs,
                  ),

                  const SizedBox(height: 32),
                  // ── Actions ──────────────────────────────────────────
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: FilledButton.icon(
                      onPressed: _submit,
                      style: FilledButton.styleFrom(
                        backgroundColor: cs.primary,
                        foregroundColor: cs.onPrimary,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        textStyle: GoogleFonts.inter(
                            fontSize: 15, fontWeight: FontWeight.w600),
                      ),
                      icon: const Icon(Icons.anchor, size: 20),
                      label: Text(isEdit ? 'Änderungen speichern' : 'In Log eintragen'),
                    ),
                  ),
                  const SizedBox(height: 12),
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
                        textStyle: GoogleFonts.inter(
                            fontSize: 15, fontWeight: FontWeight.w600),
                      ),
                      child: const Text('Abbrechen'),
                    ),
                  ),
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
          style: GoogleFonts.inter(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.5,
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
      padding: const EdgeInsets.all(16),
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

  // ── Accent card (left stripe + big number input) ──────────────────
  Widget _accentCard({
    required String label,
    required String unit,
    required TextEditingController controller,
    required String placeholder,
    required TextInputType keyboardType,
    required List<TextInputFormatter> inputFormatters,
    required ColorScheme cs,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
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
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Left accent stripe — secondary (#725c10)
            Container(
              width: 3,
              margin: const EdgeInsets.only(right: 10),
              decoration: BoxDecoration(
                color: cs.secondary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _labelSm(label, cs),
                  const SizedBox(height: 6),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: controller,
                          style: GoogleFonts.newsreader(
                            fontSize: 28,
                            fontWeight: FontWeight.w700,
                            color: cs.primary,
                          ),
                          decoration: InputDecoration(
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                            hintText: placeholder,
                            hintStyle: GoogleFonts.newsreader(
                              fontSize: 28,
                              fontWeight: FontWeight.w700,
                              color: cs.primary.withValues(alpha: 0.15),
                              ),
                          ),
                          keyboardType: keyboardType,
                          inputFormatters: inputFormatters,
                          textInputAction: TextInputAction.next,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          unit,
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: cs.outline,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Bare text field (no border, inside a card) ────────────────────
  Widget _bareTextField(
      TextEditingController ctrl, String hint, ColorScheme cs) {
    return TextField(
      controller: ctrl,
      style: GoogleFonts.inter(
          fontSize: 15, fontWeight: FontWeight.w600, color: cs.primary),
      decoration: InputDecoration(
        border: InputBorder.none,
        isDense: true,
        contentPadding: EdgeInsets.zero,
        hintText: hint,
        hintStyle:
            GoogleFonts.inter(fontSize: 15, color: cs.outline),
      ),
      textInputAction: TextInputAction.next,
    );
  }

  // ── Sail row ──────────────────────────────────────────────────────
  Widget _sailRow(String label, String? current, List<String> options,
      ValueChanged<String?> onChanged, ColorScheme cs) {
    return Row(
      children: [
        _labelSm(label.toUpperCase(), cs),
        const SizedBox(width: 12),
        Expanded(
          child: Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: cs.surfaceContainerLow,
              border: Border.all(color: cs.outlineVariant),
              borderRadius: BorderRadius.circular(8),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: current,
                isExpanded: true,
                hint: Text('—',
                    style: GoogleFonts.inter(
                        fontSize: 14, color: cs.onSurfaceVariant)),
                style: GoogleFonts.inter(
                    fontSize: 14,
                    color: cs.onSurface,
                    fontWeight: FontWeight.w500),
                items: options
                    .map((opt) => DropdownMenuItem(
                          value: opt,
                          child: Text(opt,
                              style: GoogleFonts.inter(
                                  fontSize: 14, color: cs.onSurface)),
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
            child:
                Icon(Icons.close, size: 18, color: cs.onSurfaceVariant),
          ),
        ] else
          const SizedBox(width: 22),
      ],
    );
  }

  // ── Toggle chip ───────────────────────────────────────────────────
  Widget _toggleChip(
      String label, bool selected, VoidCallback onTap, ColorScheme cs) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? cs.primary : cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color:
                selected ? cs.onPrimary : cs.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  // ── Label sm ──────────────────────────────────────────────────────
  Widget _labelSm(String text, ColorScheme cs) {
    return Text(
      text,
      style: GoogleFonts.inter(
        fontSize: 9,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.0,
        color: cs.outline,
      ),
    );
  }
}
