import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'spectrum_driver.dart';

/// A backlit analogue VU meter: cream face lit warm from below, the true VU
/// scale (-20 to +3, spaced by amplitude, so 0 sits far right), a red zone,
/// a percent scale under it, a needle with its shadow on the face and a
/// peak lamp. Reads [SpectrumDriver.needles] for [channel] (0 left, 1 right).
class VuMeter extends StatelessWidget {
  const VuMeter({super.key, required this.driver, required this.channel, required this.label, required this.tint});

  final SpectrumDriver? driver;
  final int channel;
  final String label;

  /// The backlight's colour (the song's, or amber): the face stays light in
  /// the middle so the scale reads, and deepens to it towards the corners.
  final Color tint;

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: Stack(
      fit: StackFit.expand,
      children: [
        // The face changes only with the colour: painted once per colour.
        RepaintBoundary(child: CustomPaint(painter: _FacePainter(label, tint))),
        CustomPaint(painter: _NeedlePainter(driver, channel)),
      ],
    ),
  );
}

/// Geometry shared by the face and the needle.
class _Geo {
  _Geo(Size size)
    : face = Rect.fromLTWH(9, 9, size.width - 18, size.height - 18),
      pivot = Offset(size.width / 2, size.height - 18 + (size.height - 18) * 0.42),
      radius = (size.height - 18) * 1.08;

  final Rect face;
  final Offset pivot;
  final double radius;

  /// Half the scale's sweep.
  static const sweep = 0.72; // radians, ~41 degrees each side.

  static final _lo = math.pow(10, -20 / 20);
  static final _hi = math.pow(10, 3 / 20);

  /// The needle's angle from straight up for a level in dB (-20..+3).
  static double angleOfDb(double db) {
    final a = math.pow(10, db.clamp(-23.0, 4.0) / 20);
    final p = (a - _lo) / (_hi - _lo);
    return -sweep + 2 * sweep * p;
  }

  Offset at(double angle, double r) => pivot + Offset(math.sin(angle) * r, -math.cos(angle) * r);
}

class _FacePainter extends CustomPainter {
  _FacePainter(this.label, this.tint);

  final String label;
  final Color tint;

  static const ink = Color(0xFF2A2116);
  static const red = Color(0xFFC0281E);

  @override
  void paint(Canvas canvas, Size size) {
    final g = _Geo(size);
    final outer = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(12));

    // Bezel: dark metal with a lit top edge.
    canvas.drawRRect(
      outer,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF3A3A3E), Color(0xFF16161A), Color(0xFF0C0C0E)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawRRect(
      outer.deflate(0.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.white.withValues(alpha: 0.25), Colors.white.withValues(alpha: 0.02)],
        ).createShader(Offset.zero & size),
    );

    final faceR = RRect.fromRectAndRadius(g.face, const Radius.circular(6));
    canvas.save();
    canvas.clipRRect(faceR);
    // Lamp-lit from below, warm in the middle, falling off to the corners.
    canvas.drawRect(
      g.face,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0, 1.25),
          radius: 1.35,
          // Hottest low in the middle, the tint deepening to the corners.
          colors: [
            Color.lerp(const Color(0xFFFFF4DC), tint, 0.4)!,
            Color.lerp(const Color(0xFFFFF4DC), tint, 0.58)!,
            Color.lerp(const Color(0xFFFFF4DC), tint, 0.85)!,
            Color.lerp(tint, Colors.black, 0.42)!,
          ],
          stops: const [0, 0.38, 0.76, 1],
        ).createShader(g.face),
    );

    // The scale arc: black to 0, a thick red band from 0 to +3.
    final r = g.radius * 0.86;
    final arc = Rect.fromCircle(center: g.pivot, radius: r);
    double a(double db) => _Geo.angleOfDb(db) - math.pi / 2;
    canvas.drawArc(
      arc,
      a(-20),
      a(0) - a(-20),
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.3
        ..color = ink,
    );
    canvas.drawArc(
      Rect.fromCircle(center: g.pivot, radius: r + 2.2),
      a(0),
      a(3) - a(0),
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..color = red,
    );

    // Ticks and numbers.
    const major = [-20.0, -10.0, -7.0, -5.0, -3.0, -2.0, -1.0, 0.0, 1.0, 2.0, 3.0];
    const minor = [-15.0, -8.0, -6.0, -4.0, -0.5, 0.5, 1.5, 2.5];
    for (final db in minor) {
      final ang = _Geo.angleOfDb(db);
      canvas.drawLine(
        g.at(ang, r),
        g.at(ang, r + 4),
        Paint()
          ..strokeWidth = 0.9
          ..color = db >= 0 ? red : ink,
      );
    }
    for (final db in major) {
      final ang = _Geo.angleOfDb(db);
      canvas.drawLine(
        g.at(ang, r - 1),
        g.at(ang, r + 8),
        Paint()
          ..strokeWidth = 1.4
          ..color = db > 0 ? red : ink,
      );
      final text = db == 0
          ? '0'
          : db > 0
          ? '+${db.toInt()}'
          : '${db.toInt().abs()}';
      _text(canvas, text, g.at(ang, r + 16), 9.5, db > 0 ? red : ink, weight: 600, rotate: ang);
    }
    // The percent scale under the arc.
    final pr = r - 10;
    for (var p = 0; p <= 100; p += 20) {
      final db = 20 * math.log(math.max(0.1, p / 100)) / math.ln10;
      final ang = _Geo.angleOfDb(p == 0 ? -20 : db);
      canvas.drawLine(
        g.at(ang, pr),
        g.at(ang, pr - 3.5),
        Paint()
          ..strokeWidth = 0.9
          ..color = ink.withValues(alpha: 0.7),
      );
      if (p == 0 || p == 100) {
        _text(canvas, '$p', g.at(ang, pr - 9), 6.5, ink.withValues(alpha: 0.75), rotate: ang);
      }
    }
    _text(canvas, '-', g.at(_Geo.angleOfDb(-20) - 0.1, r + 6), 11, ink);
    _text(canvas, '+', g.at(_Geo.angleOfDb(3) + 0.1, r + 6), 11, red);

    // The VU legend and the channel.
    _text(
      canvas,
      'VU',
      Offset(g.face.center.dx, g.face.top + g.face.height * 0.79),
      17,
      ink,
      weight: 700,
      family: 'ClockSourceSerif',
      spacing: 1,
    );
    _text(
      canvas,
      label,
      Offset(g.face.left + 14, g.face.bottom - 12),
      10,
      ink.withValues(alpha: 0.8),
      weight: 700,
      family: 'ClockOswald',
    );
    _text(
      canvas,
      'PEAK',
      Offset(g.face.right - 26, g.face.top + 11),
      6.2,
      ink.withValues(alpha: 0.7),
      weight: 700,
      family: 'ClockOswald',
      spacing: 0.8,
    );
    canvas.restore();

    // Inner shadow at the face's top edge: it sits behind the bezel.
    canvas.save();
    canvas.clipRRect(faceR);
    canvas.drawRRect(
      faceR.inflate(6),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 12
        ..color = Colors.black.withValues(alpha: 0.55)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );
    canvas.restore();
  }

  static void _text(
    Canvas canvas,
    String text,
    Offset center,
    double size,
    Color color, {
    int weight = 500,
    double rotate = 0,
    String family = 'ClockOswald',
    double spacing = 0,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: family,
          fontSize: size,
          color: color,
          letterSpacing: spacing,
          fontVariations: [FontVariation('wght', weight.toDouble())],
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(rotate);
    tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
    canvas.restore();
  }

  @override
  bool shouldRepaint(_FacePainter old) => old.label != label || old.tint != tint;
}

