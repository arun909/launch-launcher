import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Digits drawn as a vacuum-fluorescent 7-segment readout: slanted, pointed
/// segments with a soft bloom, and every unlit segment still faintly visible
/// behind, as on a real display ("88:88" ghosting through).
///
/// [text] holds digits, spaces (a blank cell, ghost only) and colons. The
/// lit segments are filled with [colors] running left to right.
class SevenSegment extends StatelessWidget {
  const SevenSegment({
    super.key,
    required this.text,
    required this.colors,
    required this.height,
    this.colonLit = true,
    this.ghost = 0.07,
  });

  final String text;
  final List<Color> colors;
  final double height;
  final bool colonLit;

  /// How visible the unlit segments are.
  final double ghost;

  /// A digit cell's width for its height.
  static const aspect = 0.56;

  /// A colon cell's width for the digits' height.
  static const colonAspect = 0.26;

  static const _gap = 0.17;

  static double widthOf(String text, double height) {
    var w = 0.0;
    for (final c in text.split('')) {
      w += (c == ':' ? colonAspect : aspect) * height + height * _gap * 0.5;
    }
    return w;
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: widthOf(text, height) + height * 0.12,
    height: height,
    child: CustomPaint(painter: _SegmentsPainter(text, colors, colonLit, ghost)),
  );
}

class _SegmentsPainter extends CustomPainter {
  _SegmentsPainter(this.text, this.colors, this.colonLit, this.ghost);

  final String text;
  final List<Color> colors;
  final bool colonLit;
  final double ghost;

  /// Segments a-g lit for each digit (a top, then clockwise, g the middle).
  static const _digits = {
    '0': 0x3F,
    '1': 0x06,
    '2': 0x5B,
    '3': 0x4F,
    '4': 0x66,
    '5': 0x6D,
    '6': 0x7D,
    '7': 0x07,
    '8': 0x7F,
    '9': 0x6F,
    '-': 0x40,
    ' ': 0x00,
  };

  @override
  void paint(Canvas canvas, Size size) {
    final h = size.height;
    final w = SevenSegment.aspect * h;
    final t = h * 0.11; // Segment thickness.
    final gap = t * 0.16;
    final lit = Path();
    final dark = Path();

    var x = h * 0.08; // Room for the slant's lean.
    for (final c in text.split('')) {
      if (c == ':') {
        final cw = SevenSegment.colonAspect * h;
        final d = t * 0.62;
        for (final cy in [h * 0.32, h * 0.7]) {
          final dot = Path()
            ..addRRect(
              RRect.fromRectAndRadius(
                Rect.fromCenter(center: Offset(x + cw / 2, cy), width: d * 1.15, height: d * 1.15),
                Radius.circular(d * 0.2),
              ),
            );
          (colonLit ? lit : dark).addPath(dot, Offset.zero);
        }
        x += cw + h * SevenSegment._gap * 0.5;
        continue;
      }
      final bits = _digits[c] ?? 0;
      final l = x + t / 2, r = x + w - t / 2;
      final top = t / 2, mid = h / 2, bot = h - t / 2;
      final segs = [
        _h(l + gap, r - gap, top, t), // a
        _v(r, top + gap, mid - gap, t), // b
        _v(r, mid + gap, bot - gap, t), // c
        _h(l + gap, r - gap, bot, t), // d
        _v(l, mid + gap, bot - gap, t), // e
        _v(l, top + gap, mid - gap, t), // f
        _h(l + gap, r - gap, mid, t), // g
      ];
      for (var i = 0; i < 7; i++) {
        (bits & (1 << i) != 0 ? lit : dark).addPath(segs[i], Offset.zero);
      }
      x += w + h * SevenSegment._gap * 0.5;
    }

    // Slanted like a real readout, leaning about 7 degrees.
    canvas.save();
    canvas.translate(0, h);
    canvas.transform(Matrix4.skewX(-0.12).storage);
    canvas.translate(0, -h);

    final shader = ui.Gradient.linear(
      Offset.zero,
      Offset(size.width, 0),
      colors.length >= 2 ? colors : [colors.first, colors.first],
      _stops(colors.length),
    );
    canvas.drawPath(
      dark,
      Paint()
        ..shader = shader
        ..color = Colors.white.withValues(alpha: ghost),
    );
    // Bloom, then the sharp segments over it.
    canvas.drawPath(
      lit,
      Paint()
        ..shader = shader
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, t * 0.9)
        ..color = Colors.white.withValues(alpha: 0.6),
    );
    canvas.drawPath(lit, Paint()..shader = shader);
    // A hot core: the filament's brightest line.
    canvas.drawPath(
      lit,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.18)
        ..maskFilter = MaskFilter.blur(BlurStyle.inner, t * 0.25),
    );
    canvas.restore();
  }

  static List<double>? _stops(int n) => n <= 2 ? null : [for (var i = 0; i < n; i++) i / (n - 1)];

  /// A horizontal segment with pointed ends, along y from x0 to x1.
  static Path _h(double x0, double x1, double y, double t) => Path()
    ..moveTo(x0, y)
    ..lineTo(x0 + t / 2, y - t / 2)
    ..lineTo(x1 - t / 2, y - t / 2)
    ..lineTo(x1, y)
    ..lineTo(x1 - t / 2, y + t / 2)
    ..lineTo(x0 + t / 2, y + t / 2)
    ..close();

  /// A vertical segment with pointed ends, along x from y0 to y1.
  static Path _v(double x, double y0, double y1, double t) => Path()
    ..moveTo(x, y0)
    ..lineTo(x + t / 2, y0 + t / 2)
    ..lineTo(x + t / 2, y1 - t / 2)
    ..lineTo(x, y1)
    ..lineTo(x - t / 2, y1 - t / 2)
    ..lineTo(x - t / 2, y0 + t / 2)
    ..close();

  @override
  bool shouldRepaint(_SegmentsPainter old) =>
      old.text != text || old.colonLit != colonLit || old.ghost != ghost || !_same(old.colors, colors);

  static bool _same(List<Color> a, List<Color> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
