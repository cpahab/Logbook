import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../../../core/services/auth_service.dart';
import '../../../core/services/local_logbook_service.dart';
import '../../../core/services/logbook_service.dart';
import '../../emergency/data/emergency_repository.dart';
import '../../home/data/home_repository.dart';
import '../../home/utils/filter_settings.dart';
import '../../../core/widgets/card_shell.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/nav_bar.dart';
import '../../../core/widgets/progress_snackbar.dart';
import '../../../app/theme/theme_extensions.dart';
import '../domain/theme_provider.dart';
import '../../../app/route_names.dart';
import '../../../l10n/l10n_extension.dart';
import '../utils/logbook_switch.dart';
import '../utils/settings_format_utils.dart';
import '../widgets/connect_bottom_sheet.dart';
import '../widgets/delete_account_dialog.dart';
import '../widgets/equipment_slot_editor.dart';
import '../widgets/local_logbook_dialogs.dart';
import '../widgets/logbook_actions.dart';
import '../widgets/vessel_section.dart';
import '../widgets/logbook_dialogs.dart';

/// The app's Settings screen: vessel/VHF info, display preferences (theme,
/// locale, units), GPS track-filter tuning, crew roster shortcut, multi-boat
/// logbook management (create/join/switch/share/leave/delete, guest
/// management via share code or QR), and account actions (sign out, delete
/// account). Vessel/filter fields write straight through to [ThemeProvider]
/// on every change; logbook membership actions go through [LogbookService]
/// and re-point every repository at the new logbook via [reinitFirestore].
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late ThemeProvider _themeProvider;
  bool _syncing = false;
  bool _accountExpanded = false;
  bool _appearanceExpanded = false;
  bool _logbooksExpanded = false;
  bool _trackFilterExpanded = false;
  bool _equipmentExpanded = false;
  List<Map<String, dynamic>> _logbooks = [];
  bool _loadingLogbooks = false;
  bool _guestsExpanded = false;
  bool _localLogbooksExpanded = false;
  List<(String id, String name)> _localLogbooks = [];
  Future<List<Map<String, dynamic>>>? _guestsFuture;
  late ValueNotifier<String?> _logbookIdNotifier;
  late final Future<PackageInfo> _packageInfoFuture;
  bool _isOffline = false;
  StreamSubscription<dynamic>? _connectivitySub;

  @override
  void initState() {
    super.initState();
    _themeProvider = context.read<ThemeProvider>();
    _logbookIdNotifier = context.read<ValueNotifier<String?>>();
    // Refresh list whenever the active boat changes (e.g. async init completes)
    _logbookIdNotifier.addListener(_refreshLogbooks);
    _refreshLogbooks();
    _refreshLocalLogbooks();
    _packageInfoFuture = PackageInfo.fromPlatform();
    Connectivity().checkConnectivity().then((results) {
      if (mounted) setState(() => _isOffline = results.every((r) => r == ConnectivityResult.none));
    });
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      if (mounted) setState(() => _isOffline = results.every((r) => r == ConnectivityResult.none));
    });
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    _logbookIdNotifier.removeListener(_refreshLogbooks);
    super.dispose();
  }

  /// Reloads the current user's list of accessible logbooks (owned + joined).
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

  /// Refreshes the logbook list. Exposed as a plain callback so the
  /// extracted logbook_actions.dart flows don't need direct access to
  /// _refreshLogbooks.
  void _onLogbooksChanged() => _refreshLogbooks();

  // ── Local logbooks (local mode only) ────────────────────────────────────────

  /// Reloads this device's list of local logbooks from the registry.
  Future<void> _refreshLocalLogbooks() async {
    final logbooks = await context.read<LocalLogbookService>().listLogbooks();
    if (mounted) setState(() => _localLogbooks = logbooks);
  }

  /// Switches every repository/provider over to [newLogbookId]'s local
  /// dataset — the local-mode analogue of [_reinitFirestore], but with no
  /// network involved: nothing to fetch, nothing that can fail offline.
  Future<void> _switchLocalLogbook(String newLogbookId) async {
    final l10n = context.l10n;
    final repo = context.read<HomeRepository>();
    final emergencyRepo = context.read<EmergencyRepository>();
    final messenger = ScaffoldMessenger.of(context);

    showProgressSnackBar(context, l10n.settingsSwitchLogbookInProgress);
    setState(() => _syncing = true);

    await repo.switchLocalDataset(newLogbookId);
    await emergencyRepo.switchLocalDataset(newLogbookId);
    await _themeProvider.switchLocalLogbook(newLogbookId);

    if (mounted) setState(() => _syncing = false);
    messenger.hideCurrentSnackBar();
    if (mounted) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.settingsSwitchLogbookComplete)));
    }
    _refreshLocalLogbooks();
  }

  /// Prompts for a name, creates a new local logbook, and switches to it.
  Future<void> _showNewLocalLogbookDialog() async {
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
                  style: Theme.of(context).textTheme.dialogTitle.copyWith(fontSize: 20, color: cs.onSurface),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: ctrl,
                  autofocus: true,
                  textCapitalization: TextCapitalization.words,
                  style: Theme.of(context).textTheme.bodyLarge!.copyWith(color: cs.onSurface),
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
    // Deferred to after this frame — see _showNewLogbookDialog for why.
    WidgetsBinding.instance.addPostFrameCallback((_) => ctrl.dispose());
    if (name == null || name.isEmpty || !mounted) return;

    final id = await context.read<LocalLogbookService>().createLogbook(name);
    if (!mounted) return;
    await _switchLocalLogbook(id);
  }

  /// Looks up [rawCode], confirms with the user, joins as a guest, and
  /// switches this device to the found logbook.
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
        // The caller is not a member yet, so the logbook document is not
        // readable at this point. The share-code lookup carries the display
        // name specifically for this pre-join confirmation step.
        logbookName = await LogbookService().getLogbookNameByShareCode(code) ?? code;
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

    final confirmed = await showConfirmDialog(
      context,
      title: context.l10n.settingsSwitchLogbookTitle,
      body: context.l10n.settingsJoinContent(resolvedName),
      confirmLabel: context.l10n.connect,
    );
    if (!confirmed || !mounted) return;

    setState(() => _syncing = true);
    try {
      await LogbookService().joinLogbook(resolvedId, user.uid);
      if (!mounted) return;
      await reinitFirestore(context, resolvedId);
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

  /// Confirms, then makes [logbook] the active logbook for [uid] and
  /// switches this device to it.
  Future<void> _switchLogbook(Map<String, dynamic> logbook, String uid) async {
    final l10n = context.l10n;
    final logbookId = logbook['logbookId'] as String;
    final name = logbook['name'] as String;

    final confirmed = await showConfirmDialog(
      context,
      title: context.l10n.settingsSwitchTo(name),
      confirmLabel: context.l10n.connect,
    );
    if (!confirmed || !mounted) return;

    setState(() => _syncing = true);
    try {
      await LogbookService().setActiveLogbook(uid, logbookId);
      if (!mounted) return;
      await reinitFirestore(context, logbookId);
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

  /// Prompts for a name, creates a new logbook owned by [uid], and switches
  /// this device to it.
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
                  style: Theme.of(context).textTheme.dialogTitle.copyWith(fontSize: 20, color: cs.onSurface),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: ctrl,
                  autofocus: true,
                  textCapitalization: TextCapitalization.words,
                  style: Theme.of(context).textTheme.bodyLarge!.copyWith(color: cs.onSurface),
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
    if (name == null || name.isEmpty || !mounted) return;

    setState(() => _syncing = true);
    try {
      final newLogbookId = await LogbookService().createLogbook(uid, name);
      if (!mounted) return;
      await reinitFirestore(context, newLogbookId);
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

  /// Confirms, then permanently deletes the logbook (owner-only) and — if it
  /// was this device's active logbook — switches to whichever logbook is
  /// now active for [uid].
  Future<void> _showDeleteLogbookDialog(
      String logbookId, String name, String uid) async {
    final l10n = context.l10n;
    final confirmed = await showConfirmDialog(
      context,
      title: l10n.settingsDeleteLogbook,
      body: l10n.settingsDeleteLogbookConfirm(name),
      confirmLabel: l10n.delete,
      destructive: true,
    );
    if (!confirmed || !mounted) return;

    setState(() => _syncing = true);
    try {
      final activeId = context.read<ValueNotifier<String?>>().value;
      await LogbookService().deleteLogbook(logbookId, uid);
      if (!mounted) return;
      if (activeId == logbookId) {
        final newActiveId = await LogbookService().getActiveLogbookId(uid);
        if (mounted && newActiveId != null) {
          await reinitFirestore(context, newActiveId);
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

  /// Confirms, then removes [uid] as a guest member of the logbook and — if
  /// it was this device's active logbook — switches to whichever logbook is
  /// now active.
  Future<void> _showLeaveLogbookDialog(
      String logbookId, String name, String uid) async {
    final l10n = context.l10n;
    final confirmed = await showConfirmDialog(
      context,
      title: l10n.settingsLeaveLogbook,
      body: l10n.settingsLeaveLogbookConfirm(name),
      confirmLabel: l10n.remove,
      destructive: true,
    );
    if (!confirmed || !mounted) return;

    setState(() => _syncing = true);
    try {
      final activeId = context.read<ValueNotifier<String?>>().value;
      await LogbookService().removeMember(logbookId, uid);
      if (!mounted) return;
      if (activeId == logbookId) {
        final newActiveId = await LogbookService().getActiveLogbookId(uid);
        if (mounted && newActiveId != null) {
          await reinitFirestore(context, newActiveId);
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

  /// Opens the "connect to a logbook" bottom sheet (scan QR or type a code).
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
        child: ConnectBottomSheet(onCode: _joinLogbook),
      ),
    );
  }

  /// Scaffold: app bar, bottom nav, and the scrollable settings body
  /// (account, display, logbooks, vessel info, track filter, crew roster,
  /// app version), pull-to-refresh reloading the logbook list.
  @override
  Widget build(BuildContext context) {
    final p = context.watch<ThemeProvider>();
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final isLocalMode = context.watch<AuthService>().currentUser == null &&
        p.localModeEnabled;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        centerTitle: true,
        title: Text(l10n.settingsTitle),
      ),
      bottomNavigationBar: AppBottomNav(
        active: NavTab.settings,
        showFab: false,
        onSelect: (tab) {
          if (tab == NavTab.journal) context.goNamed(AppRoute.home);
          if (tab == NavTab.map) context.goNamed(AppRoute.tracks);
          if (tab == NavTab.safety) context.goNamed(AppRoute.emergencyManifest);
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
            // ── App settings ─────────────────────────────────────────────
            // ── Account ───────────────────────────────────────────────
            isLocalMode ? _buildCloudSyncCtaSection(cs) : _buildAccountSection(cs),
            const SizedBox(height: 16),

            // ── Display & Appearance ──────────────────────────────────
            _buildDisplaySection(p, cs),
            const SizedBox(height: 24),

            // ── Logbook / vessel settings ────────────────────────────────
            _buildActiveLogbookHeader(isLocalMode, cs),
            // ── Logbooks ──────────────────────────────────────────────
            isLocalMode ? _buildLocalLogbooksSection(cs) : _buildLogbooksSection(cs),
            const SizedBox(height: 16),

            // ── Vessel Information ────────────────────────────────────
            VesselSection(themeProvider: p, cs: cs),
            const SizedBox(height: 16),

            // ── Vessel Equipment ───────────────────────────────────────
            _buildEquipmentSection(p, cs),
            const SizedBox(height: 16),

            // ── Track Filter ──────────────────────────────────────────
            _buildTrackFilterSection(p, cs),
            const SizedBox(height: 16),

            // ── Crew Roster ───────────────────────────────────────────
            _buildCrewRosterSection(cs),
            const SizedBox(height: 16),

            // ── Backup & Restore ──────────────────────────────────────
            _buildBackupSection(isLocalMode, cs),
            const SizedBox(height: 32),

            // ── App version ───────────────────────────────────────────
            FutureBuilder<PackageInfo>(
              future: _packageInfoFuture,
              builder: (_, snap) {
                final version = snap.hasData
                    ? 'Version ${snap.data!.version} (${snap.data!.buildNumber})'
                    : '';
                return Center(
                  child: Text(
                    version,
                    style: Theme.of(context).textTheme.bodySmall!.copyWith(fontSize: 11, color: cs.onSurfaceVariant.withValues(alpha: 0.5)),
                  ),
                );
              },
            ),
            const SizedBox(height: 8),

          ],
        ),
      ),
      ),
    );
  }

  /// Thin divider between rows in the equipment section below (also used,
  /// under its own copy, by [VesselSection]).
  Widget _rowDivider(ColorScheme cs) => Divider(
        color: cs.surfaceContainerHigh,
        height: 16,
        thickness: 1,
      );

  // ── Vessel Equipment ────────────────────────────────────────────────
  /// Configures the up-to-12 equipment slots (10 sails + motor + keel) shown
  /// as chip rows in the timeline entry dialog. Each edit writes straight
  /// through to [ThemeProvider.setVesselEquipment]. Collapsed by default —
  /// this is a rarely-touched, one-time setup step, not something that
  /// needs to occupy space on every visit to Settings.
  Widget _buildEquipmentSection(ThemeProvider p, ColorScheme cs) {
    final l10n = context.l10n;
    final config = p.vesselEquipment;
    return CardShell(
      accentColor: cs.logbookScopedAccent,
      child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Header (always visible, tap to expand) ────────────
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => setState(() => _equipmentExpanded = !_equipmentExpanded),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              l10n.settingsEquipmentSection.toUpperCase(),
                              style: Theme.of(context).textTheme.labelSmall!.copyWith(
                                color: cs.secondary,
                              ),
                            ),
                            Row(
                              children: [
                                Icon(Icons.settings_outlined, size: 20, color: cs.outlineVariant),
                                const SizedBox(width: 4),
                                AnimatedRotation(
                                  turns: _equipmentExpanded ? 0.5 : 0,
                                  duration: const Duration(milliseconds: 200),
                                  child: Icon(Icons.expand_more,
                                      size: 20, color: cs.outlineVariant),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          l10n.settingsEquipmentInfo,
                          style: Theme.of(context).textTheme.bodySmall!.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // ── Expandable content ────────────────────────────────
                AnimatedCrossFade(
                  duration: const Duration(milliseconds: 220),
                  crossFadeState: _equipmentExpanded
                      ? CrossFadeState.showSecond
                      : CrossFadeState.showFirst,
                  firstChild: const SizedBox(width: double.infinity),
                  secondChild: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Divider(color: cs.surfaceContainerHigh, height: 1, thickness: 1),
                        const SizedBox(height: 12),
                        // ── Segel (slots 1–10) ───────────────────────
                        Text(l10n.settingsEquipmentTypeSail.toUpperCase(),
                            style: Theme.of(context).textTheme.labelSmall!.copyWith(color: cs.outline)),
                        const SizedBox(height: 4),
                        for (int i = 0; i < 10; i++)
                          EquipmentSlotEditor(
                            slot: config.slots[i],
                            typeLabel: l10n.settingsEquipmentTypeSail,
                            onChanged: (updated) => p.setVesselEquipment(config.copyWithSlot(updated)),
                          ),
                        const SizedBox(height: 12),
                        // ── Motor (slot 11) ──────────────────────────
                        Text(l10n.entryDialogMotorLabel.toUpperCase(),
                            style: Theme.of(context).textTheme.labelSmall!.copyWith(color: cs.outline)),
                        const SizedBox(height: 4),
                        EquipmentSlotEditor(
                          slot: config.slots[10],
                          typeLabel: l10n.entryDialogMotorLabel,
                          onChanged: (updated) => p.setVesselEquipment(config.copyWithSlot(updated)),
                        ),
                        const SizedBox(height: 12),
                        // ── Kiel (slot 12) ───────────────────────────
                        Text(l10n.entryDialogKeelLabel.toUpperCase(),
                            style: Theme.of(context).textTheme.labelSmall!.copyWith(color: cs.outline)),
                        const SizedBox(height: 4),
                        EquipmentSlotEditor(
                          slot: config.slots[11],
                          typeLabel: l10n.entryDialogKeelLabel,
                          onChanged: (updated) => p.setVesselEquipment(config.copyWithSlot(updated)),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  // ── Display & Appearance ────────────────────────────────────────────
  /// Theme mode (system/light/dark) and language (German/English) segmented
  /// pickers.
  Widget _buildDisplaySection(ThemeProvider p, ColorScheme cs) {
    final l10n = context.l10n;
    return CardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => setState(() => _appearanceExpanded = !_appearanceExpanded),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        l10n.settingsAppearanceSection.toUpperCase(),
                        style: Theme.of(context).textTheme.labelSmall!.copyWith(
                          color: cs.secondary,
                        ),
                      ),
                      Row(
                        children: [
                          Icon(Icons.palette_outlined,
                              size: 20, color: cs.outlineVariant),
                          const SizedBox(width: 4),
                          AnimatedRotation(
                            turns: _appearanceExpanded ? 0.5 : 0,
                            duration: const Duration(milliseconds: 200),
                            child: Icon(Icons.expand_more,
                                size: 20, color: cs.outlineVariant),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    l10n.settingsAppearanceInfo,
                    style: Theme.of(context).textTheme.bodySmall!.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 220),
            crossFadeState: _appearanceExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            firstChild: const SizedBox(width: double.infinity),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.settingsThemeLabel,
                    style: Theme.of(context).textTheme.fieldValueCompact.copyWith(color: cs.onSurface),
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
                    style: Theme.of(context).textTheme.fieldValueCompact.copyWith(color: cs.onSurface),
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
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        l10n.settingsAutoLogPositionLabel,
                        style: Theme.of(context).textTheme.fieldValueCompact.copyWith(color: cs.onSurface),
                      ),
                      Switch(
                        value: p.autoLogPositionEnabled,
                        onChanged: p.setAutoLogPosition,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l10n.settingsAutoLogPositionDesc,
                    style: Theme.of(context).textTheme.bodySmall!.copyWith(
                      fontStyle: FontStyle.italic,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// One segment of the theme-mode picker.
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
            style: Theme.of(context).textTheme.bodyMedium!.copyWith(fontWeight: isActive ? FontWeight.w600 : FontWeight.w400, color: isActive ? cs.primary : cs.onSurfaceVariant),
          ),
        ),
      ),
    );
  }

  /// One segment of the language picker.
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
            style: Theme.of(context).textTheme.bodyMedium!.copyWith(fontWeight: isActive ? FontWeight.w600 : FontWeight.w400, color: isActive ? cs.primary : cs.onSurfaceVariant),
          ),
        ),
      ),
    );
  }

  /// Whether any GPX track-filter value differs from its factory default —
  /// shows a dot badge on the collapsed section header and a "reset" button
  /// when expanded.
  bool _filterIsModified(ThemeProvider p) =>
      p.filterMode != StationaryMode.speed ||
      p.minStopMinutes != 5.0 ||
      p.maxStopSpreadM != 30.0 ||
      p.detectColdStart != true ||
      p.coldStartSettleFactor != 3.0 ||
      p.makingWayThresholdKn != 1.0 ||
      p.topSpeedPercentile != 0.99 ||
      p.maxSpeedKn != 12.0;

  // ── Track Filter ────────────────────────────────────────────────────
  /// Collapsible advanced section tuning the GPS track-cleaning pipeline
  /// (see [FilterSettings]): stationary-detection mode, min stop duration,
  /// max anchor swing, cold-start trimming, underway threshold, max-speed
  /// percentile/ceiling, and a raw-track debug overlay toggle.
  Widget _buildTrackFilterSection(ThemeProvider p, ColorScheme cs) {
    return CardShell(
      accentColor: cs.logbookScopedAccent,
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
                    style: Theme.of(context).textTheme.labelSmall!.copyWith(
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
                  Icon(Icons.tune, size: 20, color: cs.outlineVariant),
                  const SizedBox(width: 4),
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
                    style: Theme.of(context).textTheme.fieldValueCompact.copyWith(color: cs.onSurface),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    context.l10n.settingsStationaryDesc,
                    style: Theme.of(context).textTheme.bodySmall!.copyWith(
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
                    style: Theme.of(context).textTheme.bodySmall!.copyWith(
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
                        style: Theme.of(context).textTheme.bodyMedium!.copyWith(fontWeight: FontWeight.w600, color: cs.onSurface),
                      ),
                      Text(
                        '${p.minStopMinutes.round()} ${context.l10n.settingsMinUnit}',
                        style: Theme.of(context).textTheme.chipLabel.copyWith(color: cs.primary),
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
                    style: Theme.of(context).textTheme.bodySmall!.copyWith(
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
                        style: Theme.of(context).textTheme.bodyMedium!.copyWith(fontWeight: FontWeight.w600, color: cs.onSurface),
                      ),
                      Text(
                        '${p.maxStopSpreadM.round()} ${context.l10n.settingsMetersUnit}',
                        style: Theme.of(context).textTheme.chipLabel.copyWith(color: cs.primary),
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
                    style: Theme.of(context).textTheme.bodySmall!.copyWith(
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
                        style: Theme.of(context).textTheme.bodyMedium!.copyWith(fontWeight: FontWeight.w600, color: cs.onSurface),
                      ),
                      Switch(
                        value: p.detectColdStart,
                        onChanged: p.setDetectColdStart,
                      ),
                    ],
                  ),
                  Text(
                    context.l10n.settingsColdStartDesc,
                    style: Theme.of(context).textTheme.bodySmall!.copyWith(
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
                          style: Theme.of(context).textTheme.bodyMedium!.copyWith(fontWeight: FontWeight.w600, color: cs.onSurface),
                        ),
                        Text(
                          p.coldStartSettleFactor.toStringAsFixed(1),
                          style: Theme.of(context).textTheme.chipLabel.copyWith(color: cs.primary),
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
                      style: Theme.of(context).textTheme.bodySmall!.copyWith(
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
                        style: Theme.of(context).textTheme.bodyMedium!.copyWith(fontWeight: FontWeight.w600, color: cs.onSurface),
                      ),
                      Text(
                        '${p.makingWayThresholdKn.toStringAsFixed(1)} kn',
                        style: Theme.of(context).textTheme.chipLabel.copyWith(color: cs.primary),
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
                    style: Theme.of(context).textTheme.bodySmall!.copyWith(
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
                        style: Theme.of(context).textTheme.bodyMedium!.copyWith(fontWeight: FontWeight.w600, color: cs.onSurface),
                      ),
                      Text(
                        'p${(p.topSpeedPercentile * 100).round()}',
                        style: Theme.of(context).textTheme.chipLabel.copyWith(color: cs.primary),
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
                    style: Theme.of(context).textTheme.bodySmall!.copyWith(
                      fontStyle: FontStyle.italic,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  _rowDivider(cs),
                  // ── Max speed ceiling ────────────────────────────
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        context.l10n.settingsMaxSpeedLabel,
                        style: Theme.of(context).textTheme.bodyMedium!.copyWith(fontWeight: FontWeight.w600, color: cs.onSurface),
                      ),
                      Text(
                        '${p.maxSpeedKn.round()} kn',
                        style: Theme.of(context).textTheme.chipLabel.copyWith(color: cs.primary),
                      ),
                    ],
                  ),
                  Slider(
                    value: p.maxSpeedKn,
                    min: 8,
                    max: 60,
                    divisions: 52,
                    onChanged: p.setMaxSpeedKn,
                  ),
                  Text(
                    context.l10n.settingsMaxSpeedDesc,
                    style: Theme.of(context).textTheme.bodySmall!.copyWith(
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
                        style: Theme.of(context).textTheme.bodyMedium!.copyWith(fontWeight: FontWeight.w600, color: cs.onSurface),
                      ),
                      Switch(
                        value: p.showRawTrack,
                        onChanged: p.setShowRawTrack,
                      ),
                    ],
                  ),
                  Text(
                    context.l10n.settingsShowRawTrackDesc,
                    style: Theme.of(context).textTheme.bodySmall!.copyWith(
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
                          style: Theme.of(context).textTheme.bodySmall!.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            // ── end expandable content ──
          ),
        ],
      ),
    );
  }

  /// One segment of the stationary-detection-mode picker.
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
            style: Theme.of(context).textTheme.chipLabel.copyWith(fontWeight: isActive ? FontWeight.w600 : FontWeight.w400, color: isActive ? cs.primary : cs.onSurfaceVariant),
          ),
        ),
      ),
    );
  }

  // ── Crew Roster ──────────────────────────────────────────────────────
  /// Tappable shortcut card into [CrewRosterScreen], showing the current
  /// roster count.
  Widget _buildCrewRosterSection(ColorScheme cs) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => context.pushNamed(AppRoute.crewRoster),
      child: CardShell(
        accentColor: cs.logbookScopedAccent,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 16, 14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.l10n.settingsCrewSection.toUpperCase(),
                      style: Theme.of(context).textTheme.labelSmall!.copyWith(
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
                          style: Theme.of(context).textTheme.bodySmall!.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              Icon(Icons.people_outline, size: 20, color: cs.outlineVariant),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right, color: cs.outlineVariant),
            ],
          ),
        ),
      ),
    );
  }

  // ── Backup & Restore ───────────────────────────────────────────────────
  /// Tappable shortcut card into [BackupScreen].
  /// Shown instead of [_buildAccountSection] for a local-mode user (no
  /// Firebase account, all data on this device only). Starts the upgrade
  /// path: registering/signing in from here pushes this device's local data
  /// into the new cloud logbook automatically (see `_initFirestore` in
  /// main.dart) and clears the local-mode flag once that completes.
  Widget _buildCloudSyncCtaSection(ColorScheme cs) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => context.pushNamed(AppRoute.register),
      child: CardShell(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 16, 14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.l10n.settingsSetUpCloudSync.toUpperCase(),
                      style: Theme.of(context).textTheme.labelSmall!.copyWith(
                        color: cs.secondary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      context.l10n.settingsSetUpCloudSyncSubtitle,
                      style: Theme.of(context).textTheme.bodySmall!.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.cloud_upload_outlined, size: 20, color: cs.outlineVariant),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right, color: cs.outlineVariant),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBackupSection(bool isLocalMode, ColorScheme cs) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => context.pushNamed(AppRoute.backupRestore,
          extra: _activeLogbookName(isLocalMode)),
      child: CardShell(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 16, 14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.l10n.settingsBackupSection.toUpperCase(),
                      style: Theme.of(context).textTheme.labelSmall!.copyWith(
                        color: cs.secondary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      context.l10n.settingsBackupSubtitle,
                      style: Theme.of(context).textTheme.bodySmall!.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.archive_outlined, size: 20, color: cs.outlineVariant),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right, color: cs.outlineVariant),
            ],
          ),
        ),
      ),
    );
  }

  /// The active logbook's display name — local logbook name in local mode,
  /// cloud logbook name otherwise — or `''` if not yet known. Shared by
  /// [_buildActiveLogbookHeader] and [_buildBackupSection], so Backup &
  /// Restore can name the logbook it's about to export/replace too.
  String _activeLogbookName(bool isLocalMode) {
    if (isLocalMode) {
      final activeId = _themeProvider.activeLocalLogbookId;
      final match = _localLogbooks.where((lb) => lb.$1 == activeId);
      return match.isEmpty ? '' : match.first.$2;
    } else {
      final activeId = context.watch<ValueNotifier<String?>>().value;
      final match = _logbooks.where((b) => b['logbookId'] == activeId);
      return match.isEmpty ? '' : (match.first['name'] as String? ?? '');
    }
  }

  /// A small eyebrow header naming the active logbook, shown once above the
  /// whole logbook-scoped group (Logbooks, Vessel, Equipment, Track Filter,
  /// Crew Roster) — makes it visually explicit that everything below, down
  /// to the Backup section, travels with *that* logbook and would change if
  /// you switched to a different one.
  Widget _buildActiveLogbookHeader(bool isLocalMode, ColorScheme cs) {
    final l10n = context.l10n;
    final name = _activeLogbookName(isLocalMode);
    if (name.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
      child: Row(
        children: [
          Icon(Icons.anchor, size: 14, color: cs.logbookScopedAccent),
          const SizedBox(width: 6),
          Text(
            l10n.settingsActiveLogbookHeader(name),
            style: Theme.of(context).textTheme.labelSmall!.copyWith(
                color: cs.logbookScopedAccent,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5),
          ),
        ],
      ),
    );
  }

  // ── Local logbooks (local mode only) ────────────────────────────────────────
  /// Local-mode analogue of [_buildLogbooksSection]: lists every logbook on
  /// this device (as a [_buildLocalBoatRow] each), with an add-logbook
  /// button. No owner/guest role, no share code/QR — a local logbook is a
  /// single-device concept.
  Widget _buildLocalLogbooksSection(ColorScheme cs) {
    final l10n = context.l10n;
    final activeId = _themeProvider.activeLocalLogbookId;

    return CardShell(
      accentColor: cs.logbookScopedAccent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: _syncing
                ? null
                : () => setState(() => _localLogbooksExpanded = !_localLogbooksExpanded),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        l10n.settingsLogbooksSection.toUpperCase(),
                        style: Theme.of(context).textTheme.labelSmall!.copyWith(
                          color: cs.secondary,
                        ),
                      ),
                      Row(
                        children: [
                          Icon(Icons.anchor, size: 20, color: cs.outlineVariant),
                          const SizedBox(width: 4),
                          if (_syncing)
                            SizedBox(
                              width: 16, height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: cs.secondary),
                            )
                          else
                            AnimatedRotation(
                              turns: _localLogbooksExpanded ? 0.5 : 0,
                              duration: const Duration(milliseconds: 200),
                              child: Icon(Icons.expand_more,
                                  size: 20, color: cs.outlineVariant),
                            ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    l10n.settingsLocalLogbooksInfo,
                    style: Theme.of(context).textTheme.bodySmall!.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 220),
            crossFadeState: _localLogbooksExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            firstChild: const SizedBox(width: double.infinity),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: _syncing ? null : _showNewLocalLogbookDialog,
                      style: TextButton.styleFrom(
                        foregroundColor: cs.secondary,
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        minimumSize: const Size(0, 32),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      icon: const Icon(Icons.add, size: 18),
                      label: Text(l10n.settingsNewLogbook),
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (_localLogbooks.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(l10n.settingsNoLogbooks,
                          style: Theme.of(context).textTheme.bodySmall!.copyWith(
                              color: cs.onSurfaceVariant)),
                    )
                  else
                    ..._localLogbooks.map(
                        (lb) => _buildLocalBoatRow(lb.$1, lb.$2, activeId, cs)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// One local logbook's row: active-indicator dot, name, and (trailing
  /// icon) its rename/delete options sheet. Tapping a non-active row
  /// switches to it — no confirmation needed, unlike the cloud version:
  /// there's no network round-trip to worry about, and switching back is
  /// just as instant.
  Widget _buildLocalBoatRow(
      String id, String name, String? activeId, ColorScheme cs) {
    final isActive = id == activeId;
    final canSwitch = !isActive && !_syncing;

    return InkWell(
      onTap: canSwitch ? () => _switchLocalLogbook(id) : null,
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
              child: Text(
                name,
                style: Theme.of(context).textTheme.fieldValueCompact.copyWith(
                    fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                    color: cs.onSurface),
              ),
            ),
            if (isActive) Icon(Icons.check, size: 18, color: cs.primary),
            IconButton(
              icon: Icon(Icons.more_vert, size: 18, color: cs.outlineVariant),
              onPressed: _syncing
                  ? null
                  : () => showLocalLogbookOptionsSheet(
                        context,
                        isActive: isActive,
                        onRename: () => showRenameLocalLogbookDialog(
                            context, id: id, currentName: name, onRenamed: _refreshLocalLogbooks),
                        onDelete: () => showDeleteLocalLogbookDialog(
                            context, id: id, name: name, onDeleted: _refreshLocalLogbooks),
                      ),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      ),
    );
  }

  // ── Logbooks ─────────────────────────────────────────────────────────
  /// Lists every logbook this user can access (as a [_buildBoatRow] each),
  /// with an add-logbook button, and — only when the active logbook is
  /// owned by this user — the share/manage-guests section below it.
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

    return CardShell(
      accentColor: cs.logbookScopedAccent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: _syncing
                ? null
                : () => setState(() => _logbooksExpanded = !_logbooksExpanded),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        l10n.settingsLogbooksSection.toUpperCase(),
                        style: Theme.of(context).textTheme.labelSmall!.copyWith(
                          color: cs.secondary,
                        ),
                      ),
                      Row(
                        children: [
                          Icon(Icons.anchor, size: 20, color: cs.outlineVariant),
                          const SizedBox(width: 4),
                          // Visible feedback for delete/switch/rename/join —
                          // those all set _syncing but (before this) never
                          // showed anything while awaiting Firestore, which
                          // read as the app being stuck for however long that
                          // network call took.
                          if (_syncing)
                            SizedBox(
                              width: 16, height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: cs.secondary),
                            )
                          else
                            AnimatedRotation(
                              turns: _logbooksExpanded ? 0.5 : 0,
                              duration: const Duration(milliseconds: 200),
                              child: Icon(Icons.expand_more,
                                  size: 20, color: cs.outlineVariant),
                            ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    l10n.settingsLogbooksInfo,
                    style: Theme.of(context).textTheme.bodySmall!.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 220),
            crossFadeState: _logbooksExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            firstChild: const SizedBox(width: double.infinity),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: _syncing ? null : () => _showNewLogbookDialog(uid),
                      style: TextButton.styleFrom(
                        foregroundColor: cs.secondary,
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        minimumSize: const Size(0, 32),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      icon: const Icon(Icons.add, size: 18),
                      label: Text(l10n.settingsNewLogbook),
                    ),
                  ),
                  const SizedBox(height: 4),
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
                          style: Theme.of(context).textTheme.bodySmall!.copyWith(
                              color: cs.onSurfaceVariant)),
                    )
                  else
                    ...(_logbooks.map((logbook) => _buildBoatRow(logbook, activeLogbookId, cs, uid))),
                  if (activeLogbookId != null && isActiveOwner && activeMeta.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    _buildShareSection(activeMeta, cs, uid),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// One logbook's row: active-indicator dot, name, owner/guest badge, and
  /// (long-press or trailing icon) its options sheet. Tapping a non-active
  /// row switches to it (disabled while offline or already syncing).
  Widget _buildBoatRow(Map<String, dynamic> logbook, String? activeLogbookId,
      ColorScheme cs, String uid) {
    final logbookId = logbook['logbookId'] as String;
    final name = logbook['name'] as String;
    final role = logbook['role'] as String;
    final isActive = logbookId == activeLogbookId;
    final isOwner = role == 'owner';
    final canSwitch = !isActive && !_syncing && !_isOffline;
    final l10n = context.l10n;

    return InkWell(
      onTap: canSwitch ? () => _switchLogbook(logbook, uid) : null,
      borderRadius: BorderRadius.circular(8),
      child: Opacity(
        opacity: !isActive && _isOffline ? 0.45 : 1.0,
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
                    style: Theme.of(context).textTheme.fieldValueCompact.copyWith(fontWeight: isActive ? FontWeight.w700 : FontWeight.w500, color: cs.onSurface),
                  ),
                  Text(
                    !isActive && _isOffline
                        ? l10n.offlineLabel
                        : isOwner ? l10n.settingsRoleOwner : l10n.settingsRoleGuest,
                    style: Theme.of(context).textTheme.bodySmall!.copyWith(
                        color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            if (isActive) Icon(Icons.check, size: 18, color: cs.primary),
            IconButton(
              icon: Icon(Icons.more_vert, size: 18, color: cs.outlineVariant),
              onPressed: _syncing
                  ? null
                  : () => isOwner
                      ? showLogbookOptionsSheet(
                          context,
                          onRename: () => showRenameLogbookDialog(
                              context, logbookId: logbookId, currentName: name, onLogbooksChanged: _onLogbooksChanged),
                          onShare: () => showQrModal(context, logbook['shareCode'] as String? ?? ''),
                          onDelete: () => _showDeleteLogbookDialog(logbookId, name, uid),
                        )
                      : showGuestOptionsSheet(
                          context,
                          onLeave: () => _showLeaveLogbookDialog(logbookId, name, uid),
                        ),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      ),
      ),
    );
  }

  /// Owner-only share block for the active logbook: copyable share code, QR
  /// code button, "join another logbook" shortcut, and the guest-management list.
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
                style: Theme.of(context).textTheme.labelSmall!.copyWith(
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
                  formatCode(shareCode),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.shareCode.copyWith(color: cs.onPrimaryContainer),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: () {
                Clipboard.setData(
                    ClipboardData(text: formatCode(shareCode)));
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
                onPressed: () => showQrModal(context, shareCode),
                icon: const Icon(Icons.qr_code, size: 18),
                label: Text(l10n.settingsShowQrCode),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: cs.outlineVariant),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                  textStyle: Theme.of(context).textTheme.bodySmall,
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
                  textStyle: Theme.of(context).textTheme.bodySmall,
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

  /// Collapsible list of the active logbook's guest members (fetched lazily
  /// on first expand), each removable by the owner.
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
                    style: Theme.of(context).textTheme.bodyMedium!.copyWith(fontWeight: FontWeight.w600, color: cs.onSurface),
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
                      style: Theme.of(context).textTheme.bodySmall!.copyWith(
                          color: cs.onSurfaceVariant)),
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
                              style: Theme.of(context).textTheme.bodySmall!.copyWith(
                                  color: cs.onSurface)),
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
  /// Signed-in-as line plus sign-out and delete-account actions. Both
  /// destructive actions require connectivity: sign-out warns (but allows)
  /// offline, while account deletion blocks outright so Firestore cleanup
  /// can't fail silently and leave the Auth account deleted with orphaned data.
  Widget _buildAccountSection(ColorScheme cs) {
    final l10n = context.l10n;
    final user = context.watch<AuthService>().currentUser;

    return CardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => setState(() => _accountExpanded = !_accountExpanded),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        l10n.settingsAccountSection.toUpperCase(),
                        style: Theme.of(context).textTheme.labelSmall!.copyWith(
                          color: cs.secondary,
                        ),
                      ),
                      Row(
                        children: [
                          Icon(Icons.person_outline, size: 20, color: cs.outlineVariant),
                          const SizedBox(width: 4),
                          AnimatedRotation(
                            turns: _accountExpanded ? 0.5 : 0,
                            duration: const Duration(milliseconds: 200),
                            child: Icon(Icons.expand_more,
                                size: 20, color: cs.outlineVariant),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    l10n.settingsAccountInfo,
                    style: Theme.of(context).textTheme.bodySmall!.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 220),
            crossFadeState: _accountExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            firstChild: const SizedBox(width: double.infinity),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              if (user != null) ...[
                Text(
                  l10n.settingsAccountSignedInAs,
                  style: Theme.of(context).textTheme.bodySmall!.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  user.email ?? user.displayName ?? '',
                  style: Theme.of(context).textTheme.fieldValueCompact.copyWith(color: cs.onSurface),
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
                      final confirmed = await showConfirmDialog(
                        context,
                        title: l10n.authSignOut,
                        confirmLabel: l10n.authSignOut,
                        destructive: true,
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
                                      style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                                          color: cs.error, fontSize: 13),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      );
                      if (confirmed && mounted) {
                        await context.read<AuthService>().signOut();
                      }
                    },
                    icon: Icon(Icons.logout, size: 18, color: cs.error),
                    label: Text(l10n.authSignOut,
                        style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                            color: cs.error)),
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
                        : () => runDeleteAccountFlow(
                              context,
                              uid: user.uid,
                              onSyncingChanged: (v) => setState(() => _syncing = v),
                            ),
                    child: Text(l10n.authDeleteAccount),
                  ),
                ),
              ] else ...[
                Text(
                  l10n.settingsAccountNotSignedIn,
                  style: Theme.of(context).textTheme.bodySmall!.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => context.pushNamed(AppRoute.login),
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    child: Text(l10n.settingsAccountManage,
                        style: Theme.of(context).textTheme.bodyMedium!.copyWith(fontWeight: FontWeight.w600)),
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
}

