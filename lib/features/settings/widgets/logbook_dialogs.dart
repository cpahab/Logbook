import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../app/theme/theme_extensions.dart';
import '../../../l10n/l10n_extension.dart';
import '../utils/settings_format_utils.dart';

/// Owner-only actions sheet for a cloud logbook: rename, share (QR), delete.
/// Each action is a caller-supplied callback since the actual rename/
/// share/delete flows need access to settings-screen state (sync spinner,
/// re-pointing repositories at a new logbook) that doesn't belong here.
void showLogbookOptionsSheet(
  BuildContext context, {
  required VoidCallback onRename,
  required VoidCallback onShare,
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
          ListTile(
            leading: Icon(Icons.qr_code, color: cs.onSurface),
            title: Text(l10n.settingsShare),
            onTap: () {
              Navigator.pop(sheetCtx);
              onShare();
            },
          ),
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

/// Guest-only actions sheet for a cloud logbook: leave.
void showGuestOptionsSheet(
  BuildContext context, {
  required VoidCallback onLeave,
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
            leading: Icon(Icons.exit_to_app, color: cs.error),
            title: Text(l10n.settingsLeaveLogbook,
                style: TextStyle(color: cs.error)),
            onTap: () {
              Navigator.pop(sheetCtx);
              onLeave();
            },
          ),
        ],
      ),
    ),
  );
}

/// Shows [shareCode] as a scannable QR code (`logbook://join/{code}`) for
/// another device to join this logbook.
void showQrModal(BuildContext context, String shareCode) {
  showDialog(
    context: context,
    builder: (ctx) {
      final cs = Theme.of(ctx).colorScheme;
      final cl = ctx.l10n;
      return Dialog(
        backgroundColor: cs.surface,
        surfaceTintColor: Colors.transparent,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(cl.settingsShowQrCode,
                  style: Theme.of(ctx).textTheme.bodyLarge!.copyWith(fontWeight: FontWeight.w600, color: cs.onSurface)),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12)),
                child: QrImageView(
                  data: 'logbook://join/$shareCode',
                  version: QrVersions.auto,
                  size: 200,
                  backgroundColor: Colors.white,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                formatCode(shareCode),
                style: Theme.of(ctx).textTheme.shareCode.copyWith(color: cs.onSurface),
              ),
              const SizedBox(height: 16),
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(cl.close)),
            ],
          ),
        ),
      );
    },
  );
}
