import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';

class GpsConsentService {
  /// Shows a purpose-explanation dialog once, then triggers the OS permission
  /// prompt.  Returns immediately if permission is already resolved.
  static Future<void> requestIfNeeded(BuildContext context) async {
    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse ||
        permission == LocationPermission.deniedForever) {
      return;
    }
    if (!context.mounted) return;

    final allowed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return AlertDialog(
          title: Text(
            'GPS für den Notfall',
            style: GoogleFonts.newsreader(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: cs.onSurface,
            ),
          ),
          content: const Text(
            'Beim Aktivieren des Funk-Notrufs ermittelt die App Ihren GPS-Standort '
            'und trägt ihn automatisch ins Mayday-Protokoll ein, damit Rettungskräfte '
            'Ihre genaue Position sofort erhalten. '
            'Der Standort wird ausschliesslich in diesem Moment genutzt.',
            style: TextStyle(fontSize: 14, height: 1.5),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Später'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Zugriff erlauben'),
            ),
          ],
        );
      },
    );

    if (allowed == true) {
      await Geolocator.requestPermission();
    }
  }
}
