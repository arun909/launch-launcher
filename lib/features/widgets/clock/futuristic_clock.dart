import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/platform/window_blur_platform.dart';
import '../../standard_home/home_layout.dart';
import '../../standard_home/home_layout_controller.dart';
import '../controls/tile_look.dart';
import '../launcher_widgets.dart';
import 'analog_clock.dart';
import 'wallpaper_colors.dart';

/// The futuristic clock: sci-fi faces (a HUD, a radar, lit rings, orbits,
/// binary, a dot matrix) in white with one glowing accent colour. The same
/// backgrounds as the analog clock (a round or rounded-square glass or dark
/// one behind the face, or none), and a tap opens the clock app.
const futuristicClockKind = LauncherWidgetKind(
  name: 'futuristic_clock',
  label: 'Futuristic clock',
  description: 'Eleven sci-fi faces: HUD, radar, reactor, terminal and more',
  icon: Icons.radar_rounded,
  group: 'Clocks',
  size: (2, 2),
  min: (2, 2),
  // Any span, so it can be centred on any grid (2 × 2 or 4 × 4 can't be on
  // 5 columns); the face stays round, centred in its frame.
  max: (6, 4),
  build: _build,
  customise: showFuturisticClockSettings,
  panelOf: clockNeverPanel,
  interactive: true,
);

Widget _build(BuildContext context, Map<String, dynamic> settings) => opensClockApp(
  context,
  _WithAccent(
    settings: settings,
    builder: (accent) =>
        FuturisticClock(face: _faceOf(settings), accent: accent, background: clockBackgroundOf(settings)),
  ),
);

enum FutureFace {
  hud('HUD'),
  radar('Radar'),
  rings('Rings'),
  orbital('Orbital'),
  binary('Binary'),
  matrix('Matrix'),
  pulse('Pulse'),
  hex('Hex'),
  gauge('Gauge'),
  terminal('Terminal'),
  reactor('Reactor');

  const FutureFace(this.label);

  final String label;

  /// Drawn in a circle (else a square).
  bool get round => this != binary && this != matrix && this != pulse && this != terminal;
}

/// The glow colours it comes in: saturated neons, so they punch.
const _accents = <String, Color>{
  'white': Color(0xFFFFFFFF),
  'red': Color(0xFFFF2B4A),
  'cyan': Color(0xFF00E5FF),
  'amber': Color(0xFFFFA800),
};

FutureFace _faceOf(Map<String, dynamic> s) => FutureFace.values.asNameMap()[s['face']] ?? FutureFace.hud;

Color _accentOf(Map<String, dynamic> s) => _accents[s['accent']] ?? _accents['cyan']!;

/// The glow taken from the wallpaper (settings['accent'] == 'wallpaper').
const _wallpaperAccent = 'wallpaper';

bool _fromWallpaper(Map<String, dynamic> s) => s['accent'] == _wallpaperAccent;

/// The wallpaper's main colour as a neon: fully saturated and lit, so it
/// punches like the fixed glows rather than looking faded.
Color _neon(Color c) {
  final hsv = HSVColor.fromColor(c);
  return hsv.withSaturation(math.max(hsv.saturation, 0.8)).withValue(1).toColor();
}

/// Builds with the glow colour: the chosen neon, or the wallpaper's main
/// colour as one (cyan while it's unknown or colourless). Follows the
/// wallpaper when it changes; worked out once per wallpaper and shared.
class _WithAccent extends StatelessWidget {
  const _WithAccent({required this.settings, required this.builder});

  final Map<String, dynamic> settings;
  final Widget Function(Color accent) builder;

  @override
  Widget build(BuildContext context) {
    if (!_fromWallpaper(settings)) return builder(_accentOf(settings));
    final image = context.select<WindowBlurPlatform?, ui.Image?>((p) => p?.wallpaper);
    if (image == null) return builder(_accentOf(settings));
    return FutureBuilder<List<Color>?>(
      future: wallpaperColors(image),
      builder: (context, snap) {
        final colors = snap.data;
        return builder(colors == null || colors.isEmpty ? _accentOf(settings) : _neon(colors.first));
      },
    );
  }
}

class FuturisticClock extends StatefulWidget {
  const FuturisticClock({
    super.key,
    this.face = FutureFace.hud,
    this.accent = const Color(0xFF00E5FF),
    this.background,
  });

  final FutureFace face;
  final Color accent;
  final ClockSurface? background;

  @override
  State<FuturisticClock> createState() => _FuturisticClockState();
}

