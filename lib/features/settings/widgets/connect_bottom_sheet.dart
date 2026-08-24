import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../l10n/l10n_extension.dart';

/// Parses a scanned or pasted logbook join payload: strips the
/// `logbook://join/` scheme prefix if present and extracts the `?key=`
/// query param (the sharer's base64 logbook encryption key — see
/// logbook_dialogs.dart's showQrModal). Returns the resolved code and key,
/// or null if [raw] is empty.
({String code, String? keyBase64})? parseLogbookJoinPayload(String raw) {
  if (raw.isEmpty) return null;
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
  return (code: code, keyBase64: keyBase64);
}

// ── Connect bottom sheet (scan) ───────────────────────────────────────────────
/// Sheet for joining another logbook: scan its QR code, or paste the same
/// code+key payload copied from another device (see logbook_dialogs.dart's
/// showQrModal) — for a device with no camera, e.g. a Mac Mini/Studio/Pro.
/// Calls [onCode] with the resolved 8-char code and the encryption key
/// embedded in the payload's `?key=` query param.
///
/// A bare manual code (typed, no key) used to be offered instead of paste,
/// but a manual-only join can't practically carry a 256-bit key — a guest
/// joining that way became a Firestore member but couldn't decrypt any
/// actual content (notes, crew, timeline text, photos, tracks), which is a
/// confusing half-working state. Pasting the full payload (rather than
/// typing it) carries the key just as reliably as scanning does, so it
/// doesn't have that problem.
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

  void _onDetect(BarcodeCapture capture) {
    if (_scanHandled) return;
    final raw = capture.barcodes.firstOrNull?.rawValue;
    final parsed = raw == null ? null : parseLogbookJoinPayload(raw);
    if (parsed == null) return;
    _scanHandled = true;
    Navigator.pop(context);
    widget.onCode(parsed.code, keyBase64: parsed.keyBase64);
  }

  Future<void> _pasteCode() async {
    final l10n = context.l10n;
    final ctrl = TextEditingController();
    final pasted = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.settingsPasteCodeTitle),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(hintText: l10n.settingsPasteCodeHint),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: Text(l10n.settingsPasteCodeSubmit),
          ),
        ],
      ),
    );
    if (pasted == null || pasted.isEmpty) return;
    final parsed = parseLogbookJoinPayload(pasted);
    if (parsed == null) return;
    if (!mounted) return;
    if (parsed.keyBase64 == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.settingsPasteCodeInvalid)),
      );
      return;
    }
    Navigator.pop(context);
    widget.onCode(parsed.code, keyBase64: parsed.keyBase64);
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
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: TextButton(
            onPressed: _pasteCode,
            child: Text(l10n.settingsPasteCodeButton),
          ),
        ),
      ],
    );
  }
}
