import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/theme/theme_extensions.dart';
import '../../auth/data/auth_repository.dart';
import '../../../core/services/logbook_key_store.dart';
import '../../../core/services/logbook_service.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../l10n/l10n_extension.dart';
import '../../emergency/data/emergency_repository.dart';
import '../../home/data/home_repository.dart';
import '../domain/theme_provider.dart';
import '../utils/logbook_switch.dart';

/// If a reinit right after a delete/leave fails, this repository/provider
/// set is still pointed at the just-removed logbook, which the server no
/// longer considers active — clearing local state stops those stale
/// entries from leaking into whichever logbook a later, successful
/// reattach actually lands on (same precedent as [HomeRepository.clearLocalData]'s
/// "different user signed in" use, applied to "different logbook now active").
Future<void> _clearLocalStateAfterFailedReinit(BuildContext context) async {
  await context.read<HomeRepository>().clearLocalData();
  if (!context.mounted) return;
  await context.read<EmergencyRepository>().clearLocalData();
  if (!context.mounted) return;
  await context.read<ThemeProvider>().clearVesselSettings();
}

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
    final user = context.read<AuthService>().currentUser;
    final newLogbookId = await LogbookService().createLogbook(uid, name,
        displayName: user?.displayName, email: user?.email);
    if (!context.mounted) return;
    // reinitFirestore can fail (e.g. a momentary permission-check lag right
    // after creating the logbook) — only commit newLogbookId as the active
    // logbook once the local switch actually succeeded, otherwise the
    // server would believe it's active while the app stays on the previous
    // logbook locally, which is exactly how stale data used to leak into a
    // "new" logbook on a later reattach. Its own ValueNotifier<String?>
    // write (on success) already triggers the logbook-list refresh via the
    // listener registered in initState — so, unlike the guest-panel reset,
    // no separate "logbooks changed" callback is needed here.
    final switched = await reinitFirestore(context, newLogbookId,
        showCompleteSnackbar: false);
    if (!switched) return;
    await LogbookService().setActiveLogbook(uid, newLogbookId);
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

