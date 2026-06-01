import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// Stitch / Navigator design system — light theme
// primary is a dark navy blue (not near-black) as requested
const _primary = Color(0xFF1A3A5C);
const _tertiaryFixed = Color(0xFFFFE088);
const _seafoam = Color(0xFFB7C8DE); // inverse-primary, used as accent

TextTheme _buildTextTheme() {
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
        textStyle: base.headlineSmall?.copyWith(fontWeight: FontWeight.w500)),
  );
}

final ThemeData lightTheme = ThemeData(
  useMaterial3: true,
  colorScheme: ColorScheme.fromSeed(
    seedColor: _primary,
    brightness: Brightness.light,
    primary: _primary,
    onPrimary: const Color(0xFFFFFFFF),
    primaryContainer: const Color(0xFF1A2B3C),
    onPrimaryContainer: const Color(0xFF8192A7),
    secondary: const Color(0xFF5D5F5F),
    onSecondary: const Color(0xFFFFFFFF),
    secondaryContainer: const Color(0xFFDFE0E0),
    onSecondaryContainer: const Color(0xFF616363),
    tertiary: const Color(0xFF735C00),
    onTertiary: const Color(0xFFFFFFFF),
    tertiaryContainer: const Color(0xFFCCA830),
    onTertiaryContainer: const Color(0xFF4F3E00),
    surface: const Color(0xFFFBF9FA),
    onSurface: const Color(0xFF1B1C1D),
    onSurfaceVariant: const Color(0xFF44474C),
    outline: const Color(0xFF74777D),
    outlineVariant: const Color(0xFFC4C6CD),
    inverseSurface: const Color(0xFF303032),
    onInverseSurface: const Color(0xFFF2F0F2),
    inversePrimary: _seafoam,
    error: const Color(0xFFBA1A1A),
    onError: const Color(0xFFFFFFFF),
    errorContainer: const Color(0xFFFFDAD6),
    onErrorContainer: const Color(0xFF93000A),
  ).copyWith(
    surfaceContainerHighest: const Color(0xFFE4E2E3),
    surfaceContainerHigh: const Color(0xFFE9E7E9),
    surfaceContainer: const Color(0xFFEFEDEF),
    surfaceContainerLow: const Color(0xFFF5F3F4),
    surfaceContainerLowest: const Color(0xFFFFFFFF),
    tertiaryFixed: _tertiaryFixed,
    tertiaryFixedDim: const Color(0xFFE9C349),
    onTertiaryFixed: const Color(0xFF241A00),
    onTertiaryFixedVariant: const Color(0xFF574500),
  ),
  textTheme: _buildTextTheme(),
  appBarTheme: AppBarTheme(
    backgroundColor: _primary,  // dark navy blue
    foregroundColor: const Color(0xFFFFFFFF),
    elevation: 0,
    scrolledUnderElevation: 0,
    centerTitle: false,
    titleTextStyle: GoogleFonts.newsreader(
      color: _tertiaryFixed,
      fontSize: 20,
      fontWeight: FontWeight.w700,
      letterSpacing: 3,
    ),
    iconTheme: const IconThemeData(color: Color(0xFFFFFFFF)),
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
  floatingActionButtonTheme: FloatingActionButtonThemeData(
    backgroundColor: _primary,  // dark navy blue
    foregroundColor: const Color(0xFFFFFFFF),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
  ),
);
