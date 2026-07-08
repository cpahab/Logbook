import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../app/theme/theme_extensions.dart';
import '../../l10n/l10n_extension.dart';

/// Gatekeeper in front of the OS location-permission prompt: shows our own
/// plain-language explanation dialog first, so the user isn't hit with the
/// system prompt (which most people reflexively deny) without context.
class GpsConsentService {
  /// Shows the explanation dialog once, then triggers the OS permission
  /// prompt.  Returns immediately if permission is already resolved.
  static Future<void> requestIfNeeded(BuildContext context) async {
    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse ||
        permission == LocationPermission.deniedForever) {
      return;
    }
    if (!context.mounted) return;

    // ── Explanation dialog (title + body + Later/Allow actions) ──
    final allowed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        final l10n = ctx.l10n;
        return AlertDialog(
          backgroundColor: cs.surface,
          surfaceTintColor: Colors.transparent,
          title: Text(
            l10n.gpsConsentTitle,
            style: Theme.of(ctx).textTheme.fieldValueProse.copyWith(
              color: cs.onSurface,
            ),
          ),
          content: Text(
            l10n.gpsConsentContent,
            style: TextStyle(fontSize: 14, height: 1.5, color: cs.onSurfaceVariant),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l10n.gpsConsentLater),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l10n.gpsConsentAllow),
            ),
          ],
        );
      },
    ); // ── end explanation dialog ──

    if (allowed == true) {
      await Geolocator.requestPermission();
    }
  }
}