/// Confirms, then permanently deletes the logbook (owner-only) and — if it
/// was this device's active logbook — switches to whichever logbook is
/// now active for [uid].
Future<void> showDeleteLogbookDialog(
  BuildContext context, {
  required String logbookId,
  required String name,
  required String uid,
  required ValueChanged<bool> onSyncingChanged,
  required VoidCallback onGuestsCollapse,
  required VoidCallback onLogbooksChanged,
}) async {
  final l10n = context.l10n;
  final confirmed = await showConfirmDialog(
    context,
    title: l10n.settingsDeleteLogbook,
    body: l10n.settingsDeleteLogbookConfirm(name),
    confirmLabel: l10n.delete,
    destructive: true,
  );
  if (!confirmed || !context.mounted) return;

  onSyncingChanged(true);
  try {
    final activeId = context.read<ValueNotifier<String?>>().value;
    await LogbookService().deleteLogbook(logbookId, uid);
    // Hygiene cleanup, not a security measure: only removes the key from
    // *this* device's secure storage. Doesn't (and can't) revoke it from
    // any other member's device — see LogbookKeyStore's own doc comment.
    await LogbookKeyStore.forgetKey(logbookId);
    if (!context.mounted) return;
    // reinitFirestore only runs when the deleted logbook was the active
    // one AND a new active logbook was found — its ValueNotifier<String?>
    // write is what would otherwise trigger the list refresh via the
    // listener. When it doesn't run (deleting a non-active logbook, or no
    // new active logbook exists), nothing else will refresh the list, so
    // onLogbooksChanged must be called explicitly in that case.
    var reinitialized = false;
    if (activeId == logbookId) {
      final newActiveId = await LogbookService().getActiveLogbookId(uid);
      if (context.mounted && newActiveId != null) {
        final switched = await reinitFirestore(context, newActiveId);
        if (switched) {
          reinitialized = true;
        } else if (context.mounted) {
          // The server already considers newActiveId active (deleteLogbook
          // set that as a side effect) but this repo/provider set is still
          // pointed at the just-deleted logbook — clear local state so
          // nothing stale can leak into newActiveId on a later reattach.
          await _clearLocalStateAfterFailedReinit(context);
        }
      }
    }
    if (context.mounted) {
      onGuestsCollapse();
      if (!reinitialized) onLogbooksChanged();
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

/// Confirms, then removes [uid] as a guest member of the logbook and — if
/// it was this device's active logbook — switches to whichever logbook is
/// now active.
Future<void> showLeaveLogbookDialog(
  BuildContext context, {
  required String logbookId,
  required String name,
  required String uid,
  required ValueChanged<bool> onSyncingChanged,
  required VoidCallback onGuestsCollapse,
  required VoidCallback onLogbooksChanged,
}) async {
  final l10n = context.l10n;
  final confirmed = await showConfirmDialog(
    context,
    title: l10n.settingsLeaveLogbook,
    body: l10n.settingsLeaveLogbookConfirm(name),
    confirmLabel: l10n.remove,
    destructive: true,
  );
  if (!confirmed || !context.mounted) return;

  onSyncingChanged(true);
  try {
    final activeId = context.read<ValueNotifier<String?>>().value;
    await LogbookService().removeMember(logbookId, uid);
    // Same hygiene-only cleanup as showDeleteLogbookDialog — see its comment.
    await LogbookKeyStore.forgetKey(logbookId);
    if (!context.mounted) return;
    // Same conditional-refresh rule as showDeleteLogbookDialog — see its
    // comment above for why onLogbooksChanged is only called when
    // reinitFirestore did NOT run.
    var reinitialized = false;
    if (activeId == logbookId) {
      final newActiveId = await LogbookService().getActiveLogbookId(uid);
      if (context.mounted && newActiveId != null) {
        final switched = await reinitFirestore(context, newActiveId);
        if (switched) {
          reinitialized = true;
        } else if (context.mounted) {
          // See showDeleteLogbookDialog's comment on the same pattern —
          // removeMember set newActiveId active server-side as a side
          // effect, so a failed reinit here needs the same local-state
          // wipe to stop stale data leaking into it on a later reattach.
          await _clearLocalStateAfterFailedReinit(context);
        }
      }
    }
    if (context.mounted) {
      onGuestsCollapse();
      if (!reinitialized) onLogbooksChanged();
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

/// Confirms, then makes [logbook] the active logbook for [uid] and
/// switches this device to it.
Future<void> switchLogbook(
  BuildContext context, {
  required Map<String, dynamic> logbook,
  required String uid,
  required ValueChanged<bool> onSyncingChanged,
  required VoidCallback onGuestsCollapse,
}) async {
  final l10n = context.l10n;
  final logbookId = logbook['logbookId'] as String;
  final name = logbook['name'] as String;

  final confirmed = await showConfirmDialog(
    context,
    title: l10n.settingsSwitchTo(name),
    confirmLabel: l10n.connect,
  );
  if (!confirmed || !context.mounted) return;

  onSyncingChanged(true);
  try {
    // reinitFirestore runs *before* setActiveLogbook — it can fail (network
    // blip, a momentary permission-check lag), and only committing the
    // server-side active-logbook pointer after a confirmed local switch
    // stops the server and the app from disagreeing about which logbook is
    // active (the same class of bug that used to let stale data leak into
    // whichever logbook was switched to). reinitFirestore's own
    // ValueNotifier<String?> write (on success) already triggers the
    // logbook-list refresh via the listener — see showNewLogbookDialog for
    // the same reasoning.
    final switched = await reinitFirestore(context, logbookId,
        showCompleteSnackbar: false);
    if (!switched) return;
    await LogbookService().setActiveLogbook(uid, logbookId);
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

/// Looks up [rawCode], confirms with the user, joins as a guest, and
/// switches this device to the found logbook. If [keyBase64] is given (only
/// ever true for a QR-scanned code — see connect_bottom_sheet.dart), it's
/// imported as this device's copy of the logbook's shared encryption key
/// once the join succeeds, so this device can decrypt existing content
/// immediately rather than only gaining bare membership.
Future<void> joinLogbook(
  BuildContext context, {
  required String rawCode,
  String? keyBase64,
  required ValueChanged<bool> onSyncingChanged,
  required VoidCallback onGuestsCollapse,
}) async {
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

  onSyncingChanged(true);
  String? foundLogbookId;
  String? logbookName;
  try {
    foundLogbookId = await LogbookService().findByShareCode(code);
    if (foundLogbookId != null) {
      final alreadyMember =
          await LogbookService().isMember(foundLogbookId, user.uid);
      if (!context.mounted) return;
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
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${l10n.settingsError}: $e')),
      );
    }
    return;
  } finally {
    if (context.mounted) onSyncingChanged(false);
  }
  if (!context.mounted) return;

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
    title: l10n.settingsSwitchLogbookTitle,
    body: l10n.settingsJoinContent(resolvedName),
    confirmLabel: l10n.connect,
  );
  if (!confirmed || !context.mounted) return;

  onSyncingChanged(true);
  try {
    // Adds the membership doc (needed before reinitFirestore can read this
    // logbook at all) but deliberately does not mark it active yet — see
    // its doc comment. Only commit that once the local switch has actually
    // succeeded, so the server and the app can't end up disagreeing about
    // which logbook is active (the same class of bug that used to let
    // stale data leak into whichever logbook was joined).
    await LogbookService().joinLogbook(resolvedId, user.uid,
        displayName: user.displayName, email: user.email);
    // Import the shared key (if the QR scan carried one) before syncing
    // this logbook's data below, so entries decrypt correctly from the
    // very first fetch rather than needing a second sync pass once the
    // key arrives.
    if (keyBase64 != null) {
      await LogbookKeyStore.importKeyBase64(resolvedId, keyBase64);
    }
    if (!context.mounted) return;
    final switched = await reinitFirestore(context, resolvedId,
        showCompleteSnackbar: false);
    if (!switched) return;
    await LogbookService().setActiveLogbook(user.uid, resolvedId);
    if (context.mounted) {
      onGuestsCollapse();
      FocusScope.of(context).unfocus();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.settingsJoinedLogbook(resolvedName))),
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
