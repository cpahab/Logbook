import 'package:flutter/material.dart';

import '../../../app/theme/theme_extensions.dart';
import '../../../l10n/l10n_extension.dart';
import '../../home/domain/vessel_equipment.dart';

// ── Equipment slot editor ────────────────────────────────────────────────────
/// Inline (no-dialog) editor for one [EquipmentSlot]: its name and up to
/// [EquipmentSlot.maxStates] state labels. Collapsed to a single tappable
/// row when the slot isn't already configured, so the 10 sail slots don't
/// dominate the screen before the captain has named any of them.
class EquipmentSlotEditor extends StatefulWidget {
  final EquipmentSlot slot;
  /// The equipment type this slot represents (e.g. "Segel"/"Motor"/"Kiel"),
  /// used to phrase the add/delete affordances by what they actually do
  /// ("Segel hinzufügen") instead of a generic "Slot 3".
  final String typeLabel;
  /// Placeholder for the "add state" field, e.g. "Add state (e.g. 1st reef)"
  /// for a sail slot vs. "(e.g. On)" for the motor slot — sail's own example
  /// doesn't fit the motor/keel slots, which have their own hint per category.
  final String stateHint;
  final ValueChanged<EquipmentSlot> onChanged;
  const EquipmentSlotEditor({super.key, required this.slot, required this.typeLabel, required this.stateHint, required this.onChanged});

  @override
  State<EquipmentSlotEditor> createState() => _EquipmentSlotEditorState();
}

class _EquipmentSlotEditorState extends State<EquipmentSlotEditor> {
  late TextEditingController _labelCtrl;
  late List<String> _states;
  final _addCtrl = TextEditingController();
  late bool _expanded;

  // What this editor itself last pushed via [_notify], so [didUpdateWidget]
  // can tell "the provider echoing my own edit back" (ignore — the local
  // text may still have an untrimmed trailing character mid-keystroke) apart
  // from "another device changed this slot" (resync from the incoming value).
  String? _lastPushedLabel;
  List<String>? _lastPushedStates;

  @override
  void initState() {
    super.initState();
    _labelCtrl = TextEditingController(text: widget.slot.label);
    _states = List.of(widget.slot.states);
    _expanded = !widget.slot.isEmpty;
  }

  @override
  void didUpdateWidget(covariant EquipmentSlotEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    final isEcho = widget.slot.label == _lastPushedLabel &&
        _sameStates(widget.slot.states, _lastPushedStates ?? const []);
    if (!isEcho) {
      _labelCtrl.text = widget.slot.label;
      _states = List.of(widget.slot.states);
    }
  }

  bool _sameStates(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    _addCtrl.dispose();
    super.dispose();
  }

  void _notify() {
    final label = _labelCtrl.text.trim();
    final states = List.of(_states);
    _lastPushedLabel = label;
    _lastPushedStates = states;
    widget.onChanged(widget.slot.copyWith(label: label, states: states));
  }

  void _addState() {
    final v = _addCtrl.text.trim();
    if (v.isEmpty || _states.length >= EquipmentSlot.maxStates) return;
    setState(() {
      _states.add(v);
      _addCtrl.clear();
    });
    _notify();
  }

  void _removeState(int i) {
    setState(() => _states.removeAt(i));
    _notify();
  }

  void _clearSlot() {
    setState(() {
      _labelCtrl.clear();
      _states = [];
      _expanded = false;
    });
    _notify();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final isEmpty = widget.slot.label.trim().isEmpty && _states.isEmpty;
    final headerLabel = widget.slot.label.trim().isEmpty
        ? l10n.settingsEquipmentAddType(widget.typeLabel)
        : widget.slot.label;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Icon(Icons.edit_outlined, size: 16, color: cs.secondary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      headerLabel,
                      style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                        fontWeight: FontWeight.w600,
                        color: isEmpty ? cs.outline : cs.onSurface,
                      ),
                    ),
                  ),
                  Icon(_expanded ? Icons.expand_less : Icons.expand_more,
                      size: 20, color: cs.outlineVariant),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox(width: double.infinity, height: 0),
            secondChild: Padding(
              padding: const EdgeInsets.only(left: 24, bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _labelCtrl,
                    style: Theme.of(context).textTheme.bodyMedium,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: l10n.settingsEquipmentSlotLabel,
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (_) => _notify(),
                  ),
                  if (_states.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (int i = 0; i < _states.length; i++)
                          _removableStateChip(_states[i], () => _removeState(i), cs),
                      ],
                    ),
                  ],
                  if (_states.length < EquipmentSlot.maxStates) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _addCtrl,
                            style: Theme.of(context).textTheme.bodyMedium,
                            decoration: InputDecoration(
                              isDense: true,
                              hintText: widget.stateHint,
                              border: const OutlineInputBorder(),
                            ),
                            onSubmitted: (_) => _addState(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        TextButton(onPressed: _addState, child: Text(l10n.settingsEquipmentAddState)),
                      ],
                    ),
                  ],
                  if (!isEmpty) ...[
                    const SizedBox(height: 4),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: _clearSlot,
                        style: TextButton.styleFrom(
                          foregroundColor: cs.error,
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(0, 32),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Text(l10n.settingsEquipmentDeleteType(widget.typeLabel)),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            crossFadeState: _expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 200),
          ),
        ],
      ),
    );
  }

  /// Small removable pill chip — same visual language as the dialog's state
  /// chips, plus a trailing × so the captain sees exactly what a filled-in
  /// slot will look like when logging an entry.
  Widget _removableStateChip(String label, VoidCallback onRemove, ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.only(left: 12, right: 6, top: 6, bottom: 6),
      decoration: BoxDecoration(
        color: cs.primary,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: Theme.of(context).textTheme.chipLabel.copyWith(color: cs.onPrimary)),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: onRemove,
            child: Icon(Icons.close, size: 14, color: cs.onPrimary),
          ),
        ],
      ),
    );
  }
}
