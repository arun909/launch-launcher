import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// A record with the song's cover filling it, turning slowly while
/// [playing]. On play it spins up, and on pause it brakes to a stop over
/// about a second, like a turntable. The light on the grooves stays put while
/// the record turns, as it would under a lamp.
class RecordPlayer extends StatefulWidget {
  const RecordPlayer({
    super.key,
    required this.playing,
    this.art,
    this.artKey,
    required this.accent,
    this.animate = true,
  });

  final bool playing;
  final Uint8List? art;
  final Object? artKey;

  final List<Color> accent;

  /// Off in previews and tests: drawn still.
  final bool animate;

  @override
  State<RecordPlayer> createState() => _RecordPlayerState();
}

class _RecordPlayerState extends State<RecordPlayer> with SingleTickerProviderStateMixin {
  /// 5 turns a minute, in radians a second: slow and calm, the cover
  /// easy to make out.
  static const _speed = 2 * math.pi * 5 / 60;

  /// How long spinning up and braking to a stop take, in seconds.
  static const _spinUp = 0.8;
  static const _brake = 1.1;

  late final Ticker _ticker = createTicker(_tick);
  final _angle = ValueNotifier<double>(0);
  double _omega = 0;
  Duration? _last;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(RecordPlayer old) {
    super.didUpdateWidget(old);
    if (old.playing != widget.playing || old.animate != widget.animate) _sync();
  }

  void _sync() {
    if (!widget.animate) return;
    if ((widget.playing || _omega > 0) && !_ticker.isActive) {
      _last = null;
      _ticker.start();
    }
  }

  void _tick(Duration elapsed) {
    final last = _last;
    final dt = last == null ? 1 / 60 : (elapsed - last).inMicroseconds / 1e6;
    _last = elapsed;
    final target = widget.playing ? _speed : 0.0;
    // Spins up in about a second, coasts down a little slower.
    // Steady acceleration and braking, so the stop reads as a turntable's.
    if (_omega < target) {
      _omega = math.min(target, _omega + _speed / _spinUp * dt);
    } else if (_omega > target) {
      _omega = math.max(target, _omega - _speed / _brake * dt);
    }
    if (!widget.playing && _omega <= 0) {
      _omega = 0;
      _ticker.stop();
    }
    _angle.value = (_angle.value + _omega * dt) % (2 * math.pi);
  }

