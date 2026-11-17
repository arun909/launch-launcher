import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/platform/launcher_platform.dart';
import '../../../core/platform/window_blur_platform.dart';
import '../../appearance/wallpaper_glass.dart';
import '../../standard_home/app_container_tile.dart';
import '../../standard_home/home_layout.dart';
import '../../standard_home/home_layout_controller.dart';
import '../controls/tile_look.dart';
import '../launcher_widgets.dart';
import 'wallpaper_colors.dart';

/// The analog clock: a watch face, in one of several styles after classic
/// watches, with the date under 12 and the digital time in a small window
/// above 6, like a watch's complication. Its background (glass or dark) is
/// a round one just behind the face, not the widget's square panel; or none,
/// just the face on the wallpaper. A tap opens the phone's clock app.
const analogClockKind = LauncherWidgetKind(
  name: 'analog_clock',
  label: 'Analog clock',
  description: 'Watch faces with the digital time in a small window',
  icon: Icons.watch_later_outlined,
  group: 'Clocks',
  size: (2, 2),
  min: (2, 2),
  // Any span, so it can be centred on any grid (2 × 2 or 4 × 4 can't be on
  // 5 columns); the face stays round, centred in its frame.
  max: (6, 4),
  build: _build,
  customise: showAnalogClockSettings,
  // The background is drawn round the dial, by the clock itself.
  panelOf: clockNeverPanel,
  // Takes taps itself, to open the clock app.
  interactive: true,
);

/// A clock's background behind its face (settings['style']; 'none' for
/// none): the launcher's glass, a dark one, a Material You tonal one
/// tinted from the wallpaper, or a solid Material dark or light surface
/// (GroupStyle.material / materialLight; stored as their own names here,
/// since 'material' is the tonal one).
enum ClockSurface {
  glass,
  dark,
  material,
  materialDark,
  materialLight;

  /// A light surface: what's drawn straight on it goes dark.
  bool get light => this == materialLight;
}

/// settings['style'] for no background.
const clockNoBackground = 'none';

bool clockNeverPanel(Map<String, dynamic> settings) => false;

/// The round background behind the face; null for none.
ClockSurface? clockBackgroundOf(Map<String, dynamic> settings) => settings['style'] == clockNoBackground
    ? null
    : ClockSurface.values.asNameMap()[settings['style']] ?? ClockSurface.glass;

WatchFace _faceOf(Map<String, dynamic> settings) => WatchFace.values.asNameMap()[settings['face']] ?? WatchFace.classic;

Widget _build(BuildContext context, Map<String, dynamic> settings) => Semantics(
  button: true,
  hint: 'Opens the clock app',
  child: GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: () => context.read<LauncherPlatform?>()?.openClock(),
    child: AnalogClock(face: _faceOf(settings), background: clockBackgroundOf(settings)),
  ),
);

/// The faces, each after a classic kind of watch (no makers' names or marks).
enum WatchFace {
  classic('Classic'),
  railway('Railway'),
  diver('Diver'),
  pilot('Pilot'),
  bauhaus('Bauhaus'),
  chrono('Chronograph'),
  field('Field'),
  orbit('Orbit'),
  minimal('Minimal');

  const WatchFace(this.label);

  final String label;

  /// White dial, black ink.
  bool get light => this == railway || this == bauhaus;

  /// A see-through dial, drawn in the background's ink (dark on a light one).
  bool get seeThrough => this == classic || this == orbit || this == minimal;
}

/// Ink for what's drawn on [face]: black on its own white dial, dark on a
/// light background (if the dial's see-through), else white.
Color _inkOf(WatchFace face, bool onLight) => face.light
    ? Colors.black
    : onLight && face.seeThrough
    ? GroupStyle.materialLight.ink
    : Colors.white;

class AnalogClock extends StatefulWidget {
  const AnalogClock({super.key, this.face = WatchFace.classic, this.background});

  final WatchFace face;

  /// A round glass or dark background just behind the face, a little
  /// bigger than it; null for none.
  final ClockSurface? background;

  /// On the dark (or Material) background the see-through dials go a shade lighter so
  /// they still show.
  bool get dark =>
      background == ClockSurface.dark || background == ClockSurface.material || background == ClockSurface.materialDark;

