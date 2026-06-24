import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../l10n/l10n_extension.dart';

enum NavTab { journal, map, settings, safety }

class AppBottomNav extends StatefulWidget {
  final NavTab active;
  final VoidCallback? onFabTap;
  final void Function(NavTab tab)? onSelect;
  final bool showFab;

  const AppBottomNav({
    super.key,
    required this.active,
    this.onFabTap,
    this.onSelect,
    this.showFab = true,
  });

  static const double _navHeight = 64;
  static const double _fabRise = 24;

  static double totalHeight(BuildContext context) =>
      _navHeight + _fabRise + MediaQuery.viewPaddingOf(context).bottom;

  @override
  State<AppBottomNav> createState() => _AppBottomNavState();
}

class _AppBottomNavState extends State<AppBottomNav> {
  bool _isOffline = false;
  StreamSubscription<List<ConnectivityResult>>? _sub;

  @override
  void initState() {
    super.initState();
    Connectivity().checkConnectivity().then((results) {
      if (mounted) setState(() => _isOffline = _allNone(results));
    });
    _sub = Connectivity().onConnectivityChanged.listen((results) {
      if (mounted) setState(() => _isOffline = _allNone(results));
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  static bool _allNone(List<ConnectivityResult> r) =>
      r.every((c) => c == ConnectivityResult.none);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final safeBottom = MediaQuery.viewPaddingOf(context).bottom;
    final totalH = AppBottomNav._navHeight + safeBottom +
        (widget.showFab ? AppBottomNav._fabRise : 0);

    return SizedBox(
      height: totalH,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // ── Nav bar ───────────────────────────────────────────────
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: Container(
              height: AppBottomNav._navHeight + safeBottom,
              decoration: BoxDecoration(
                color: cs.tertiaryContainer,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(12)),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x33000000),
                    blurRadius: 16,
                    offset: Offset(0, -4),
                  ),
                ],
              ),
              child: Stack(
                children: [
                  // Tab row pinned to top of the container
                  Positioned(
                    top: 0, left: 0, right: 0,
                    height: AppBottomNav._navHeight,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(child: Center(child: _tab(context, cs, NavTab.journal, Icons.auto_stories, 'Journal'))),
                        Expanded(child: Center(child: _tab(context, cs, NavTab.map, Icons.explore, context.l10n.tracksTitle))),
                        const SizedBox(width: 64),
                        Expanded(child: Center(child: _tab(context, cs, NavTab.settings, Icons.settings_outlined, 'Einstellungen'))),
                        Expanded(child: Center(child: _tab(context, cs, NavTab.safety, Icons.health_and_safety, 'Sicherheit'))),
                      ],
                    ),
                  ),
                  // Offline indicator pinned to the very bottom (sits in safe area)
                  if (_isOffline)
                    Positioned(
                      bottom: 0, left: 0, right: 0,
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 3),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.wifi_off,
                                size: 10,
                                color: cs.onTertiaryContainer
                                    .withValues(alpha: 0.45),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Offline',
                                style: GoogleFonts.inter(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w500,
                                  color: cs.onTertiaryContainer
                                      .withValues(alpha: 0.45),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),

          // ── Raised centre FAB (journal & day-detail only) ─────────
          if (widget.showFab)
            Positioned(
              top: 0, left: 0, right: 0,
              child: Center(
                child: GestureDetector(
                  onTap: widget.onFabTap,
                  child: Container(
                    width: 64, height: 64,
                    decoration: BoxDecoration(
                      color: cs.primaryContainer,
                      shape: BoxShape.circle,
                      border: Border.all(color: cs.tertiaryContainer, width: 4),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.25),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Icon(Icons.add, color: cs.onPrimaryContainer, size: 30),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _tab(BuildContext context, ColorScheme cs, NavTab tab,
      IconData icon, String label) {
    final isActive = widget.active == tab;
    final inactiveColor = cs.onTertiaryContainer;

    void handleTap() => widget.onSelect?.call(tab);

    if (isActive) {
      return GestureDetector(
        onTap: handleTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: cs.secondaryContainer,
            borderRadius: BorderRadius.circular(24),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: cs.onSecondaryContainer, size: 22),
                const SizedBox(height: 2),
                Text(
                  label.toUpperCase(),
                  maxLines: 1,
                  style: GoogleFonts.inter(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                    color: cs.onSecondaryContainer,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return InkWell(
      onTap: handleTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: inactiveColor, size: 22),
              const SizedBox(height: 2),
              Text(
                label.toUpperCase(),
                maxLines: 1,
                style: GoogleFonts.inter(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                  color: inactiveColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
