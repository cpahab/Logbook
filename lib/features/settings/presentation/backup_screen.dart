import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../../../app/theme/theme_extensions.dart';
import '../../../core/services/backup_service.dart';
import '../../../core/widgets/card_shell.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/progress_snackbar.dart';
import '../../../l10n/l10n_extension.dart';
import '../../emergency/data/emergency_repository.dart';
import '../../home/data/home_repository.dart';
import '../domain/theme_provider.dart';

/// Settings > Backup & Restore: export the active logbook (day entries,
/// tracks, crew roster, emergency contacts, reachable photos) to a single
/// `.zip`, or restore one back — replacing whatever is currently in the
/// active logbook.
class BackupScreen extends StatefulWidget {
  /// The active logbook's display name, passed by the caller (see
  /// `settings_screen.dart`'s `_buildBackupSection`) — null if unknown yet.
  final String? activeLogbookName;

  const BackupScreen({super.key, this.activeLogbookName});

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  bool _busy = false;

  Future<void> _export() async {
    if (_busy) return;
    setState(() => _busy = true);

    final home = context.read<HomeRepository>();
    final emergency = context.read<EmergencyRepository>();
    final theme = context.read<ThemeProvider>();
    final logbookId = context.read<ValueNotifier<String?>>().value ?? '';
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);

    showProgressSnackBar(context, l10n.backupExportInProgress);

    try {
      final info = await PackageInfo.fromPlatform();
      final activeName = widget.activeLogbookName;
      final bytes = await BackupService.exportBackup(
        home: home,
        emergency: emergency,
        theme: theme,
        logbookId: logbookId,
        logbookName: activeName == null || activeName.isEmpty ? l10n.appTitle : activeName,
        appVersion: '${info.version}+${info.buildNumber}',
      );

      messenger.hideCurrentSnackBar();
      if (!mounted) return;

      final dateStr = DateTime.now().toIso8601String().substring(0, 10);
      await FilePicker.saveFile(
        dialogTitle: l10n.backupExportTitle,
        fileName: 'logbook_backup_$dateStr.zip',
        type: FileType.custom,
        allowedExtensions: ['zip'],
        bytes: bytes,
      );

      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(l10n.backupExportSuccess)));
    } catch (e, st) {
      if (kDebugMode) debugPrint('BackupScreen export failed: $e\n$st');
      messenger.hideCurrentSnackBar();
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(l10n.backupExportError)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    if (_busy) return;

    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final bytes = result.files.single.bytes;
    if (bytes == null || bytes.isEmpty) return;

    if (!mounted) return;
    final l10n = context.l10n;

    final confirmed = await showConfirmDialog(
      context,
      title: l10n.backupRestoreConfirmTitle,
      body: l10n.backupRestoreConfirmBody,
      confirmLabel: l10n.backupRestoreButton,
      destructive: true,
    );
    if (!confirmed || !mounted) return;

    setState(() => _busy = true);

    final home = context.read<HomeRepository>();
    final emergency = context.read<EmergencyRepository>();
    final theme = context.read<ThemeProvider>();
    final messenger = ScaffoldMessenger.of(context);

    showProgressSnackBar(context, l10n.backupRestoreInProgress);

    try {
      await BackupService.restoreBackup(
        zipBytes: Uint8List.fromList(bytes),
        home: home,
        emergency: emergency,
        theme: theme,
      );

      messenger.hideCurrentSnackBar();
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(l10n.backupRestoreSuccess)));
    } on BackupFormatException catch (e) {
      messenger.hideCurrentSnackBar();
      if (!mounted) return;
      final message = e.message == 'backupSchemaTooNew'
          ? l10n.backupRestoreSchemaTooNew
          : l10n.backupRestoreInvalidFile;
      messenger.showSnackBar(SnackBar(content: Text(message)));
    } catch (e, st) {
      if (kDebugMode) debugPrint('BackupScreen restore failed: $e\n$st');
      messenger.hideCurrentSnackBar();
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(l10n.backupRestoreError)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

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
          l10n.settingsBackupSection,
          style: Theme.of(context).textTheme.dialogTitle.copyWith(color: cs.primary),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.activeLogbookName != null && widget.activeLogbookName!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 16),
                child: Row(
                  children: [
                    Icon(Icons.anchor, size: 14, color: cs.logbookScopedAccent),
                    const SizedBox(width: 6),
                    Text(
                      l10n.settingsActiveLogbookHeader(widget.activeLogbookName!),
                      style: Theme.of(context).textTheme.labelSmall!.copyWith(
                          color: cs.logbookScopedAccent,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5),
                    ),
                  ],
                ),
              ),
            CardShell(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.backupExportTitle,
                      style: Theme.of(context).textTheme.labelSmall!.copyWith(color: cs.secondary),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      l10n.backupExportDescription,
                      style: Theme.of(context).textTheme.bodySmall!.copyWith(color: cs.onSurfaceVariant),
                    ),
                    const SizedBox(height: 14),
                    FilledButton.icon(
                      onPressed: _busy ? null : _export,
                      icon: _busy
                          ? const SizedBox(
                              width: 16, height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.upload_outlined, size: 18),
                      label: Text(l10n.backupExportButton),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            CardShell(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.backupRestoreTitle,
                      style: Theme.of(context).textTheme.labelSmall!.copyWith(color: cs.secondary),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      l10n.backupRestoreDescription,
                      style: Theme.of(context).textTheme.bodySmall!.copyWith(color: cs.onSurfaceVariant),
                    ),
                    const SizedBox(height: 14),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _restore,
                      icon: _busy
                          ? const SizedBox(
                              width: 16, height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.download_outlined, size: 18),
                      label: Text(l10n.backupRestoreButton),
                      style: OutlinedButton.styleFrom(foregroundColor: cs.error),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
