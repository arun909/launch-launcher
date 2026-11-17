import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// The media controls' glyphs, drawn rather than taken from an icon font:
/// soft-cornered triangles and bars with even weight, in the clean style of
/// current phone players.
enum Glyph { play, pause, next, previous, volumeOff, volumeLow, volumeHigh }

/// One [Glyph], [size] square, in [color].
class MediaGlyph extends StatelessWidget {
  const MediaGlyph(this.glyph, {super.key, this.size = 24, this.color = const Color(0xFFFFFFFF)});

  final Glyph glyph;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CustomPaint(painter: _GlyphPainter(glyph, color)),
  );
}

class _GlyphPainter extends CustomPainter {
  _GlyphPainter(this.glyph, this.color);

  final Glyph glyph;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // Drawn on a 24-unit grid.
    canvas.scale(size.width / 24, size.height / 24);
    final fill = Paint()
      ..color = color
      ..isAntiAlias = true;
    // A round stroke over a filled shape softens its corners.
    final soft = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    void triangle(Offset a, Offset b, Offset c) {
      final p = Path()
        ..moveTo(a.dx, a.dy)
        ..lineTo(b.dx, b.dy)
        ..lineTo(c.dx, c.dy)
        ..close();
      canvas
        ..drawPath(p, fill)
        ..drawPath(p, soft);
    }

    void bar(double left, double top, double width, double height) => canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(left, top, width, height), Radius.circular(width / 2)),
      fill,
    );

    switch (glyph) {
      case Glyph.play:
        // Nudged right: a triangle looks centred a little past the middle.
        triangle(const Offset(8.2, 5.4), const Offset(18.6, 12), const Offset(8.2, 18.6));
      case Glyph.pause:
        bar(6.6, 5, 3.8, 14);
        bar(13.6, 5, 3.8, 14);
      case Glyph.next:
        triangle(const Offset(5.6, 7), const Offset(14, 12), const Offset(5.6, 17));
        bar(16.4, 6, 2.6, 12);
      case Glyph.previous:
        triangle(const Offset(18.4, 7), const Offset(10, 12), const Offset(18.4, 17));
        bar(5, 6, 2.6, 12);
      case Glyph.volumeOff:
      case Glyph.volumeLow:
      case Glyph.volumeHigh:
        _speaker(canvas, fill, soft);
    }
  }

  void _speaker(Canvas canvas, Paint fill, Paint soft) {
    final body = Path()
      ..moveTo(3.6, 9.4)
      ..lineTo(6.8, 9.4)
      ..lineTo(11, 5.8)
      ..lineTo(11, 18.2)
      ..lineTo(6.8, 14.6)
      ..lineTo(3.6, 14.6)
      ..close();
    canvas
      ..drawPath(body, fill)
      ..drawPath(body, soft..strokeWidth = 1.6);
    final line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;
    if (glyph == Glyph.volumeOff) {
      canvas
        ..drawLine(const Offset(15, 9.5), const Offset(20, 14.5), line)
        ..drawLine(const Offset(20, 9.5), const Offset(15, 14.5), line);
      return;
    }
    const centre = Offset(11.5, 12);
    void wave(double r) =>
        canvas.drawArc(Rect.fromCircle(center: centre, radius: r), -math.pi / 4, math.pi / 2, false, line);
    wave(4.2);
    if (glyph == Glyph.volumeHigh) wave(7.8);
  }

  @override
  bool shouldRepaint(_GlyphPainter old) => old.glyph != glyph || old.color != color;
}
