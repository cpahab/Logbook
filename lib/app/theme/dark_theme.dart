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

/// DM Sans text theme for dark mode — same weight overrides as light_theme.dart's
/// `_buildTextTheme()`, kept in its own copy since [TextTheme] doesn't carry color.
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
    primary: _lightBlue, // App bar text/icons, primary buttons, links, borders on emphasis elements, non-satellite map track color
    onPrimary: _onPrimary, // Text/icon on a primary-filled surface
    primaryContainer: Color(0xFF4C7FD9), // FAB background
    onPrimaryContainer: _ink, // Text/icon on primaryContainer
    inversePrimary: Color(0xFF002B6A), // Not referenced directly in app code — Material's own default (e.g. SnackBar action color)
    // ── Secondary — Captain's Gold ───────────────────────────────────
    // One gold everywhere: secondary/secondaryContainer/secondaryFixed/
    // secondaryFixedDim all share the same brightest value (_secondary)
    // instead of stepping through darker goldenrod/dimmed variants.
    secondary: _secondary, // Section-header eyebrow labels, active bottom-nav label, icon accents, badge text
    onSecondary: _ink, // Text on a secondary-filled surface
    secondaryContainer: _secondary, // Pale gold fill: active bottom-nav icon, most-recent-day journal card's left accent
    onSecondaryContainer: Color(0xFF3A2E00), // Mirrors secondary's family deliberately — one consistent gold everywhere
    // ── Tertiary — Seafoam (lighter than light theme) ────────────────
    tertiary: Color(0xFFB7C8DE), // Dark-navy-role accent surface, e.g. vessel-status card fill; also the Settings "logbook-scoped" left accent
    onTertiary: _ink, // Text/icon on a tertiary-filled surface
    tertiaryContainer: Color(0xFF2A3D5B), // Bottom-nav bar background — was drifted to a cyan-ish 202° hue; now matches the 216° navy family
    onTertiaryContainer: Color(0xFFC9D5E8), // Inactive bottom-nav icon/label
    // ── Error ───────────────────────────────────────────────────────
    error: Color(0xFFFFB4AB), // Destructive actions, critical/urgent emergency accents (criticalColor)
    onError: Color(0xFF690005), // Text/icon on an error-filled surface
    errorContainer: Color(0xFF93000A), // Critical/urgent card background (criticalBgColor), blood-type badge fill
    onErrorContainer: Color(0xFFFFDAD6), // Text on errorContainer, blood-type badge text
    // ── Neutrals ───────────────────────────────────────────────────
    surface: _surface, // Screen background
    onSurface: Color(0xFFF2F0F1), // Primary body text
    onSurfaceVariant: _onSurfaceVariant, // Secondary/caption body text (mutedLabel derives from this)
    surfaceContainerHighest: Color(0xFF1C3254), // Alternate divider/highlight surface (e.g. day-detail stat-grid dividers)
    outline: _outline, // Input borders, dividers
    outlineVariant: Color(0xFF343D4B), // Card borders (dividerColor derives from this)
    inverseSurface: Color(0xFFF2F0F1), // Not referenced directly in app code — Material's own default (e.g. SnackBar background)
    onInverseSurface: Color(0xFF1B1C1D), // Not referenced directly in app code — pairs with inverseSurface
    scrim: Color(0xFF000000), // Not referenced directly in app code — Material's own default modal-barrier color
    shadow: Color(0xFF000000), // Ad hoc box-shadow tint outside the standard cardShadowColor token (e.g. Settings rows, timeline entry dialog)
    surfaceTint: _lightBlue, // Neutralized in practice — dialogs/cards set surfaceTintColor: Colors.transparent to disable M3's elevation tint overlay
  ).copyWith(
    // ── Surface tonal ─────────────────────────────────────────────
    surfaceDim: const Color(0xFF080E17), // Not referenced directly in app code — required tonal step
    surfaceBright: const Color(0xFF1A2E4D), // Not referenced directly in app code — required tonal step
    // ── Surface containers ─────────────────────────────────────────
    surfaceContainerLowest: const Color(0xFF060A11), // Card fill — the default "card on background" surface
    surfaceContainerLow: const Color(0xFF09101B), // Secondary card fill, input fill
    surfaceContainer: _container, // Base container tier — chip/pill unselected fill
    surfaceContainerHigh: const Color(0xFF14253D), // Nested "card on a card" fill (e.g. stat sub-cards)
    surfaceContainerHighest: const Color(0xFF1C3254), // See surfaceContainerHighest above (duplicate role, both tiers share one value)
    // ── Primary fixed ──────────────────────────────────────────────
    primaryFixed: const Color(0xFFD2E4FF), // Not referenced directly in app code — required by ColorScheme's fixed-color API
    primaryFixedDim: const Color(0xFFABC9F2), // Not referenced directly in app code
    onPrimaryFixed: _ink, // Not referenced directly in app code
    onPrimaryFixedVariant: const Color(0xFF2A486B), // Not referenced directly in app code
    // ── Secondary fixed (gold) ──────────────────────────────────────
    // "Fixed" roles are meant to stay the same across brightness (that's
    // the point). secondaryFixedDim used to be a dimmed step down from
    // secondaryFixed — now the same brightest gold as every other gold
    // role in this theme.
    secondaryFixed: _secondary, // Map track/position color in satellite view (reads gold against photo imagery instead of navy)
    secondaryFixedDim: _secondary, // Not referenced directly in app code
    onSecondaryFixed: const Color(0xFF241A00), // Not referenced directly in app code
    onSecondaryFixedVariant: const Color(0xFF574500), // Not referenced directly in app code
    // ── Tertiary fixed (dark navy) ──────────────────────────────────
    tertiaryFixed: const Color(0xFFD3E4FB), // Not referenced directly in app code
    tertiaryFixedDim: const Color(0xFFB7C8DE), // Not referenced directly in app code — dormant seafoam accent, mirrors light theme's _seafoam
    onTertiaryFixed: _ink, // Not referenced directly in app code
    onTertiaryFixedVariant: const Color(0xFF38485A), // Not referenced directly in app code
  ),
  textTheme: _buildDarkTextTheme(),
  // Full-screen dialogs: dark surfaceContainer card, 16px corners.
  dialogTheme: const DialogThemeData(
    backgroundColor: _container,
    surfaceTintColor: Colors.transparent,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(16))),
  ),
  // Top app bar: flush with the surface, left-aligned title.
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
  // Section/data cards: slight elevation (dark mode needs it for card/background
  // separation, unlike light mode's flat cards) — 16px corners.
  cardTheme: const CardThemeData(
    elevation: 2.0,
    margin: EdgeInsets.zero,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(16)),
    ),
  ),
  // Filter/selection pills: stadium shape, no checkmark.
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
    backgroundColor: const Color(0xFF2A5A99),
    foregroundColor: const Color(0xFFFFFFFF),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
  ),
  // Date-range filter picker on the home/tracks screens.
  datePickerTheme: DatePickerThemeData(
    backgroundColor: _container,                        // surfaceContainer
    headerBackgroundColor: const Color(0xFF09101B),     // surfaceContainerLow
    headerForegroundColor: const Color(0xFFF2F0F1),     // onSurface
    headerHeadlineStyle: GoogleFonts.dmSans(
        fontSize: 28, fontWeight: FontWeight.w600, color: const Color(0xFFF2F0F1)),
    weekdayStyle: GoogleFonts.dmSans(fontSize: 12, color: const Color(0xFFC3C6CF)),
    dayStyle: GoogleFonts.dmSans(fontSize: 13, color: const Color(0xFFF2F0F1)),
    rangePickerBackgroundColor: _surface,
    rangePickerHeaderBackgroundColor: _surface,
    rangePickerHeaderForegroundColor: const Color(0xFFF2F0F1),
    rangePickerHeaderHelpStyle: GoogleFonts.dmSans(
        fontSize: 11, fontWeight: FontWeight.w700, color: const Color(0xFFC3C6CF),
        letterSpacing: 1.2),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFF14253D),
      labelStyle: GoogleFonts.dmSans(fontSize: 12, color: const Color(0xFFC3C6CF)),
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
