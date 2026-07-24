import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../app/theme/theme_extensions.dart';
import '../../../core/services/backup_service.dart';
import '../../../l10n/l10n_extension.dart';
import '../../home/domain/timeline_entry.dart';
import '../domain/theme_provider.dart';

/// Shown before an "update" mode import is applied, whenever
/// [BackupService.previewUpdate] finds at least one day present in both
/// the current logbook and the backup — the whole point of this screen is
/// that the resolution is visible and confirmed by the user, never a
/// silent automatic decision (see BackupImportMode.update's doc comment
/// and HomeRepository.backupEntryWins).
///
/// Returns a `List<ConflictResolution>` (same length/order as [conflicts])
/// once the user taps Apply, or null if they cancel — additions from the
/// same backup are applied by the caller regardless, since they're never
/// ambiguous in the first place.
Future<List<ConflictResolution>?> showImportConflictsScreen(
  BuildContext context,
  List<UpdateConflict> conflicts,
) {
  return Navigator.of(context).push<List<ConflictResolution>>(
    MaterialPageRoute(builder: (_) => ImportConflictsScreen(conflicts: conflicts)),
  );
}

/// One timeline moment within a conflict: present on "mine" ([mine] set),
/// on "backup" ([backup] set), or — when both sides logged the exact same
/// [time] — both, meaning the two are almost certainly the same real event
/// and must resolve to exactly one of them, never both (which would show
/// the same moment twice in the merged result).
class _Slot {
  final DateTime time;
  final TimelineEntry? mine;
  final TimelineEntry? backup;
  const _Slot({required this.time, this.mine, this.backup});
  bool get isMatched => mine != null && backup != null;
}

List<_Slot> _buildSlots(UpdateConflict c) {
  final mine = c.current.timeline;
  final backup = c.backup.entry.timeline;
  final usedBackup = List.filled(backup.length, false);
  final slots = <_Slot>[];
  for (final m in mine) {
    var matchedIdx = -1;
    for (var j = 0; j < backup.length; j++) {
      if (!usedBackup[j] && backup[j].time.isAtSameMomentAs(m.time)) {
        matchedIdx = j;
        break;
      }
    }
    if (matchedIdx >= 0) {
      usedBackup[matchedIdx] = true;
      slots.add(_Slot(time: m.time, mine: m, backup: backup[matchedIdx]));
    } else {
      slots.add(_Slot(time: m.time, mine: m));
    }
  }
  for (var j = 0; j < backup.length; j++) {
    if (!usedBackup[j]) slots.add(_Slot(time: backup[j].time, backup: backup[j]));
  }
  slots.sort((a, b) => a.time.compareTo(b.time));
  return slots;
}

class ImportConflictsScreen extends StatefulWidget {
  final List<UpdateConflict> conflicts;
  const ImportConflictsScreen({super.key, required this.conflicts});

  @override
  State<ImportConflictsScreen> createState() => _ImportConflictsScreenState();
}

class _ImportConflictsScreenState extends State<ImportConflictsScreen> {
  /// Per-conflict state, same order/index as widget.conflicts.
  late List<bool> _useBackupFields;
  late List<List<_Slot>> _slots;
  /// Per-slot choice, same index as [_slots]. For a matched slot (logged by
  /// both sides at the same instant): true means "use backup's version of
  /// this moment". For an unmatched slot (only one side logged it at all):
  /// true means "include it in the merged timeline".
  late List<List<bool>> _slotChoice;
  late List<bool> _timelineExpanded;

  @override
  void initState() {
    super.initState();
    final n = widget.conflicts.length;
    _useBackupFields = List.filled(n, false);
    _slots = [for (final c in widget.conflicts) _buildSlots(c)];
    _slotChoice = List.generate(n, (_) => <bool>[]);
    _timelineExpanded = List.filled(n, false);
    for (var i = 0; i < n; i++) {
      _applyDefault(i, widget.conflicts[i].backupWinsByDefault);
    }
  }

  /// Resets one conflict's whole resolution to a clean, unmixed "[useBackup]'s
  /// side wins entirely" — the starting point both at load (each conflict's
  /// own suggested default) and whenever its day-level Mine/Backup toggle or
  /// one of the bulk actions is tapped, so picking a side always starts from
  /// a predictable state rather than layering onto a prior custom selection.
  /// Matched slots resolve to that side; unmatched slots are included only
  /// if they belong to that side (an unmatched entry from the *other* side
  /// is left out, since "keep mine"/"use backup" means exactly that side's
  /// version of the day, not a mix).
  void _applyDefault(int i, bool useBackup) {
    _useBackupFields[i] = useBackup;
    _slotChoice[i] = [
      for (final s in _slots[i])
        s.isMatched ? useBackup : (useBackup ? s.backup != null : s.mine != null),
    ];
  }

  List<ConflictResolution> _buildResolutions() => [
        for (var i = 0; i < widget.conflicts.length; i++) _resolutionFor(i),
      ];

