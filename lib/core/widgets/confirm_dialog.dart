import 'package:flutter/material.dart';

import '../../app/theme/theme_extensions.dart';
import '../../l10n/l10n_extension.dart';

/// Shows a standard confirmation dialog (title + body + Cancel/confirm
/// actions), styled consistently across the app, and returns true only if
/// the user tapped the confirm action.
///
/// Pass either [body] (a plain string, wrapped in `Text`) or [content] (a
/// custom widget, e.g. text plus a conditional warning) — not both. Set
/// [destructive] for actions that delete or replace data: the confirm
/// button becomes an error-colored fill instead of the default emphasis.
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  String? body,
  Widget? content,
  required String confirmLabel,
  bool destructive = false,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      final cs = Theme.of(ctx).colorScheme;
      return AlertDialog(
        backgroundColor: cs.surface,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: Theme.of(ctx).textTheme.fieldValueProse.copyWith(color: cs.onSurface),
        contentTextStyle: Theme.of(ctx).textTheme.bodyMedium!.copyWith(color: cs.onSurfaceVariant),
        title: Text(title),
        content: content ?? (body != null ? Text(body) : null),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(ctx.l10n.cancel),
          ),
          FilledButton(
            style: destructive
                ? FilledButton.styleFrom(backgroundColor: cs.error, foregroundColor: cs.onError)
                : null,
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmLabel),
          ),
        ],
      );
    },
  );
  return confirmed == true;
}
