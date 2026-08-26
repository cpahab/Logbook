import 'dart:io';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../l10n/l10n_extension.dart';
import '../widgets/confirm_dialog.dart';

/// Gatekeeper in front of the OS location-permission prompt: shows our own
/// plain-language explanation dialog first, so the user isn't hit with the
/// system prompt (which most people reflexively deny) without context.
class GpsConsentService {
  static bool _isResolved(LocationPermission permission) =>
      permission == LocationPermission.always ||
      permission == LocationPermission.whileInUse ||
      permission == LocationPermission.deniedForever;

  /// Shows the explanation dialog once, then triggers the OS permission
  /// prompt.  Returns immediately if permission is already resolved.
  static Future<void> requestIfNeeded(BuildContext context) async {
    var permission = await Geolocator.checkPermission();
    if (_isResolved(permission)) return;

    // A freshly-created CLLocationManager on macOS briefly reports a stale
    // "not determined" status immediately on cold launch, even when the user
    // already granted access in a previous session — it corrects itself
    // about a second later once CoreLocation's internal state has synced
    // with the OS (confirmed empirically: an immediate read returned 0/not-
    // determined, a read one second later on the same manager correctly
    // returned 3/authorizedAlways). Without this recheck, this dialog (and
    // the OS's own, right behind it) reappeared on every single launch.
    if (Platform.isMacOS) {
      await Future.delayed(const Duration(seconds: 1));
      permission = await Geolocator.checkPermission();
      if (_isResolved(permission)) return;
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
