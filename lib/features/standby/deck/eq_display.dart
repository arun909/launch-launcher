import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'spectrum_driver.dart';

/// The 10-band spectrum: crisp LED segments in the standard analyser
/// colours (green, then yellow, red at the top), unlit segments faintly showing, and a held peak
/// cap over each column. Snapped to whole segments and pixels, so it reads
/// sharp rather than soft.
class EqDisplay extends StatelessWidget {
  const EqDisplay({super.key, required this.driver});

  final SpectrumDriver? driver;

  /// Segments per column.
  static const segments = 20;

  static const green = Color(0xFF35E05A);
  static const yellow = Color(0xFFF7D23A);
  static const red = Color(0xFFFF3B30);

  /// Segment [s]'s colour (0 at the bottom): green for the lower 60%,
  /// yellow up to 85%, red above.
  static Color colorOf(int s) => s < segments * 0.6
      ? green
      : s < segments * 0.85
      ? yellow
      : red;

  @override
  Widget build(BuildContext context) => RepaintBoundary(child: CustomPaint(painter: _EqPainter(driver)));
}

class _EqPainter extends CustomPainter {
  _EqPainter(this.driver) : super(repaint: driver);

  final SpectrumDriver? driver;

  @override
  void paint(Canvas canvas, Size size) {
    const n = SpectrumDriver.bandCount;
    const segs = EqDisplay.segments;
    const labelH = 13.0;
    final barsH = size.height - labelH;
    final pitchX = size.width / n;
    final barW = (pitchX * 0.7).floorToDouble();
    final pitchY = barsH / segs;
    final segH = math.max(1.0, (pitchY * 0.62).floorToDouble());

    final lit = Paint();
    final glow = Paint()..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.5);
    for (var i = 0; i < n; i++) {
      final x = (i * pitchX + (pitchX - barW) / 2).roundToDouble();
      final level = driver?.bands[i] ?? 0;
      final on = (level * segs).round();
      final peak = ((driver?.peaks[i] ?? 0) * segs).ceil().clamp(0, segs);

      for (var s = 0; s < segs; s++) {
        final y = (barsH - (s + 1) * pitchY + (pitchY - segH) / 2).roundToDouble();
        final r = Rect.fromLTWH(x, y, barW, segH);
        final isOn = s < on;
        final isPeak = s == peak - 1 && peak > on && peak > 0;
        final color = EqDisplay.colorOf(s);
        if (isOn || isPeak) {
          final c = isPeak ? Color.lerp(color, Colors.white, 0.35)! : color;
          glow.color = c.withValues(alpha: 0.38);
          canvas.drawRect(r.inflate(1.5), glow);
          lit.color = c;
          canvas.drawRect(r, lit);
        } else {
          lit.color = color.withValues(alpha: 0.075);
          canvas.drawRect(r, lit);
        }
      }

      final tp = TextPainter(
        text: TextSpan(
          text: SpectrumDriver.labels[i],
          style: TextStyle(
            fontFamily: 'ClockOswald',
            fontSize: 8.5,
            letterSpacing: 0.3,
            color: const Color(0xFF8E877A),
            fontVariations: const [FontVariation('wght', 500)],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x + barW / 2 - tp.width / 2, size.height - tp.height));
    }
  }

  @override
  bool shouldRepaint(_EqPainter old) => old.driver != driver;
}
