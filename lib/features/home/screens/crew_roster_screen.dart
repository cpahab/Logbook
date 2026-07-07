import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/theme/theme_extensions.dart';
import '../data/home_repository.dart';
import '../domain/crew_member.dart';
import '../widgets/add_crew_member_dialog.dart';
import '../../../l10n/l10n_extension.dart';

class CrewRosterScreen extends StatelessWidget {
  const CrewRosterScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: cs.primary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          context.l10n.crewRosterTitle,
          style: Theme.of(context).textTheme.dialogTitle.copyWith(
            color: cs.primary,
          ),
        ),
      ),
      body: Consumer<HomeRepository>(
        builder: (context, repo, _) {
          final roster = repo.roster;

          if (roster.isEmpty) {
            final l10n = context.l10n;
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

class _RosterListTile extends StatelessWidget {
  final CrewMember member;
  final HomeRepository repo;

  const _RosterListTile({required this.member, required this.repo});

  String _subtitle(BuildContext context) {
    final parts = <String>[];
    if (member.bloodType != null) parts.add('${context.l10n.crewBloodGroupPrefix} ${member.bloodType}');
    if (member.allergies != null) parts.add(member.allergies!);
    if (member.conditions != null) parts.add(member.conditions!);
    return parts.join(' · ');
  }

  Future<void> _edit(BuildContext context) async {
    final cs = Theme.of(context).colorScheme;
    final updated = await showDialog<CrewMember>(
      context: context,
      builder: (_) => AddCrewMemberDialog(
        initialMember: member,
        onDelete: () => _confirmDelete(context, cs),
      ),
    );
    if (!context.mounted || updated == null) return;
    updated.id = member.id;
    repo.saveEditedRosterMember(updated);
  }

  Future<bool> _confirmDelete(BuildContext context, ColorScheme cs) async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: cs.surface,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: Theme.of(context).textTheme.fieldValueProse.copyWith(color: cs.onSurface),
        contentTextStyle: Theme.of(context).textTheme.bodyMedium!.copyWith(color: cs.onSurfaceVariant),
        title: Text(l10n.crewRosterRemoveTitle),
        content: Text(l10n.crewRosterRemoveContent(member.name)),
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
    if (!context.mounted || confirmed != true) return false;
    repo.deleteRosterMember(member.id!);
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
      trailing: Icon(Icons.chevron_right, color: cs.outlineVariant),
      onTap: () => _edit(context),
    );
  }
}
