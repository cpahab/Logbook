import 'package:flutter/material.dart';

import '../../../app/theme/theme_extensions.dart';

/// Small icon + label used for inline day/track stats (wind, average speed,
/// distance, ...). No pill/background — just the glyph and the value.
Widget statInline(BuildContext context, IconData icon, String label, ColorScheme cs) {
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 12, color: cs.onSurfaceVariant),
      const SizedBox(width: 4),
      Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.microLabel.copyWith(
          letterSpacing: 0.5,
          color: cs.primary,
        ),
      ),
    ],
  );
}
