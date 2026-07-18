import 'package:flutter/material.dart';

import '../../../core/services/logbook_service.dart';
import '../../../l10n/l10n_extension.dart';

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