  /// On the Material light background the see-through dials take dark ink.
  bool get onLight => background?.light ?? false;

  @override
  State<AnalogClock> createState() => _AnalogClockState();
}

class _AnalogClockState extends State<AnalogClock> with SingleTickerProviderStateMixin {
  late DateTime _now = DateTime.now();
  Timer? _timer;

  /// Each second's tick: the seconds hand springs from the last second to
  /// this one (a mechanical tick, not a 120 Hz sweep).
  late final _tick = AnimationController(vsync: this, duration: const Duration(milliseconds: 260), value: 1);

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  void _schedule() {
    final now = DateTime.now();
    _timer = Timer(Duration(milliseconds: 1000 - now.millisecond + 2), () {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
      _tick.forward(from: 0);
      _schedule();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _tick.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ClockBackground(style: widget.background, child: _face(context));

  Widget _face(BuildContext context) {
    final use24 = MediaQuery.alwaysUse24HourFormatOf(context);
    final face = widget.face;
    final ink = _inkOf(face, widget.onLight);
    // Dark ink: the time window goes near-black, as on the white dials.
    final inkDark = ink != Colors.white;
    return LayoutBuilder(
      builder: (context, box) {
        final d = math.min(box.maxWidth, box.maxHeight);
        final h = use24 ? _now.hour : (_now.hour % 12 == 0 ? 12 : _now.hour % 12);
        final time = '${use24 ? h.toString().padLeft(2, '0') : h}:${_now.minute.toString().padLeft(2, '0')}';
        final date = '${_days[_now.weekday - 1]} ${_now.day}';
        final text = TextStyle(
          fontFamily: 'ClockSpaceGrotesk',
          decoration: TextDecoration.none,
          fontFeatures: const [FontFeature.tabularFigures()],
          color: ink,
        );
        return Center(
          child: SizedBox.square(
            dimension: d,
            child: Stack(
              children: [
                // The dial changes once a second at most (Orbit's dots);
                // kept apart from the hands.
                Positioned.fill(
                  child: RepaintBoundary(
                    child: CustomPaint(
                      painter: _DialPainter(
                        face: face,
                        dark: widget.dark,
                        onLight: widget.onLight,
                        second: face == WatchFace.orbit ? _now.second : 0,
                      ),
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment(0, face == WatchFace.pilot ? -0.36 : -0.42),
                  child: Text(
                    date,
                    style: text.copyWith(
                      fontSize: d * 0.058,
                      fontWeight: FontWeight.w500,
                      letterSpacing: d * 0.008,
                      color: ink.withValues(alpha: 0.6),
                    ),
                  ),
                ),
                Align(
                  alignment: const Alignment(0, 0.42),
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: d * 0.042, vertical: d * 0.012),
                    decoration: BoxDecoration(
                      color: inkDark
                          ? Colors.black.withValues(alpha: 0.88)
                          : Colors.black.withValues(alpha: widget.dark ? 0.55 : 0.4),
                      borderRadius: BorderRadius.circular(d * 0.035),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: inkDark ? 0 : 0.14),
                        width: math.max(0.6, d * 0.004),
                      ),
                    ),
                    child: Text(
                      time,
                      style: text.copyWith(
                        fontSize: d * 0.08,
                        fontWeight: FontWeight.w600,
                        height: 1.1,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: AnimatedBuilder(
                    animation: _tick,
                    builder: (context, _) => CustomPaint(
                      painter: _HandsPainter(
                        face: face,
                        onLight: widget.onLight,
                        now: _now,
                        tick: Curves.easeOutBack.transform(_tick.value),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

const _days = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];

const _red = TileLook.alert;

Offset _dir(double turns) => Offset(math.sin(turns * 2 * math.pi), -math.cos(turns * 2 * math.pi));

void _text(
  Canvas canvas,
  String s,
  Offset at,
  double size,
  Color color, {
  String family = 'ClockSpaceGrotesk',
  FontWeight weight = FontWeight.w500,
  double rotate = 0,
}) {
  final tp = TextPainter(
    text: TextSpan(
      text: s,
      style: TextStyle(fontFamily: family, fontSize: size, fontWeight: weight, color: color, height: 1),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  canvas.save();
  canvas.translate(at.dx, at.dy);
  if (rotate != 0) canvas.rotate(rotate);
  tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
  canvas.restore();
}

/// Ticks from [inner] to [outer] (fractions of the radius) every 1/[count]
/// of a turn, skipping those [skip] says.
void _ticks(
  Canvas canvas,
  Offset c,
  double r, {
  required int count,
  required double inner,
  required double outer,
  required Paint paint,
  bool Function(int i)? skip,
}) {
  for (var i = 0; i < count; i++) {
    if (skip?.call(i) ?? false) continue;
    final dir = _dir(i / count);
    canvas.drawLine(c + dir * (r * inner), c + dir * (r * outer), paint);
  }
}

Paint _stroke(Color color, double width, {StrokeCap cap = StrokeCap.round}) => Paint()
  ..color = color
  ..strokeWidth = width
  ..strokeCap = cap
  ..style = PaintingStyle.stroke;

/// The face under the hands: its dial and markings.
class _DialPainter extends CustomPainter {
  const _DialPainter({required this.face, required this.dark, required this.onLight, required this.second});

  final WatchFace face;
  final bool dark;

  /// On a light background: the see-through dials' white goes dark ink.
  final bool onLight;

  /// Orbit's dots fill with the seconds; 0 for the others.
  final int second;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    final w = _inkOf(face, onLight);

    // A see-through dial (on the glass), or a solid one with a soft sheen.
    void seeThrough() {
      final fill = onLight ? Colors.black.withValues(alpha: 0.06) : TileLook.part(false, dark);
      canvas.drawCircle(c, r, Paint()..color = fill);
      canvas.drawCircle(c, r * 0.985, _stroke(w.withValues(alpha: 0.10), math.max(0.6, r * 0.012)));
    }

    void solid(Color base, Color sheen) {
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(-0.3, -0.4),
            radius: 1.1,
            colors: [sheen, base],
          ).createShader(Rect.fromCircle(center: c, radius: r)),
      );
    }

    switch (face) {
      case WatchFace.classic:
        seeThrough();
        _ticks(canvas, c, r, count: 60, inner: 0.86, outer: 0.9, paint: _stroke(w.withValues(alpha: 0.28), r * 0.012));
        for (var i = 0; i < 12; i++) {
          final dir = _dir(i / 12);
          canvas.drawLine(
            c + dir * (r * (i % 3 == 0 ? 0.74 : 0.79)),
            c + dir * (r * 0.9),
            _stroke(w.withValues(alpha: 0.9), r * 0.03),
          );
        }

      case WatchFace.railway:
        solid(const Color(0xFFF4F4F2), Colors.white);
        canvas.drawCircle(c, r * 0.985, _stroke(Colors.black.withValues(alpha: 0.12), r * 0.015));
        _ticks(
          canvas,
          c,
          r,
          count: 60,
          inner: 0.86,
          outer: 0.92,
          paint: _stroke(Colors.black, r * 0.018, cap: StrokeCap.butt),
          skip: (i) => i % 5 == 0,
        );
        _ticks(
          canvas,
          c,
          r,
          count: 12,
          inner: 0.7,
          outer: 0.92,
          paint: _stroke(Colors.black, r * 0.06, cap: StrokeCap.butt),
        );

      case WatchFace.diver:
        // A black minute bezel round a black dial.
        solid(const Color(0xFF0E0E10), const Color(0xFF26272B));
        canvas.drawCircle(c, r * 0.9, _stroke(const Color(0xFF050505), r * 0.2, cap: StrokeCap.butt));
        canvas.drawCircle(c, r * 0.8, _stroke(w.withValues(alpha: 0.18), r * 0.008));
        _ticks(
          canvas,
          c,
          r,
          count: 60,
          inner: 0.91,
          outer: 0.95,
          paint: _stroke(w.withValues(alpha: 0.7), r * 0.012),
          skip: (i) => i % 10 == 0 || i > 15,
        );
        for (var m = 10; m < 60; m += 10) {
          _text(
            canvas,
            '$m',
            c + _dir(m / 60) * (r * 0.9),
            r * 0.11,
            w,
            weight: FontWeight.w600,
            rotate: m / 60 * 2 * math.pi,
          );
        }
        // The bezel's triangle at 12, with a red pip.
        final tri = Path()
          ..moveTo(c.dx, c.dy - r * 0.84)
          ..lineTo(c.dx - r * 0.07, c.dy - r * 0.96)
          ..lineTo(c.dx + r * 0.07, c.dy - r * 0.96)
          ..close();
        canvas.drawPath(tri, Paint()..color = w);
        canvas.drawCircle(Offset(c.dx, c.dy - r * 0.92), r * 0.016, Paint()..color = _red);
        // Lume: dots for the hours, bars at 3 and 9, a triangle at 12.
        final lume = Paint()..color = const Color(0xFFF2F2EA);
        for (var i = 1; i < 12; i++) {
          final at = c + _dir(i / 12) * (r * 0.68);
          if (i % 3 == 0) {
            canvas.drawLine(
              c + _dir(i / 12) * (r * 0.6),
              c + _dir(i / 12) * (r * 0.74),
              _stroke(lume.color, r * 0.065, cap: StrokeCap.round),
            );
          } else {
            canvas.drawCircle(at, r * 0.045, lume);
          }
        }
        canvas.drawPath(
          Path()
            ..moveTo(c.dx, c.dy - r * 0.6)
            ..lineTo(c.dx - r * 0.07, c.dy - r * 0.75)
            ..lineTo(c.dx + r * 0.07, c.dy - r * 0.75)
            ..close(),
          lume,
        );

      case WatchFace.pilot:
        solid(const Color(0xFF111214), const Color(0xFF2A2B2F));
        _ticks(canvas, c, r, count: 60, inner: 0.88, outer: 0.94, paint: _stroke(w.withValues(alpha: 0.75), r * 0.012));
        // A triangle with two dots at 12.
        canvas.drawPath(
          Path()
            ..moveTo(c.dx, c.dy - r * 0.68)
            ..lineTo(c.dx - r * 0.09, c.dy - r * 0.88)
            ..lineTo(c.dx + r * 0.09, c.dy - r * 0.88)
            ..close(),
          Paint()..color = w,
        );
        canvas.drawCircle(Offset(c.dx - r * 0.17, c.dy - r * 0.86), r * 0.022, Paint()..color = w);
        canvas.drawCircle(Offset(c.dx + r * 0.17, c.dy - r * 0.86), r * 0.022, Paint()..color = w);
        for (var i = 1; i < 12; i++) {
          _text(
            canvas,
            '$i',
            c + _dir(i / 12) * (r * 0.72),
            r * 0.17,
            w,
            family: 'ClockOswald',
            weight: FontWeight.w500,
          );
        }

      case WatchFace.bauhaus:
        solid(const Color(0xFFEDEBE6), const Color(0xFFFAF9F6));
        _ticks(
          canvas,
          c,
          r,
          count: 60,
          inner: 0.9,
          outer: 0.94,
          paint: _stroke(Colors.black.withValues(alpha: 0.55), r * 0.008),
        );
        _ticks(canvas, c, r, count: 12, inner: 0.86, outer: 0.94, paint: _stroke(Colors.black, r * 0.014));
        for (var i = 1; i <= 12; i++) {
          _text(
            canvas,
            '$i',
            c + _dir(i / 12) * (r * 0.73),
            r * 0.12,
            Colors.black,
            family: 'ClockInter',
            weight: FontWeight.w300,
          );
        }

      case WatchFace.chrono:
        solid(const Color(0xFF0D0D0F), const Color(0xFF232428));
        // A seconds scale round the edge.
        _ticks(canvas, c, r, count: 60, inner: 0.9, outer: 0.95, paint: _stroke(w.withValues(alpha: 0.5), r * 0.01));
        _ticks(
          canvas,
          c,
          r,
          count: 240,
          inner: 0.93,
          outer: 0.95,
          paint: _stroke(w.withValues(alpha: 0.25), r * 0.005),
        );
        canvas.drawCircle(c, r * 0.86, _stroke(w.withValues(alpha: 0.15), r * 0.006));
        for (var i = 0; i < 12; i++) {
          final dir = _dir(i / 12);
          if (i == 3 || i == 9) continue;
          canvas.drawLine(c + dir * (r * 0.68), c + dir * (r * 0.82), _stroke(w, r * 0.035, cap: StrokeCap.butt));
        }
        // Sub-dials at 3 and 9: hands are drawn by the hands painter.
        for (final x in [-1.0, 1.0]) {
          final sc = c + Offset(x * r * 0.44, 0);
          canvas.drawCircle(sc, r * 0.2, Paint()..color = const Color(0xFF1C1D21));
          canvas.drawCircle(sc, r * 0.2, _stroke(w.withValues(alpha: 0.35), r * 0.008));
          _ticks(
            canvas,
            sc,
            r * 0.2,
            count: 12,
            inner: 0.78,
            outer: 0.95,
            paint: _stroke(w.withValues(alpha: 0.6), r * 0.008),
          );
        }

      case WatchFace.field:
        solid(const Color(0xFF121311), const Color(0xFF2A2C28));
        _ticks(canvas, c, r, count: 60, inner: 0.9, outer: 0.95, paint: _stroke(w.withValues(alpha: 0.6), r * 0.01));
        _ticks(canvas, c, r, count: 12, inner: 0.86, outer: 0.95, paint: _stroke(w, r * 0.025));
        for (var i = 1; i <= 12; i++) {
          _text(
            canvas,
            '$i',
            c + _dir(i / 12) * (r * 0.72),
            r * 0.15,
            w,
            family: 'ClockOswald',
            weight: FontWeight.w500,
          );
          if (i % 6 <= 1 || i % 6 == 5) continue; // clear of the date and the window
          _text(canvas, '${i + 12}', c + _dir(i / 12) * (r * 0.52), r * 0.075, _red.withValues(alpha: 0.9));
        }

      case WatchFace.orbit:
        seeThrough();
        // 60 dots: those passed this minute lit, this second's red.
        for (var i = 0; i < 60; i++) {
          final at = c + _dir(i / 60) * (r * 0.86);
          final Color color;
          if (i == second) {
            color = _red;
          } else if (i < second) {
            color = w.withValues(alpha: 0.9);
          } else {
            color = w.withValues(alpha: i % 5 == 0 ? 0.35 : 0.16);
          }
          canvas.drawCircle(at, r * (i % 5 == 0 ? 0.03 : 0.018), Paint()..color = color);
        }

      case WatchFace.minimal:
        seeThrough();
        _ticks(canvas, c, r, count: 4, inner: 0.78, outer: 0.88, paint: _stroke(w, r * 0.035));
    }
  }

  @override
  bool shouldRepaint(_DialPainter old) =>
      old.face != face || old.dark != dark || old.onLight != onLight || old.second != second;
}

/// The hands, drawn pointing up from the centre (negative y) and turned.
class _HandsPainter extends CustomPainter {
  const _HandsPainter({required this.face, required this.onLight, required this.now, required this.tick});

  final WatchFace face;

  /// On a light background (see [_DialPainter.onLight]).
  final bool onLight;
  final DateTime now;

  /// 0 → 1 through this second's tick (may overshoot a little).
  final double tick;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    final s = now.second;
    final m = now.minute + s / 60;
    final h = now.hour % 12 + m / 60;
    final sec = (s - 1 + tick) / 60;
    final ink = _inkOf(face, onLight);
    final shadow = Colors.black.withValues(alpha: ink != Colors.white ? 0.18 : 0.35);

    void turned(Offset at, double turns, void Function() draw) {
      canvas.save();
      canvas.translate(at.dx, at.dy);
      canvas.rotate(turns * 2 * math.pi);
      draw();
      canvas.restore();
    }

    void withShadow(Path path, Color color, {Offset? at, double turns = 0}) {
      final o = at ?? c;
      turned(o + Offset(0, r * 0.02), turns, () {
        canvas.drawPath(
          path,
          Paint()
            ..color = shadow
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.02),
        );
      });
      turned(o, turns, () => canvas.drawPath(path, Paint()..color = color));
    }

    Path stick(double len, double tail, double width) => Path()
      ..addRRect(
        RRect.fromRectAndRadius(Rect.fromLTRB(-width / 2, -len * r, width / 2, tail * r), Radius.circular(width / 2)),
      );

    Path block(double len, double tail, double base, double tip) => Path()
      ..moveTo(-base * r / 2, tail * r)
      ..lineTo(base * r / 2, tail * r)
      ..lineTo(tip * r / 2, -len * r)
      ..lineTo(-tip * r / 2, -len * r)
      ..close();

    Path sword(double len, double tail, double width) => Path()
      ..moveTo(0, -len * r)
      ..lineTo(width * r / 2, -len * r * 0.78)
      ..lineTo(width * r * 0.3, tail * r)
      ..lineTo(-width * r * 0.3, tail * r)
      ..lineTo(-width * r / 2, -len * r * 0.78)
      ..close();

    void needle(double len, double tail, double width, Color color, {double? lollipop, double at = 0.72}) {
      turned(c, sec, () {
        canvas.drawLine(Offset(0, tail * r), Offset(0, -len * r), _stroke(color, math.max(1, width * r)));
        if (lollipop != null) canvas.drawCircle(Offset(0, -len * r * at), lollipop * r, Paint()..color = color);
      });
    }

    void cap(Color outer, Color inner, {double size = 0.055}) {
      canvas.drawCircle(c, r * size, Paint()..color = outer);
      canvas.drawCircle(c, r * size * 0.45, Paint()..color = inner);
    }

    switch (face) {
      case WatchFace.classic:
        withShadow(stick(0.5, 0.08, math.max(3, r * 0.075)), ink, turns: h / 12);
        withShadow(stick(0.78, 0.08, math.max(2, r * 0.045)), ink, turns: m / 60);
        needle(0.86, 0.18, 0.016, _red);
        cap(_red, Colors.black);

      case WatchFace.railway:
        withShadow(block(0.56, 0.16, 0.1, 0.075), Colors.black, turns: h / 12);
        withShadow(block(0.86, 0.16, 0.08, 0.06), Colors.black, turns: m / 60);
        canvas.drawCircle(c, r * 0.05, Paint()..color = Colors.black);
        needle(0.62, 0.26, 0.022, _red, lollipop: 0.075, at: 1);
        canvas.drawCircle(c, r * 0.03, Paint()..color = _red);

      case WatchFace.diver:
        // Lume-filled swords with a dark spine.
        withShadow(sword(0.46, 0.1, 0.13), const Color(0xFFF2F2EA), turns: h / 12);
        withShadow(sword(0.7, 0.1, 0.1), const Color(0xFFF2F2EA), turns: m / 60);
        needle(0.78, 0.2, 0.018, _red, lollipop: 0.045, at: 0.78);
        cap(Colors.white, _red, size: 0.05);

      case WatchFace.pilot:
        withShadow(sword(0.48, 0.1, 0.1), ink, turns: h / 12);
        withShadow(sword(0.8, 0.1, 0.075), ink, turns: m / 60);
        needle(0.88, 0.2, 0.014, ink);
        cap(ink, Colors.black, size: 0.045);

      case WatchFace.bauhaus:
        withShadow(stick(0.5, 0.0, math.max(2, r * 0.035)), Colors.black, turns: h / 12);
        withShadow(stick(0.8, 0.0, math.max(1.5, r * 0.022)), Colors.black, turns: m / 60);
        needle(0.86, 0.16, 0.01, _red);
        cap(Colors.black, Colors.black, size: 0.035);

      case WatchFace.chrono:
        // Small hands first: running seconds at 9, a 24-hour hand at 3.
        final left = c + Offset(-r * 0.44, 0), right = c + Offset(r * 0.44, 0);
        turned(left, sec, () => canvas.drawLine(Offset.zero, Offset(0, -r * 0.17), _stroke(Colors.white, r * 0.014)));
        turned(right, (now.hour + m / 60) / 24, () {
          canvas.drawLine(Offset.zero, Offset(0, -r * 0.17), _stroke(_red, r * 0.014));
        });
        canvas.drawCircle(left, r * 0.022, Paint()..color = Colors.white);
        canvas.drawCircle(right, r * 0.022, Paint()..color = _red);
        withShadow(stick(0.5, 0.06, math.max(3, r * 0.06)), ink, turns: h / 12);
        withShadow(stick(0.82, 0.06, math.max(2, r * 0.04)), ink, turns: m / 60);
        needle(0.92, 0.22, 0.012, _red);
        cap(_red, Colors.black, size: 0.05);

      case WatchFace.field:
        withShadow(block(0.5, 0.08, 0.075, 0.05), ink, turns: h / 12);
        withShadow(block(0.8, 0.08, 0.06, 0.035), ink, turns: m / 60);
        needle(0.88, 0.2, 0.012, _red);
        cap(ink, Colors.black, size: 0.045);

      case WatchFace.orbit:
        // No seconds hand: the dots are the seconds.
        withShadow(stick(0.45, 0.0, math.max(3, r * 0.09)), ink, turns: h / 12);
        withShadow(stick(0.7, 0.0, math.max(2, r * 0.055)), ink.withValues(alpha: 0.85), turns: m / 60);
        cap(Colors.black, _red, size: 0.04);

      case WatchFace.minimal:
        withShadow(stick(0.48, 0.0, math.max(2, r * 0.045)), ink, turns: h / 12);
        withShadow(stick(0.76, 0.0, math.max(1.5, r * 0.028)), ink, turns: m / 60);
        needle(0.8, 0.0, 0.01, _red);
        canvas.drawCircle(c, r * 0.03, Paint()..color = ink);
    }
  }

  @override
  bool shouldRepaint(_HandsPainter old) =>
      old.now != now || old.tick != tick || old.face != face || old.onLight != onLight;
}

// ---- Shared with the futuristic clock --------------------------------------

/// A clock's background (settings['style']): a glass, dark or Material disc (or
/// rounded square, for a square face) just behind the face, a little bigger
/// than it; none ([style] null) leaves the face on the wallpaper.
class ClockBackground extends StatelessWidget {
  const ClockBackground({super.key, required this.style, required this.child, this.round = true});

  final ClockSurface? style;
  final bool round;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final style = this.style;
    if (style == null) return child;
    return LayoutBuilder(
      builder: (context, box) {
        final d = math.min(box.maxWidth, box.maxHeight);
        final inner = Padding(padding: EdgeInsets.all(d * 0.055), child: child);
        if (style == ClockSurface.material) {
          return Center(
            child: SizedBox.square(
              dimension: d,
              child: _MaterialDisc(round: round, size: d, child: inner),
            ),
          );
        }
        final decoration = AppContainerTile.decoration(
          d * 0.24,
          switch (style) {
            ClockSurface.glass => GroupStyle.glass,
            ClockSurface.materialDark => GroupStyle.material,
            ClockSurface.materialLight => GroupStyle.materialLight,
            _ => GroupStyle.dark,
          },
          null,
          round ? FolderShape.circle : FolderShape.rounded,
        );
        Widget disc = DecoratedBox(decoration: decoration, child: inner);
        if (style == ClockSurface.glass) disc = WallpaperGlass(shape: decoration.shape, child: disc);
        return Center(
          child: SizedBox.square(dimension: d, child: disc),
        );
      },
    );
  }
}

/// Material 3's tonal look: the wallpaper's main colour (else a slate
/// blue) as a dark scheme's primary container, a lighter rim, and a soft
/// shadow under it.
class _MaterialDisc extends StatelessWidget {
  const _MaterialDisc({required this.round, required this.size, required this.child});

  static const _fallback = Color(0xFF5B7083);

  final bool round;
  final double size;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final wallpaper = context.select<WindowBlurPlatform?, dynamic>((p) => p?.wallpaper);
    return FutureBuilder<List<Color>?>(
      future: wallpaper == null ? null : wallpaperColors(wallpaper),
      builder: (context, snapshot) {
        final seed = snapshot.data?.firstOrNull ?? _fallback;
        final scheme = ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark);
        final shape = round
            ? CircleBorder(
                side: BorderSide(color: scheme.primary.withValues(alpha: 0.35), width: size * 0.012),
              )
            : RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(size * 0.24),
                side: BorderSide(color: scheme.primary.withValues(alpha: 0.35), width: size * 0.012),
              );
        return AnimatedContainer(
          duration: const Duration(milliseconds: 400),
          decoration: ShapeDecoration(
            shape: shape,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color.lerp(scheme.primaryContainer, scheme.primary, 0.18)!, scheme.primaryContainer],
            ),
            shadows: const [BoxShadow(color: Color(0x55000000), blurRadius: 16, offset: Offset(0, 6))],
          ),
          child: child,
        );
      },
    );
  }
}

/// Glass / Dark / Material You / Material dark / Material light / None, for
/// [ClockBackground]: chips, wrapping (too many for one line).
class ClockBackgroundPicker extends StatelessWidget {
  const ClockBackgroundPicker({super.key, required this.selected, required this.onChanged});

  final String selected;
  final ValueChanged<String> onChanged;

  /// (stored value, icon, label), in order.
  static const _options = [
    ('glass', Icons.blur_on, 'Glass'),
    ('dark', Icons.dark_mode_outlined, 'Dark'),
    ('material', Icons.palette_outlined, 'Material You'),
    ('materialDark', Icons.layers_outlined, 'Material dark'),
    ('materialLight', Icons.layers, 'Material light'),
    (clockNoBackground, Icons.hide_source_outlined, 'None'),
  ];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final (value, icon, label) in _options)
          ChoiceChip(
            avatar: Icon(icon, size: 18),
            label: Text(label),
            showCheckmark: false,
            selected: selected == value,
            onSelected: (_) => onChanged(value),
          ),
      ],
    );
  }
}

/// Opens the phone's clock app when tapped.
Widget opensClockApp(BuildContext context, Widget child) => Semantics(
  button: true,
  hint: 'Opens the clock app',
  child: GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: () => context.read<LauncherPlatform?>()?.openClock(),
    child: child,
  ),
);

// ---- Settings --------------------------------------------------------------

/// Its options: the face, and the panel (glass, dark or none).
Future<void> showAnalogClockSettings(BuildContext context, WidgetItem item) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  barrierColor: Colors.black26,
  builder: (_) => _AnalogClockSettingsSheet(id: item.id),
);

