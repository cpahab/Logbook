import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/theme/theme_extensions.dart';
import '../../../core/widgets/reorderable_list_card.dart';
import '../../../core/widgets/undo_delete_snackbar.dart';
import '../data/home_repository.dart';
import '../domain/crew_member.dart';
import '../widgets/add_crew_member_dialog.dart';
import '../../../l10n/l10n_extension.dart';

/// The persistent crew roster (Settings → Crew Roster): everyone who has
/// ever sailed on this boat, distinct from any single day's crew list. Add,
/// edit, and remove members here; adding a day's crew from the roster
/// (crew_picker_sheet.dart) copies from these records.
class CrewRosterScreen extends StatefulWidget {
  const CrewRosterScreen({super.key});

  @override
  State<CrewRosterScreen> createState() => _CrewRosterScreenState();
}

class _CrewRosterScreenState extends State<CrewRosterScreen> {
  bool _reordering = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: cs.primary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          l10n.crewRosterTitle,
          style: Theme.of(context).textTheme.dialogTitle.copyWith(
            color: cs.primary,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(
              _reordering ? Icons.check_rounded : Icons.swap_vert,
              color: _reordering ? cs.primary : cs.onSurfaceVariant,
            ),
            tooltip: _reordering
                ? l10n.crewRosterReorderDoneTooltip
                : l10n.crewRosterReorderTooltip,
            onPressed: () => setState(() => _reordering = !_reordering),
          ),
        ],
      ),
      body: Consumer<HomeRepository>(
        builder: (context, repo, _) {
          final roster = repo.roster;

          if (roster.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.people_outline,
                      size: 64, color: cs.outlineVariant),
                  const SizedBox(height: 16),
                  Text(
                    l10n.crewRosterEmpty,
                    style: Theme.of(context).textTheme.fieldHintCompact.copyWith(
                        color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.crewRosterEmptyHint,
                    style: Theme.of(context).textTheme.bodySmall!.copyWith(
                        color: cs.mutedLabel),
                  ),
                ],
              ),
            );
          }

          if (_reordering) {
            return ReorderableListCard<CrewMember>(
              items: roster,
              padding: const EdgeInsets.symmetric(vertical: 8),
              dividerColor: cs.outlineVariant,
              keyOf: (m) => ValueKey(m.id),
              onReorder: (oldIndex, newIndex) {
                final newOrder = List.of(roster);
                final m = newOrder.removeAt(oldIndex);
                newOrder.insert(newIndex, m);
                repo.reorderRoster(newOrder);
              },
              itemBuilder: (context, member, i) => _RosterListTile(
                member: member,
                repo: repo,
                reordering: true,
                index: i,
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: roster.length,
            separatorBuilder: (_, _) =>
                Divider(height: 1, indent: 68, color: cs.outlineVariant),
            itemBuilder: (context, i) =>
                _RosterListTile(member: roster[i], repo: repo),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _addMember(context),
        tooltip: context.l10n.crewRosterNewPerson,
        child: const Icon(Icons.person_add_outlined),
      ),
    );
  }

  /// Opens the add-crew-member dialog and saves the result to the roster.
  Future<void> _addMember(BuildContext context) async {
    final repo = context.read<HomeRepository>();
    final member = await showDialog<CrewMember>(
      context: context,
      builder: (_) => const AddCrewMemberDialog(),
    );
    if (!context.mounted || member == null) return;
    repo.saveRosterMember(member);
  }
}

/// One roster member's row: avatar, name, blood-type/allergies/conditions
/// preview line, tap to edit. Shows a drag handle when [reordering].
class _RosterListTile extends StatelessWidget {
  final CrewMember member;
  final HomeRepository repo;
  final bool reordering;
  final int index;

  const _RosterListTile({
    required this.member,
    required this.repo,
    this.reordering = false,
    this.index = 0,
  });

  /// Blood type / allergies / conditions preview line, joined with " · ".
  String _subtitle(BuildContext context) {
    final parts = <String>[];
    if (member.bloodType != null) parts.add('${context.l10n.crewBloodGroupPrefix} ${member.bloodType}');
    if (member.allergies != null) parts.add(member.allergies!);
    if (member.conditions != null) parts.add(member.conditions!);
    return parts.join(' · ');
  }

  /// Opens the edit dialog and saves changes back to the roster.
  Future<void> _edit(BuildContext context) async {
    final updated = await showDialog<CrewMember>(
      context: context,
      builder: (_) => AddCrewMemberDialog(
        initialMember: member,
        onDelete: () => _delete(context),
      ),
    );
    if (!context.mounted || updated == null) return;
    updated.id = member.id;
    repo.saveEditedRosterMember(updated);
  }

  /// Removes this person from the roster immediately, offering an "undo"
  /// snackbar action instead of a blocking confirm dialog — same policy as
  /// every other list's delete (see undo_delete_snackbar.dart). Returns
  /// true always, since the deletion always happens now.
  Future<bool> _delete(BuildContext context) async {
    repo.deleteRosterMember(member.id!);
    if (context.mounted) {
      showUndoDeleteSnackBar(
        context,
        message: context.l10n.crewRosterMemberDeleted(member.name),
        onUndo: () => repo.saveRosterMember(member),
      );
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sub = _subtitle(context);

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: CircleAvatar(
        radius: 22,
        backgroundColor: cs.primaryContainer,
        child: Text(
          member.name.isNotEmpty ? member.name[0].toUpperCase() : '?',
          style: Theme.of(context).textTheme.bodyLarge!.copyWith(
              color: cs.onPrimaryContainer,
              fontWeight: FontWeight.w700),
        ),
      ),
      title: Text(
        member.name,
        style: Theme.of(context).textTheme.fieldValueCompact.copyWith(color: cs.onSurface),
      ),
      subtitle: sub.isNotEmpty
          ? Text(
              sub,
              style: Theme.of(context).textTheme.bodySmall!.copyWith(
                  color: cs.onSurfaceVariant),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            )
          : null,
      trailing: reordering
          ? ReorderableDragStartListener(
              index: index,
              child: Icon(Icons.drag_handle, color: cs.outline.withValues(alpha: 0.4)),
            )
          : Icon(Icons.chevron_right, color: cs.outlineVariant),
      onTap: reordering ? null : () => _edit(context),
    );
  }
}
