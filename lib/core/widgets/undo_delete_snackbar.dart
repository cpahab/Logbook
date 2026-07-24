import 'package:flutter/material.dart';

import '../../l10n/l10n_extension.dart';

/// Shows a delete-with-undo snackbar: the caller must already have removed
/// the item *before* calling this (matching the app's existing timeline-entry
/// delete pattern, day_detail_screen.dart) — this only offers the user a
/// window to reverse it via [onUndo], it doesn't perform the delete itself.
///
/// Used to give every "remove one item from a list" action in the app
/// (Crew Roster, Emergency Contacts, VHF frequencies, Equipment states) the
/// same single policy: instant delete, no blocking confirmation dialog, with
/// a consistent safety net.
void showUndoDeleteSnackBar(
  BuildContext context, {
  required String message,
  required VoidCallback onUndo,
}) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(message),
    // Longer than the default 4s: this snackbar carries an undo action, so
    // it needs enough time to notice, read, and react — still well within
    // Material's own guidance of 4-10s for actionable snackbars.
    duration: const Duration(seconds: 10),
    // SnackBar defaults `persist` to true whenever `action` is set (see its
    // own doc comment), which makes it ignore `duration` entirely and stay
    // open until manually dismissed. Without this, the 10s above is a
    // no-op — the snackbar just... never times out.
    persist: false,
    action: SnackBarAction(
      label: context.l10n.undo,
      onPressed: onUndo,
    ),
  ));
}
