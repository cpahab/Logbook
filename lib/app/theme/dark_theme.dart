import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'theme_extensions.dart';

// Dark theme
const _darkNavy = Color(0xFF0D1E33); // Very dark background
const _lightBlue = Color(0xFF7DB3F0); // Primary (light)
const _cyan = Color(0xFF4CC9D4); // Secondary (cyan)

TextTheme _buildDarkTextTheme() {
  final base = GoogleFonts.interTextTheme();
  return base.copyWith(
    displayLarge: GoogleFonts.newsreader(textStyle: base.displayLarge),
    displayMedium: GoogleFonts.newsreader(textStyle: base.displayMedium),
    displaySmall: GoogleFonts.newsreader(textStyle: base.displaySmall),
    headlineLarge: GoogleFonts.newsreader(
        textStyle: base.headlineLarge?.copyWith(fontWeight: FontWeight.w500)),
    headlineMedium: GoogleFonts.newsreader(
        textStyle: base.headlineMedium?.copyWith(fontWeight: FontWeight.w500)),
    headlineSmall: GoogleFonts.newsreader(
        textStyle: base.headlineSmall?.copyWith(fontWeight: FontWeight.w600)),
  );
}

final ThemeData darkTheme = ThemeData(
  useMaterial3: true,
  colorScheme: const ColorScheme(
    brightness: Brightness.dark,
    // ── Primary — Light Blue ─────────────────────────────────────────
    primary: _lightBlue,
    onPrimary: _darkNavy,
    primaryContainer: Color(0xFF4C7FD9),
    onPrimaryContainer: Color(0xFF001C37),
    inversePrimary: Color(0xFF002B6A),
    // ── Secondary — Cyan ────────────────────────────────────────────
    secondary: _cyan,
    onSecondary: _darkNavy,
    secondaryContainer: Color(0xFF4CBFD4),
    onSecondaryContainer: Color(0xFF00474E),
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
    surface: _darkNavy,
    onSurface: Color(0xFFF2F0F1),
    onSurfaceVariant: Color(0xFFC3C6CF),
    surfaceContainerHighest: Color(0xFF3E3E3F),
    outline: Color(0xFF8D9199),
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
    surfaceContainer: const Color(0xFF1B1D22),
    surfaceContainerHigh: const Color(0xFF25272C),
    surfaceContainerHighest: const Color(0xFF3E3E3F),
    // ── Primary fixed ──────────────────────────────────────────────
    primaryFixed: const Color(0xFFD2E4FF),
    primaryFixedDim: const Color(0xFFABC9F2),
    onPrimaryFixed: const Color(0xFF001C37),
    onPrimaryFixedVariant: const Color(0xFF2A486B),
    // ── Secondary fixed (cyan) ─────────────────────────────────────
    secondaryFixed: const Color(0xFFB5E7FF),
    secondaryFixedDim: const Color(0xFF80CFEA),
    onSecondaryFixed: const Color(0xFF00474E),
    onSecondaryFixedVariant: const Color(0xFF1F5E6E),
    // ── Tertiary fixed (dark navy) ──────────────────────────────────
    tertiaryFixed: const Color(0xFFD3E4FB),
    tertiaryFixedDim: const Color(0xFFB7C8DE),
    onTertiaryFixed: const Color(0xFF0B1D2D),
    onTertiaryFixedVariant: const Color(0xFF38485A),
  ),
  textTheme: _buildDarkTextTheme(),
  dialogTheme: const DialogThemeData(
    backgroundColor: Color(0xFF1B1D22),
    surfaceTintColor: Colors.transparent,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(16))),
  ),
  appBarTheme: const AppBarTheme(
    backgroundColor: Color(0xFF0D1E33), // surface (Dark Navy)
    foregroundColor: Color(0xFF7DB3F0), // primary (Light Blue)
    elevation: 0,
    scrolledUnderElevation: 1,
    shadowColor: Colors.black12,
    centerTitle: true, // top-level tabs and sub-screens alike — consistent centring
    iconTheme:        IconThemeData(color: Color(0xFF7DB3F0)),
    actionsIconTheme: IconThemeData(color: Color(0xFF7DB3F0)),
  ),
  cardTheme: const CardThemeData(
    elevation: 1,
    margin: EdgeInsets.zero,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(12)),
    ),
  ),
  chipTheme: ChipThemeData(
    shape: const StadiumBorder(),
    showCheckmark: false,
    selectedColor: _lightBlue,
    labelStyle: GoogleFonts.inter(
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
    backgroundColor: const Color(0xFF1B1D22),           // surfaceContainer
    headerBackgroundColor: const Color(0xFF17191D),     // surfaceContainerLow
    headerForegroundColor: const Color(0xFFF2F0F1),     // onSurface
    headerHeadlineStyle: GoogleFonts.newsreader(
        fontSize: 28, fontWeight: FontWeight.w600, color: Color(0xFFF2F0F1)),
    weekdayStyle: GoogleFonts.inter(fontSize: 12, color: Color(0xFFC3C6CF)),
    dayStyle: GoogleFonts.inter(fontSize: 13, color: Color(0xFFF2F0F1)),
    rangePickerBackgroundColor: const Color(0xFF0D1E33),
    rangePickerHeaderBackgroundColor: const Color(0xFF0D1E33),
    rangePickerHeaderForegroundColor: const Color(0xFFF2F0F1),
    rangePickerHeaderHelpStyle: GoogleFonts.inter(
        fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFFC3C6CF),
        letterSpacing: 1.2),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFF25272C),
      labelStyle: GoogleFonts.inter(fontSize: 12, color: Color(0xFFC3C6CF)),
      border: const OutlineInputBorder(
        borderSide: BorderSide(color: Color(0xFF8D9199)),
      ),
      enabledBorder: const OutlineInputBorder(
        borderSide: BorderSide(color: Color(0xFF8D9199)),
      ),
      focusedBorder: const OutlineInputBorder(
        borderSide: BorderSide(color: _lightBlue, width: 2),
      ),
    ),
  ),
  extensions: const [
    LogbookTimelineColors(
      crewAccent:      Color(0xFF4CC9D4), // cs.secondary — Cyan
      dividerColor:    Color(0x4D49454E), // cs.outlineVariant @ 30 %
      cardShadowColor: Color(0x0DFFFFFF), // white @ 5 %
    ),
    LogbookEmergencyColors(
      criticalColor:      Color(0xFFFFB4AB), // cs.error (dark)
      criticalBgColor:    Color(0xFF93000A), // cs.errorContainer (dark)
      criticalMutedColor: Color(0x33FFB4AB), // cs.error @ 20 %
      cardShadowColor:    Color(0x0DFFFFFF), // white @ 5 %
    ),
  ],
);
