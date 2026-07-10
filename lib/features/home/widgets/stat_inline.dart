import 'package:flutter/material.dart';

import '../../../app/theme/theme_extensions.dart';

/// Small icon + label used for inline day/track stats (wind, average speed,
/// distance, ...). No pill/background — just the glyph and the value.
///
/// [label] is styled uppercase; pass a unit (e.g. "kn", "nm") via [unit] to
/// keep it lowercase per nautical convention, since it isn't affected by the
/// label's uppercase styling.
Widget statInline(BuildContext context, IconData icon, String label, ColorScheme cs, {String unit = ''}) {
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 12, color: cs.onSurfaceVariant),
      const SizedBox(width: 4),
      Text.rich(
        TextSpan(
          children: [
            TextSpan(text: label.toUpperCase()),
            if (unit.isNotEmpty) TextSpan(text: ' $unit'),
          ],
        ),
        style: Theme.of(context).textTheme.microLabel.copyWith(
          letterSpacing: 0.5,
          color: cs.primary,
        ),
      ),
    ],
  );
}
