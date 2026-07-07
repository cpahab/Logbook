import 'package:flutter/material.dart';

import '../../../app/theme/theme_extensions.dart';
import '../data/home_repository.dart';
import '../domain/crew_member.dart';
import 'add_crew_member_dialog.dart';
import '../../../l10n/l10n_extension.dart';

/// Bottom sheet for picking a crew member from the roster or creating a new one.
///
/// Returns the selected/created [CrewMember] via `Navigator.pop`, or null if
/// the user cancels. New members are automatically saved to the roster.
class CrewPickerSheet extends StatelessWidget {
  final HomeRepository repo;
  /// Names already present on today's entry — filtered out from the roster list.
  final Set<String> excludeNames;

  const CrewPickerSheet({
    super.key,
    required this.repo,
    this.excludeNames = const {},
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: repo,
      builder: (context, _) {
        final cs = Theme.of(context).colorScheme;
        final roster = repo.roster
            .where((m) => !excludeNames.contains(m.name))
            .toList();

        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // drag handle
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Row(
                  children: [
                    Icon(Icons.people_outline, size: 18, color: cs.primary),
                    const SizedBox(width: 8),
                    Text(
                      context.l10n.crewPickerTitle,
                      style: Theme.of(context).textTheme.labelSmall!.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (roster.isNotEmpty) ...[
                const Divider(height: 1),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.5,
                  ),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: roster.length,
                    itemBuilder: (context, i) =>
                        _RosterTile(member: roster[i], repo: repo),
                  ),
                ),
              ],
              const Divider(height: 1),
              _NewPersonTile(repo: repo),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }
}

class _RosterTile extends StatelessWidget {
  final CrewMember member;
  final HomeRepository repo;

  const _RosterTile({required this.member, required this.repo});

  Future<void> _edit(BuildContext context) async {
    final updated = await showDialog<CrewMember>(
      context: context,
      builder: (_) => AddCrewMemberDialog(initialMember: member),
    );
    if (!context.mounted || updated == null) return;
    updated.id = member.id;
    repo.saveEditedRosterMember(updated);
  }

  Future<void> _delete(BuildContext context) async {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: cs.surface,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: Theme.of(context).textTheme.fieldValueProse.copyWith(color: cs.onSurface),
        contentTextStyle: Theme.of(context).textTheme.bodyMedium!.copyWith(color: cs.onSurfaceVariant),
        title: Text(l10n.crewPickerRemoveTitle),
        content: Text('${member.name} ${l10n.crewPickerRemoveContent}'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l10n.cancel)),
          FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: cs.error, foregroundColor: cs.onError),
              onPressed: () => Navigator.pop(context, true),
              child: Text(l10n.remove)),
        ],
      ),
    );
    if (!context.mounted || confirmed != true) return;
    repo.deleteRosterMember(member.id!);
  }

  String _subtitle(BuildContext context) {
    final parts = <String>[];
    if (member.bloodType != null) parts.add('${context.l10n.crewFieldBloodGroup} ${member.bloodType}');
    if (member.allergies != null) parts.add(member.allergies!);
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sub = _subtitle(context);

    return InkWell(
      onTap: () => Navigator.pop(context, member),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: cs.primaryContainer,
              child: Text(
                member.name.isNotEmpty ? member.name[0].toUpperCase() : '?',
                style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                    color: cs.onPrimaryContainer,
                    fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    member.name,
                    style: Theme.of(context).textTheme.fieldValueCompact.copyWith(
                        color: cs.onSurface),
                  ),
                  if (sub.isNotEmpty)
                    Text(
                      sub,
                      style: Theme.of(context).textTheme.bodySmall!.copyWith(
                          color: cs.onSurfaceVariant),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            IconButton(
              icon: Icon(Icons.edit_outlined, size: 18, color: cs.mutedLabel),
              onPressed: () => _edit(context),
              tooltip: context.l10n.edit,
            ),
            IconButton(
              icon: Icon(Icons.delete_outline, size: 18, color: cs.error),
              onPressed: () => _delete(context),
              tooltip: context.l10n.remove,
            ),
          ],
        ),
      ),
    );
  }
}

class _NewPersonTile extends StatelessWidget {
  final HomeRepository repo;

  const _NewPersonTile({required this.repo});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return InkWell(
      onTap: () async {
        final member = await showDialog<CrewMember>(
          context: context,
          builder: (_) => const AddCrewMemberDialog(),
        );
        if (!context.mounted || member == null) return;
        repo.saveRosterMember(member);
        if (context.mounted) Navigator.pop(context, member);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: cs.secondaryContainer,
              child: Icon(Icons.person_add_outlined,
                  size: 18, color: cs.onSecondaryContainer),
            ),
            const SizedBox(width: 12),
            Text(
              context.l10n.crewPickerNewPerson,
              style: Theme.of(context).textTheme.bodyLarge!.copyWith(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: cs.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
