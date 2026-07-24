import 'package:flutter/material.dart';

import '../../../app/theme/theme_extensions.dart';
import '../../../core/widgets/danger_outlined_button.dart';
import '../domain/crew_member.dart';
import '../../../l10n/l10n_extension.dart';

/// Fullscreen dialog for adding a new crew member or editing an existing
/// one's identity/medical/safety-equipment/remarks fields. Returns the
/// resulting [CrewMember] via `Navigator.pop`, or null if cancelled.
class AddCrewMemberDialog extends StatefulWidget {
  final CrewMember? initialMember;
  /// Called when the delete button is tapped. Must perform the deletion
  /// itself (instant delete + undo snackbar — see undo_delete_snackbar.dart)
  /// and return whether it actually happened; the dialog only closes itself
  /// if this resolves to `true`.
  final Future<bool> Function()? onDelete;
  /// Delete button's label — this dialog is shared between two different
  /// actions (Crew Roster: permanently remove the person; per-day crew
  /// editing: remove them from just this one day, roster untouched), so the
  /// label must say which one applies. Defaults to the roster wording.
  final String? deleteLabel;

  const AddCrewMemberDialog({
    super.key,
    this.initialMember,
    this.onDelete,
    this.deleteLabel,
  });

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

  /// Validates (name required) and pops the dialog with the resulting
  /// [CrewMember]; no-ops if the name is empty.
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
            style: Theme.of(context).textTheme.dialogTitle.copyWith(
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

                  // ── end Identity ──

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

                  // ── end Medical Info ──

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

                  // ── end Safety Equipment ──

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

                  // ── end Remarks ──

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
                        textStyle: Theme.of(context).textTheme.fieldValueCompact,
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
                        textStyle: Theme.of(context).textTheme.fieldValueCompact,
                      ),
                      child: Text(l10n.cancel),
                    ),
                  ),
                  if (isEdit && widget.onDelete != null) ...[
                    const SizedBox(height: 32),
                    DangerOutlinedButton(
                      icon: Icons.person_remove_outlined,
                      label: widget.deleteLabel ?? l10n.crewButtonRemoveFromCrew,
                      onPressed: () async {
                        final deleted = await widget.onDelete!();
                        if (deleted && context.mounted) {
                          Navigator.pop(context, null);
                        }
                      },
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

  /// Bordered card shell wrapping one field (or group of fields).
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
            color: cs.cardShadowColor,
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }

  /// Small muted field label above a [_field].
  Widget _label(String text, ColorScheme cs) {
    return Text(
      text,
      style: Theme.of(context).textTheme.microLabel.copyWith(
        color: cs.mutedLabel,
      ),
    );
  }

  /// Borderless text input styled to sit flush inside a [_card].
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
      style: Theme.of(context).textTheme.fieldValueProse.copyWith(
        fontStyle: italic ? FontStyle.italic : FontStyle.normal,
        color: cs.primary,
      ),
      decoration: InputDecoration(
        border: InputBorder.none,
        isDense: true,
        contentPadding: EdgeInsets.zero,
        hintText: hint,
        hintStyle: Theme.of(context).textTheme.fieldValueProse.copyWith(
          fontStyle: italic ? FontStyle.italic : FontStyle.normal,
          color: cs.outline,
        ),
      ),
    );
  }
}
