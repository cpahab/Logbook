import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

enum NavTab { journal, map, settings, safety }

class AppBottomNav extends StatelessWidget {
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
  static const Color _navBg = Color(0xFF2A3A4C);

  static double totalHeight(BuildContext context) =>
      _navHeight + _fabRise + MediaQuery.viewPaddingOf(context).bottom;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final safeBottom = MediaQuery.viewPaddingOf(context).bottom;
    final totalH = _navHeight + safeBottom + (showFab ? _fabRise : 0);

    return SizedBox(
      height: totalH,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // ── Nav bar ───────────────────────────────────────────────
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: Container(
              height: _navHeight + safeBottom,
              padding: EdgeInsets.only(bottom: safeBottom),
              decoration: const BoxDecoration(
                color: _navBg,
                borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
                boxShadow: [
                  BoxShadow(
                    color: Color(0x33000000),
                    blurRadius: 16,
                    offset: Offset(0, -4),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _tab(context, cs, NavTab.journal, Icons.auto_stories, 'Journal'),
                  _tab(context, cs, NavTab.map, Icons.explore, 'Karte'),
                  const SizedBox(width: 64),
                  _tab(context, cs, NavTab.settings, Icons.settings_outlined, 'Einstellg.'),
                  _tab(context, cs, NavTab.safety, Icons.health_and_safety, 'Sicherheit'),
                ],
              ),
            ),
          ),

          // ── Raised centre FAB (journal & day-detail only) ─────────
          if (showFab)
            Positioned(
              top: 0, left: 0, right: 0,
              child: Center(
                child: GestureDetector(
                  onTap: onFabTap,
                  child: Container(
                    width: 64, height: 64,
                    decoration: BoxDecoration(
                      color: cs.primaryContainer,
                      shape: BoxShape.circle,
                      border: Border.all(color: _navBg, width: 4),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.25),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.add, color: Colors.white, size: 30),
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
    final isActive = active == tab;
    const inactiveColor = Color(0xFF93A4B9); // on-tertiary-container

    void handleTap() => onSelect?.call(tab);

    if (isActive) {
      return GestureDetector(
        onTap: handleTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: cs.secondaryContainer,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: cs.onSecondaryContainer, size: 22),
              const SizedBox(height: 2),
              Text(
                label.toUpperCase(),
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
      );
    }

    return InkWell(
      onTap: handleTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: inactiveColor, size: 22),
            const SizedBox(height: 2),
            Text(
              label.toUpperCase(),
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
    );
  }
}
