import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

enum NavTab { logbook, maps, weather, settings }

/// Bottom navigation bar matching the Stitch design.
///
/// [withCompass] — detail screen variant: shows a raised compass button in
/// the centre slot (5 items). Home screen uses 4 items, no compass.
class AppBottomNav extends StatelessWidget {
  final NavTab active;
  final bool withCompass;
  final VoidCallback? onCompassTap;
  final void Function(NavTab tab)? onSelect;

  const AppBottomNav({
    super.key,
    required this.active,
    this.withCompass = false,
    this.onCompassTap,
    this.onSelect,
  });

  static const double _navHeight = 64;
  static const double _compassRise = 28; // how many px compass floats above bar

  /// Total height consumed from the Scaffold bottom — includes compass rise
  /// so the body is scrollable underneath the full raised button.
  static double totalHeight(BuildContext context) =>
      _navHeight +
      (MediaQuery.viewPaddingOf(context).bottom) +
      0; // compass rise is handled inside the stack

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final safeBottom = MediaQuery.viewPaddingOf(context).bottom;

    // For the compass variant we allocate extra height at the top so the
    // raised button is fully visible and tappable within the widget bounds.
    final totalH = _navHeight + safeBottom + (withCompass ? _compassRise : 0);

    return SizedBox(
      height: totalH,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // ── Nav bar container ───────────────────────────────────
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              height: _navHeight + safeBottom,
              padding: EdgeInsets.only(bottom: safeBottom),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHigh,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(12)),
                border: Border(
                    top: BorderSide(
                        color: cs.outlineVariant.withValues(alpha: 0.8),
                        width: 0.5)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 12,
                    offset: const Offset(0, -3),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _tab(context, cs, NavTab.logbook, Icons.sailing, 'Logbook'),
                  if (withCompass)
                    const SizedBox(width: 56)
                  else
                    _tab(context, cs, NavTab.maps, Icons.map, 'Karte'),
                  _tab(context, cs, NavTab.weather, Icons.air, 'Wetter'),
                  _tab(context, cs, NavTab.settings,
                      Icons.settings_outlined, 'Einstell.'),
                ],
              ),
            ),
          ),

          // ── Raised compass button (detail screen only) ──────────
          if (withCompass)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Center(
                child: GestureDetector(
                  onTap: onCompassTap,
                  child: Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: cs.primary,
                      shape: BoxShape.circle,
                      border: Border.all(color: cs.surface, width: 4),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.25),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Icon(Icons.explore,
                        color: cs.tertiaryFixed, size: 26),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _tab(BuildContext context, ColorScheme cs, NavTab tab, IconData icon,
      String label) {
    final isActive = active == tab;

    if (isActive) {
      return GestureDetector(
        onTap: () => onSelect?.call(tab),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: cs.primary,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: cs.onPrimary, size: 22),
              const SizedBox(height: 2),
              Text(
                label.toUpperCase(),
                style: GoogleFonts.inter(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                  color: cs.onPrimary,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return InkWell(
      onTap: () => onSelect?.call(tab),
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: cs.onSurfaceVariant, size: 22),
            const SizedBox(height: 2),
            Text(
              label.toUpperCase(),
              style: GoogleFonts.inter(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