class _AnalogClockSettingsSheet extends StatelessWidget {
  const _AnalogClockSettingsSheet({required this.id});

  final String id;

  @override
  Widget build(BuildContext context) {
    final layout = context.watch<HomeLayoutController>();
    final item = layout.findWidget(id);
    if (item == null) return const SizedBox.shrink();
    final face = _faceOf(item.settings);
    final background = clockBackgroundOf(item.settings);
    final style = background?.name ?? clockNoBackground;
    void set(String key, Object value) => layout.updateWidgetSettings(id, {...item.settings, key: value});
    final theme = Theme.of(context);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Face', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, box) {
                const columns = 3, spacing = 12.0;
                final tile = (box.maxWidth - spacing * (columns - 1)) / columns;
                return Wrap(
                  spacing: spacing,
                  runSpacing: spacing,
                  children: [
                    for (final f in WatchFace.values)
                      _FaceTile(
                        face: f,
                        background: background,
                        size: tile,
                        selected: f == face,
                        onTap: () => set('face', f.name),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 24),
            Text('Background', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            ClockBackgroundPicker(selected: style, onChanged: (v) => set('style', v)),
          ],
        ),
      ),
    );
  }
}

class _FaceTile extends StatelessWidget {
  const _FaceTile({
    required this.face,
    required this.background,
    required this.size,
    required this.selected,
    required this.onTap,
  });

  final WatchFace face;
  final ClockSurface? background;
  final double size;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: face.label,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: size,
          child: Column(
            children: [
              AnimatedContainer(
                duration: TileLook.motion,
                width: size,
                height: size,
                padding: EdgeInsets.all(size * 0.07),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(size * 0.2),
                  border: Border.all(
                    color: selected ? Colors.white : Colors.white.withValues(alpha: 0.08),
                    width: selected ? 2 : 1,
                  ),
                ),
                child: AnalogClock(face: face, background: background),
              ),
              const SizedBox(height: 6),
              Text(face.label, style: TextStyle(fontSize: 12, color: selected ? Colors.white : Colors.white60)),
            ],
          ),
        ),
      ),
    );
  }
}
