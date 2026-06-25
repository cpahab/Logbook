import 'package:flutter/material.dart';

/// Semantic colour tokens for the timeline / day-detail / crew areas.
@immutable
class LogbookTimelineColors extends ThemeExtension<LogbookTimelineColors> {
  const LogbookTimelineColors({
    required this.crewAccent,
    required this.dividerColor,
    required this.cardShadowColor,
  });

  /// Colour used for all crew-note elements (icons, labels, backgrounds, chips).
  final Color crewAccent;

  /// Border/divider colour for timeline entry cards.
  /// Typically `outlineVariant` at 30 % opacity.
  final Color dividerColor;

  /// Box-shadow tint on timeline/day cards.
  /// Adapts between themes (near-black in light, near-white in dark).
  final Color cardShadowColor;

  @override
  LogbookTimelineColors copyWith({
    Color? crewAccent,
    Color? dividerColor,
    Color? cardShadowColor,
  }) =>
      LogbookTimelineColors(
        crewAccent: crewAccent ?? this.crewAccent,
        dividerColor: dividerColor ?? this.dividerColor,
        cardShadowColor: cardShadowColor ?? this.cardShadowColor,
      );

  @override
  LogbookTimelineColors lerp(LogbookTimelineColors? other, double t) {
    if (other is! LogbookTimelineColors) return this;
    return LogbookTimelineColors(
      crewAccent: Color.lerp(crewAccent, other.crewAccent, t)!,
      dividerColor: Color.lerp(dividerColor, other.dividerColor, t)!,
      cardShadowColor: Color.lerp(cardShadowColor, other.cardShadowColor, t)!,
    );
  }
}

/// Semantic colour tokens for the emergency / mayday screens.
@immutable
class LogbookEmergencyColors extends ThemeExtension<LogbookEmergencyColors> {
  const LogbookEmergencyColors({
    required this.criticalColor,
    required this.criticalBgColor,
    required this.criticalMutedColor,
    required this.cardShadowColor,
  });

  /// Solid critical/urgent colour (borders, pulse border, delete icons).
  /// Matches `ColorScheme.error`.
  final Color criticalColor;

  /// Background fill for critical/urgent cards.
  /// Matches `ColorScheme.errorContainer`.
  final Color criticalBgColor;

  /// Muted variant at ~20 % opacity: pulsing ring, section dividers.
  final Color criticalMutedColor;

  /// Box-shadow tint on emergency cards.
  final Color cardShadowColor;

  @override
  LogbookEmergencyColors copyWith({
    Color? criticalColor,
    Color? criticalBgColor,
    Color? criticalMutedColor,
    Color? cardShadowColor,
  }) =>
      LogbookEmergencyColors(
        criticalColor: criticalColor ?? this.criticalColor,
        criticalBgColor: criticalBgColor ?? this.criticalBgColor,
        criticalMutedColor: criticalMutedColor ?? this.criticalMutedColor,
        cardShadowColor: cardShadowColor ?? this.cardShadowColor,
      );

  @override
  LogbookEmergencyColors lerp(LogbookEmergencyColors? other, double t) {
    if (other is! LogbookEmergencyColors) return this;
    return LogbookEmergencyColors(
      criticalColor: Color.lerp(criticalColor, other.criticalColor, t)!,
      criticalBgColor: Color.lerp(criticalBgColor, other.criticalBgColor, t)!,
      criticalMutedColor:
          Color.lerp(criticalMutedColor, other.criticalMutedColor, t)!,
      cardShadowColor: Color.lerp(cardShadowColor, other.cardShadowColor, t)!,
    );
  }
}
