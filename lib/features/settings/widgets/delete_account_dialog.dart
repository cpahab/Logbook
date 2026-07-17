import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/theme/theme_extensions.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/logbook_service.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../l10n/l10n_extension.dart';
import '../../emergency/data/emergency_repository.dart';
import '../../home/data/home_repository.dart';
import '../domain/theme_provider.dart';

/// Confirms, then permanently deletes [uid]'s account: all Firestore/
/// Storage data for every logbook it owns or is a member of, all local
/// caches, and finally the Firebase Auth account itself. Aborts before
/// deleting the Auth account if Firestore cleanup fails, to avoid leaving
/// orphaned cloud data with no owner. [onSyncingChanged] drives the
/// caller's sync-spinner state (e.g. disabling other actions mid-flow).
Future<void> runDeleteAccountFlow(
  BuildContext context, {
  required String uid,
  required ValueChanged<bool> onSyncingChanged,
}) async {
  final l10n = context.l10n;
  final confirmed = await showConfirmDialog(
    context,
    title: l10n.authDeleteAccount,
    body: l10n.authDeleteAccountConfirm,
    confirmLabel: l10n.authDeleteAccount,
    destructive: true,
  );
  if (!confirmed || !context.mounted) return;

  // Block deletion when offline — Firestore cleanup would fail silently
  // and the Auth account would still be deleted.
  final connResults = await Connectivity().checkConnectivity();
  if (!context.mounted) return;
  if (connResults.every((r) => r == ConnectivityResult.none)) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.authErrorNetworkFailed)),
    );
    return;
  }

  onSyncingChanged(true);
  // Capture refs before any await.
  final repo = context.read<HomeRepository>();
  final emergencyRepo = context.read<EmergencyRepository>();
  final themeProvider = context.read<ThemeProvider>();
  final authService = context.read<AuthService>();

  // 1. Delete all Firestore data. Abort if any cleanup fails — do NOT
  //    delete the Auth account and leave orphaned data.
  try {
    await LogbookService().deleteUserAndAllLogbooks(uid);
  } catch (_) {
    if (!context.mounted) return;
    onSyncingChanged(false);
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        final dcs = Theme.of(ctx).colorScheme;
        return AlertDialog(
          backgroundColor: dcs.surface,
          surfaceTintColor: Colors.transparent,
          icon: Icon(Icons.cloud_off_rounded, color: dcs.error),
          title: Text(
            l10n.authDeleteCleanupFailedTitle,
            style: Theme.of(ctx).textTheme.fieldValueProse.copyWith(color: dcs.onSurface),
          ),
          content: Text(
            l10n.authDeleteCleanupFailedBody,
            style: Theme.of(ctx).textTheme.bodyMedium!.copyWith(
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

  // 3. Delete the Firebase Auth account only if Firestore cleanup
  //    succeeded. Router redirect to /auth/login happens automatically
  //    via authService.notifyListeners().
  try {
    await authService.deleteAccount();
  } on FirebaseAuthException catch (e) {
    if (!context.mounted) return;
    onSyncingChanged(false);
    final msg = e.code == 'requires-recent-login'
        ? l10n.authErrorRequiresRecentLogin
        : (e.message ?? l10n.authErrorGeneric);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  } catch (_) {
    if (context.mounted) onSyncingChanged(false);
  }
}
