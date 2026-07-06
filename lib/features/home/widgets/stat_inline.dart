import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Small icon + label used for inline day/track stats (wind, average speed,
/// distance, ...). No pill/background — just the glyph and the value.
Widget statInline(IconData icon, String label, ColorScheme cs) {
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 12, color: cs.onSurfaceVariant),
      const SizedBox(width: 4),
      Text(
        label.toUpperCase(),
        style: GoogleFonts.dmSans(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
          color: cs.primary,
        ),
      ),
    ],
  );
}