class _FuturisticClockState extends State<FuturisticClock> with SingleTickerProviderStateMixin {
  late DateTime _now = DateTime.now();
  Timer? _timer;

  /// Eases each second's step (the sweep, the arcs), rather than redrawing
  /// at 120 Hz all the time.
  late final _tick = AnimationController(vsync: this, duration: const Duration(milliseconds: 380), value: 1);

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
  Widget build(BuildContext context) {
    final use24 = MediaQuery.alwaysUse24HourFormatOf(context);
    // On the Material light background: dark ink, and the white glow too.
    final light = widget.background?.light ?? false;
    final accent = light && widget.accent == _accents['white'] ? GroupStyle.materialLight.ink : widget.accent;
    return ClockBackground(
      style: widget.background,
      round: widget.face.round,
      // Square and centred in a frame of any shape.
      child: Center(
        child: AspectRatio(
          aspectRatio: 1,
          child: AnimatedBuilder(
            animation: _tick,
            builder: (context, _) => CustomPaint(
              painter: _FuturePainter(
                face: widget.face,
                accent: accent,
                light: light,
                now: _now,
                tick: Curves.easeOutCubic.transform(_tick.value),
                use24: use24,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

const _days = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];

String _two(int n) => n.toString().padLeft(2, '0');

Offset _dir(double turns) => Offset(math.sin(turns * 2 * math.pi), -math.cos(turns * 2 * math.pi));

class _FuturePainter extends CustomPainter {
  _FuturePainter({
    required this.face,
    required this.accent,
    required this.light,
    required this.now,
    required this.tick,
    required this.use24,
  });

  final FutureFace face;
  final Color accent;

  /// On a light background: drawn in dark ink rather than white.
  final bool light;
  final DateTime now;

  /// 0 → 1 through this second's step.
  final double tick;
  final bool use24;

  late Canvas _canvas;
  late Offset c;
  late double r;

  /// What's otherwise white: the ink.
  Color get _white => light ? GroupStyle.materialLight.ink : Colors.white;

  /// The dark wells under readouts: light ones on a light background.
  Color get _shade => light ? Colors.white : Colors.black;

  int get _hour12 => now.hour % 12 == 0 ? 12 : now.hour % 12;
  String get _hh => use24 ? _two(now.hour) : '$_hour12';
  String get _time => '$_hh:${_two(now.minute)}';
  String get _date => '${_days[now.weekday - 1]} ${_two(now.day)}';

  /// Seconds into this minute, easing from the last second to this one.
  double get _sec => now.second - 1 + tick;

  Paint _stroke(Color color, double width, {StrokeCap cap = StrokeCap.round}) => Paint()
    ..color = color
    ..strokeWidth = width
    ..strokeCap = cap
    ..style = PaintingStyle.stroke;

  /// The accent at [alpha], lifted half again: its tints stay vivid
  /// rather than fading into the background.
  Color _tint(double alpha) => accent.withValues(alpha: math.min(1.0, alpha * 1.5));

  /// [paint] as it is: crisp and flat, like a lit display, with no glow
  /// around it ([spread] kept for the callers).
  void _glow(void Function(Paint p) draw, Paint paint, {double spread = 1}) => draw(paint);

  void _arc(double radius, double from, double sweep, Paint paint, {bool glow = false}) {
    void draw(Paint p) => _canvas.drawArc(
      Rect.fromCircle(center: c, radius: radius),
      -math.pi / 2 + from * 2 * math.pi,
      sweep * 2 * math.pi,
      false,
      p,
    );
    glow ? _glow(draw, paint) : draw(paint);
  }

  void _dot(Offset at, double radius, Color color, {bool glow = false}) {
    final p = Paint()..color = color;
    void draw(Paint p) => _canvas.drawCircle(at, radius, p..style = PaintingStyle.fill);
    glow ? _glow(draw, p, spread: 1.4) : draw(p);
  }

  void _text(
    String s,
    Offset at,
    double size,
    Color color, {
    String family = 'ClockSpaceGrotesk',
    FontWeight weight = FontWeight.w500,
    double spacing = 0,
    bool glow = false,
  }) {
    TextPainter painter(List<Shadow>? shadows) => TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(
          fontFamily: family,
          fontSize: size,
          fontWeight: weight,
          color: color,
          letterSpacing: spacing,
          height: 1,
          shadows: shadows,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    // Crisp, no glow (see _glow).
    final tp = painter(null);
    tp.paint(_canvas, at - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  void paint(Canvas canvas, Size size) {
    _canvas = canvas;
    c = size.center(Offset.zero);
    r = size.shortestSide / 2;
    switch (face) {
      case FutureFace.hud:
        _hud();
      case FutureFace.radar:
        _radar();
      case FutureFace.rings:
        _rings();
      case FutureFace.orbital:
        _orbital();
      case FutureFace.binary:
        _binary();
      case FutureFace.matrix:
        _matrix();
      case FutureFace.pulse:
        _pulse();
      case FutureFace.hex:
        _hex();
      case FutureFace.gauge:
        _gauge();
      case FutureFace.terminal:
        _terminal();
      case FutureFace.reactor:
        _reactor();
    }
  }

  /// Thin progress arcs for seconds, minutes and hours round a readout,
  /// with corner brackets.
  void _hud() {
    final dim = _white.withValues(alpha: 0.1);
    // Seconds: a fine scale and an arc.
    for (var i = 0; i < 60; i++) {
      final d = _dir(i / 60);
      final long = i % 5 == 0;
      _canvas.drawLine(
        c + d * (r * (long ? 0.86 : 0.89)),
        c + d * (r * 0.93),
        _stroke(_white.withValues(alpha: long ? 0.45 : 0.18), r * (long ? 0.014 : 0.008)),
      );
    }
    _arc(r * 0.97, 0, 1, _stroke(dim, r * 0.012));
    _arc(r * 0.97, 0, _sec / 60, _stroke(accent, r * 0.022), glow: true);
    _dot(c + _dir(_sec / 60) * (r * 0.97), r * 0.03, accent, glow: true);
    // Minutes.
    final m = now.minute + now.second / 60;
    _arc(r * 0.76, 0, 1, _stroke(dim, r * 0.05, cap: StrokeCap.butt));
    _arc(r * 0.76, 0, m / 60, _stroke(_white.withValues(alpha: 0.9), r * 0.05, cap: StrokeCap.butt), glow: true);
    // Hours: twelve segments.
    final h = now.hour % 12 + m / 60;
    for (var i = 0; i < 12; i++) {
      final lit = i < h.floor() ? 1.0 : (i == h.floor() ? 0.5 : 0.0);
      _arc(
        r * 0.65,
        i / 12 + 0.006,
        1 / 12 - 0.012,
        _stroke(lit > 0 ? _tint(0.4 + 0.5 * lit) : dim, r * 0.03, cap: StrokeCap.butt),
        glow: lit == 1,
      );
    }
    // Readout.
    _text(_date, c + Offset(0, -r * 0.3), r * 0.1, _white.withValues(alpha: 0.55), spacing: r * 0.02);
    _text(_time, c + Offset(0, r * 0.02), r * 0.32, _white, weight: FontWeight.w400, glow: true);
    _text(
      'SEC ${_two(now.second)}',
      c + Offset(0, r * 0.32),
      r * 0.09,
      accent,
      spacing: r * 0.02,
      family: 'ClockSpaceGrotesk',
    );
    // Brackets on the diagonals.
    for (var i = 0; i < 4; i++) {
      _arc(r * 1.0, i / 4 + 0.105, 0.04, _stroke(_white.withValues(alpha: 0.5), r * 0.012, cap: StrokeCap.butt));
    }
  }

  /// A sweep going round once a minute, leaving a fading trail, over a
  /// grid; the hour and minute are blips that flare as it passes.
  void _radar() {
    final grid = _stroke(_tint(0.16), r * 0.008);
    for (final f in [0.32, 0.6, 0.88]) {
      _canvas.drawCircle(c, r * f, grid);
    }
    _canvas.drawLine(c + Offset(-r * 0.92, 0), c + Offset(r * 0.92, 0), grid);
    _canvas.drawLine(c + Offset(0, -r * 0.92), c + Offset(0, r * 0.92), grid);
    for (var i = 0; i < 72; i++) {
      final d = _dir(i / 72);
      _canvas.drawLine(
        c + d * (r * (i % 6 == 0 ? 0.9 : 0.94)),
        c + d * (r * 0.97),
        _stroke(_tint(i % 6 == 0 ? 0.6 : 0.25), r * 0.01),
      );
    }

    final sweep = _sec / 60;
    final a = -math.pi / 2 + sweep * 2 * math.pi;
    // Trail: a wedge behind the line, fading out over a sixth of a turn.
    final trail = math.pi / 3;
    _canvas.save();
    _canvas.translate(c.dx, c.dy);
    _canvas.rotate(a - trail);
    _canvas.drawArc(
      Rect.fromCircle(center: Offset.zero, radius: r * 0.88),
      0,
      trail,
      true,
      Paint()
        ..shader = SweepGradient(
          endAngle: trail,
          colors: [_tint(0), _tint(0.38)],
        ).createShader(Rect.fromCircle(center: Offset.zero, radius: r * 0.88)),
    );
    _canvas.restore();
    _glow((p) => _canvas.drawLine(c, c + _dir(sweep) * (r * 0.88), p), _stroke(accent, r * 0.016));

    // Blips: bright just after the sweep passes, then fading.
    void blip(double turns, double radius, double size) {
      final since = (sweep - turns) % 1;
      final alpha = (1 - since * 1.4).clamp(0.25, 1.0);
      _dot(c + _dir(turns) * (r * radius), r * size, _white.withValues(alpha: alpha), glow: alpha > 0.5);
      _canvas.drawCircle(
        c + _dir(turns) * (r * radius),
        r * size * 2.2,
        _stroke(_white.withValues(alpha: alpha * 0.35), r * 0.006),
      );
    }

    final m = now.minute + now.second / 60;
    blip((now.hour % 12 + m / 60) / 12, 0.45, 0.055);
    blip(m / 60, 0.74, 0.04);
    _dot(c, r * 0.03, accent, glow: true);

    _text('$_time:${_two(now.second)}', c + Offset(0, r * 0.6), r * 0.13, _white, weight: FontWeight.w600, glow: true);
    _text(_date, c + Offset(0, -r * 0.6), r * 0.085, _tint(0.85), spacing: r * 0.02);
  }

  /// Three chunky segmented rings lighting up: seconds, minutes, hours;
  /// hours and minutes stacked in the middle.
  void _rings() {
    void ring(double radius, int count, double lit, double width, Color on) {
      final gap = 0.35 / count;
      for (var i = 0; i < count; i++) {
        final full = i < lit.floor();
        final partial = i == lit.floor() ? lit - lit.floor() : 0.0;
        final color = full
            ? on
            : partial > 0
            ? on.withValues(alpha: 0.25 + 0.6 * partial)
            : _white.withValues(alpha: 0.07);
        _arc(
          radius,
          i / count + gap / 2,
          1 / count - gap,
          _stroke(color, width, cap: StrokeCap.butt),
          glow: full && i == lit.floor() - 1,
        );
      }
    }

    final m = now.minute + now.second / 60;
    ring(r * 0.92, 60, _sec + 1, r * 0.07, accent);
    ring(r * 0.78, 60, m, r * 0.07, _white.withValues(alpha: 0.9));
    ring(r * 0.64, 12, now.hour % 12 + m / 60, r * 0.07, _white.withValues(alpha: 0.6));

    _text(_hh.padLeft(2, '0'), c + Offset(0, -r * 0.17), r * 0.34, _white, weight: FontWeight.w700, glow: true);
    _text(_two(now.minute), c + Offset(0, r * 0.17), r * 0.34, accent, weight: FontWeight.w700, glow: true);
  }

  /// Orbits: the hour, minute and second as bodies going round a core,
  /// the second leaving a short trail.
  void _orbital() {
    final orbit = _stroke(_white.withValues(alpha: 0.14), r * 0.008);
    for (final f in [0.42, 0.64, 0.88]) {
      _canvas.drawCircle(c, r * f, orbit);
    }
    // Dashes on the outer orbit.
    for (var i = 0; i < 12; i++) {
      final d = _dir(i / 12);
      _canvas.drawLine(c + d * (r * 0.85), c + d * (r * 0.91), _stroke(_white.withValues(alpha: 0.4), r * 0.012));
    }
    final m = now.minute + now.second / 60;
    final h = now.hour % 12 + m / 60;
    final s = _sec / 60;
    _arc(r * 0.88, s - 0.12, 0.12, _stroke(_tint(0.5), r * 0.02));
    _dot(c + _dir(s) * (r * 0.88), r * 0.045, accent, glow: true);
    _dot(c + _dir(m / 60) * (r * 0.64), r * 0.06, _white.withValues(alpha: 0.9), glow: true);
    _dot(c + _dir(h / 12) * (r * 0.42), r * 0.08, _white, glow: true);
    // The core and the time on it.
    _dot(c, r * 0.25, _shade.withValues(alpha: 0.35));
    _canvas.drawCircle(c, r * 0.25, _stroke(_tint(0.5), r * 0.01));
    _text(_time, c, r * 0.15, _white, weight: FontWeight.w600, glow: true);
  }

  /// Each digit of the time as a column of four lit / unlit dots (8 4 2 1),
  /// the seconds' columns in the accent; the time above.
  void _binary() {
    final digits = [..._two(now.hour).split(''), ..._two(now.minute).split(''), ..._two(now.second).split('')];
    final cols = digits.length;
    final cell = r * 0.25;
    final gapExtra = r * 0.08; // between the pairs
    final width = cell * (cols - 1) + gapExtra * 2;
    final top = c.dy - r * 0.12;
    for (var col = 0; col < cols; col++) {
      final v = int.parse(digits[col]);
      final x = c.dx - width / 2 + col * cell + (col ~/ 2) * gapExtra;
      final isSec = col >= 4;
      for (var bit = 0; bit < 4; bit++) {
        final on = (v >> (3 - bit)) & 1 == 1;
        final at = Offset(x, top + bit * cell * 0.82);
        if (on) {
          _dot(at, r * 0.075, isSec ? accent : _white, glow: true);
        } else {
          _canvas.drawCircle(at, r * 0.075, _stroke(_white.withValues(alpha: 0.18), r * 0.012));
        }
      }
    }
    for (final (i, label) in ['H', 'M', 'S'].indexed) {
      final x = c.dx - width / 2 + (i * 2 + 0.5) * cell + i * gapExtra;
      _text(label, Offset(x, top + cell * 0.82 * 3 + r * 0.22), r * 0.09, _white.withValues(alpha: 0.5), spacing: 0);
    }
    _text(
      '$_time:${_two(now.second)}',
      c + Offset(0, -r * 0.55),
      r * 0.17,
      _white,
      weight: FontWeight.w600,
      glow: true,
    );
    _text(_date, c + Offset(0, -r * 0.8), r * 0.08, accent, spacing: r * 0.02);
  }

  /// A dot-matrix display: a faint grid of dots, the hours over the minutes
  /// in big dot digits, and the seconds as a row of dots filling up.
  void _matrix() {
    final grid = Paint()..color = _white.withValues(alpha: 0.06);
    final step = r * 0.08;
    for (var y = c.dy - r + step / 2; y < c.dy + r; y += step) {
      for (var x = c.dx - r + step / 2; x < c.dx + r; x += step) {
        _canvas.drawCircle(Offset(x, y), r * 0.012, grid);
      }
    }
    _text(
      _date,
      c + Offset(0, -r * 0.78),
      r * 0.11,
      accent,
      family: 'ClockDoto',
      weight: FontWeight.w800,
      spacing: r * 0.02,
    );
    _text(
      _hh.padLeft(2, '0'),
      c + Offset(0, -r * 0.33),
      r * 0.52,
      _white,
      family: 'ClockDoto',
      weight: FontWeight.w900,
      glow: true,
    );
    _text(
      _two(now.minute),
      c + Offset(0, r * 0.25),
      r * 0.52,
      _white,
      family: 'ClockDoto',
      weight: FontWeight.w900,
      glow: true,
    );
    // Seconds: twelve dots, one per five seconds, the current one pulsing.
    const n = 12;
    final y = c.dy + r * 0.78;
    final span = r * 1.5;
    final lit = now.second / 5;
    for (var i = 0; i < n; i++) {
      final x = c.dx - span / 2 + i * span / (n - 1);
      if (i < lit.floor()) {
        _dot(Offset(x, y), r * 0.035, accent, glow: true);
      } else if (i == lit.floor()) {
        _dot(Offset(x, y), r * 0.035, _tint(0.3 + 0.7 * (1 - tick)));
      } else {
        _dot(Offset(x, y), r * 0.025, _white.withValues(alpha: 0.15));
      }
    }
  }

  /// A heartbeat trace across the face, beating once a second (the beat
  /// sweeps left to right), the time big above it.
  void _pulse() {
    final left = c.dx - r * 0.9, right = c.dx + r * 0.9, base = c.dy + r * 0.32;
    final grid = _stroke(_tint(0.1), r * 0.006);
    for (var i = 0; i <= 8; i++) {
      final x = left + i * (right - left) / 8;
      _canvas.drawLine(Offset(x, base - r * 0.3), Offset(x, base + r * 0.3), grid);
    }
    for (final dy in [-0.3, 0.0, 0.3]) {
      _canvas.drawLine(Offset(left, base + r * dy), Offset(right, base + r * dy), grid);
    }
    // One beat (P, QRS, T) over the trace's width, the head at [tick].
    double wave(double t) {
      double bump(double at, double w, double h) => h * math.exp(-math.pow((t - at) / w, 2));
      return bump(0.22, 0.03, -0.08) +
          bump(0.36, 0.012, 0.12) +
          bump(0.4, 0.014, -0.95) +
          bump(0.44, 0.012, 0.38) +
          bump(0.64, 0.05, -0.2);
    }

    final head = tick;
    final path = Path();
    const n = 120;
    for (var i = 0; i <= n; i++) {
      final t = i / n;
      final at = Offset(left + t * (right - left), base + wave(t) * r * 0.3);
      i == 0 ? path.moveTo(at.dx, at.dy) : path.lineTo(at.dx, at.dy);
    }
    // Drawn up to the head; what's behind it fades, like a monitor's trace.
    _canvas.save();
    _canvas.clipRect(Rect.fromLTRB(left, base - r * 0.4, left + head * (right - left), base + r * 0.4));
    final shader = LinearGradient(colors: [_tint(0.1), accent])
        .createShader(Rect.fromLTRB(left, 0, left + math.max(1, head * (right - left)), 1));
    _glow((p) => _canvas.drawPath(path, p), _stroke(accent, r * 0.018)..shader = shader);
    _canvas.restore();
    _dot(Offset(left + head * (right - left), base + wave(head) * r * 0.3), r * 0.03, _white, glow: true);

    _text(_date, c + Offset(0, -r * 0.72), r * 0.09, accent, spacing: r * 0.02);
    _text(_time, c + Offset(0, -r * 0.36), r * 0.4, _white, weight: FontWeight.w300, glow: true);
    _text(
      '${_two(now.second)} BPS',
      c + Offset(0, r * 0.78),
      r * 0.08,
      _white.withValues(alpha: 0.5),
      spacing: r * 0.02,
    );
  }

  /// A ring of twelve honeycomb cells for the hours (those passed lit, this
  /// hour's filling with the minutes), the seconds round the edge.
  void _hex() {
    Path hexagon(Offset at, double size) {
      final p = Path();
      for (var i = 0; i < 6; i++) {
        final a = math.pi / 6 + i * math.pi / 3;
        final v = at + Offset(math.cos(a), math.sin(a)) * size;
        i == 0 ? p.moveTo(v.dx, v.dy) : p.lineTo(v.dx, v.dy);
      }
      return p..close();
    }

    final m = now.minute + now.second / 60;
    final hour = now.hour % 12;
    for (var i = 0; i < 12; i++) {
      final at = c + _dir(i / 12) * (r * 0.68);
      final cell = hexagon(at, r * 0.15);
      if (i < hour) {
        _glow((p) => _canvas.drawPath(cell, p), Paint()..color = _white.withValues(alpha: 0.85));
      } else if (i == hour) {
        // Filling from the bottom with the minutes.
        _canvas.drawPath(cell, Paint()..color = _tint(0.15));
        _canvas.save();
        _canvas.clipPath(cell);
        final fill = m / 60;
        _canvas.drawRect(
          Rect.fromLTRB(at.dx - r * 0.2, at.dy + r * 0.15 - fill * r * 0.3, at.dx + r * 0.2, at.dy + r * 0.2),
          Paint()..color = accent,
        );
        _canvas.restore();
        _glow((p) => _canvas.drawPath(cell, p), _stroke(accent, r * 0.014));
      } else {
        _canvas.drawPath(cell, _stroke(_white.withValues(alpha: 0.2), r * 0.01));
      }
    }
    // Seconds: dashes round the edge.
    for (var i = 0; i < 60; i++) {
      final d = _dir(i / 60);
      final on = i <= now.second;
      _canvas.drawLine(
        c + d * (r * 0.9),
        c + d * (r * 0.97),
        _stroke(on ? _tint(i == now.second ? 1 : 0.6) : _white.withValues(alpha: 0.1), r * 0.018),
      );
    }
    final core = hexagon(c, r * 0.36);
    _canvas.drawPath(core, Paint()..color = _shade.withValues(alpha: 0.35));
    _canvas.drawPath(core, _stroke(_white.withValues(alpha: 0.35), r * 0.01));
    _text(_time, c + Offset(0, -r * 0.02), r * 0.2, _white, weight: FontWeight.w600, glow: true);
    _text(_date, c + Offset(0, r * 0.18), r * 0.07, accent, spacing: r * 0.015);
  }

  /// A car cluster's gauge: a 270° arc of the seconds with a needle and a
  /// lit band, the time in the middle and the minutes as a bar under it.
  void _gauge() {
    const start = -0.375, span = 0.75; // in turns, from 7:30 round to 4:30
    final s = _sec / 60;
    _arc(r * 0.88, start, span, _stroke(_white.withValues(alpha: 0.08), r * 0.09, cap: StrokeCap.butt));
    // The lit band, brightening towards the needle.
    final rect = Rect.fromCircle(center: c, radius: r * 0.88);
    _canvas.drawArc(
      rect,
      -math.pi / 2 + start * 2 * math.pi,
      span * s * 2 * math.pi,
      false,
      // Solid, as a lit segment is.
      _stroke(accent, r * 0.09, cap: StrokeCap.butt),
    );
    // Scale: 0–60 every 10, ticks every 2.
    for (var i = 0; i <= 30; i++) {
      final t = start + span * i / 30;
      final major = i % 5 == 0;
      final d = _dir(t);
      _canvas.drawLine(
        c + d * (r * (major ? 0.7 : 0.75)),
        c + d * (r * 0.79),
        _stroke(_white.withValues(alpha: major ? 0.85 : 0.35), r * (major ? 0.02 : 0.01)),
      );
      if (major) _text('${i * 2}', c + d * (r * 0.58), r * 0.08, _white.withValues(alpha: 0.6));
    }
    // The needle.
    final nd = _dir(start + span * s);
    _glow((p) => _canvas.drawLine(c + nd * (r * 0.2), c + nd * (r * 0.92), p), _stroke(TileLook.alert, r * 0.02));
    _dot(c, r * 0.05, Colors.black);
    _canvas.drawCircle(c, r * 0.05, _stroke(TileLook.alert, r * 0.012));
    // Readout under the hub.
    _text(_time, c + Offset(0, r * 0.38), r * 0.22, _white, weight: FontWeight.w600, glow: true);
    final barW = r * 0.5, y = c.dy + r * 0.58;
    _canvas.drawLine(
      Offset(c.dx - barW / 2, y),
      Offset(c.dx + barW / 2, y),
      _stroke(_white.withValues(alpha: 0.12), r * 0.02),
    );
    _canvas.drawLine(
      Offset(c.dx - barW / 2, y),
      Offset(c.dx - barW / 2 + barW * now.minute / 59, y),
      _stroke(accent, r * 0.02),
    );
    _text(_date, c + Offset(0, r * 0.72), r * 0.07, _white.withValues(alpha: 0.5), spacing: r * 0.015);
  }

  /// A retro terminal: prompt lines, a progress bar for the minute and a
  /// blinking cursor, over faint scanlines.
  void _terminal() {
    final box = Rect.fromCircle(center: c, radius: r);
    for (var y = box.top; y < box.bottom; y += r * 0.035) {
      _canvas.drawLine(Offset(box.left, y), Offset(box.right, y), _stroke(_tint(0.05), r * 0.012));
    }
    final x = box.left + r * 0.12;
    final size = r * 0.105;
    void line(String s, double row, Color color, {bool glow = false, double? fontSize}) {
      final tp = TextPainter(
        text: TextSpan(
          text: s,
          style: TextStyle(fontFamily: 'monospace', fontSize: fontSize ?? size, color: color, height: 1),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(_canvas, Offset(x, box.top + r * 0.14 + row * size * 1.5));
    }

    final dim = _tint(0.55);
    line('> sys.clock', 0, dim);
    line('${_date.toLowerCase()} ${now.year}', 1, dim);
    line('$_time:${_two(now.second)}', 2.1, accent, glow: true, fontSize: size * 2.3);
    const cells = 12;
    final filled = (now.second / 60 * cells).floor();
    line('[${'█' * filled}${'░' * (cells - filled)}]', 5.4, _tint(0.85));
    line('${_two(now.second)}s · sync ok', 6.6, dim);
    final cursor = now.second.isEven ? '█' : ' ';
    line('> $cursor', 7.9, accent, glow: true);
  }

  /// An arc reactor: a glowing core, a ring of segments, and two dashed
  /// rings turning against each other (one with the minutes, one with the
  /// seconds).
  void _reactor() {
    final s = _sec / 60;
    final m = (now.minute + now.second / 60) / 60;
    // Outer dashed ring, turning with the seconds.
    for (var i = 0; i < 40; i++) {
      _arc(r * 0.93, s + i / 40, 1 / 80, _stroke(_tint(i % 10 == 0 ? 0.9 : 0.35), r * 0.03, cap: StrokeCap.butt));
    }
    // Inner dashed ring, turning back with the minutes.
    for (var i = 0; i < 24; i++) {
      _arc(r * 0.79, -m + i / 24, 1 / 60, _stroke(_white.withValues(alpha: 0.4), r * 0.05, cap: StrokeCap.butt));
    }
    // Twelve coil segments, lit up to the hour.
    final hour = now.hour % 12;
    for (var i = 0; i < 12; i++) {
      final lit = i <= hour;
      _arc(
        r * 0.62,
        i / 12 + 0.01,
        1 / 12 - 0.02,
        _stroke(lit ? accent : _tint(0.15), r * 0.11, cap: StrokeCap.butt),
        glow: lit,
      );
    }
    // The core.
    _canvas.drawCircle(
      c,
      r * 0.46,
      // A flat lit disc, no glow round it.
      Paint()..color = accent,
    );
    _canvas.drawCircle(c, r * 0.3, Paint()..color = _shade.withValues(alpha: 0.55));
    _canvas.drawCircle(c, r * 0.3, _stroke(_white.withValues(alpha: 0.6), r * 0.01));
    _text(_time, c + Offset(0, -r * 0.03), r * 0.17, _white, weight: FontWeight.w600, glow: true);
    _text(_two(now.second), c + Offset(0, r * 0.15), r * 0.08, accent, weight: FontWeight.w600);
  }

  @override
  bool shouldRepaint(_FuturePainter old) =>
      old.now != now ||
      old.tick != tick ||
      old.face != face ||
      old.accent != accent ||
      old.light != light ||
      old.use24 != use24;
}

// ---- Settings --------------------------------------------------------------

/// Its options: the face, the accent colour and the background.
Future<void> showFuturisticClockSettings(BuildContext context, WidgetItem item) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  barrierColor: Colors.black26,
  builder: (_) => _SettingsSheet(id: item.id),
);

class _SettingsSheet extends StatelessWidget {
  const _SettingsSheet({required this.id});

  final String id;

  @override
  Widget build(BuildContext context) {
    final layout = context.watch<HomeLayoutController>();
    final item = layout.findWidget(id);
    if (item == null) return const SizedBox.shrink();
    final face = _faceOf(item.settings);
    final chosen = item.settings['accent'] as String? ?? 'cyan';
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
                    for (final f in FutureFace.values)
                      _FaceTile(
                        label: f.label,
                        size: tile,
                        selected: f == face,
                        onTap: () => set('face', f.name),
                        child: _WithAccent(
                          settings: item.settings,
                          builder: (accent) => FuturisticClock(face: f, accent: accent, background: background),
                        ),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 24),
            Text('Glow', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              chosen == _wallpaperAccent
                  ? 'From your wallpaper; it changes with it'
                  : 'The colour of everything that isn\'t white',
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 14,
              children: [
                for (final MapEntry(key: name, value: color) in _accents.entries)
                  Semantics(
                    button: true,
                    selected: name == chosen,
                    label: name,
                    child: GestureDetector(
                      onTap: () => set('accent', name),
                      child: AnimatedContainer(
                        duration: TileLook.motion,
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: color,
                          border: Border.all(
                            color: name == chosen ? Colors.white : Colors.transparent,
                            width: 3,
                            strokeAlign: BorderSide.strokeAlignOutside,
                          ),
                          boxShadow: [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 10)],
                        ),
                      ),
                    ),
                  ),
                // The wallpaper's colour, as a neon.
                Semantics(
                  button: true,
                  selected: chosen == _wallpaperAccent,
                  label: 'From wallpaper',
                  child: GestureDetector(
                    onTap: () {
                      // Its colour needs the wallpaper image.
                      context.read<WindowBlurPlatform?>()?.requestWallpaperAccess();
                      set('accent', _wallpaperAccent);
                    },
                    child: _WithAccent(
                      settings: const {'accent': _wallpaperAccent},
                      builder: (color) => AnimatedContainer(
                        duration: TileLook.motion,
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: color,
                          border: Border.all(
                            color: chosen == _wallpaperAccent ? Colors.white : Colors.transparent,
                            width: 3,
                            strokeAlign: BorderSide.strokeAlignOutside,
                          ),
                        ),
                        child: const Icon(Icons.wallpaper_rounded, size: 18, color: Colors.black87),
                      ),
                    ),
                  ),
                ),
              ],
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
    required this.label,
    required this.size,
    required this.selected,
    required this.onTap,
    required this.child,
  });

  final String label;
  final double size;
  final bool selected;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
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
                child: child,
              ),
              const SizedBox(height: 6),
              Text(label, style: TextStyle(fontSize: 12, color: selected ? Colors.white : Colors.white60)),
            ],
          ),
        ),
      ),
    );
  }
}
