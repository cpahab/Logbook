import 'package:flutter/material.dart';

import '../../app/theme/theme_extensions.dart';

/// Shared card chrome: a rounded surface with a colored accent bar down the
/// left edge, optionally bordered/shadowed — used for settings sections,
/// backup/restore panels, and emergency reference cards so they all read as
/// one consistent visual pattern instead of each screen hand-rolling its own.
class CardShell extends StatelessWidget {
  final Widget child;
  final Color? backgroundColor;
  final Color? accentColor;
  final bool bordered;
  final bool shadowed;
  final BorderRadius borderRadius;

  const CardShell({
    super.key,
    required this.child,
    this.backgroundColor,
    this.accentColor,
    this.bordered = false,
    this.shadowed = false,
    this.borderRadius = const BorderRadius.all(Radius.circular(12)),
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: backgroundColor ?? cs.surfaceContainerLowest,
        borderRadius: borderRadius,
        border: bordered
            ? Border.all(color: cs.outlineVariant.withValues(alpha: 0.3))
            : null,
        boxShadow: shadowed
            ? [
                BoxShadow(
                  color: cs.cardShadowColor,
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: Stack(
          children: [
            Positioned(
              left: 0, top: 0, bottom: 0,
              child: Container(width: 4, color: accentColor ?? cs.primary),
            ),
            child,
          ],
        ),
      ),
    );
  }
}
