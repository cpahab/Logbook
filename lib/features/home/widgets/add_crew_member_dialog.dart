import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/theme_extensions.dart';
import '../domain/crew_member.dart';
import '../../../l10n/l10n_extension.dart';

class AddCrewMemberDialog extends StatefulWidget {
  final CrewMember? initialMember;
  /// Called when "Remove from crew" is tapped. Must perform (or cancel) the
  /// deletion itself — e.g. showing its own confirmation dialog — and return
  /// whether the member was actually deleted. The dialog only closes itself
  /// if this resolves to `true`, so an in-progress or cancelled confirmation
  /// doesn't get raced by this dialog popping out from under it.
  final Future<bool> Function()? onDelete;

  const AddCrewMemberDialog({super.key, this.initialMember, this.onDelete});

  @override
  State<AddCrewMemberDialog> createState() => _AddCrewMemberDialogState();
}

class _AddCrewMemberDialogState extends State<AddCrewMemberDialog> {
  final _nameCtrl         = TextEditingController();
  final _bloodTypeCtrl    = TextEditingController();
  final _allergiesCtrl    = TextEditingController();
  final _conditionsCtrl   = TextEditingController();
  final _remarksCtrl      = TextEditingController();
  final _personalEpirbCtrl = TextEditingController();

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
      _personalEpirbCtrl.text = m.personalEpirb ?? '';
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _bloodTypeCtrl.dispose();
    _allergiesCtrl.dispose();
    _conditionsCtrl.dispose();
    _remarksCtrl.dispose();
    _personalEpirbCtrl.dispose();
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
        personalEpirb: _personalEpirbCtrl.text.trim().isEmpty ? null : _personalEpirbCtrl.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final isEdit = widget.initialMember != null;

    return Dialog.fullscreen(
      child: Scaffold(
        backgroundColor: cs.surface,
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: Text(
            isEdit ? l10n.crewDialogTitleEdit : l10n.crewDialogTitleAdd,
            style: GoogleFonts.dmSans(
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
                  _sectionHeader(Icons.person, l10n.crewSectionIdentity, cs),
                  const SizedBox(height: 12),
                  _card(
                    cs: cs,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _label(l10n.crewFieldFullName, cs),
                        const SizedBox(height: 6),
                        _field(
                          controller: _nameCtrl,
                          hint: l10n.crewFieldFullNameHint,
                          cs: cs,
                          autofocus: true,
                          capitalization: TextCapitalization.words,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),
                  // ── Medical Info ──────────────────────────────────────
                  _sectionHeader(Icons.medical_services, l10n.crewSectionMedical, cs),
                  const SizedBox(height: 12),
                  _card(
                    cs: cs,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _label(l10n.crewFieldBloodGroup, cs),
                        const SizedBox(height: 6),
                        _field(
                          controller: _bloodTypeCtrl,
                          hint: l10n.crewFieldBloodGroupHint,
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
                        _label(l10n.crewFieldAllergies, cs),
                        const SizedBox(height: 6),
                        _field(
                          controller: _allergiesCtrl,
                          hint: l10n.crewFieldAllergiesHint,
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
                        _label(l10n.crewFieldConditions, cs),
                        const SizedBox(height: 6),
                        _field(
                          controller: _conditionsCtrl,
                          hint: l10n.crewFieldConditionsHint,
                          cs: cs,
                          maxLines: 2,
                          italic: true,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),
                  // ── Safety Equipment ──────────────────────────────────
                  _sectionHeader(Icons.sensors, l10n.crewSectionSafety, cs),
                  const SizedBox(height: 12),
                  _card(
                    cs: cs,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _label(l10n.crewFieldPersonalEpirb, cs),
                        const SizedBox(height: 6),
                        _field(
                          controller: _personalEpirbCtrl,
                          hint: l10n.crewFieldPersonalEpirbHint,
                          cs: cs,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),
                  // ── Remarks ───────────────────────────────────────────
                  _sectionHeader(Icons.description, l10n.crewSectionRemarks, cs),
                  const SizedBox(height: 12),
                  _card(
                    cs: cs,
                    child: _field(
                      controller: _remarksCtrl,
                      hint: l10n.crewFieldRemarksHint,
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
                        textStyle: GoogleFonts.dmSans(
                            fontSize: 15, fontWeight: FontWeight.w600),
                      ),
                      icon: const Icon(Icons.anchor, size: 20),
                      label: Text(isEdit
                          ? l10n.saveChanges
                          : l10n.crewButtonAddToCrew),
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
                        textStyle: GoogleFonts.dmSans(
                            fontSize: 15, fontWeight: FontWeight.w600),
                      ),
                      child: Text(l10n.cancel),
                    ),
                  ),
                  if (isEdit && widget.onDelete != null) ...[
                    const SizedBox(height: 32),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final deleted = await widget.onDelete!();
                          if (deleted && context.mounted) {
                            Navigator.pop(context, null);
                          }
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: cs.error,
                          side: BorderSide(
                              color: cs.error.withValues(alpha: 0.4)),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          textStyle: GoogleFonts.dmSans(
                              fontSize: 15, fontWeight: FontWeight.w600),
                        ),
                        icon: const Icon(Icons.person_remove_outlined,
                            size: 20),
                        label: Text(l10n.crewButtonRemoveFromCrew),
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

  Widget _sectionHeader(IconData icon, String label, ColorScheme cs) {
    return Row(
      children: [
        Icon(icon, size: 20, color: cs.secondary),
        const SizedBox(width: 8),
        Text(
          label.toUpperCase(),
          style: Theme.of(context).textTheme.labelSmall!.copyWith(
            color: cs.secondary,
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
      style: GoogleFonts.dmSans(
        fontSize: 9,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.0,
        color: cs.mutedLabel,
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
      style: GoogleFonts.dmSans(
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
        hintStyle: GoogleFonts.dmSans(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          fontStyle: italic ? FontStyle.italic : FontStyle.normal,
          color: cs.outline,
        ),
      ),
    );
  }
}