class _NeedlePainter extends CustomPainter {
  _NeedlePainter(this.driver, this.channel) : super(repaint: driver);

  final SpectrumDriver? driver;
  final int channel;

  @override
  void paint(Canvas canvas, Size size) {
    final g = _Geo(size);
    final v = driver?.needles[channel] ?? 0;
    final ang = _Geo.angleOfDb(-20 + v * 23);
    final faceR = RRect.fromRectAndRadius(g.face, const Radius.circular(6));
    canvas.save();
    canvas.clipRRect(faceR);

    final tip = g.at(ang, g.radius * 0.98);
    final base = g.at(ang, g.radius * 0.3);
    // Its shadow on the face, down and right of the lamp.
    canvas.drawLine(
      base + const Offset(2.5, 3),
      tip + const Offset(2.5, 3),
      Paint()
        ..strokeWidth = 1.8
        ..color = Colors.black.withValues(alpha: 0.22)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.6),
    );
    canvas.drawLine(
      base,
      tip,
      Paint()
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFF141110),
    );

    // The pivot's cover plate along the bottom.
    final plate = Rect.fromCenter(
      center: Offset(g.face.center.dx, g.face.bottom + 2),
      width: g.face.width * 0.42,
      height: g.face.height * 0.26,
    );
    canvas.drawRRect(
      RRect.fromRectAndCorners(plate, topLeft: const Radius.circular(40), topRight: const Radius.circular(40)),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF34302B), Color(0xFF151311)],
        ).createShader(plate),
    );

    // The peak lamp.
    final lamp = Offset(g.face.right - 12, g.face.top + 11);
    final on = driver?.overload[channel] ?? false;
    if (on) {
      canvas.drawCircle(
        lamp,
        9,
        Paint()
          ..color = const Color(0xFFFF3B2E).withValues(alpha: 0.55)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
    }
    canvas.drawCircle(lamp, 3.4, Paint()..color = on ? const Color(0xFFFF5546) : const Color(0xFF5A1D17));
    canvas.drawCircle(lamp - const Offset(1, 1), 1.1, Paint()..color = Colors.white.withValues(alpha: on ? 0.8 : 0.18));

    // The glass over it all: a soft reflection across the top.
    canvas.drawRect(
      g.face,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: const Alignment(0.2, 0.1),
          colors: [Colors.white.withValues(alpha: 0.16), Colors.white.withValues(alpha: 0)],
        ).createShader(g.face),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_NeedlePainter old) => old.driver != driver || old.channel != channel;
}
