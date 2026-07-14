import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../l10n/l10n_extension.dart';
import '../widgets/confirm_dialog.dart';

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

    final allowed = await showConfirmDialog(
      context,
      title: context.l10n.gpsConsentTitle,
      body: context.l10n.gpsConsentContent,
      confirmLabel: context.l10n.gpsConsentAllow,
    );

    if (allowed) {
      await Geolocator.requestPermission();
    }
  }
}