  ConflictResolution _resolutionFor(int i) {
    final slots = _slots[i];
    final choice = _slotChoice[i];
    final timeline = <TimelineEntry>[
      for (var k = 0; k < slots.length; k++)
        if (slots[k].isMatched)
          (choice[k] ? slots[k].backup! : slots[k].mine!)
        else if (choice[k])
          (slots[k].mine ?? slots[k].backup!),
    ];
    return ConflictResolution(useBackupFields: _useBackupFields[i], timeline: timeline);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final locale = context.read<ThemeProvider>().localeString;
    final dateFmt = DateFormat('d MMM yyyy', locale);
    final timeFmt = DateFormat('d MMM yyyy, HH:mm', locale);
    final entryTimeFmt = DateFormat('HH:mm', locale);

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: IconButton(
          icon: Icon(Icons.close, color: cs.primary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          l10n.backupConflictsTitle(widget.conflicts.length),
          style: Theme.of(context).textTheme.dialogTitle.copyWith(color: cs.primary),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.backupConflictsIntro,
                  style: Theme.of(context).textTheme.bodySmall!.copyWith(color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _bulkButton(
                        l10n.backupConflictsKeepMineAll,
                        () => setState(() {
                              for (var i = 0; i < widget.conflicts.length; i++) {
                                _applyDefault(i, false);
                              }
                            }),
                        cs),
                    _bulkButton(
                        l10n.backupConflictsUseBackupAll,
                        () => setState(() {
                              for (var i = 0; i < widget.conflicts.length; i++) {
                                _applyDefault(i, true);
                              }
                            }),
                        cs),
                    _bulkButton(
                        l10n.backupConflictsUseSuggestedAll,
                        () => setState(() {
                              for (var i = 0; i < widget.conflicts.length; i++) {
                                _applyDefault(i, widget.conflicts[i].backupWinsByDefault);
                              }
                            }),
                        cs),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.all(20),
              itemCount: widget.conflicts.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, i) => _ConflictTile(
                conflict: widget.conflicts[i],
                useBackupFields: _useBackupFields[i],
                dateLabel: dateFmt.format(widget.conflicts[i].current.date),
                timeFmt: timeFmt,
                entryTimeFmt: entryTimeFmt,
                slots: _slots[i],
                choice: _slotChoice[i],
                expanded: _timelineExpanded[i],
                onChanged: (v) => setState(() => _applyDefault(i, v)),
                onToggleExpanded: () => setState(() => _timelineExpanded[i] = !_timelineExpanded[i]),
                onSlotChanged: (k, v) => setState(() => _slotChoice[i][k] = v),
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(l10n.backupConflictsCancel),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).pop(_buildResolutions()),
                      child: Text(l10n.backupConflictsApply),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bulkButton(String label, VoidCallback onTap, ColorScheme cs) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: cs.outlineVariant),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: Text(label, style: Theme.of(context).textTheme.bodySmall),
    );
  }
}

/// One conflicting day: date header, updated-at timestamps for each side, a
/// Mine/Backup toggle for the day's non-timeline fields, and an expandable
/// timeline panel for hand-picking which entries make it into the merged
/// result.
class _ConflictTile extends StatelessWidget {
  final UpdateConflict conflict;
  final bool useBackupFields;
  final String dateLabel;
  final DateFormat timeFmt;
  final DateFormat entryTimeFmt;
  final List<_Slot> slots;
  final List<bool> choice;
  final bool expanded;
  final ValueChanged<bool> onChanged;
  final VoidCallback onToggleExpanded;
  final void Function(int slotIndex, bool value) onSlotChanged;

  const _ConflictTile({
    required this.conflict,
    required this.useBackupFields,
    required this.dateLabel,
    required this.timeFmt,
    required this.entryTimeFmt,
    required this.slots,
    required this.choice,
    required this.expanded,
    required this.onChanged,
    required this.onToggleExpanded,
    required this.onSlotChanged,
  });

  String _updatedLabel(DateTime? updatedAt) =>
      updatedAt == null ? '—' : timeFmt.format(updatedAt.toLocal());

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            dateLabel,
            style: Theme.of(context)
                .textTheme
                .fieldValueCompact
                .copyWith(color: cs.onSurface, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            l10n.backupConflictsMineSummary(
                _updatedLabel(conflict.current.updatedAt), conflict.current.timeline.length),
            style: Theme.of(context).textTheme.bodySmall!.copyWith(color: cs.onSurfaceVariant),
          ),
          Text(
            l10n.backupConflictsBackupSummary(
                _updatedLabel(conflict.backup.entry.updatedAt), conflict.backup.entry.timeline.length),
            style: Theme.of(context).textTheme.bodySmall!.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _choice(context, l10n.backupConflictsMine, !useBackupFields, () => onChanged(false), cs)),
              const SizedBox(width: 8),
              Expanded(child: _choice(context, l10n.backupConflictsBackup, useBackupFields, () => onChanged(true), cs)),
            ],
          ),
          const SizedBox(height: 10),
          _TimelinePanel(
            label: l10n.backupConflictsTimelineLabel,
            slots: slots,
            choice: choice,
            expanded: expanded,
            entryTimeFmt: entryTimeFmt,
            onToggleExpanded: onToggleExpanded,
            onSlotChanged: onSlotChanged,
          ),
        ],
      ),
    );
  }

  Widget _choice(BuildContext context, String label, bool active, VoidCallback onTap, ColorScheme cs) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: active ? cs.primaryContainer : cs.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: active ? cs.primary : cs.outlineVariant),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall!.copyWith(
              fontWeight: active ? FontWeight.w600 : FontWeight.w400,
              color: active ? cs.onPrimaryContainer : cs.onSurfaceVariant),
        ),
      ),
    );
  }
}

