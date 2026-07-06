import 'package:flutter/material.dart';

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
