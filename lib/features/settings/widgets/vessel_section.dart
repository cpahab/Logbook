import 'package:flutter/material.dart';

import '../../../app/theme/theme_extensions.dart';
import '../../../core/widgets/card_shell.dart';
import '../../../l10n/l10n_extension.dart';
import '../domain/theme_provider.dart';

/// Vessel/VHF info section: name, MMSI, call sign, life raft, EPIRB, fire
/// suppression. Owns its own TextEditingControllers/FocusNodes so it can
/// resync from [themeProvider] (backup restore, logbook switch, remote
/// sync can all replace these fields wholesale while this screen stays
/// mounted) without fighting the user's own typing.
class VesselSection extends StatefulWidget {
  final ThemeProvider themeProvider;
  final ColorScheme cs;
  const VesselSection({super.key, required this.themeProvider, required this.cs});

  @override
  State<VesselSection> createState() => _VesselSectionState();
}

class _VesselSectionState extends State<VesselSection> {
  late TextEditingController _vesselNameCtrl;
  late TextEditingController _vesselMmsiCtrl;
  late TextEditingController _vesselCallSignCtrl;
  late TextEditingController _lifeRaftCtrl;
  late TextEditingController _epirbCtrl;
  late TextEditingController _fireSuppCtrl;
  final _vesselNameFocus     = FocusNode();
  final _vesselMmsiFocus     = FocusNode();
  final _vesselCallSignFocus = FocusNode();
  final _lifeRaftFocus       = FocusNode();
  final _epirbFocus          = FocusNode();
  final _fireSuppFocus       = FocusNode();
  bool _expanded = false;

  ThemeProvider get _themeProvider => widget.themeProvider;

  @override
  void initState() {
    super.initState();
    final p = _themeProvider;
    _vesselNameCtrl = TextEditingController(text: p.vesselName);
    _vesselMmsiCtrl = TextEditingController(text: p.vesselMmsi);
    _vesselCallSignCtrl = TextEditingController(text: p.vesselCallSign);
    _lifeRaftCtrl = TextEditingController(text: p.lifeRaftInfo);
    _epirbCtrl = TextEditingController(text: p.epirbInfo);
    _fireSuppCtrl = TextEditingController(text: p.fireSuppInfo);
    // Vessel fields are also replaced wholesale by a backup restore or a
    // logbook switch, both of which can happen while this screen stays
    // mounted — resync from the provider whenever it changes, but only for
    // fields the user isn't actively typing into.
    _themeProvider.addListener(_syncVesselControllers);
  }

  @override
  void dispose() {
    _themeProvider.removeListener(_syncVesselControllers);
    _vesselNameCtrl.dispose();
    _vesselMmsiCtrl.dispose();
    _vesselCallSignCtrl.dispose();
    _lifeRaftCtrl.dispose();
    _epirbCtrl.dispose();
    _fireSuppCtrl.dispose();
    _vesselNameFocus.dispose();
    _vesselMmsiFocus.dispose();
    _vesselCallSignFocus.dispose();
    _lifeRaftFocus.dispose();
    _epirbFocus.dispose();
    _fireSuppFocus.dispose();
    super.dispose();
  }