  @override
  void dispose() {
    _ticker.dispose();
    _angle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final d = math.min(box.maxHeight, box.maxWidth);
      final art = widget.art;
      // A cover fills the whole disc, like a picture disc; without one, a
      // black record with a small coloured label.
      final labelD = art == null ? d * 0.4 : d;
      final Widget label = art == null
          ? _PlainLabel(accent: widget.accent)
          : Image.memory(
              art,
              key: ValueKey(widget.artKey),
              fit: BoxFit.cover,
              gaplessPlayback: true,
              filterQuality: FilterQuality.medium,
              cacheWidth: 512,
            );
      return Center(
        child: SizedBox(
          width: d,
          height: d,
          child: Stack(
            alignment: Alignment.center,
            children: [
              const Positioned.fill(
                child: RepaintBoundary(child: CustomPaint(painter: _VinylPainter())),
              ),
              ValueListenableBuilder<double>(
                valueListenable: _angle,
                builder: (context, a, child) => Transform.rotate(angle: a, child: child),
                child: SizedBox(
                  width: labelD,
                  height: labelD,
                  child: ClipOval(
                    // Stretched to the disc: on its own the cover would sit at its
                    // natural size in the middle (the switcher's stack is loose).
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 500),
                      layoutBuilder: (current, previous) =>
                          Stack(fit: StackFit.expand, children: [...previous, ?current]),
                      child: label,
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: RepaintBoundary(
                  child: CustomPaint(painter: _SheenPainter(picture: art != null)),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _PlainLabel extends StatelessWidget {
  const _PlainLabel({required this.accent});

  final List<Color> accent;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(gradient: SweepGradient(colors: [...accent, accent.first])),
    child: const Align(
      // Below the spindle.
      alignment: Alignment(0, 0.45),
      child: Text(
        'HI-FI',
        style: TextStyle(
          fontFamily: 'ClockOswald',
          fontSize: 10,
          letterSpacing: 1.5,
          color: Color(0xCC111111),
          fontVariations: [FontVariation('wght', 600)],
        ),
      ),
    ),
  );
}

class _VinylPainter extends CustomPainter {
  const _VinylPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    // The platter's rim under the record.
    canvas.drawCircle(
      c + const Offset(0, 3),
      r,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.8)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0xFF1A1A1C), Color(0xFF0B0B0C), Color(0xFF141416)],
          stops: [0.3, 0.85, 1],
        ).createShader(Rect.fromCircle(center: c, radius: r)),
    );
    // Grooves: fine rings, a few gaps between "tracks".
    final groove = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6;
    for (var gr = r * 0.25; gr < r * 0.97; gr += 1.7) {
      final band = ((gr / r) * 9).floor();
      final gapRing = (gr / r * 9) % 1 < 0.04;
      groove.color = Colors.white.withValues(alpha: gapRing ? 0.0 : (band.isEven ? 0.045 : 0.03));
      canvas.drawCircle(c, gr, groove);
    }
    // The lead-in edge.
    canvas.drawCircle(
      c,
      r - 0.5,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.white.withValues(alpha: 0.12),
    );
  }

  @override
  bool shouldRepaint(_VinylPainter old) => false;
}

/// The lamp's reflection on the grooves (fixed) and the spindle. On a
/// [picture] disc (the cover filling it), fine grooves over the picture too,
/// a darker rim and a small hub, so it still reads as a record.
class _SheenPainter extends CustomPainter {
  const _SheenPainter({this.picture = false});

  final bool picture;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    final rect = Rect.fromCircle(center: c, radius: r);
    if (picture) {
      final groove = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.6;
      for (var gr = r * 0.16; gr < r * 0.98; gr += 1.8) {
        final gapRing = (gr / r * 9) % 1 < 0.05;
        groove.color = gapRing ? Colors.black.withValues(alpha: 0.28) : Colors.black.withValues(alpha: 0.1);
        canvas.drawCircle(c, gr, groove);
      }
      // Edge vignette and a lit rim.
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = RadialGradient(
            colors: [Colors.transparent, Colors.black.withValues(alpha: 0.45)],
            stops: const [0.78, 1],
          ).createShader(rect),
      );
      canvas.drawCircle(
        c,
        r - 0.5,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = Colors.white.withValues(alpha: 0.18),
      );
      // The hub around the spindle.
      canvas.drawCircle(c, r * 0.11, Paint()..color = const Color(0xFF111113));
      canvas.drawCircle(
        c,
        r * 0.11,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8
          ..color = Colors.white.withValues(alpha: 0.2),
      );
    }
    final ring = Path()
      ..addOval(rect)
      ..addOval(Rect.fromCircle(center: c, radius: r * (picture ? 0.11 : 0.205)))
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(
      ring,
      Paint()
        ..shader = SweepGradient(
          colors: [
            Colors.transparent,
            Colors.white.withValues(alpha: 0.13),
            Colors.transparent,
            Colors.transparent,
            Colors.white.withValues(alpha: 0.09),
            Colors.transparent,
            Colors.transparent,
          ],
          stops: const [0.04, 0.12, 0.2, 0.54, 0.62, 0.7, 1],
        ).createShader(rect),
    );
    // Spindle.
    canvas.drawCircle(
      c,
      r * 0.035,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-0.4, -0.4),
          colors: [Color(0xFFF2F2F2), Color(0xFF8C8C8C), Color(0xFF3A3A3A)],
        ).createShader(Rect.fromCircle(center: c, radius: r * 0.035)),
    );
  }

  @override
  bool shouldRepaint(_SheenPainter old) => old.picture != picture;
}
