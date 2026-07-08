import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// Dark theme — Horizon Minimalist
//
// Surface/container/outline tiers below are one consistent navy family
// (hue ~216°, stepped only in lightness) instead of mixing saturated-navy
// tiers with near-neutral greys — a prior pass had surfaceDim/
// surfaceContainerLowest/Low/High at 9-17% saturation next to a surface/
// surfaceContainer at 63-86%, so they read as plain charcoal next to
// properly-tinted navy. _ink consolidates five previously-slightly-
// different "dark ink" text colors (onPrimaryContainer, onTertiary,
// onTertiaryFixed, onSecondary) into one canonical value.
const _ink = Color(0xFF001C37); // canonical dark ink — text/icons on light accents
const _lightBlue = Color(0xFF7DB3F0); // Primary (unchanged — matches Horizon Minimalist)
const _secondary = Color(0xFFFFE088); // Secondary (was cyan)
const _surface = Color(0xFF0A121E); // "midnight navy" — calmer/less inky than the previous #031428
const _onPrimary = Color(0xFF0A121E); // same value as surface, per spec
const _outline = Color(0xFF4E5D74); // muted navy-grey (was pure neutral, no blue tint at all)
const _container = Color(0xFF0E192A); // surfaceContainer (base tier)
const _onSurfaceVariant = Color(0xFFC3C6CF);

TextTheme _buildDarkTextTheme() {
  final base = GoogleFonts.dmSansTextTheme();
  return base.copyWith(
    headlineLarge: base.headlineLarge?.copyWith(fontWeight: FontWeight.w500),
    headlineMedium: base.headlineMedium?.copyWith(fontWeight: FontWeight.w500),
    headlineSmall: base.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
    // Eyebrow labels (bold, tracked, uppercase small-caps style) app-wide.
    labelSmall: base.labelSmall?.copyWith(
        fontWeight: FontWeight.w700, letterSpacing: 1.5),
  );
}