  /// Resyncs each vessel-field controller from [_themeProvider] whenever it
  /// changes externally (backup restore, logbook switch, remote sync) — but
  /// only for fields that don't currently have focus, so this never fights
  /// the user's own typing (which is what triggers these same notifications
  /// on every keystroke, via the field's own onChanged → setVesselXxx call).
  void _syncVesselControllers() {
    void sync(TextEditingController ctrl, FocusNode focus, String value) {
      if (!focus.hasFocus && ctrl.text != value) ctrl.text = value;
    }
    sync(_vesselNameCtrl, _vesselNameFocus, _themeProvider.vesselName);
    sync(_vesselMmsiCtrl, _vesselMmsiFocus, _themeProvider.vesselMmsi);
    sync(_vesselCallSignCtrl, _vesselCallSignFocus, _themeProvider.vesselCallSign);
    sync(_lifeRaftCtrl, _lifeRaftFocus, _themeProvider.lifeRaftInfo);
    sync(_epirbCtrl, _epirbFocus, _themeProvider.epirbInfo);
    sync(_fireSuppCtrl, _fireSuppFocus, _themeProvider.fireSuppInfo);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final p = _themeProvider;
    final cs = widget.cs;
    return CardShell(
      accentColor: cs.logbookScopedAccent,
      child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => setState(() => _expanded = !_expanded),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              l10n.settingsVesselSection.toUpperCase(),
                              style: Theme.of(context).textTheme.labelSmall!.copyWith(
                                color: cs.secondary,
                              ),
                            ),
                            Row(
                              children: [
                                Icon(Icons.directions_boat_outlined,
                                    size: 20, color: cs.outlineVariant),
                                const SizedBox(width: 4),
                                AnimatedRotation(
                                  turns: _expanded ? 0.5 : 0,
                                  duration: const Duration(milliseconds: 200),
                                  child: Icon(Icons.expand_more,
                                      size: 20, color: cs.outlineVariant),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          l10n.settingsVesselInfo,
                          style: Theme.of(context).textTheme.bodySmall!.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                AnimatedCrossFade(
                  duration: const Duration(milliseconds: 220),
                  crossFadeState: _expanded
                      ? CrossFadeState.showSecond
                      : CrossFadeState.showFirst,
                  firstChild: const SizedBox(width: double.infinity),
                  secondChild: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _vesselRow(
                          label: l10n.settingsFieldName,
                          controller: _vesselNameCtrl,
                          focusNode: _vesselNameFocus,
                          hint: l10n.settingsFieldNameHint,
                          onChanged: p.setVesselName,
                          cs: cs,
                        ),
                        _rowDivider(cs),
                        _vesselRow(
                          label: 'MMSI',
                          controller: _vesselMmsiCtrl,
                          focusNode: _vesselMmsiFocus,
                          hint: '123456789',
                          onChanged: p.setVesselMmsi,
                          keyboard: TextInputType.number,
                          cs: cs,
                        ),
                        _rowDivider(cs),
                        _vesselRow(
                          label: l10n.settingsFieldCallSign,
                          controller: _vesselCallSignCtrl,
                          focusNode: _vesselCallSignFocus,
                          hint: l10n.settingsFieldCallSignHint,
                          onChanged: p.setVesselCallSign,
                          cs: cs,
                        ),
                        _rowDivider(cs),
                        _vesselRow(
                          label: l10n.emergencyLifeRaft,
                          controller: _lifeRaftCtrl,
                          focusNode: _lifeRaftFocus,
                          hint: l10n.settingsFieldLifeRaftHint,
                          onChanged: p.setLifeRaftInfo,
                          cs: cs,
                        ),
                        _rowDivider(cs),
                        _vesselRow(
                          // EPIRB is an international maritime acronym — kept
                          // in English, matching the emergency manifest screen.
                          label: 'EPIRB',
                          controller: _epirbCtrl,
                          focusNode: _epirbFocus,
                          hint: l10n.settingsFieldEpirbHint,
                          onChanged: p.setEpirbInfo,
                          cs: cs,
                        ),
                        _rowDivider(cs),
                        _vesselRow(
                          label: l10n.emergencyFireSuppression,
                          controller: _fireSuppCtrl,
                          focusNode: _fireSuppFocus,
                          hint: l10n.settingsFieldFireSuppHint,
                          onChanged: p.setFireSuppInfo,
                          cs: cs,
                          isLast: true,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  /// One label/value row within [VesselSection].
  Widget _vesselRow({
    required String label,
    required TextEditingController controller,
    required FocusNode focusNode,
    required String hint,
    required ValueChanged<String> onChanged,
    required ColorScheme cs,
    TextInputType keyboard = TextInputType.text,
    bool isLast = false,
  }) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                  fontWeight: FontWeight.w600, color: cs.onSurface),
            ),
          ),
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              textAlign: TextAlign.right,
              keyboardType: keyboard,
              // Unbounded so longer entries (e.g. a life raft/EPIRB
              // description) wrap onto more lines instead of scrolling
              // off-field in a single fixed line, which read as if the
              // text had been silently truncated.
              maxLines: null,
              textInputAction: TextInputAction.next,
              style: Theme.of(context).textTheme.chipLabel.copyWith(color: cs.primary),
              decoration: InputDecoration(
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
                hintText: hint,
                hintStyle: Theme.of(context).textTheme.chipLabel.copyWith(color: cs.outline.withValues(alpha: 0.5)),
              ),
              onChanged: onChanged,
              onSubmitted: (_) => FocusScope.of(context).unfocus(),
            ),
          ),
        ],
      ),
    );
  }

  /// Thin divider between [_vesselRow]s.
  Widget _rowDivider(ColorScheme cs) => Divider(
        color: cs.surfaceContainerHigh,
        height: 16,
        thickness: 1,
      );
}
