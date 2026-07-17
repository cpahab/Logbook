import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../l10n/l10n_extension.dart';

// ── Connect bottom sheet (scan / enter code) ─────────────────────────────────
/// Two-tab sheet for joining another logbook: a QR scanner tab and a
/// type-the-code tab, both calling [onCode] with the resolved 8-char code.
class ConnectBottomSheet extends StatefulWidget {
  final Future<void> Function(String code) onCode;
  const ConnectBottomSheet({super.key, required this.onCode});

  @override
  State<ConnectBottomSheet> createState() => _ConnectBottomSheetState();
}

class _ConnectBottomSheetState extends State<ConnectBottomSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final MobileScannerController _scanCtrl = MobileScannerController();
  final TextEditingController _codeCtrl = TextEditingController();
  bool _scanHandled = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) return;
      if (_tabController.index == 0) {
        _scanHandled = false;
        _scanCtrl.start();
      } else {
        _scanCtrl.stop();
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _scanCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  /// Handles a scanned QR code: strips the `logbook://join/` scheme prefix
  /// if present, then closes the sheet and reports the code.
  void _onDetect(BarcodeCapture capture) {
    if (_scanHandled) return;
    final raw = capture.barcodes.firstOrNull?.rawValue;
    if (raw == null || raw.isEmpty) return;
    _scanHandled = true;
    const scheme = 'logbook://join/';
    final code = raw.startsWith(scheme) ? raw.substring(scheme.length) : raw;
    Navigator.pop(context);
    widget.onCode(code);
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
        TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: l10n.settingsScanTitle),
            Tab(text: l10n.settingsEnterInviteCode),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              // Scan tab
              Padding(
                padding: const EdgeInsets.all(16),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child:
                      MobileScanner(controller: _scanCtrl, onDetect: _onDetect),
                ),
              ),
              // Enter code tab
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 8),
                    TextField(
                      controller: _codeCtrl,
                      textCapitalization: TextCapitalization.characters,
                      style: TextStyle(color: cs.onSurface),
                      decoration: InputDecoration(
                        hintText: l10n.settingsEnterInviteCode,
                        hintStyle: TextStyle(color: cs.onSurfaceVariant),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8)),
                        enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide:
                                BorderSide(color: cs.outlineVariant)),
                        focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: cs.primary, width: 2)),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        filled: true,
                        fillColor: cs.surfaceContainerLow,
                      ),
                      onSubmitted: (v) {
                        if (v.trim().isNotEmpty) {
                          Navigator.pop(context);
                          widget.onCode(v);
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: () {
                        final code = _codeCtrl.text;
                        if (code.trim().isNotEmpty) {
                          Navigator.pop(context);
                          widget.onCode(code);
                        }
                      },
                      child: Text(l10n.connect),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