final ThemeData darkTheme = ThemeData(
  useMaterial3: true,
  colorScheme: const ColorScheme(
    brightness: Brightness.dark,
    // ── Primary — Light Blue ─────────────────────────────────────────
    primary: _lightBlue,
    onPrimary: _onPrimary,
    primaryContainer: Color(0xFF4C7FD9),
    onPrimaryContainer: _ink,
    inversePrimary: Color(0xFF002B6A),
    // ── Secondary — Captain's Gold ───────────────────────────────────
    // secondaryContainer/onSecondaryContainer were still the pre-redesign
    // cyan (left over from when secondary itself was cyan) — a rich
    // goldenrod fill with a dark ink "on" color, matching how
    // primaryContainer/onPrimaryContainer relate to primary here.
    secondary: _secondary,
    onSecondary: _ink,
    secondaryContainer: Color(0xFFB8860B),
    onSecondaryContainer: Color(0xFF3A2E00),
    // ── Tertiary — Seafoam (lighter than light theme) ────────────────
    tertiary: Color(0xFFB7C8DE),
    onTertiary: _ink,
    tertiaryContainer: Color(0xFF2A3D5B), // was drifted to a cyan-ish 202° hue; now matches the 216° navy family
    onTertiaryContainer: Color(0xFFC9D5E8),
    // ── Error ───────────────────────────────────────────────────────
    error: Color(0xFFFFB4AB),
    onError: Color(0xFF690005),
    errorContainer: Color(0xFF93000A),
    onErrorContainer: Color(0xFFFFDAD6),
    // ── Neutrals ───────────────────────────────────────────────────
    surface: _surface,
    onSurface: Color(0xFFF2F0F1),
    onSurfaceVariant: _onSurfaceVariant,
    surfaceContainerHighest: Color(0xFF1C3254),
    outline: _outline,
    outlineVariant: Color(0xFF343D4B),
    inverseSurface: Color(0xFFF2F0F1),
    onInverseSurface: Color(0xFF1B1C1D),
    scrim: Color(0xFF000000),
    shadow: Color(0xFF000000),
    surfaceTint: _lightBlue,
  ).copyWith(
    // ── Surface tonal ─────────────────────────────────────────────
    surfaceDim: const Color(0xFF080E17),
    surfaceBright: const Color(0xFF1A2E4D),
    // ── Surface containers ─────────────────────────────────────────
    surfaceContainerLowest: const Color(0xFF060A11),
    surfaceContainerLow: const Color(0xFF09101B),
    surfaceContainer: _container,
    surfaceContainerHigh: const Color(0xFF14253D),
    surfaceContainerHighest: const Color(0xFF1C3254),
    // ── Primary fixed ──────────────────────────────────────────────
    primaryFixed: const Color(0xFFD2E4FF),
    primaryFixedDim: const Color(0xFFABC9F2),
    onPrimaryFixed: _ink,
    onPrimaryFixedVariant: const Color(0xFF2A486B),
    // ── Secondary fixed (gold) ──────────────────────────────────────
    // "Fixed" roles are meant to stay the same across brightness (that's
    // the point) — these were still the pre-redesign cyan. Match light
    // theme's values exactly instead of inventing a separate dark-mode set.
    secondaryFixed: const Color(0xFFFFE088),
    secondaryFixedDim: const Color(0xFFE1C46F),
    onSecondaryFixed: const Color(0xFF241A00),
    onSecondaryFixedVariant: const Color(0xFF574500),
    // ── Tertiary fixed (dark navy) ──────────────────────────────────
    tertiaryFixed: const Color(0xFFD3E4FB),
    tertiaryFixedDim: const Color(0xFFB7C8DE),
    onTertiaryFixed: _ink,
    onTertiaryFixedVariant: const Color(0xFF38485A),
  ),
  textTheme: _buildDarkTextTheme(),
  dialogTheme: const DialogThemeData(
    backgroundColor: _container,
    surfaceTintColor: Colors.transparent,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(16))),
  ),
  appBarTheme: AppBarTheme(
    backgroundColor: _surface,
    foregroundColor: _lightBlue,
    elevation: 0,
    scrolledUnderElevation: 0,
    centerTitle: false, // Horizon Minimalist: left-aligned titles
    titleTextStyle: GoogleFonts.dmSans(
      fontSize: 18, fontWeight: FontWeight.bold, color: _lightBlue,
    ),
    iconTheme:        const IconThemeData(color: _lightBlue),
    actionsIconTheme: const IconThemeData(color: _lightBlue),
  ),
  cardTheme: const CardThemeData(
    elevation: 2.0,
    margin: EdgeInsets.zero,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(16)),
    ),
  ),
  chipTheme: ChipThemeData(
    shape: const StadiumBorder(),
    showCheckmark: false,
    selectedColor: _lightBlue,
    labelStyle: GoogleFonts.dmSans(
      fontSize: 12,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.5,
    ),
  ),
  floatingActionButtonTheme: FloatingActionButtonThemeData(
    backgroundColor: Color(0xFF2A5A99),
    foregroundColor: const Color(0xFFFFFFFF),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
  ),
  datePickerTheme: DatePickerThemeData(
    backgroundColor: _container,                        // surfaceContainer
    headerBackgroundColor: const Color(0xFF09101B),     // surfaceContainerLow
    headerForegroundColor: const Color(0xFFF2F0F1),     // onSurface
    headerHeadlineStyle: GoogleFonts.dmSans(
        fontSize: 28, fontWeight: FontWeight.w600, color: Color(0xFFF2F0F1)),
    weekdayStyle: GoogleFonts.dmSans(fontSize: 12, color: Color(0xFFC3C6CF)),
    dayStyle: GoogleFonts.dmSans(fontSize: 13, color: Color(0xFFF2F0F1)),
    rangePickerBackgroundColor: _surface,
    rangePickerHeaderBackgroundColor: _surface,
    rangePickerHeaderForegroundColor: const Color(0xFFF2F0F1),
    rangePickerHeaderHelpStyle: GoogleFonts.dmSans(
        fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFFC3C6CF),
        letterSpacing: 1.2),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFF14253D),
      labelStyle: GoogleFonts.dmSans(fontSize: 12, color: Color(0xFFC3C6CF)),
      border: const OutlineInputBorder(
        borderSide: BorderSide(color: _outline),
      ),
      enabledBorder: const OutlineInputBorder(
        borderSide: BorderSide(color: _outline),
      ),
      focusedBorder: const OutlineInputBorder(
        borderSide: BorderSide(color: _lightBlue, width: 2),
      ),
    ),
  ),
);
