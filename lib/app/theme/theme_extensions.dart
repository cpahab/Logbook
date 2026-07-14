import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Semantic colour tokens for the timeline / day-detail / crew areas,
/// derived from [ColorScheme] roles rather than hardcoded per theme.
extension LogbookTimelineColors on ColorScheme {
  /// Colour used for all crew-note elements (icons, labels, backgrounds, chips).
  Color get crewAccent => secondary;

  /// Border/divider colour for timeline entry cards.
  Color get dividerColor => outlineVariant.withValues(alpha: 0.3);

  /// Box-shadow tint on timeline/day and emergency cards.
  /// Adapts between themes (near-black in light, near-white in dark).
  Color get cardShadowColor => brightness == Brightness.dark
      ? Colors.white.withValues(alpha: 0.05)
      : Colors.black.withValues(alpha: 0.04);
}

/// Semantic colour token distinguishing logbook-scoped data from
/// device-scoped data in the Settings screen.
extension LogbookScopeColors on ColorScheme {
  /// Left-edge accent for CardShell sections whose data belongs to the
  /// active logbook (travels with it, resets on switch) rather than to
  /// this device (theme, locale, account) — a quiet per-section signal
  /// instead of a text label on every card.
  Color get logbookScopedAccent => tertiary;
}

/// General-purpose text colours, derived from [ColorScheme] roles.
extension LogbookTextColors on ColorScheme {
  /// Small-caps eyebrow labels, secondary stat/date text, and similar
  /// low-emphasis content. Softer than `onSurfaceVariant` on its own —
  /// bold/tracked/uppercase styling reads visually heavier at full
  /// strength, so this keeps it level with adjacent plain-weight text.
  Color get mutedLabel => onSurfaceVariant.withValues(alpha: 0.8);
}

/// Semantic colour tokens for the emergency / mayday screens, derived
/// from [ColorScheme] roles rather than hardcoded per theme.
extension LogbookEmergencyColors on ColorScheme {
  /// Solid critical/urgent colour (borders, pulse border, delete icons).
  Color get criticalColor => error;

  /// Background fill for critical/urgent cards.
  Color get criticalBgColor => errorContainer;

  /// Muted variant at ~20 % opacity: pulsing ring, section dividers.
  Color get criticalMutedColor => error.withValues(alpha: 0.2);
}

/// Recurring dialog/form text styles that don't match a stock Material
/// role, derived from [TextTheme] roles rather than hardcoded per call
/// site. Callers still supply `color` (and, where meaningful, `fontStyle`)
/// via `.copyWith` — those are legitimate per-instance choices, unlike
/// size/weight which belong here.
extension LogbookFormTextStyles on TextTheme {
  /// Fullscreen-dialog title (e.g. add/edit timeline entry, add/edit crew).
  TextStyle get dialogTitle =>
      titleLarge!.copyWith(fontStyle: FontStyle.italic, fontWeight: FontWeight.w500);

  /// Compact field value/input text — dense multi-column forms (timeline
  /// entry's time/course/speed/wind/remarks, dialog buttons).
  TextStyle get fieldValueCompact => bodyLarge!.copyWith(fontSize: 15, fontWeight: FontWeight.w600);

  /// Compact field hint text — same size as [fieldValueCompact] but at
  /// bodyLarge's default (regular) weight.
  TextStyle get fieldHintCompact => bodyLarge!.copyWith(fontSize: 15);

  /// Prose field value/hint text — single-column forms with more room
  /// (crew dialog's name/blood type/allergies/etc.).
  TextStyle get fieldValueProse => bodyLarge!.copyWith(fontSize: 18, fontWeight: FontWeight.w600);

  /// Field-level eyebrow label (e.g. "COURSE", "BLOOD GROUP") — smaller and
  /// less tracked than a section header's [TextTheme.labelSmall].
  TextStyle get microLabel => labelSmall!.copyWith(fontSize: 9, letterSpacing: 1.0);

  /// Selectable chip text (sail state, motor/keel toggles).
  TextStyle get chipLabel => bodyMedium!.copyWith(fontSize: 13, fontWeight: FontWeight.w600);

  /// Small unit suffix next to a numeric field (e.g. "deg", "kn").
  TextStyle get unitLabel => bodySmall!.copyWith(fontWeight: FontWeight.w600);

  /// Monospace logbook share/join-code display (e.g. "AB12-CD34") — large,
  /// bold, and letter-spaced for scan-ability.
  TextStyle get shareCode => const TextStyle(
        fontFamily: 'monospace',
        fontSize: 22,
        fontWeight: FontWeight.bold,
        letterSpacing: 6,
      );

  /// App-bar hero title (e.g. "LOGBOOK") — Newsreader serif, bold, tight tracking.
  TextStyle get brandTitle => GoogleFonts.newsreader(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
        height: 1.0,
      );

  /// App-bar vessel-name subtitle beneath [brandTitle] — Newsreader serif, italic.
  TextStyle get brandSubtitle => GoogleFonts.newsreader(
        fontSize: 20,
        fontWeight: FontWeight.w500,
        fontStyle: FontStyle.italic,
        height: 1.1,
      );
}
