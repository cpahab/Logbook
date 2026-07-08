import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';

import '../../../app/theme/theme_extensions.dart';
import '../../../l10n/l10n_extension.dart';

/// The 4 destinations reachable from the bottom nav bar.
enum NavTab { journal, map, settings, safety }

/// App-wide bottom navigation bar: 4 tabs plus an optional raised centre FAB
/// (shown only on the journal/day-detail screens) and an offline indicator
/// that appears automatically when connectivity drops.
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

  /// The full height this nav bar occupies (nav strip + FAB rise + safe-area
  /// inset) — use to size a `Scaffold` body's bottom padding.
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

  /// True only when every reported connectivity type is "none" — a device
  /// can report multiple simultaneous interfaces, so any single active one
  /// means online.
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
                        Expanded(child: Center(child: _tab(context, cs, NavTab.journal, Icons.auto_stories, context.l10n.navJournal))),
                        Expanded(child: Center(child: _tab(context, cs, NavTab.map, Icons.explore, context.l10n.navTracks))),
                        const SizedBox(width: 64),
                        Expanded(child: Center(child: _tab(context, cs, NavTab.settings, Icons.settings_outlined, context.l10n.navSettings))),
                        Expanded(child: Center(child: _tab(context, cs, NavTab.safety, Icons.health_and_safety, context.l10n.navSafety))),
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
                                context.l10n.offlineLabel,
                                style: Theme.of(context).textTheme.bodyMedium!.copyWith(
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
          // ── end nav bar ──

          // ── Raised centre FAB (journal & day-detail only) ─────────
          if (widget.showFab)
            Positioned(
              top: 0, left: 0, right: 0,
              child: Center(
                child: Tooltip(
                  message: context.l10n.add,
                  child: Semantics(
                    label: context.l10n.add,
                    button: true,
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
              ),
            ),
          // ── end raised centre FAB ──
        ],
      ),
    );
  }

  /// One tab's icon + label, active state shown purely via gold coloring
  /// (no background pill).
  Widget _tab(BuildContext context, ColorScheme cs, NavTab tab,
      IconData icon, String label) {
    final isActive = widget.active == tab;
    // Active state reads purely from the gold icon/label — no pill. Uses the
    // paler secondaryContainer gold (matches the custom-range picker highlight).
    final color = isActive ? cs.secondaryContainer : cs.onTertiaryContainer;

    return InkWell(
      onTap: () => widget.onSelect?.call(tab),
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(height: 2),
              Text(
                label.toUpperCase(),
                maxLines: 1,
                style: Theme.of(context).textTheme.microLabel.copyWith(
                  letterSpacing: 0.5,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
