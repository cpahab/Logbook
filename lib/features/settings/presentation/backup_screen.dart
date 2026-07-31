import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../../../app/theme/theme_extensions.dart';
import '../data/backup_service.dart';
import '../../../core/widgets/card_shell.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/date_range_picker.dart';
import '../../../core/widgets/progress_snackbar.dart';
import '../../../l10n/l10n_extension.dart';
import '../../emergency/data/emergency_repository.dart';
import '../../home/data/home_repository.dart';
import '../domain/theme_provider.dart';
import 'import_conflicts_screen.dart';

/// Settings > Backup & Restore: export the active logbook (day entries,
/// tracks, crew roster, emergency contacts, reachable photos) — all of it,
/// or just a date range — to a single `.zip`, and restore one back, either
/// replacing everything or only adding/updating day entries.
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
  DateTimeRange? _exportRange;
  BackupImportMode _importMode = BackupImportMode.replace;
  DateTimeRange? _updateRange;
  // "Update" mode's day-entry handling (additions/newer-wins/conflict
  // review) always runs; these three opt-ins additionally replace the crew
  // roster, vessel/settings info, and/or emergency contacts wholesale from
  // the backup — off by default, so update mode's existing "never touches
  // anything but day entries" behavior is unchanged unless explicitly
  // requested.
  bool _syncRoster = false;
  bool _syncSettings = false;
  bool _syncEmergency = false;

  Future<void> _pickExportRange() async {
    final range = await pickDateRange(context, initialRange: _exportRange);
    if (range == null) return;
    setState(() => _exportRange = range);
  }

  Future<void> _pickUpdateRange() async {
    final range = await pickDateRange(context, initialRange: _updateRange);
    if (range == null) return;
    setState(() => _updateRange = range);
  }

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
        dateRange: _exportRange,
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
    final rawBytes = result.files.single.bytes;
    if (rawBytes == null || rawBytes.isEmpty) return;
    final bytes = Uint8List.fromList(rawBytes);

    if (!mounted) return;

    if (_importMode == BackupImportMode.replace) {
      await _restoreReplace(bytes);
    } else {
      await _restoreUpdate(bytes);
    }
  }

  Future<void> _restoreReplace(Uint8List bytes) async {
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
        zipBytes: bytes,
        home: home,
        emergency: emergency,
        theme: theme,
        mode: BackupImportMode.replace,
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

  /// "Update" mode never applies anything silently — this previews the
  /// backup against current local data first (read-only, nothing written
  /// yet); if any day is a genuine conflict (present in both), the user
  /// resolves each one explicitly on [ImportConflictsScreen] before
  /// anything is actually applied. Pure additions never need a decision,
  /// so a backup with none is still confirmed (a plain, non-destructive
  /// dialog) before applying — but there's nothing ambiguous to show.
  Future<void> _restoreUpdate(Uint8List bytes) async {
    final l10n = context.l10n;
    setState(() => _busy = true);
    final home = context.read<HomeRepository>();
    final theme = context.read<ThemeProvider>();
    final emergency = context.read<EmergencyRepository>();
    final messenger = ScaffoldMessenger.of(context);

    final UpdatePreview preview;
    try {
      preview = await BackupService.previewUpdate(zipBytes: bytes, home: home, dateRange: _updateRange);
    } on BackupFormatException catch (e) {
      if (!mounted) return;
      final message = e.message == 'backupSchemaTooNew'
          ? l10n.backupRestoreSchemaTooNew
          : l10n.backupRestoreInvalidFile;
      messenger.showSnackBar(SnackBar(content: Text(message)));
      setState(() => _busy = false);
      return;
    } catch (e, st) {
      if (kDebugMode) debugPrint('BackupScreen preview failed: $e\n$st');
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(l10n.backupRestoreError)));
      setState(() => _busy = false);
      return;
    }

    List<ConflictResolution>? resolutions = const [];
    if (preview.conflicts.isNotEmpty) {
      if (!mounted) return;
      setState(() => _busy = false); // screen has its own nav; not "busy" while shown
      resolutions = await showImportConflictsScreen(context, preview.conflicts);
      if (resolutions == null || !mounted) return;
      setState(() => _busy = true);
    } else {
      if (!mounted) return;
      final confirmed = await showConfirmDialog(
        context,
        title: l10n.backupUpdateConfirmTitle,
        body: l10n.backupUpdateConfirmBody,
        confirmLabel: l10n.backupRestoreButton,
        destructive: false,
      );
      if (!confirmed || !mounted) {
        setState(() => _busy = false);
        return;
      }
    }

    showProgressSnackBar(context, l10n.backupRestoreInProgress);
    try {
      await BackupService.applyUpdate(
        home: home,
        additions: preview.additions,
        conflicts: preview.conflicts,
        resolutions: resolutions,
        photoBytesByFilename: preview.photoBytesByFilename,
      );
      if (_syncRoster) {
        await BackupService.applyUpdateRoster(home: home, roster: preview.roster);
      }
      if (_syncSettings) {
        await BackupService.applyUpdateSettings(theme: theme, vessel: preview.vessel);
      }
      if (_syncEmergency) {
        await BackupService.applyUpdateContacts(emergency: emergency, contacts: preview.contacts);
      }
      messenger.hideCurrentSnackBar();
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(l10n.backupRestoreSuccess)));
    } catch (e, st) {
      if (kDebugMode) debugPrint('BackupScreen apply failed: $e\n$st');
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
                    _segmentedToggle(cs, children: [
                      _segment(
                        label: l10n.backupExportRangeAll,
                        active: _exportRange == null,
                        onTap: () => setState(() => _exportRange = null),
                        cs: cs,
                      ),
                      _segment(
                        label: _exportRange == null
                            ? l10n.backupExportRangeCustom
                            : '${DateFormat('d.M.yy').format(_exportRange!.start)}–${DateFormat('d.M.yy').format(_exportRange!.end)}',
                        active: _exportRange != null,
                        onTap: _pickExportRange,
                        cs: cs,
                      ),
                    ]),
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
                    _segmentedToggle(cs, children: [
                      _segment(
                        label: l10n.backupImportModeReplace,
                        active: _importMode == BackupImportMode.replace,
                        onTap: () => setState(() => _importMode = BackupImportMode.replace),
                        cs: cs,
                      ),
                      _segment(
                        label: l10n.backupImportModeUpdate,
                        active: _importMode == BackupImportMode.update,
                        onTap: () => setState(() => _importMode = BackupImportMode.update),
                        cs: cs,
                      ),
                    ]),
                    const SizedBox(height: 8),
                    Text(
                      _importMode == BackupImportMode.replace
                          ? l10n.backupImportModeReplaceDesc
                          : l10n.backupImportModeUpdateDesc,
                      style: Theme.of(context).textTheme.bodySmall!.copyWith(color: cs.onSurfaceVariant),
                    ),
                    if (_importMode == BackupImportMode.update) ...[
                      const SizedBox(height: 12),
                      _segmentedToggle(cs, children: [
                        _segment(
                          label: l10n.backupExportRangeAll,
                          active: _updateRange == null,
                          onTap: () => setState(() => _updateRange = null),
                          cs: cs,
                        ),
                        _segment(
                          label: _updateRange == null
                              ? l10n.backupExportRangeCustom
                              : '${DateFormat('d.M.yy').format(_updateRange!.start)}–${DateFormat('d.M.yy').format(_updateRange!.end)}',
                          active: _updateRange != null,
                          onTap: _pickUpdateRange,
                          cs: cs,
                        ),
                      ]),
                      CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        value: _syncRoster,
                        onChanged: (v) => setState(() => _syncRoster = v ?? false),
                        title: Text(l10n.backupSyncRosterLabel,
                            style: Theme.of(context).textTheme.bodySmall),
                      ),
                      CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        value: _syncSettings,
                        onChanged: (v) => setState(() => _syncSettings = v ?? false),
                        title: Text(l10n.backupSyncSettingsLabel,
                            style: Theme.of(context).textTheme.bodySmall),
                      ),
                      CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        value: _syncEmergency,
                        onChanged: (v) => setState(() => _syncEmergency = v ?? false),
                        title: Text(l10n.backupSyncEmergencyLabel,
                            style: Theme.of(context).textTheme.bodySmall),
                      ),
                    ],
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
                      style: OutlinedButton.styleFrom(
                          foregroundColor: _importMode == BackupImportMode.replace ? cs.error : cs.primary),
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

  /// Two-segment pill toggle — same visual language as the theme/language
  /// selectors in settings_screen.dart's `_themeButton`/`_langButton`.
  Widget _segmentedToggle(ColorScheme cs, {required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(children: children),
    );
  }

  Widget _segment({
    required String label,
    required bool active,
    required VoidCallback onTap,
    required ColorScheme cs,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          decoration: BoxDecoration(
            color: active ? cs.surfaceContainerLowest : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            boxShadow: active
                ? [
                    BoxShadow(
                      color: cs.shadow.withValues(alpha: 0.06),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                color: active ? cs.primary : cs.onSurfaceVariant),
          ),
        ),
      ),
    );
  }
}
