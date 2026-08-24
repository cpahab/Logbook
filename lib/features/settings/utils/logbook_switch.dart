import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/services/crash_reporter.dart';
import '../../../core/services/firestore_service.dart';
import '../../../core/services/storage_service.dart';
import '../../../core/utils/retry_with_backoff.dart';
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
///
/// [showCompleteSnackbar] controls whether the generic "Logbook switched."
/// message is shown on success. Callers that show their own more specific
/// follow-up message (e.g. "Connected.", "Joined `name`") should pass
/// `false` — otherwise both queue and play back-to-back, showing two
/// snackbars in a row for what's conceptually one outcome.
Future<bool> reinitFirestore(
  BuildContext context,
  String logbookId, {
  bool showCompleteSnackbar = true,
}) async {
  // Cache context-dependent objects before any await.
  final repo          = context.read<HomeRepository>();
  final themeProvider = context.read<ThemeProvider>();
  final emergencyRepo = context.read<EmergencyRepository>();
  final notifier      = context.read<ValueNotifier<String?>>();
  final switchInProgress = context.read<ValueNotifier<bool>>();
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

  final firestore = await FirestoreService.create(logbookId);
  final storage = await StorageService.create(logbookId);

  // Set for the rest of this function — read by AppBottomNav to block
  // navigating to another tab while this repository is mid-reattach
  // (subscriptions cancelled, local state not yet replaced with the new
  // logbook's). Reset in `finally` so it can't get stuck true on any of
  // the early-return failure paths below.
  switchInProgress.value = true;
  try {
    // Fetch the new logbook's vessel/VHF settings and emergency contacts
    // before clearing anything — a fetch failure here aborts the switch
    // instead of wiping local data with nothing confirmed to replace it.
    // Retried with backoff: these are forced server reads (Source.server),
    // so right after joining/creating a logbook, the security rule check
    // for the membership doc just written can transiently lag behind it.
    final Map<String, String>? remoteSettings;
    final List<Map<String, String>>? remoteContacts;
    try {
      final settingsResult =
          await retryWithBackoff(firestore.fetchSettingsWithMeta);
      remoteSettings = settingsResult.data;
      final contactsResult =
          await retryWithBackoff(firestore.fetchContactsWithMeta);
      remoteContacts = contactsResult.contacts;
    } catch (e, st) {
      // Connectivity was already confirmed above, so a failure here (after
      // retrying) is something else — a permission-check lag right after
      // joining/creating a logbook, or a genuine server error — never
      // "offline", which would be actively misleading to show.
      debugPrint('reinitFirestore: settings/contacts fetch failed: $e\n$st');
      reportNonFatal(e, st, reason: 'reinitFirestore settings/contacts fetch failed');
      messenger.hideCurrentSnackBar();
      if (context.mounted) {
        messenger.showSnackBar(SnackBar(content: Text(l10n.settingsSwitchLogbookError)));
      }
      return false;
    }

    // reattachAndSync can itself fail to download the new logbook's entries
    // (network blip, or a momentary permission-check lag right after
    // joining/creating a logbook) and abort *without* switching anything —
    // if we didn't check this, every other repo/provider below would still
    // get pointed at the new logbook while HomeRepository silently stayed
    // on the old one, which then reappears everywhere and — worse — gets
    // pushed into the new logbook on the next successful reattach.
    final entriesSwitched = await repo.reattachAndSync(firestore, storage);
    if (!entriesSwitched) {
      messenger.hideCurrentSnackBar();
      if (context.mounted) {
        messenger.showSnackBar(SnackBar(content: Text(l10n.settingsSwitchLogbookError)));
      }
      return false;
    }

    await themeProvider.applySwitchedLogbookSettings(remoteSettings, firestore);
    await emergencyRepo.applySwitchedLogbookContacts(remoteContacts, firestore);
    if (context.mounted) notifier.value = logbookId;

    messenger.hideCurrentSnackBar();
    if (showCompleteSnackbar && context.mounted) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.settingsSwitchLogbookComplete)));
    }
    return true;
  } catch (e, st) {
    // None of the steps above (unlike the settings/contacts fetch further up)
    // have their own catch — without one here, an exception from any of them
    // would propagate to the caller with this progress snackbar still on
    // screen (its 2-minute duration far outlasting the caller's own error
    // snackbar), looking like a sync that never finishes.
    debugPrint('reinitFirestore: switch failed: $e\n$st');
    reportNonFatal(e, st, reason: 'reinitFirestore switch failed');
    messenger.hideCurrentSnackBar();
    if (context.mounted) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.settingsSwitchLogbookError)));
    }
    return false;
  } finally {
    switchInProgress.value = false;
  }
}
