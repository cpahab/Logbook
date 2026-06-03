import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// Maritime Journal — Stitch design system, light theme
const _primary            = Color(0xFF002444); // Deep Navy
const _primaryContainer   = Color(0xFF1A3A5C);
const _gold               = Color(0xFFFFE088); // Captain's Gold  (secondaryContainer)
const _seafoam            = Color(0xFFB7C8DE); // Seafoam accent  (tertiaryFixedDim)

TextTheme _buildTextTheme() {
  final base = GoogleFonts.interTextTheme();
  return base.copyWith(
    displayLarge:  GoogleFonts.newsreader(textStyle: base.displayLarge),
    displayMedium: GoogleFonts.newsreader(textStyle: base.displayMedium),
    displaySmall:  GoogleFonts.newsreader(textStyle: base.displaySmall),
    headlineLarge:  GoogleFonts.newsreader(
        textStyle: base.headlineLarge?.copyWith(fontWeight: FontWeight.w500)),
    headlineMedium: GoogleFonts.newsreader(
        textStyle: base.headlineMedium?.copyWith(fontWeight: FontWeight.w500)),
    headlineSmall:  GoogleFonts.newsreader(
        textStyle: base.headlineSmall?.copyWith(fontWeight: FontWeight.w600)),
  );
}

final ThemeData lightTheme = ThemeData(
  useMaterial3: true,
  colorScheme: const ColorScheme(
    brightness: Brightness.light,
    // ── Primary — Deep Navy ─────────────────────────────────────────
    primary:            Color(0xFF002444),
    onPrimary:          Color(0xFFFFFFFF),
    primaryContainer:   Color(0xFF1A3A5C),
    onPrimaryContainer: Color(0xFF87A4CC),
    inversePrimary:     Color(0xFFABC9F2),
    // ── Secondary — Captain's Gold ──────────────────────────────────
    secondary:            Color(0xFF725C10),
    onSecondary:          Color(0xFFFFFFFF),
    secondaryContainer:   Color(0xFFFFE088),
    onSecondaryContainer: Color(0xFF786216),
    // ── Tertiary — Seafoam / Dark Navy ─────────────────────────────
    tertiary:            Color(0xFF142435),
    onTertiary:          Color(0xFFFFFFFF),
    tertiaryContainer:   Color(0xFF2A3A4C),
    onTertiaryContainer: Color(0xFF93A4B9),
    // ── Error ───────────────────────────────────────────────────────
    error:            Color(0xFFBA1A1A),
    onError:          Color(0xFFFFFFFF),
    errorContainer:   Color(0xFFFFDAD6),
    onErrorContainer: Color(0xFF93000A),
    // ── Neutrals ───────────────────────────────────────────────────
    surface:            Color(0xFFFAF9FA),
    onSurface:          Color(0xFF1B1C1D),
    onSurfaceVariant:   Color(0xFF43474E),
    surfaceContainerHighest: Color(0xFFE3E2E3),
    outline:            Color(0xFF73777F),
    outlineVariant:     Color(0xFFC3C6CF),
    inverseSurface:     Color(0xFF303031),
    onInverseSurface:   Color(0xFFF2F0F1),
    scrim:              Color(0xFF000000),
    shadow:             Color(0xFF000000),
    surfaceTint:        Color(0xFF436084),
  ).copyWith(
    // ── Surface containers ─────────────────────────────────────────
    surfaceContainerLowest: const Color(0xFFFFFFFF),
    surfaceContainerLow:    const Color(0xFFF5F3F4),
    surfaceContainer:       const Color(0xFFEFEDEE),
    surfaceContainerHigh:   const Color(0xFFE9E8E9),
    surfaceContainerHighest:const Color(0xFFE3E2E3),
    // ── Primary fixed ──────────────────────────────────────────────
    primaryFixed:           const Color(0xFFD2E4FF),
    primaryFixedDim:        const Color(0xFFABC9F2),
    onPrimaryFixed:         const Color(0xFF001C37),
    onPrimaryFixedVariant:  const Color(0xFF2A486B),
    // ── Secondary fixed (gold) ─────────────────────────────────────
    secondaryFixed:         const Color(0xFFFFE088),
    secondaryFixedDim:      const Color(0xFFE1C46F),
    onSecondaryFixed:       const Color(0xFF241A00),
    onSecondaryFixedVariant:const Color(0xFF574500),
    // ── Tertiary fixed (seafoam) ────────────────────────────────────
    tertiaryFixed:          const Color(0xFFD3E4FB),
    tertiaryFixedDim:       _seafoam,
    onTertiaryFixed:        const Color(0xFF0B1D2D),
    onTertiaryFixedVariant: const Color(0xFF38485A),
  ),
  textTheme: _buildTextTheme(),
  appBarTheme: AppBarTheme(
    backgroundColor: _primary,
    foregroundColor: const Color(0xFFFFFFFF),
    elevation: 0,
    scrolledUnderElevation: 0,
    centerTitle: false,
    // headline-sm with +3px letter-spacing per design spec
    titleTextStyle: GoogleFonts.newsreader(
      color: _gold,
      fontSize: 18,
      fontWeight: FontWeight.w700,
      letterSpacing: 3,
    ),
    iconTheme:        const IconThemeData(color: Color(0xFFFFFFFF)),
    actionsIconTheme: const IconThemeData(color: Color(0xFFFFFFFF)),
  ),
  cardTheme: const CardThemeData(
    elevation: 0,
    margin: EdgeInsets.zero,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(12)),
    ),
  ),
  chipTheme: ChipThemeData(
    shape: const StadiumBorder(),
    showCheckmark: false,
    selectedColor: _primary,
    labelStyle: GoogleFonts.inter(
      fontSize: 12,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.5,
    ),
  ),
  // FAB: Deep Navy bg, 2px Gold border per design spec
  floatingActionButtonTheme: FloatingActionButtonThemeData(
    backgroundColor: _primaryContainer,
    foregroundColor: const Color(0xFFFFFFFF),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
  ),
);
