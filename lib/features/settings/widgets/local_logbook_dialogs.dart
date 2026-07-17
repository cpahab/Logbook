import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/services/local_logbook_service.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../l10n/l10n_extension.dart';

/// Rename/delete actions sheet for a local logbook. Delete is omitted for
/// the active logbook — switch away from it first (see the local-mode
/// analogue of _reinitFirestore in settings_screen.dart, which this sheet
/// deliberately doesn't reach into).
void showLocalLogbookOptionsSheet(
  BuildContext context, {
  required bool isActive,
  required VoidCallback onRename,
  required VoidCallback onDelete,
}) {
  final cs = Theme.of(context).colorScheme;
  final l10n = context.l10n;
  showModalBottomSheet(
    context: context,
    backgroundColor: cs.surface,
    builder: (sheetCtx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading:
                Icon(Icons.drive_file_rename_outline, color: cs.onSurface),
            title: Text(l10n.settingsRename),
            onTap: () {
              Navigator.pop(sheetCtx);
              onRename();
            },
          ),
          if (!isActive)
            ListTile(
              leading: Icon(Icons.delete_outline, color: cs.error),
              title: Text(l10n.settingsDeleteLogbook,
                  style: TextStyle(color: cs.error)),
              onTap: () {
                Navigator.pop(sheetCtx);
                onDelete();
              },
            ),
        ],
      ),
    ),
  );
}

/// Prompts for a new name and renames local logbook [id], then calls
/// [onRenamed] (e.g. to refresh the caller's local-logbook list).
Future<void> showRenameLocalLogbookDialog(
  BuildContext context, {
  required String id,
  required String currentName,
  required VoidCallback onRenamed,
}) async {
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
  WidgetsBinding.instance.addPostFrameCallback((_) => ctrl.dispose());
  if (newName == null || newName == currentName || !context.mounted) return;

  await context.read<LocalLogbookService>().renameLogbook(id, newName);
  if (context.mounted) onRenamed();
}

/// Confirms — warning that local logbooks have no cloud backup — then
/// permanently deletes local logbook [id], then calls [onDeleted]. Never
/// called on the active logbook (see [showLocalLogbookOptionsSheet]).
Future<void> showDeleteLocalLogbookDialog(
  BuildContext context, {
  required String id,
  required String name,
  required VoidCallback onDeleted,
}) async {
  final l10n = context.l10n;
  final confirmed = await showConfirmDialog(
    context,
    title: l10n.settingsDeleteLogbook,
    body: l10n.settingsDeleteLocalLogbookConfirm(name),
    confirmLabel: l10n.delete,
    destructive: true,
  );
  if (!confirmed || !context.mounted) return;

  await context.read<LocalLogbookService>().deleteLogbook(id);
  if (context.mounted) onDeleted();
}
