import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// Light theme — Horizon Minimalist. Pairs with dark_theme.dart, which
// mirrors this file's structure/roles with its own dark-mode palette; see
// wiki/design.md for the full color rationale and usage table.
const _primary            = Color(0xFF002B49); // Deep Navy
const _primaryContainer   = Color(0xFF1A3A5C);
const _seafoam            = Color(0xFFB7C8DE); // Seafoam accent  (tertiaryFixedDim)
const _surface            = Color(0xFFF7F9FB);
const _outline            = Color(0xFFC3C6CF);
const _container          = Color(0xFFF2F4F6); // surfaceContainer (base tier)
const _onSurfaceVariant   = Color(0xFF43474E);

/// DM Sans text theme, with a few weight overrides on top of the Google
/// Fonts default so headlines/eyebrow labels match the design spec.
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
    primary:            _primary, // App bar text/icons, primary buttons, links, borders on emphasis elements, non-satellite map track color
    onPrimary:          Color(0xFFFFFFFF), // Text/icon on a primary-filled surface
    primaryContainer:   Color(0xFF1A3A5C), // FAB background
    onPrimaryContainer: Color(0xFF87A4CC), // Text/icon on primaryContainer
    inversePrimary:     Color(0xFFABC9F2), // No app code reads this directly, but Flutter's stock SnackBar does — it's the default action-button/close-icon color (no custom snackBarTheme is set, and SnackBars are shown throughout the app without per-instance color overrides)
    // ── Secondary — Captain's Gold ──────────────────────────────────
    // Text/icon-safe gold, same ~45° hue family as secondaryContainer's pale
    // yellow (they're already near-identical in hue — the visual difference
    // is lightness, not hue) — nudged a bit lighter than a plain "safe" gold
    // to read closer to that yellow while keeping ~3.5:1 contrast against
    // the surface, comfortably above the 3:1 UI-component floor used for
    // this label/icon role. onSecondary flipped to a dark ink since this is
    // too bright for legible white text on top of it. onSecondaryContainer
    // is a dark brown ink for the same reason — secondaryContainer's pale
    // gold is too light for legible white/light text on top of it.
    secondary:            Color.fromARGB(255, 189, 142, 3), // Section-header eyebrow labels, active bottom-nav label, icon accents, badge text
    onSecondary:          Color(0xFF241A00), // Text on a secondary-filled surface
    secondaryContainer:   Color.fromARGB(255, 235, 179, 13), // Pale gold fill: active bottom-nav icon, most-recent-day journal card's left accent
    onSecondaryContainer: Color(0xFF3A2E00), // Dark ink for legible text/icons on the pale-gold secondaryContainer fill (e.g. collapsed-month day-count badge)
    // ── Tertiary — Seafoam / Dark Navy ─────────────────────────────
    tertiary:            Color(0xFF142435), // Dark navy accent surface, e.g. vessel-status card fill; also the Settings "logbook-scoped" left accent
    onTertiary:          Color(0xFFFFFFFF), // Text/icon on a tertiary-filled surface
    tertiaryContainer:   Color(0xFF2A3A4C), // Bottom-nav bar background
    onTertiaryContainer: Color(0xFF93A4B9), // Inactive bottom-nav icon/label
    // ── Error ───────────────────────────────────────────────────────
    error:            Color(0xFFBA1A1A), // Destructive actions, critical/urgent emergency accents (criticalColor)
    onError:          Color(0xFFFFFFFF), // Text/icon on an error-filled surface
    errorContainer:   Color(0xFFFFDAD6), // Critical/urgent card background (criticalBgColor), blood-type badge fill
    onErrorContainer: Color(0xFF93000A), // Text on errorContainer, blood-type badge text
    // ── Neutrals ───────────────────────────────────────────────────
    surface:            _surface, // Screen background
    onSurface:          Color(0xFF1B1C1D), // Primary body text
    onSurfaceVariant:   _onSurfaceVariant, // Secondary/caption body text (mutedLabel derives from this)
    surfaceContainerHighest: Color(0xFFE3E2E3), // Alternate divider/highlight surface (e.g. day-detail stat-grid dividers)
    outline:            _outline, // Input borders, dividers
    outlineVariant:     Color(0xFFC3C6CF), // Card borders (dividerColor derives from this)
    inverseSurface:     Color(0xFF303031), // No app code reads this directly, but Flutter's stock SnackBar/Slider/RangeSlider do — default SnackBar background, and the drag value-indicator bubble fill (both used in Settings/vessel-status editing)
    onInverseSurface:   Color(0xFFF2F0F1), // No app code reads this directly, but Flutter's stock SnackBar/Slider/RangeSlider do — default SnackBar text/close-icon, value-indicator text
    surfaceTint:        Color(0xFF436084), // Consulted by AppBar's elevation-tint overlay, but inert in practice — elevation/scrolledUnderElevation are pinned to 0 on every app bar, so the tint always renders at 0% opacity; the other stock widgets that read this (Card, BottomAppBar, SearchAnchor) aren't used in this app
  ).copyWith(
    // ── Surface tonal ─────────────────────────────────────────────
    surfaceDim:              const Color(0xFFDBDADB), // Unused — no app code or Flutter widget reads this (required tonal step)
    surfaceBright:           const Color(0xFFFAF9FA), // Unused — no app code or Flutter widget reads this (required tonal step)
    // ── Surface containers ─────────────────────────────────────────
    surfaceContainerLowest: const Color(0xFFFFFFFF), // Card fill — the default "card on background" surface
    surfaceContainerLow:    const Color(0xFFF5F3F4), // Secondary card fill, input fill
    surfaceContainer:       _container, // Base container tier — chip/pill unselected fill
    surfaceContainerHigh:   const Color(0xFFE9E8E9), // Nested "card on a card" fill (e.g. stat sub-cards)
    surfaceContainerHighest:const Color(0xFFE3E2E3), // See surfaceContainerHighest above (duplicate role, both tiers share one value)
    // ── Primary fixed ──────────────────────────────────────────────
    primaryFixed:           const Color(0xFFD2E4FF), // Unused — no app code or Flutter widget reads this (required by ColorScheme's fixed-color API)
    primaryFixedDim:        const Color(0xFFABC9F2), // Unused — no app code or Flutter widget reads this
    onPrimaryFixed:         const Color(0xFF001C37), // Unused — no app code or Flutter widget reads this
    onPrimaryFixedVariant:  const Color(0xFF2A486B), // Unused — no app code or Flutter widget reads this
    // ── Secondary fixed (gold) ─────────────────────────────────────
    secondaryFixed:         const Color(0xFFFFE088), // Map track/position color in satellite view (reads gold against photo imagery instead of navy)
    secondaryFixedDim:      const Color(0xFFE1C46F), // Unused — no app code or Flutter widget reads this
    onSecondaryFixed:       const Color(0xFF241A00), // Unused — no app code or Flutter widget reads this
    onSecondaryFixedVariant:const Color(0xFF574500), // Unused — no app code or Flutter widget reads this
    // ── Tertiary fixed (seafoam) ────────────────────────────────────
    tertiaryFixed:          const Color(0xFFD3E4FB), // Unused — no app code or Flutter widget reads this
    tertiaryFixedDim:       _seafoam, // Unused — no app code or Flutter widget reads this (defined for a future seafoam accent, dormant today)
    onTertiaryFixed:        const Color(0xFF0B1D2D), // Unused — no app code or Flutter widget reads this
    onTertiaryFixedVariant: const Color(0xFF38485A), // Unused — no app code or Flutter widget reads this
  ),
  textTheme: _buildTextTheme(),
  // Full-screen dialogs (add/edit timeline entry, add/edit crew): white card, 16px corners.
  dialogTheme: const DialogThemeData(
    backgroundColor: Color(0xFFFFFFFF),
    surfaceTintColor: Colors.transparent,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(16))),
  ),
  // Top app bar: flush with the surface (no elevation shadow), left-aligned title.
  appBarTheme: AppBarTheme(
    backgroundColor: _surface,
    foregroundColor: _primary,
    elevation: 0,
    scrolledUnderElevation: 0,
    centerTitle: false, // Horizon Minimalist: left-aligned titles
    titleTextStyle: GoogleFonts.dmSans(
      fontSize: 18, fontWeight: FontWeight.bold, color: _primary,
    ),
    iconTheme:        const IconThemeData(color: _primary),
    actionsIconTheme: const IconThemeData(color: _primary),
  ),
  // Section/data cards throughout the app: flat (no shadow), 16px corners.
  cardTheme: const CardThemeData(
    elevation: 0,
    margin: EdgeInsets.zero,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(16)),
    ),
  ),
  // Filter/selection pills (e.g. date-range filter, sail-state chips): stadium shape, no checkmark.
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
  // Date-range filter picker on the home/tracks screens.
  datePickerTheme: DatePickerThemeData(
    backgroundColor: const Color(0xFFFFFFFF),
    headerBackgroundColor: _primary,
    headerForegroundColor: const Color(0xFFFFFFFF),
    headerHeadlineStyle: GoogleFonts.dmSans(
        fontSize: 28, fontWeight: FontWeight.w600, color: const Color(0xFFFFFFFF)),
    weekdayStyle: GoogleFonts.dmSans(fontSize: 12, color: const Color(0xFF43474E)),
    dayStyle: GoogleFonts.dmSans(fontSize: 13, color: const Color(0xFF1B1C1D)),
    rangePickerBackgroundColor: _surface,
    rangePickerHeaderBackgroundColor: _primary,
    rangePickerHeaderForegroundColor: const Color(0xFFFFFFFF),
    rangePickerHeaderHelpStyle: GoogleFonts.dmSans(
        fontSize: 11, fontWeight: FontWeight.w700, color: const Color(0xFFABC9F2),
        letterSpacing: 1.2),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFFF5F3F4),
      labelStyle: GoogleFonts.dmSans(fontSize: 12, color: const Color(0xFF43474E)),
      border: const OutlineInputBorder(
        borderSide: BorderSide(color: _outline),
      ),
      enabledBorder: const OutlineInputBorder(
        borderSide: BorderSide(color: _outline),
      ),
      focusedBorder: const OutlineInputBorder(
        borderSide: BorderSide(color: _primary, width: 2),
      ),
    ),
  ),
);
