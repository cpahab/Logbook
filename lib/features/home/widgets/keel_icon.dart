import 'package:flutter/material.dart';

/// Side-view icon of a sailboat hull with a retractable keel.
///
/// [keelDown] true  → full-length fin below the hull
/// [keelDown] false → short stub (keel retracted)
/// [keelDown] null  → hull only, no fin
class KeelIcon extends StatelessWidget {
  final double size;
  final Color? color;
  final bool? keelDown;

  const KeelIcon({
    super.key,
    this.size = 40,
    this.color,
    this.keelDown,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.onSurface;
    return CustomPaint(
      size: Size(size, size * 0.75),
      painter: _KeelPainter(color: c, keelDown: keelDown),
    );
  }
}

/// Draws the hull silhouette and (if applicable) the keel fin/stub for [KeelIcon].
class _KeelPainter extends CustomPainter {
  final Color color;
  final bool? keelDown;

  const _KeelPainter({required this.color, this.keelDown});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final dimFill = Paint()
      ..color = color.withValues(alpha: 0.35)
      ..style = PaintingStyle.fill;

    // ── Hull ──────────────────────────────────────────────────────────
    // Side view: pointed bow (left), raked transom (right).
    // Waterline sits at ~55 % of height; hull depth peaks near centre.
    final hull = Path()
      ..moveTo(w * 0.10, h * 0.14)              // deck at bow
      ..lineTo(w * 0.88, h * 0.14)              // deck line
      ..lineTo(w * 0.94, h * 0.46)              // transom bottom
      // hull bottom, stern → bow
      ..cubicTo(w * 0.72, h * 0.62,
                w * 0.28, h * 0.62,
                w * 0.05, h * 0.44)             // bow waterline
      // bow nose curve back up to deck
      ..cubicTo(w * 0.01, h * 0.32,
                w * 0.04, h * 0.14,
                w * 0.10, h * 0.14)
      ..close();
    canvas.drawPath(hull, fill);

    // ── Keel ──────────────────────────────────────────────────────────
    // Centred at x≈0.50; top connects to hull bottom (~y 0.60).
    if (keelDown == true) {
      final keel = Path()
        ..moveTo(w * 0.43, h * 0.59)
        ..lineTo(w * 0.57, h * 0.59)
        ..lineTo(w * 0.52, h * 0.97)            // tapered to narrow tip
        ..lineTo(w * 0.48, h * 0.97)
        ..close();
      canvas.drawPath(keel, fill);
    } else if (keelDown == false) {
      // Short stub — keel retracted inside hull
      final stub = Path()
        ..moveTo(w * 0.43, h * 0.59)
        ..lineTo(w * 0.57, h * 0.59)
        ..lineTo(w * 0.55, h * 0.72)
        ..lineTo(w * 0.45, h * 0.72)
        ..close();
      canvas.drawPath(stub, dimFill);
    }
  }

  @override
  bool shouldRepaint(_KeelPainter old) =>
      old.color != color || old.keelDown != keelDown;
}
