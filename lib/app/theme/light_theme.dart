import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// Light theme — Horizon Minimalist
const _primary            = Color(0xFF002B49); // Deep Navy
const _primaryContainer   = Color(0xFF1A3A5C);
const _seafoam            = Color(0xFFB7C8DE); // Seafoam accent  (tertiaryFixedDim)
const _surface            = Color(0xFFF7F9FB);
const _outline            = Color(0xFFC3C6CF);
const _container          = Color(0xFFF2F4F6); // surfaceContainer (base tier)
const _onSurfaceVariant   = Color(0xFF43474E);

TextTheme _buildTextTheme() {
  final base = GoogleFonts.dmSansTextTheme();
  return base.copyWith(
    headlineLarge:  base.headlineLarge?.copyWith(fontWeight: FontWeight.w500),
    headlineMedium: base.headlineMedium?.copyWith(fontWeight: FontWeight.w500),
    headlineSmall:  base.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
    // Eyebrow labels (bold, tracked, uppercase small-caps style) app-wide.
    labelSmall: base.labelSmall?.copyWith(
        fontWeight: FontWeight.w700, letterSpacing: 1.5),
  );
}

final ThemeData lightTheme = ThemeData(
  useMaterial3: true,
  colorScheme: const ColorScheme(
    brightness: Brightness.light,
    // ── Primary — Deep Navy ─────────────────────────────────────────
    primary:            _primary,
    onPrimary:          Color(0xFFFFFFFF),
    primaryContainer:   Color(0xFF1A3A5C),
    onPrimaryContainer: Color(0xFF87A4CC),
    inversePrimary:     Color(0xFFABC9F2),
    // ── Secondary — Captain's Gold ──────────────────────────────────
    // Same hue as before (~46°) but higher saturation/less blue — reads as
    // a warmer, more vivid gold instead of a muddy olive-brown.
    secondary:            Color(0xFF7E6207),
    onSecondary:          Color(0xFFFFFFFF),
    secondaryContainer:   Color(0xFFFFE088),
    onSecondaryContainer: Color(0xFF7E6207),
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
    surface:            _surface,
    onSurface:          Color(0xFF1B1C1D),
    onSurfaceVariant:   _onSurfaceVariant,
    surfaceContainerHighest: Color(0xFFE3E2E3),
    outline:            _outline,
    outlineVariant:     Color(0xFFC3C6CF),
    inverseSurface:     Color(0xFF303031),
    onInverseSurface:   Color(0xFFF2F0F1),
    scrim:              Color(0xFF000000),
    shadow:             Color(0xFF000000),
    surfaceTint:        Color(0xFF436084),
  ).copyWith(
    // ── Surface tonal ─────────────────────────────────────────────
    surfaceDim:              const Color(0xFFDBDADB),
    surfaceBright:           const Color(0xFFFAF9FA),
    // ── Surface containers ─────────────────────────────────────────
    surfaceContainerLowest: const Color(0xFFFFFFFF),
    surfaceContainerLow:    const Color(0xFFF5F3F4),
    surfaceContainer:       _container,
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
  dialogTheme: const DialogThemeData(
    backgroundColor: Color(0xFFFFFFFF),
    surfaceTintColor: Colors.transparent,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(16))),
  ),
  appBarTheme: AppBarTheme(
    backgroundColor: _surface,
    foregroundColor: _primary,
    elevation: 0,
    scrolledUnderElevation: 0,
    centerTitle: false, // Horizon Minimalist: left-aligned titles
    titleTextStyle: GoogleFonts.dmSans(
      fontSize: 18, fontWeight: FontWeight.bold, color: _primary,
    ),
    shape: const Border(bottom: BorderSide(color: _outline, width: 1)),
    iconTheme:        const IconThemeData(color: _primary),
    actionsIconTheme: const IconThemeData(color: _primary),
  ),
  cardTheme: const CardThemeData(
    elevation: 0,
    margin: EdgeInsets.zero,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(16)),
    ),
  ),
  chipTheme: ChipThemeData(
    shape: const StadiumBorder(),
    showCheckmark: false,
    selectedColor: _primary,
    labelStyle: GoogleFonts.dmSans(
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
  datePickerTheme: DatePickerThemeData(
    backgroundColor: const Color(0xFFFFFFFF),
    headerBackgroundColor: _primary,
    headerForegroundColor: const Color(0xFFFFFFFF),
    headerHeadlineStyle: GoogleFonts.dmSans(
        fontSize: 28, fontWeight: FontWeight.w600, color: Color(0xFFFFFFFF)),
    weekdayStyle: GoogleFonts.dmSans(fontSize: 12, color: Color(0xFF43474E)),
    dayStyle: GoogleFonts.dmSans(fontSize: 13, color: Color(0xFF1B1C1D)),
    rangePickerBackgroundColor: _surface,
    rangePickerHeaderBackgroundColor: _primary,
    rangePickerHeaderForegroundColor: const Color(0xFFFFFFFF),
    rangePickerHeaderHelpStyle: GoogleFonts.dmSans(
        fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFFABC9F2),
        letterSpacing: 1.2),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFFF5F3F4),
      labelStyle: GoogleFonts.dmSans(fontSize: 12, color: Color(0xFF43474E)),
      border: OutlineInputBorder(
        borderSide: BorderSide(color: _outline),
      ),
      enabledBorder: OutlineInputBorder(
        borderSide: BorderSide(color: _outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: BorderSide(color: _primary, width: 2),
      ),
    ),
  ),
);
