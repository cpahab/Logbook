import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/services/firestore_service.dart';
import '../../../core/services/storage_service.dart';
import '../../../core/widgets/progress_snackbar.dart';
import '../../../l10n/l10n_extension.dart';
import '../../emergency/data/emergency_repository.dart';
import '../../home/data/home_repository.dart';
import '../domain/theme_provider.dart';

/// Switches every repository/provider over to [logbookId]'s Firestore
/// backend. Downloads the new boat's vessel/VHF settings and emergency
/// contacts *before* touching any local state, and aborts the whole switch
/// (leaving the current logbook's data untouched) if either download
/// fails — the same fetch-before-replace safety
/// [HomeRepository.reattachAndSync] already uses for day entries.
/// Requires connectivity for the same reason.
///
/// Returns `false` if the switch was aborted for any reason (offline, a
/// fetch failure, or [HomeRepository.reattachAndSync] itself failing).
/// Callers MUST check this and skip anything that "commits" to the new
/// logbook being active (e.g. LogbookService.setActiveLogbook) on a false
/// return — see createLogbook/joinLogbook's doc comments for why.
Future<bool> reinitFirestore(BuildContext context, String logbookId) async {
  // Cache context-dependent objects before any await.
  final repo          = context.read<HomeRepository>();
  final themeProvider = context.read<ThemeProvider>();
  final emergencyRepo = context.read<EmergencyRepository>();
  final notifier      = context.read<ValueNotifier<String?>>();
  final l10n          = context.l10n;
  final messenger     = ScaffoldMessenger.of(context);

  // Switching logbooks requires a live connection — we must download the new
  // logbook's data before replacing local state.
  final connectivity = await Connectivity().checkConnectivity();
  final isOffline = connectivity.every((r) => r == ConnectivityResult.none);
  if (isOffline) {
    if (context.mounted) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.settingsSwitchLogbookOffline)));
    }
    return false;
  }
  if (!context.mounted) return false;

  showProgressSnackBar(context, l10n.settingsSwitchLogbookInProgress);

  final firestore = FirestoreService(logbookId: logbookId);
  final storage = StorageService(logbookId: logbookId);

  // Fetch the new logbook's vessel/VHF settings and emergency contacts
  // before clearing anything — a fetch failure here aborts the switch
  // instead of wiping local data with nothing confirmed to replace it.
  final Map<String, String>? remoteSettings;
  final List<Map<String, String>>? remoteContacts;
  try {
    final settingsResult = await firestore.fetchSettingsWithMeta();
    remoteSettings = settingsResult.data;
    final contactsResult = await firestore.fetchContactsWithMeta();
    remoteContacts = contactsResult.contacts;
  } catch (_) {
    messenger.hideCurrentSnackBar();
    if (context.mounted) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.settingsSwitchLogbookOffline)));
    }
    return false;
  }

  // reattachAndSync can itself fail to download the new logbook's entries
  // (network blip, or a momentary permission-check lag right after
  // joining/creating a logbook) and abort *without* switching anything —
  // if we didn't check this, every other repo/provider below would still
  // get pointed at the new logbook while HomeRepository silently stayed on
  // the old one, which then reappears everywhere and — worse — gets
  // pushed into the new logbook on the next successful reattach.
  final entriesSwitched = await repo.reattachAndSync(firestore, storage);
  if (!entriesSwitched) {
    messenger.hideCurrentSnackBar();
    if (context.mounted) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.settingsSwitchLogbookOffline)));
    }
    return false;
  }

  await themeProvider.applySwitchedLogbookSettings(remoteSettings, firestore);
  await emergencyRepo.applySwitchedLogbookContacts(remoteContacts, firestore);
  if (context.mounted) notifier.value = logbookId;

  messenger.hideCurrentSnackBar();
  if (context.mounted) {
    messenger.showSnackBar(SnackBar(content: Text(l10n.settingsSwitchLogbookComplete)));
  }
  return true;
}
