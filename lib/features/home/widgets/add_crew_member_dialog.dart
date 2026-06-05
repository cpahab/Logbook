import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../domain/crew_member.dart';

class AddCrewMemberDialog extends StatefulWidget {
  final CrewMember? initialMember;

  const AddCrewMemberDialog({super.key, this.initialMember});

  @override
  State<AddCrewMemberDialog> createState() => _AddCrewMemberDialogState();
}

class _AddCrewMemberDialogState extends State<AddCrewMemberDialog> {
  final _nameCtrl       = TextEditingController();
  final _bloodTypeCtrl  = TextEditingController();
  final _allergiesCtrl  = TextEditingController();
  final _conditionsCtrl = TextEditingController();
  final _remarksCtrl    = TextEditingController();

  @override
  void initState() {
    super.initState();
    final m = widget.initialMember;
    if (m != null) {
      _nameCtrl.text       = m.name;
      _bloodTypeCtrl.text  = m.bloodType ?? '';
      _allergiesCtrl.text  = m.allergies ?? '';
      _conditionsCtrl.text = m.conditions ?? '';
      _remarksCtrl.text    = m.remarks ?? '';
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _bloodTypeCtrl.dispose();
    _allergiesCtrl.dispose();
    _conditionsCtrl.dispose();
    _remarksCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;
    Navigator.pop(
      context,
      CrewMember(
        name:       name,
        bloodType:  _bloodTypeCtrl.text.trim().isEmpty ? null : _bloodTypeCtrl.text.trim(),
        allergies:  _allergiesCtrl.text.trim().isEmpty ? null : _allergiesCtrl.text.trim(),
        conditions: _conditionsCtrl.text.trim().isEmpty ? null : _conditionsCtrl.text.trim(),
        remarks:    _remarksCtrl.text.trim().isEmpty ? null : _remarksCtrl.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isEdit = widget.initialMember != null;

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
          automaticallyImplyLeading: false,
          title: Text(
            isEdit ? 'Besatzung bearbeiten' : 'Besatzung hinzufügen',
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
                  // ── Identity ─────────────────────────────────────────
                  _sectionHeader(Icons.person, 'Identität', cs),
                  const SizedBox(height: 12),
                  _card(
                    cs: cs,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _label('VOLLSTÄNDIGER NAME', cs),
                        const SizedBox(height: 6),
                        _field(
                          controller: _nameCtrl,
                          hint: 'z.B. Thomas Müller',
                          cs: cs,
                          autofocus: true,
                          capitalization: TextCapitalization.words,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),
                  // ── Medical Info ──────────────────────────────────────
                  _sectionHeader(Icons.medical_services, 'Medizinische Info', cs),
                  const SizedBox(height: 12),
                  _card(
                    cs: cs,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _label('BLUTGRUPPE', cs),
                        const SizedBox(height: 6),
                        _field(
                          controller: _bloodTypeCtrl,
                          hint: 'z.B. 0+, A-',
                          cs: cs,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _card(
                    cs: cs,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _label('ALLERGIEN', cs),
                        const SizedBox(height: 6),
                        _field(
                          controller: _allergiesCtrl,
                          hint: 'Bekannte Allergien auflisten…',
                          cs: cs,
                          maxLines: 2,
                          italic: true,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _card(
                    cs: cs,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _label('ERKRANKUNGEN / MEDIKAMENTE', cs),
                        const SizedBox(height: 6),
                        _field(
                          controller: _conditionsCtrl,
                          hint: 'z.B. Benötigt Inhalator (Asthma)…',
                          cs: cs,
                          maxLines: 2,
                          italic: true,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),
                  // ── Remarks ───────────────────────────────────────────
                  _sectionHeader(Icons.description, 'Bemerkungen', cs),
                  const SizedBox(height: 12),
                  _card(
                    cs: cs,
                    child: _field(
                      controller: _remarksCtrl,
                      hint: 'Allgemeine Notizen zu dieser Person…',
                      cs: cs,
                      maxLines: 3,
                      italic: true,
                    ),
                  ),

                  const SizedBox(height: 32),
                  // ── Actions ───────────────────────────────────────────
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
                      label: Text(isEdit
                          ? 'Änderungen speichern'
                          : 'Zur Besatzung hinzufügen'),
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

  Widget _card({required Widget child, required ColorScheme cs}) {
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

  Widget _label(String text, ColorScheme cs) {
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

  Widget _field({
    required TextEditingController controller,
    required String hint,
    required ColorScheme cs,
    int maxLines = 1,
    bool italic = false,
    bool autofocus = false,
    TextCapitalization capitalization = TextCapitalization.sentences,
  }) {
    return TextField(
      controller: controller,
      autofocus: autofocus,
      maxLines: maxLines,
      keyboardType:
          maxLines > 1 ? TextInputType.multiline : TextInputType.text,
      textInputAction:
          maxLines > 1 ? TextInputAction.newline : TextInputAction.next,
      textCapitalization: capitalization,
      style: GoogleFonts.newsreader(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        fontStyle: italic ? FontStyle.italic : FontStyle.normal,
        color: cs.primary,
      ),
      decoration: InputDecoration(
        border: InputBorder.none,
        isDense: true,
        contentPadding: EdgeInsets.zero,
        hintText: hint,
        hintStyle: GoogleFonts.newsreader(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          fontStyle: italic ? FontStyle.italic : FontStyle.normal,
          color: cs.primary.withValues(alpha: 0.20),
        ),
      ),
    );
  }
}
