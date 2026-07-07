import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// Dark theme — Horizon Minimalist
const _darkNavy = Color(0xFF0D1E33); // legacy ink — still used for onSecondary (unlisted role)
const _lightBlue = Color(0xFF7DB3F0); // Primary (unchanged — matches Horizon Minimalist)
const _secondary = Color(0xFFFFE088); // Secondary (was cyan)
const _surface = Color(0xFF031428);
const _onPrimary = Color(0xFF031428); // same value as surface, per spec
const _outline = Color(0xFF3E3E3F);
const _container = Color(0xFF0B1C31); // surfaceContainer (base tier)
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
    onPrimaryContainer: Color(0xFF001C37),
    inversePrimary: Color(0xFF002B6A),
    // ── Secondary — Captain's Gold ───────────────────────────────────
    // secondaryContainer/onSecondaryContainer were still the pre-redesign
    // cyan (left over from when secondary itself was cyan) — a rich
    // goldenrod fill with a dark ink "on" color, matching how
    // primaryContainer/onPrimaryContainer relate to primary here.
    secondary: _secondary,
    onSecondary: _darkNavy,
    secondaryContainer: Color(0xFFB8860B),
    onSecondaryContainer: Color(0xFF3A2E00),
    // ── Tertiary — Seafoam (lighter than light theme) ────────────────
    tertiary: Color(0xFFB7C8DE),
    onTertiary: Color(0xFF0B1D2D),
    tertiaryContainer: Color(0xFF2A4A5C),
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
    surfaceContainerHighest: Color(0xFF3E3E3F),
    outline: _outline,
    outlineVariant: Color(0xFF49454E),
    inverseSurface: Color(0xFFF2F0F1),
    onInverseSurface: Color(0xFF1B1C1D),
    scrim: Color(0xFF000000),
    shadow: Color(0xFF000000),
    surfaceTint: _lightBlue,
  ).copyWith(
    // ── Surface tonal ─────────────────────────────────────────────
    surfaceDim: const Color(0xFF0F1114),
    surfaceBright: const Color(0xFF35363A),
    // ── Surface containers ─────────────────────────────────────────
    surfaceContainerLowest: const Color(0xFF0A0A0E),
    surfaceContainerLow: const Color(0xFF17191D),
    surfaceContainer: _container,
    surfaceContainerHigh: const Color(0xFF25272C),
    surfaceContainerHighest: const Color(0xFF3E3E3F),
    // ── Primary fixed ──────────────────────────────────────────────
    primaryFixed: const Color(0xFFD2E4FF),
    primaryFixedDim: const Color(0xFFABC9F2),
    onPrimaryFixed: const Color(0xFF001C37),
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
    onTertiaryFixed: const Color(0xFF0B1D2D),
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
    shape: const Border(bottom: BorderSide(color: _outline, width: 1)),
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
    headerBackgroundColor: const Color(0xFF17191D),     // surfaceContainerLow
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
      fillColor: const Color(0xFF25272C),
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
