import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../settings/domain/theme_provider.dart';

enum NavTab { journal, map, weather, settings }

/// Bottom navigation bar — Maritime Journal design system.
///
/// [withCompass] — detail screen variant: raised compass button in the
/// centre slot (replaces the Map tab).
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
  static const double _compassRise = 28;
  static const Color _navBg = Color(0xFF142435); // tertiary

  static double totalHeight(BuildContext context) =>
      _navHeight + MediaQuery.viewPaddingOf(context).bottom;

  Future<void> _launchWeather(BuildContext context) async {
    final url = context.read<ThemeProvider>().weatherUrl;
    if (url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final safeBottom = MediaQuery.viewPaddingOf(context).bottom;
    final totalH = _navHeight + safeBottom + (withCompass ? _compassRise : 0);

    return SizedBox(
      height: totalH,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // ── Nav bar container ─────────────────────────────────────
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
                    color: Color(0x1A000000),
                    blurRadius: 12,
                    offset: Offset(0, -4),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _tab(context, cs, NavTab.journal, Icons.menu_book_rounded, 'Journal'),
                  if (withCompass)
                    const SizedBox(width: 56)
                  else
                    _tab(context, cs, NavTab.map, Icons.explore, 'Karte'),
                  _tab(context, cs, NavTab.weather, Icons.cloud_outlined, 'Wetter'),
                  _tab(context, cs, NavTab.settings, Icons.settings_outlined, 'Einstellg.'),
                ],
              ),
            ),
          ),

          // ── Raised compass button (detail screen only) ────────────
          if (withCompass)
            Positioned(
              top: 0, left: 0, right: 0,
              child: Center(
                child: GestureDetector(
                  onTap: onCompassTap,
                  child: Container(
                    width: 56, height: 56,
                    decoration: BoxDecoration(
                      color: cs.primary,
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
                    child: Icon(Icons.explore,
                        color: cs.secondaryContainer, size: 26),
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

    // Weather tap opens URL directly — no routing needed.
    void handleTap() {
      if (tab == NavTab.weather) {
        _launchWeather(context);
      } else {
        onSelect?.call(tab);
      }
    }

    if (isActive) {
      return GestureDetector(
        onTap: handleTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: cs.primaryContainer,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: cs.secondary, size: 22),
              const SizedBox(height: 2),
              Text(
                label.toUpperCase(),
                style: GoogleFonts.inter(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                  color: cs.secondary,
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
