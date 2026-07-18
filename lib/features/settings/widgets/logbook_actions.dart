import 'package:flutter/material.dart';

import '../../../app/theme/theme_extensions.dart';
import '../../../core/services/logbook_service.dart';
import '../../../l10n/l10n_extension.dart';
import '../utils/logbook_switch.dart';

/// Prompts for a new name and renames the logbook, then calls
/// [onLogbooksChanged] (e.g. to refresh the caller's logbook list).
Future<void> showRenameLogbookDialog(
  BuildContext context, {
  required String logbookId,
  required String currentName,
  required VoidCallback onLogbooksChanged,
}) async {
  final l10n = context.l10n;
  final ctrl = TextEditingController(text: currentName);
  final newName = await showDialog<String>(
    context: context,
    builder: (ctx) {
      final cl = ctx.l10n;
      final dcs = Theme.of(ctx).colorScheme;
      return AlertDialog(
        backgroundColor: dcs.surface,
        surfaceTintColor: Colors.transparent,
        title: Text(cl.settingsRename, style: TextStyle(color: dcs.onSurface)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          style: TextStyle(color: dcs.onSurface),
          decoration: InputDecoration(
            hintText: cl.settingsNewLogbookHint,
            hintStyle: TextStyle(color: dcs.onSurfaceVariant),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: dcs.outlineVariant),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: dcs.primary, width: 2),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
          onSubmitted: (v) {
            if (v.trim().isNotEmpty) Navigator.pop(ctx, v.trim());
          },
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: Text(cl.cancel)),
          FilledButton(
            onPressed: () {
              final v = ctrl.text.trim();
              if (v.isNotEmpty) Navigator.pop(ctx, v);
            },
            child: Text(cl.saveChanges),
          ),
        ],
      );
    },
  );
  // Deferred to after this frame: the dialog's exit animation may still be
  // tearing down its TextField (and thus still touching ctrl) for a moment
  // after this Future resolves — disposing synchronously here races that
  // teardown and throws "used after being disposed".
  WidgetsBinding.instance.addPostFrameCallback((_) => ctrl.dispose());
  if (newName == null || newName == currentName || !context.mounted) return;

  try {
    await LogbookService().renameLogbook(logbookId, newName);
    if (context.mounted) onLogbooksChanged();
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${l10n.settingsError}: $e')),
      );
    }
  }
}

/// Prompts for a name, creates a new logbook owned by [uid], and switches
/// this device to it.
Future<void> showNewLogbookDialog(
  BuildContext context, {
  required String uid,
  required ValueChanged<bool> onSyncingChanged,
  required VoidCallback onGuestsCollapse,
}) async {
  final l10n = context.l10n;
  final ctrl = TextEditingController();
  final name = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      final cs = Theme.of(ctx).colorScheme;
      final cl = ctx.l10n;
      return Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: cs.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                cl.settingsNewLogbookTitle,
                style: Theme.of(ctx).textTheme.dialogTitle.copyWith(fontSize: 20, color: cs.onSurface),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: ctrl,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                style: Theme.of(ctx).textTheme.bodyLarge!.copyWith(color: cs.onSurface),
                decoration: InputDecoration(
                  hintText: cl.settingsNewLogbookHint,
                  hintStyle: TextStyle(color: cs.onSurfaceVariant),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: cs.outlineVariant),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: cs.primary, width: 2),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 14),
                ),
                onSubmitted: (v) {
                  if (v.trim().isNotEmpty) Navigator.pop(ctx, v.trim());
                },
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: Text(cl.cancel),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () {
                        final v = ctrl.text.trim();
                        if (v.isNotEmpty) Navigator.pop(ctx, v);
                      },
                      child: Text(cl.add),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
  // Deferred to after this frame: the bottom sheet's exit animation may
  // still be tearing down its TextField (and thus still touching ctrl)
  // for a moment after this Future resolves — disposing synchronously
  // here races that teardown and throws "used after being disposed".
  WidgetsBinding.instance.addPostFrameCallback((_) => ctrl.dispose());
  if (name == null || name.isEmpty || !context.mounted) return;

  onSyncingChanged(true);
  try {
    final newLogbookId = await LogbookService().createLogbook(uid, name);
    if (!context.mounted) return;
    // reinitFirestore always runs here (unconditional on this success path)
    // and its own ValueNotifier<String?> write already triggers the
    // logbook-list refresh via the listener registered in initState — so,
    // unlike the guest-panel reset, no separate "logbooks changed" callback
    // is needed here.
    await reinitFirestore(context, newLogbookId);
    if (context.mounted) {
      onGuestsCollapse();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.settingsConnected)),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${l10n.settingsError}: $e')),
      );
    }
  } finally {
    if (context.mounted) onSyncingChanged(false);
  }
}