/// A conflict's merged timeline, collapsed by default to a single summary
/// row, expandable to reveal each [_Slot]: a matched slot (both sides logged
/// the same instant) shows a Mine/Backup either-or choice, since only one
/// can be kept; an unmatched slot (only one side has it) shows a plain
/// include/exclude checkbox, since there's nothing to conflict with.
class _TimelinePanel extends StatelessWidget {
  final String label;
  final List<_Slot> slots;
  final List<bool> choice;
  final bool expanded;
  final DateFormat entryTimeFmt;
  final VoidCallback onToggleExpanded;
  final void Function(int slotIndex, bool value) onSlotChanged;

  const _TimelinePanel({
    required this.label,
    required this.slots,
    required this.choice,
    required this.expanded,
    required this.entryTimeFmt,
    required this.onToggleExpanded,
    required this.onSlotChanged,
  });

  static String _summary(TimelineEntry e) {
    final parts = <String>[
      if ((e.wind ?? '').isNotEmpty) e.wind!,
      if ((e.sea ?? '').isNotEmpty) e.sea!,
      if ((e.weather ?? '').isNotEmpty) e.weather!,
    ];
    if (parts.isNotEmpty) return parts.join(' · ');
    return e.remarks ?? '';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;

    if (slots.isEmpty) {
      return Text(
        label,
        style: Theme.of(context).textTheme.bodySmall!.copyWith(color: cs.onSurfaceVariant),
      );
    }

    // A matched slot always contributes exactly one entry (it's never
    // dropped, just resolved to one side), so it always counts as
    // "selected"; an unmatched slot counts only if its checkbox is on.
    final selectedCount = [
      for (var k = 0; k < slots.length; k++)
        if (slots[k].isMatched || choice[k]) k,
    ].length;

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onToggleExpanded,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '$label · ${l10n.backupConflictsEntriesSelected(selectedCount, slots.length)}',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall!
                          .copyWith(color: cs.onSurfaceVariant, fontWeight: FontWeight.w600),
                    ),
                  ),
                  Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                    color: cs.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          if (expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var k = 0; k < slots.length; k++) ...[
                    if (k > 0) const SizedBox(height: 8),
                    _SlotRow(
                      slot: slots[k],
                      useBackup: choice[k],
                      entryTimeFmt: entryTimeFmt,
                      onChanged: (v) => onSlotChanged(k, v),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _SlotRow extends StatelessWidget {
  final _Slot slot;
  /// Matched slot: true = use backup's version of this moment.
  /// Unmatched slot: true = include this entry at all.
  final bool useBackup;
  final DateFormat entryTimeFmt;
  final ValueChanged<bool> onChanged;

  const _SlotRow({
    required this.slot,
    required this.useBackup,
    required this.entryTimeFmt,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final timeLabel = entryTimeFmt.format(slot.time.toLocal());

    if (!slot.isMatched) {
      final entry = slot.mine ?? slot.backup!;
      final sourceLabel = slot.mine != null ? l10n.backupConflictsMine : l10n.backupConflictsBackup;
      final summary = _TimelinePanel._summary(entry);
      return CheckboxListTile(
        dense: true,
        controlAffinity: ListTileControlAffinity.leading,
        contentPadding: EdgeInsets.zero,
        value: useBackup, // "included" for an unmatched slot
        onChanged: (v) => onChanged(v ?? false),
        title: Text('$timeLabel · $sourceLabel',
            style: Theme.of(context).textTheme.bodySmall!.copyWith(fontWeight: FontWeight.w600)),
        subtitle: summary.isEmpty ? null : Text(summary, style: Theme.of(context).textTheme.bodySmall),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(timeLabel, style: Theme.of(context).textTheme.bodySmall!.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _miniChoice(
                  context, l10n.backupConflictsMine, _TimelinePanel._summary(slot.mine!), !useBackup, () => onChanged(false), cs),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _miniChoice(
                  context, l10n.backupConflictsBackup, _TimelinePanel._summary(slot.backup!), useBackup, () => onChanged(true), cs),
            ),
          ],
        ),
      ],
    );
  }

  Widget _miniChoice(
      BuildContext context, String label, String summary, bool active, VoidCallback onTap, ColorScheme cs) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
        decoration: BoxDecoration(
          color: active ? cs.primaryContainer : cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: active ? cs.primary : cs.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall!.copyWith(
                  fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                  color: active ? cs.onPrimaryContainer : cs.onSurfaceVariant),
            ),
            if (summary.isNotEmpty)
              Text(
                summary,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall!.copyWith(
                    fontSize: 11, color: active ? cs.onPrimaryContainer : cs.onSurfaceVariant),
              ),
          ],
        ),
      ),
    );
  }
}
