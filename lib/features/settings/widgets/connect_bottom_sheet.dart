import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../l10n/l10n_extension.dart';

// ── Connect bottom sheet (scan) ───────────────────────────────────────────────
/// QR-only sheet for joining another logbook. Calls [onCode] with the
/// resolved 8-char code and the encryption key embedded in the scanned
/// payload's `?key=` query param.
///
/// Manual code entry (no camera) used to be offered as a second tab here,
/// but a manual-only join can't practically carry a 256-bit key — a guest
/// joining that way became a Firestore member but couldn't decrypt any
/// actual content (notes, crew, timeline text, photos, tracks), which is a
/// confusing half-working state. QR scanning is now the only join path so
/// every successful join comes with working decryption from the start.
class ConnectBottomSheet extends StatefulWidget {
  final Future<void> Function(String code, {String? keyBase64}) onCode;
  const ConnectBottomSheet({super.key, required this.onCode});

  @override
  State<ConnectBottomSheet> createState() => _ConnectBottomSheetState();
}

class _ConnectBottomSheetState extends State<ConnectBottomSheet> {
  final MobileScannerController _scanCtrl = MobileScannerController();
  bool _scanHandled = false;

  @override
  void dispose() {
    _scanCtrl.dispose();
    super.dispose();
  }

  /// Handles a scanned QR code: strips the `logbook://join/` scheme prefix
  /// if present, extracts the `?key=` query param (the sharer's base64
  /// logbook encryption key — see logbook_dialogs.dart's showQrModal), then
  /// closes the sheet and reports both to [onCode].
  void _onDetect(BarcodeCapture capture) {
    if (_scanHandled) return;
    final raw = capture.barcodes.firstOrNull?.rawValue;
    if (raw == null || raw.isEmpty) return;
    _scanHandled = true;
    const scheme = 'logbook://join/';
    String code = raw;
    String? keyBase64;
    if (raw.startsWith(scheme)) {
      // 'logbook://join/ABCD1234?key=...' parses with 'join' as the URI's
      // authority (host) and '/ABCD1234' as its path — pathSegments strips
      // the leading slash back off.
      final uri = Uri.tryParse(raw);
      final firstSegment = uri?.pathSegments.firstOrNull;
      code = firstSegment != null && firstSegment.isNotEmpty
          ? firstSegment
          : raw.substring(scheme.length).split('?').first;
      keyBase64 = uri?.queryParameters['key'];
    }
    Navigator.pop(context);
    widget.onCode(code, keyBase64: keyBase64);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;

    return Column(
      children: [
        const SizedBox(height: 8),
        Container(
          width: 36,
          height: 4,
          decoration: BoxDecoration(
              color: cs.outlineVariant,
              borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(l10n.settingsScanTitle,
              style: Theme.of(context)
                  .textTheme
                  .bodyLarge!
                  .copyWith(fontWeight: FontWeight.w600, color: cs.onSurface)),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: MobileScanner(controller: _scanCtrl, onDetect: _onDetect),
            ),
          ),
        ),
      ],
    );
  }
}
