import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/services/auth_service.dart';
import '../../../core/services/logbook_service.dart';
import '../../../core/services/firestore_service.dart';
import '../../../core/services/storage_service.dart';
import '../../emergency/data/emergency_repository.dart';
import '../../home/data/home_repository.dart';
import '../../home/utils/filter_settings.dart';
import '../../home/widgets/nav_bar.dart';
import '../domain/theme_provider.dart';
import '../../../l10n/l10n_extension.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _vesselNameCtrl;
  late TextEditingController _vesselMmsiCtrl;
  late TextEditingController _vesselCallSignCtrl;
  bool _syncing = false;
  bool _trackFilterExpanded = false;
  List<Map<String, dynamic>> _logbooks = [];
  bool _loadingLogbooks = false;
  bool _guestsExpanded = false;
  Future<List<Map<String, dynamic>>>? _guestsFuture;
  late ValueNotifier<String?> _logbookIdNotifier;

  @override
  void initState() {
    super.initState();
    final p = context.read<ThemeProvider>();
    _vesselNameCtrl = TextEditingController(text: p.vesselName);
    _vesselMmsiCtrl = TextEditingController(text: p.vesselMmsi);
    _vesselCallSignCtrl = TextEditingController(text: p.vesselCallSign);
    _logbookIdNotifier = context.read<ValueNotifier<String?>>();
    // Refresh list whenever the active boat changes (e.g. async init completes)
    _logbookIdNotifier.addListener(_refreshLogbooks);
    _refreshLogbooks();
  }

  @override
  void dispose() {
    _logbookIdNotifier.removeListener(_refreshLogbooks);
    _vesselNameCtrl.dispose();
    _vesselMmsiCtrl.dispose();
    _vesselCallSignCtrl.dispose();
    super.dispose();
  }

  String _formatCode(String code) {
    if (code.length == 8) return '${code.substring(0, 4)}-${code.substring(4)}';
    return code;
  }


  Future<void> _refreshLogbooks() async {
    final user = context.read<AuthService>().currentUser;
    if (user == null || !mounted) return;
    setState(() => _loadingLogbooks = true);
    try {
      final boats = await LogbookService().listLogbooks(user.uid);
      if (mounted) setState(() { _logbooks = boats; _loadingLogbooks = false; });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingLogbooks = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.authErrorGeneric)),
      );
    }
  }

  Future<void> _reinitFirestore(String logbookId) async {
    final repo = context.read<HomeRepository>();
    final themeProvider = context.read<ThemeProvider>();
    final emergencyRepo = context.read<EmergencyRepository>();
    final notifier = context.read<ValueNotifier<String?>>();

    // Clear all per-boat local caches so the new boat's remote data always wins.
    await emergencyRepo.clearLocalData();
    await themeProvider.clearVesselSettings();
    themeProvider.resetInitialSync();

    final firestore = FirestoreService(logbookId: logbookId);
    final storage = StorageService(logbookId: logbookId);
    await repo.reattachAndSync(firestore, storage);
    await themeProvider.attachFirestore(firestore);
    await emergencyRepo.attachFirestore(firestore);
    if (mounted) notifier.value = logbookId;
  }

  Future<void> _joinLogbook(String rawCode) async {
    final l10n = context.l10n;
    final code = rawCode.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    if (code.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.settingsInvalidCode)),
      );
      return;
    }
    final user = context.read<AuthService>().currentUser;
    if (user == null) return;

    setState(() => _syncing = true);
    String? foundLogbookId;
    String? logbookName;
    try {
      foundLogbookId = await LogbookService().findByShareCode(code);
      if (foundLogbookId != null) {
        final alreadyMember =
            await LogbookService().isMember(foundLogbookId, user.uid);
        if (!mounted) return;
        if (alreadyMember) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.settingsAlreadyConnected)),
          );
          return;
        }
        logbookName = await LogbookService().getLogbookName(foundLogbookId) ?? code;
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${l10n.settingsError}: $e')),
        );
      }
      return;
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
    if (!mounted) return;

    if (foundLogbookId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.settingsCodeNotFound)),
      );
      return;
    }

    final resolvedName = logbookName ?? code;
    final resolvedId = foundLogbookId;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        final cl = ctx.l10n;
        return AlertDialog(
          titleTextStyle: TextStyle(
              color: cs.onSurface, fontSize: 20, fontWeight: FontWeight.w600),
          contentTextStyle:
              TextStyle(color: cs.onSurfaceVariant, fontSize: 14),
          title: Text(cl.settingsSwitchLogbookTitle),
          content: Text(cl.settingsJoinContent(resolvedName)),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(cl.cancel)),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(cl.connect)),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;

    setState(() => _syncing = true);
    try {
      await LogbookService().joinLogbook(resolvedId, user.uid);
      if (!mounted) return;
      await _reinitFirestore(resolvedId);
      if (mounted) {
        _guestsExpanded = false;
        _refreshLogbooks();
        FocusScope.of(context).unfocus();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.settingsJoinedLogbook(resolvedName))),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${l10n.settingsError}: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _switchLogbook(Map<String, dynamic> logbook, String uid) async {
    final l10n = context.l10n;
    final logbookId = logbook['logbookId'] as String;
    final name = logbook['name'] as String;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        final cl = ctx.l10n;
        return AlertDialog(
          titleTextStyle: TextStyle(
              color: cs.onSurface, fontSize: 20, fontWeight: FontWeight.w600),
          title: Text(cl.settingsSwitchTo(name)),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(cl.cancel)),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(cl.connect)),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;

    setState(() => _syncing = true);
    try {
      await LogbookService().setActiveLogbook(uid, logbookId);
      if (!mounted) return;
      await _reinitFirestore(logbookId);
      if (mounted) {
        _guestsExpanded = false;
        _refreshLogbooks();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.settingsConnected)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${l10n.settingsError}: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  void _showLogbookOptionsSheet(Map<String, dynamic> logbook, String uid) {
    final logbookId = logbook['logbookId'] as String;
    final name = logbook['name'] as String;
    final shareCode = logbook['shareCode'] as String? ?? '';
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
                _showRenameDialog(logbookId, name, uid);
              },
            ),
            ListTile(
              leading: Icon(Icons.qr_code, color: cs.onSurface),
              title: Text(l10n.settingsShare),
              onTap: () {
                Navigator.pop(sheetCtx);
                _showQrModal(shareCode);
              },
            ),
            ListTile(
              leading: Icon(Icons.delete_outline, color: cs.error),
              title: Text(l10n.settingsDeleteLogbook,
                  style: TextStyle(color: cs.error)),
              onTap: () {
                Navigator.pop(sheetCtx);
                _showDeleteLogbookDialog(logbookId, name, uid);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showGuestOptionsSheet(Map<String, dynamic> logbook, String uid) {
    final logbookId = logbook['logbookId'] as String;
    final name = logbook['name'] as String;
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
                _showLeaveLogbookDialog(logbookId, name, uid);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showNewLogbookDialog(String uid) async {
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
                  style: GoogleFonts.newsreader(
                    fontSize: 20,
                    fontStyle: FontStyle.italic,
                    fontWeight: FontWeight.w500,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: ctrl,
                  autofocus: true,
                  textCapitalization: TextCapitalization.words,
                  style: TextStyle(color: cs.onSurface, fontSize: 16),
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
    ctrl.dispose();
    if (name == null || name.isEmpty || !mounted) return;

    setState(() => _syncing = true);
    try {
      final newLogbookId = await LogbookService().createLogbook(uid, name);
      if (!mounted) return;
      await _reinitFirestore(newLogbookId);
      if (mounted) {
        _guestsExpanded = false;
        _refreshLogbooks();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.settingsConnected)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${l10n.settingsError}: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _showRenameDialog(
      String logbookId, String currentName, String uid) async {
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
    ctrl.dispose();
    if (newName == null || newName == currentName || !mounted) return;

    try {
      await LogbookService().renameLogbook(logbookId, newName);
      if (mounted) _refreshLogbooks();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${l10n.settingsError}: $e')),
        );
      }
    }
  }

  Future<void> _showDeleteLogbookDialog(
      String logbookId, String name, String uid) async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        final cl = ctx.l10n;
        return AlertDialog(
          backgroundColor: cs.surface,
          surfaceTintColor: Colors.transparent,
          titleTextStyle: TextStyle(color: cs.onSurface, fontSize: 18, fontWeight: FontWeight.w600),
          contentTextStyle: TextStyle(color: cs.onSurfaceVariant, fontSize: 14),
          title: Text(cl.settingsDeleteLogbook),
          content: Text(cl.settingsDeleteLogbookConfirm(name)),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(cl.cancel)),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: cs.error),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(cl.delete),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;

    setState(() => _syncing = true);
    try {
      final activeId = context.read<ValueNotifier<String?>>().value;
      await LogbookService().deleteLogbook(logbookId, uid);
      if (!mounted) return;
      if (activeId == logbookId) {
        final newActiveId = await LogbookService().getActiveLogbookId(uid);
        if (mounted && newActiveId != null) {
          await _reinitFirestore(newActiveId);
        }
      }
      if (mounted) {
        _guestsExpanded = false;
        _refreshLogbooks();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${l10n.settingsError}: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _showLeaveLogbookDialog(
      String logbookId, String name, String uid) async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        final cl = ctx.l10n;
        return AlertDialog(
          backgroundColor: cs.surface,
          surfaceTintColor: Colors.transparent,
          titleTextStyle: TextStyle(color: cs.onSurface, fontSize: 18, fontWeight: FontWeight.w600),
          contentTextStyle: TextStyle(color: cs.onSurfaceVariant, fontSize: 14),
          title: Text(cl.settingsLeaveLogbook),
          content: Text(cl.settingsLeaveLogbookConfirm(name)),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(cl.cancel)),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: cs.error),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(cl.remove),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;

    setState(() => _syncing = true);
    try {
      final activeId = context.read<ValueNotifier<String?>>().value;
      await LogbookService().removeMember(logbookId, uid);
      if (!mounted) return;
      if (activeId == logbookId) {
        final newActiveId = await LogbookService().getActiveLogbookId(uid);
        if (mounted && newActiveId != null) {
          await _reinitFirestore(newActiveId);
        }
      }
      if (mounted) {
        _guestsExpanded = false;
        _refreshLogbooks();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${l10n.settingsError}: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  void _showQrModal(String shareCode) {
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
                    style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface)),
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
                  _formatCode(shareCode),
                  style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: cs.onSurface,
                      letterSpacing: 6),
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

  void _showConnectSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        height: MediaQuery.of(ctx).size.height * 0.75,
        decoration: BoxDecoration(
          color: Theme.of(ctx).colorScheme.surface,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: _ConnectBottomSheet(onCode: _joinLogbook),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<ThemeProvider>();
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/'),
        ),
        automaticallyImplyLeading: false,
      ),
      bottomNavigationBar: AppBottomNav(
        active: NavTab.settings,
        showFab: false,
        onSelect: (tab) {
          if (tab == NavTab.journal) context.go('/');
          if (tab == NavTab.map) context.go('/tracks');
          if (tab == NavTab.safety) context.go('/emergency');
        },
      ),
      body: RefreshIndicator(
        onRefresh: _refreshLogbooks,
        child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Page header ───────────────────────────────────────────
            Text(
              l10n.settingsTitle,
              style: GoogleFonts.newsreader(
                fontSize: 24,
                fontWeight: FontWeight.w500,
                letterSpacing: -0.24,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              l10n.settingsSubtitle,
              style: GoogleFonts.inter(
                fontSize: 15,
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),

            // ── Account ───────────────────────────────────────────────
            _buildAccountSection(cs),
            const SizedBox(height: 16),

            // ── Vessel Information ────────────────────────────────────
            _buildVesselSection(p, cs),
            const SizedBox(height: 16),

            // ── Display & Appearance ──────────────────────────────────
            _buildDisplaySection(p, cs),
            const SizedBox(height: 16),

            // ── Track Filter ──────────────────────────────────────────
            _buildTrackFilterSection(p, cs),
            const SizedBox(height: 16),

            // ── Crew Roster ───────────────────────────────────────────
            _buildCrewRosterSection(cs),
            const SizedBox(height: 16),

            // ── Logbooks ──────────────────────────────────────────────
            _buildLogbooksSection(cs),
            const SizedBox(height: 32),

          ],
        ),
      ),
      ),
    );
  }

  // ── Vessel Information ──────────────────────────────────────────────
  Widget _buildVesselSection(ThemeProvider p, ColorScheme cs) {
    final l10n = context.l10n;
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          children: [
            Positioned(
              left: 0, top: 0, bottom: 0,
              child: Container(width: 4, color: cs.onTertiaryFixedVariant),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        context.l10n.settingsVesselSection.toUpperCase(),
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.5,
                          color: cs.secondary,
                        ),
                      ),
                      Icon(Icons.directions_boat_outlined,
                          size: 20, color: cs.outlineVariant),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _vesselRow(
                    label: l10n.settingsFieldName,
                    controller: _vesselNameCtrl,
                    hint: l10n.settingsFieldNameHint,
                    onChanged: p.setVesselName,
                    cs: cs,
                  ),
                  _rowDivider(cs),
                  _vesselRow(
                    label: 'MMSI',
                    controller: _vesselMmsiCtrl,
                    hint: '123456789',
                    onChanged: p.setVesselMmsi,
                    keyboard: TextInputType.number,
                    cs: cs,
                  ),
                  _rowDivider(cs),
                  _vesselRow(
                    label: l10n.settingsFieldCallSign,
                    controller: _vesselCallSignCtrl,
                    hint: l10n.settingsFieldCallSignHint,
                    onChanged: p.setVesselCallSign,
                    cs: cs,
                    isLast: true,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _vesselRow({
    required String label,
    required TextEditingController controller,
    required String hint,
    required ValueChanged<String> onChanged,
    required ColorScheme cs,
    TextInputType keyboard = TextInputType.text,
    bool isLast = false,
  }) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 8),
      child: Row(
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 15,
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: TextField(
              controller: controller,
              textAlign: TextAlign.right,
              keyboardType: keyboard,
              textInputAction: TextInputAction.next,
              style: GoogleFonts.newsreader(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
              decoration: InputDecoration(
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
                hintText: hint,
                hintStyle: GoogleFonts.inter(
                  fontSize: 15,
                  color: cs.outline.withValues(alpha: 0.5),
                ),
              ),
              onChanged: onChanged,
              onSubmitted: (_) => FocusScope.of(context).unfocus(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _rowDivider(ColorScheme cs) => Divider(
        color: cs.surfaceContainerHigh,
        height: 16,
        thickness: 1,
      );

  // ── Display & Appearance ────────────────────────────────────────────
  Widget _buildDisplaySection(ThemeProvider p, ColorScheme cs) {
    final l10n = context.l10n;
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                l10n.settingsAppearanceSection.toUpperCase(),
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                  color: cs.secondary,
                ),
              ),
              Icon(Icons.palette_outlined,
                  size: 20, color: cs.outlineVariant),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            l10n.settingsThemeLabel,
            style: GoogleFonts.inter(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: cs.surfaceContainerLow,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                _themeButton(l10n.settingsThemeSystem, ThemeMode.system, p, cs),
                _themeButton(l10n.settingsThemeLight, ThemeMode.light, p, cs),
                _themeButton(l10n.settingsThemeDark, ThemeMode.dark, p, cs),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            l10n.settingsLanguageLabel,
            style: GoogleFonts.inter(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: cs.surfaceContainerLow,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                _langButton(l10n.settingsLanguageDe, const Locale('de'), p, cs),
                _langButton(l10n.settingsLanguageEn, const Locale('en'), p, cs),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _themeButton(
      String label, ThemeMode mode, ThemeProvider p, ColorScheme cs) {
    final isActive = p.themeMode == mode;
    return Expanded(
      child: GestureDetector(
        onTap: () => p.setThemeMode(mode),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isActive ? cs.surfaceContainerLowest : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
              color: isActive ? cs.primary : cs.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }

  Widget _langButton(
      String label, Locale locale, ThemeProvider p, ColorScheme cs) {
    final isActive = p.locale == locale;
    return Expanded(
      child: GestureDetector(
        onTap: () => p.setLocale(locale),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isActive ? cs.surfaceContainerLowest : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
              color: isActive ? cs.primary : cs.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }

  bool _filterIsModified(ThemeProvider p) =>
      p.filterMode != StationaryMode.speed ||
      p.minStopMinutes != 5.0 ||
      p.maxStopSpreadM != 30.0 ||
      p.detectColdStart != true ||
      p.coldStartSettleFactor != 3.0 ||
      p.makingWayThresholdKn != 1.0 ||
      p.topSpeedPercentile != 0.99;

  // ── Track Filter ────────────────────────────────────────────────────
  Widget _buildTrackFilterSection(ThemeProvider p, ColorScheme cs) {
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header (always visible, tap to expand) ────────────
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => setState(() => _trackFilterExpanded = !_trackFilterExpanded),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              child: Row(
                children: [
                  Text(
                    context.l10n.settingsTrackFilterSection.toUpperCase(),
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.5,
                      color: cs.secondary,
                    ),
                  ),
                  if (_filterIsModified(p)) ...[
                    const SizedBox(width: 6),
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: cs.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                  const Spacer(),
                  if (!_trackFilterExpanded)
                    Text(
                      p.filterMode == StationaryMode.speed
                          ? context.l10n.settingsFilterModeMooring
                          : context.l10n.settingsFilterModeExact,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  const SizedBox(width: 8),
                  AnimatedRotation(
                    turns: _trackFilterExpanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(Icons.expand_more,
                        size: 20, color: cs.outlineVariant),
                  ),
                ],
              ),
            ),
          ),
          // ── Expandable content ────────────────────────────────
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 220),
            crossFadeState: _trackFilterExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            firstChild: const SizedBox(width: double.infinity),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Divider(color: cs.surfaceContainerHigh, height: 1, thickness: 1),
                  const SizedBox(height: 12),
                  Text(
                    context.l10n.settingsStationaryLabel,
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    context.l10n.settingsStationaryDesc,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        _filterModeButton(
                          label: context.l10n.settingsFilterModeMooring,
                          mode: StationaryMode.speed,
                          current: p.filterMode,
                          onTap: () => p.setFilterMode(StationaryMode.speed),
                          cs: cs,
                        ),
                        _filterModeButton(
                          label: context.l10n.settingsFilterModeExact,
                          mode: StationaryMode.both,
                          current: p.filterMode,
                          onTap: () => p.setFilterMode(StationaryMode.both),
                          cs: cs,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    p.filterMode == StationaryMode.speed
                        ? context.l10n.settingsMooringDesc
                        : context.l10n.settingsExactPositionDesc,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  _rowDivider(cs),
                  // ── Min. stop duration ──────────────────────────
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        context.l10n.settingsMinStopLabel,
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface,
                        ),
                      ),
                      Text(
                        '${p.minStopMinutes.round()} ${context.l10n.settingsMinUnit}',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: cs.primary,
                        ),
                      ),
                    ],
                  ),
                  Slider(
                    value: p.minStopMinutes,
                    min: 1,
                    max: 30,
                    divisions: 29,
                    onChanged: p.setMinStopMinutes,
                  ),
                  Text(
                    context.l10n.settingsMinStopDesc,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  _rowDivider(cs),
                  // ── Max anchor swing ────────────────────────────
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        context.l10n.settingsMaxAnchorLabel,
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface,
                        ),
                      ),
                      Text(
                        '${p.maxStopSpreadM.round()} ${context.l10n.settingsMetersUnit}',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: cs.primary,
                        ),
                      ),
                    ],
                  ),
                  Slider(
                    value: p.maxStopSpreadM,
                    min: 10,
                    max: 100,
                    divisions: 18,
                    onChanged: p.setMaxStopSpreadM,
                  ),
                  Text(
                    context.l10n.settingsMaxAnchorDesc,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  _rowDivider(cs),
                  // ── Cold-start trimming ─────────────────────────
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        context.l10n.settingsColdStartLabel,
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface,
                        ),
                      ),
                      Switch(
                        value: p.detectColdStart,
                        onChanged: p.setDetectColdStart,
                      ),
                    ],
                  ),
                  Text(
                    context.l10n.settingsColdStartDesc,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  if (p.detectColdStart) ...[
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          context.l10n.settingsTrimSharpnessLabel,
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: cs.onSurface,
                          ),
                        ),
                        Text(
                          p.coldStartSettleFactor.toStringAsFixed(1),
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: cs.primary,
                          ),
                        ),
                      ],
                    ),
                    Slider(
                      value: p.coldStartSettleFactor,
                      min: 1.0,
                      max: 6.0,
                      divisions: 10,
                      onChanged: p.setColdStartSettleFactor,
                    ),
                    Text(
                      context.l10n.settingsTrimSharpnessDesc,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                  _rowDivider(cs),
                  // ── Underway threshold ──────────────────────────
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        context.l10n.settingsUnderwayLabel,
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface,
                        ),
                      ),
                      Text(
                        '${p.makingWayThresholdKn.toStringAsFixed(1)} kn',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: cs.primary,
                        ),
                      ),
                    ],
                  ),
                  Slider(
                    value: p.makingWayThresholdKn,
                    min: 0.3,
                    max: 3.0,
                    divisions: 27,
                    onChanged: p.setMakingWayThresholdKn,
                  ),
                  Text(
                    context.l10n.settingsUnderwayDesc,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  _rowDivider(cs),
                  // ── Max-speed percentile ────────────────────────
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        context.l10n.settingsPercentileLabel,
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface,
                        ),
                      ),
                      Text(
                        'p${(p.topSpeedPercentile * 100).round()}',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: cs.primary,
                        ),
                      ),
                    ],
                  ),
                  Slider(
                    value: p.topSpeedPercentile,
                    min: 0.90,
                    max: 1.00,
                    divisions: 10,
                    onChanged: p.setTopSpeedPercentile,
                  ),
                  Text(
                    context.l10n.settingsPercentileDesc,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  _rowDivider(cs),
                  // ── Raw track overlay ───────────────────────────
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        context.l10n.settingsShowRawTrackLabel,
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface,
                        ),
                      ),
                      Switch(
                        value: p.showRawTrack,
                        onChanged: p.setShowRawTrack,
                      ),
                    ],
                  ),
                  Text(
                    context.l10n.settingsShowRawTrackDesc,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  if (_filterIsModified(p)) ...[
                    _rowDivider(cs),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: p.resetFilterDefaults,
                        icon: Icon(Icons.restart_alt,
                            size: 16, color: cs.onSurfaceVariant),
                        label: Text(
                          context.l10n.reset,
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterModeButton({
    required String label,
    required StationaryMode mode,
    required StationaryMode current,
    required VoidCallback onTap,
    required ColorScheme cs,
  }) {
    final isActive = current == mode;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isActive ? cs.surfaceContainerLowest : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
              color: isActive ? cs.primary : cs.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }

  // ── Crew Roster ──────────────────────────────────────────────────────
  Widget _buildCrewRosterSection(ColorScheme cs) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => context.push('/settings/crew-roster'),
      child: Container(
        decoration: BoxDecoration(
          color: cs.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            children: [
              Positioned(
                left: 0, top: 0, bottom: 0,
                child: Container(width: 4, color: cs.tertiaryContainer),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 16, 14),
                child: Row(
                  children: [
                    Icon(Icons.people_outline, size: 20, color: cs.tertiary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            context.l10n.settingsCrewSection.toUpperCase(),
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.5,
                              color: cs.secondary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Consumer<HomeRepository>(
                            builder: (_, repo, _) {
                              final count = repo.roster.length;
                              return Text(
                                count == 0
                                    ? context.l10n.settingsNoEntries
                                    : '$count ${context.l10n.settingsPersonCount(count)}',
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  color: cs.onSurfaceVariant,
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right, color: cs.outlineVariant),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Logbooks ─────────────────────────────────────────────────────────
  Widget _buildLogbooksSection(ColorScheme cs) {
    final l10n = context.l10n;
    final auth = context.watch<AuthService>();
    if (auth.currentUser == null) return const SizedBox.shrink();

    final uid = auth.currentUser!.uid;
    final activeLogbookId = context.watch<ValueNotifier<String?>>().value;
    final activeMeta = _logbooks.firstWhere(
      (b) => b['logbookId'] == activeLogbookId,
      orElse: () => {},
    );
    final isActiveOwner = activeMeta['role'] == 'owner';

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                l10n.settingsLogbooksSection.toUpperCase(),
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                  color: cs.secondary,
                ),
              ),
              Tooltip(
                message: l10n.settingsNewLogbook,
                child: GestureDetector(
                  onTap: _syncing ? null : () => _showNewLogbookDialog(uid),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: cs.surfaceContainer,
                    ),
                    child: Icon(Icons.add, size: 18, color: cs.secondary),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_loadingLogbooks)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Center(
                  child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))),
            )
          else if (_logbooks.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(l10n.settingsNoLogbooks,
                  style: GoogleFonts.inter(
                      fontSize: 13, color: cs.onSurfaceVariant)),
            )
          else
            ...(_logbooks.map((logbook) => _buildBoatRow(logbook, activeLogbookId, cs, uid))),
          if (activeLogbookId != null && isActiveOwner && activeMeta.isNotEmpty) ...[
            const SizedBox(height: 20),
            _buildShareSection(activeMeta, cs, uid),
          ],
        ],
      ),
    );
  }

  Widget _buildBoatRow(Map<String, dynamic> logbook, String? activeLogbookId,
      ColorScheme cs, String uid) {
    final logbookId = logbook['logbookId'] as String;
    final name = logbook['name'] as String;
    final role = logbook['role'] as String;
    final isActive = logbookId == activeLogbookId;
    final isOwner = role == 'owner';
    final l10n = context.l10n;

    return InkWell(
      onTap: isActive || _syncing ? null : () => _switchLogbook(logbook, uid),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isActive
                    ? cs.primary
                    : cs.outlineVariant.withValues(alpha: 0.4),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      fontWeight:
                          isActive ? FontWeight.w700 : FontWeight.w500,
                      color: cs.onSurface,
                    ),
                  ),
                  Text(
                    isOwner ? l10n.settingsRoleOwner : l10n.settingsRoleGuest,
                    style: GoogleFonts.inter(
                        fontSize: 12, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            if (isActive) Icon(Icons.check, size: 18, color: cs.primary),
            IconButton(
              icon: Icon(Icons.more_vert, size: 18, color: cs.outlineVariant),
              onPressed: () => isOwner
                  ? _showLogbookOptionsSheet(logbook, uid)
                  : _showGuestOptionsSheet(logbook, uid),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShareSection(
      Map<String, dynamic> activeMeta, ColorScheme cs, String uid) {
    final l10n = context.l10n;
    final shareCode = activeMeta['shareCode'] as String? ?? '';
    final logbookId = activeMeta['logbookId'] as String;
    final logbookName = activeMeta['name'] as String? ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                '$logbookName · ${l10n.settingsShare}'.toUpperCase(),
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                  color: cs.secondary,
                ),
              ),
            ),
            Icon(Icons.share_outlined, size: 20, color: cs.outlineVariant),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  _formatCode(shareCode),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: cs.onPrimaryContainer,
                    letterSpacing: 6,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: () {
                Clipboard.setData(
                    ClipboardData(text: _formatCode(shareCode)));
                ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(l10n.settingsCodeCopied)));
              },
              icon: const Icon(Icons.copy_outlined),
              tooltip: l10n.copy,
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _showQrModal(shareCode),
                icon: const Icon(Icons.qr_code, size: 18),
                label: Text(l10n.settingsShowQrCode),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: cs.outlineVariant),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                  textStyle: GoogleFonts.inter(fontSize: 13),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _syncing ? null : _showConnectSheet,
                icon: const Icon(Icons.qr_code_scanner, size: 18),
                label: Text(l10n.settingsScanOrEnterCode),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: cs.outlineVariant),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                  textStyle: GoogleFonts.inter(fontSize: 13),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _buildManageGuests(logbookId, cs, uid),
      ],
    );
  }

  Widget _buildManageGuests(String logbookId, ColorScheme cs, String uid) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () {
            setState(() {
              _guestsExpanded = !_guestsExpanded;
              if (_guestsExpanded) {
                _guestsFuture = LogbookService().listMembers(logbookId);
              }
            });
          },
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding:
                const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.settingsManageGuests,
                    style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface),
                  ),
                ),
                Icon(
                  _guestsExpanded
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  color: cs.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
        if (_guestsExpanded) ...[
          const SizedBox(height: 8),
          FutureBuilder<List<Map<String, dynamic>>>(
            future: _guestsFuture,
            builder: (ctx, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(
                    child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2)));
              }
              final members = (snap.data ?? [])
                  .where((m) => m['role'] != 'owner')
                  .toList();
              if (members.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Text(l10n.settingsNoGuests,
                      style: GoogleFonts.inter(
                          fontSize: 13, color: cs.onSurfaceVariant)),
                );
              }
              return Column(
                children: members.map((m) {
                  final memberUid = m['uid'] as String? ?? '';
                  final shortId = memberUid.length > 8
                      ? memberUid.substring(0, 8)
                      : memberUid;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Icon(Icons.person_outline,
                            size: 16, color: cs.onSurfaceVariant),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text('…$shortId',
                              style: GoogleFonts.inter(
                                  fontSize: 13, color: cs.onSurface)),
                        ),
                        TextButton(
                          style: TextButton.styleFrom(
                            foregroundColor: cs.error,
                            padding: EdgeInsets.zero,
                            visualDensity: VisualDensity.compact,
                          ),
                          onPressed: () async {
                            await LogbookService()
                                .removeMember(logbookId, memberUid);
                            if (mounted) {
                              setState(() {
                                _guestsFuture =
                                    LogbookService().listMembers(logbookId);
                              });
                            }
                          },
                          child: Text(l10n.remove),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ],
    );
  }

  // ── Account ──────────────────────────────────────────────────────────
  Widget _buildAccountSection(ColorScheme cs) {
    final l10n = context.l10n;
    final user = context.watch<AuthService>().currentUser;

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                l10n.settingsAccountSection.toUpperCase(),
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                  color: cs.secondary,
                ),
              ),
              Icon(Icons.person_outline, size: 20, color: cs.outlineVariant),
            ],
          ),
          const SizedBox(height: 12),
          if (user != null) ...[
            Text(
              l10n.settingsAccountSignedInAs,
              style: GoogleFonts.inter(
                fontSize: 13,
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              user.email ?? user.displayName ?? '',
              style: GoogleFonts.inter(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () async {
                  final results = await Connectivity().checkConnectivity();
                  final isOffline = results.every(
                      (r) => r == ConnectivityResult.none);
                  if (!mounted) return;
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      backgroundColor: cs.surface,
                      surfaceTintColor: Colors.transparent,
                      titleTextStyle: TextStyle(color: cs.onSurface, fontSize: 18, fontWeight: FontWeight.w600),
                      contentTextStyle: TextStyle(color: cs.onSurfaceVariant, fontSize: 14),
                      title: Text(l10n.authSignOut),
                      content: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(l10n.authSignOutConfirmDesc),
                          if (isOffline) ...[
                            const SizedBox(height: 12),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(Icons.wifi_off, size: 14,
                                    color: cs.error),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    l10n.authSignOutOfflineWarning,
                                    style: TextStyle(
                                        color: cs.error, fontSize: 13),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: Text(l10n.cancel),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: Text(l10n.authSignOut,
                              style: TextStyle(color: cs.error)),
                        ),
                      ],
                    ),
                  );
                  if (confirmed == true && mounted) {
                    await context.read<AuthService>().signOut();
                  }
                },
                icon: Icon(Icons.logout, size: 18, color: cs.error),
                label: Text(l10n.authSignOut,
                    style: GoogleFonts.inter(
                        fontSize: 14, color: cs.error)),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: cs.outlineVariant),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                style: TextButton.styleFrom(foregroundColor: cs.error),
                onPressed: _syncing
                    ? null
                    : () async {
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (ctx) {
                            final dcs = Theme.of(ctx).colorScheme;
                            return AlertDialog(
                              backgroundColor: dcs.surface,
                              surfaceTintColor: Colors.transparent,
                              title: Text(l10n.authDeleteAccount,
                                  style: TextStyle(color: dcs.onSurface)),
                              content: Text(l10n.authDeleteAccountConfirm,
                                  style: TextStyle(color: dcs.onSurfaceVariant)),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: Text(l10n.cancel),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, true),
                                  child: Text(l10n.authDeleteAccount,
                                      style: TextStyle(color: dcs.error)),
                                ),
                              ],
                            );
                          },
                        );
                        if (confirmed != true || !mounted) return;

                        // Block deletion when offline — Firestore cleanup would
                        // fail silently and the Auth account would still be deleted.
                        final connResults = await Connectivity().checkConnectivity();
                        if (!mounted) return;
                        if (connResults.every((r) => r == ConnectivityResult.none)) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(l10n.authErrorNetworkFailed)),
                          );
                          return;
                        }

                        setState(() => _syncing = true);
                        // Capture refs before any await.
                        final repo = context.read<HomeRepository>();
                        final emergencyRepo = context.read<EmergencyRepository>();
                        final themeProvider = context.read<ThemeProvider>();
                        final authService = context.read<AuthService>();
                        final uid = user.uid;

                        // 1. Delete all Firestore data. Abort if any cleanup fails —
                        //    do NOT delete the Auth account and leave orphaned data.
                        try {
                          await LogbookService().deleteUserAndAllLogbooks(uid);
                        } catch (_) {
                          if (!mounted) return;
                          setState(() => _syncing = false);
                          await showDialog<void>(
                            context: context,
                            builder: (ctx) {
                              final dcs = Theme.of(ctx).colorScheme;
                              return AlertDialog(
                                backgroundColor: dcs.surface,
                                surfaceTintColor: Colors.transparent,
                                icon: Icon(Icons.cloud_off_rounded,
                                    color: dcs.error),
                                title: Text(
                                  l10n.authDeleteCleanupFailedTitle,
                                  style: GoogleFonts.newsreader(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                    color: dcs.onSurface,
                                  ),
                                ),
                                content: Text(
                                  l10n.authDeleteCleanupFailedBody,
                                  style: TextStyle(
                                    fontSize: 14,
                                    height: 1.5,
                                    color: dcs.onSurfaceVariant,
                                  ),
                                ),
                                actions: [
                                  FilledButton(
                                    onPressed: () => Navigator.pop(ctx),
                                    child: Text(l10n.done),
                                  ),
                                ],
                              );
                            },
                          );
                          return;
                        }

                        // 2. Wipe all local caches.
                        await repo.clearLocalData();
                        await emergencyRepo.clearLocalData();
                        await themeProvider.clearVesselSettings();
                        themeProvider.resetInitialSync();

                        // 3. Delete the Firebase Auth account only if Firestore
                        //    cleanup succeeded. Router redirect to /auth/login
                        //    happens automatically via authService.notifyListeners().
                        try {
                          await authService.deleteAccount();
                        } on FirebaseAuthException catch (e) {
                          if (!mounted) return;
                          setState(() => _syncing = false);
                          final msg = e.code == 'requires-recent-login'
                              ? l10n.authErrorRequiresRecentLogin
                              : (e.message ?? l10n.authErrorGeneric);
                          ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(msg)));
                        } catch (_) {
                          if (mounted) setState(() => _syncing = false);
                        }
                      },
                child: Text(l10n.authDeleteAccount),
              ),
            ),
          ] else ...[
            Text(
              l10n.settingsAccountNotSignedIn,
              style: GoogleFonts.inter(
                fontSize: 13,
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => context.push('/auth/login'),
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                child: Text(l10n.settingsAccountManage,
                    style: GoogleFonts.inter(
                        fontSize: 14, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Connect bottom sheet (scan / enter code) ─────────────────────────────────

class _ConnectBottomSheet extends StatefulWidget {
  final Future<void> Function(String code) onCode;
  const _ConnectBottomSheet({required this.onCode});

  @override
  State<_ConnectBottomSheet> createState() => _ConnectBottomSheetState();
}

class _ConnectBottomSheetState extends State<_ConnectBottomSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final MobileScannerController _scanCtrl = MobileScannerController();
  final TextEditingController _codeCtrl = TextEditingController();
  bool _scanHandled = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) return;
      if (_tabController.index == 0) {
        _scanHandled = false;
        _scanCtrl.start();
      } else {
        _scanCtrl.stop();
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _scanCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_scanHandled) return;
    final raw = capture.barcodes.firstOrNull?.rawValue;
    if (raw == null || raw.isEmpty) return;
    _scanHandled = true;
    const scheme = 'logbook://join/';
    final code = raw.startsWith(scheme) ? raw.substring(scheme.length) : raw;
    Navigator.pop(context);
    widget.onCode(code);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;

    return Column(
      children: [
        const SizedBox(height: 8),
        Container(
          width: 36,
          height: 4,
          decoration: BoxDecoration(
              color: cs.outlineVariant,
              borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(height: 8),
        TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: l10n.settingsScanTitle),
            Tab(text: l10n.settingsEnterInviteCode),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              // Scan tab
              Padding(
                padding: const EdgeInsets.all(16),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child:
                      MobileScanner(controller: _scanCtrl, onDetect: _onDetect),
                ),
              ),
              // Enter code tab
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 8),
                    TextField(
                      controller: _codeCtrl,
                      textCapitalization: TextCapitalization.characters,
                      style: TextStyle(color: cs.onSurface),
                      decoration: InputDecoration(
                        hintText: l10n.settingsEnterInviteCode,
                        hintStyle: TextStyle(color: cs.onSurfaceVariant),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8)),
                        enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide:
                                BorderSide(color: cs.outlineVariant)),
                        focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: cs.primary, width: 2)),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        filled: true,
                        fillColor: cs.surfaceContainerLow,
                      ),
                      onSubmitted: (v) {
                        if (v.trim().isNotEmpty) {
                          Navigator.pop(context);
                          widget.onCode(v);
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: () {
                        final code = _codeCtrl.text;
                        if (code.trim().isNotEmpty) {
                          Navigator.pop(context);
                          widget.onCode(code);
                        }
                      },
                      child: Text(l10n.connect),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
