import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart' show Uint8List;

import 'package:flutter/material.dart';

import '../../core/platform/standby_platform.dart';
import '../widgets/clock/digital_clock.dart';
import 'beat_driver.dart';
import 'standby_media_tile.dart';
import 'standby_settings.dart';

/// The standby clock: the time, huge and thin, on black, filled with one
/// gradient from the first hour digit to the last minute digit, the seconds
/// small beside the minutes. Made for landscape; hours over minutes when it's
/// taller than wide.
///
/// Built to sip power on an OLED screen: mostly black pixels, a glow that's
/// painted once and never again, and at most one redraw a second (the
/// seconds; once a minute without them). Hour and minute digits roll when
/// they change, and everything shifts a few pixels each minute so nothing
/// burns in. From 10 PM to 6 AM (if [StandbySettings.nightMode]) it turns dim
/// and red.
class StandbyClock extends StatefulWidget {
  const StandbyClock({
    super.key,
    required this.settings,
    this.status,
    this.now,
    this.footer,
    this.colors,
    this.beats,
    this.art,
    this.artKey,
  });

  final StandbySettings settings;

  /// The next alarm; none is shown while null.
  final StandbyStatus? status;

  /// A fixed time instead of the real one (tests): nothing moves.
  final DateTime? now;

  /// Along the bottom (the now-playing tile), [StandbyMediaTile.extent]
  /// high, given its width, the clock's gradient and whether it's night. The
  /// time moves up to make room.
  final Widget Function(BuildContext context, double width, List<Color> accent, bool night)? footer;

  /// Instead of the settings' colours (a song's cover colours); faded to and
  /// from. Not at night, which stays red.
  final List<Color>? colors;

  /// The beat pulse: the glow behind the time swells on each beat.
  final BeatDriver? beats;

  /// A song's cover, shown dim and heavily blurred behind everything; and
  /// whose it is, so a new cover crossfades in. Not at night.
  final Uint8List? art;
  final Object? artKey;

  @override
  State<StandbyClock> createState() => _StandbyClockState();
}

class _StandbyClockState extends State<StandbyClock> {
  Timer? _timer;
  late DateTime _now;

  bool get _live => widget.now == null;

  @override
  void initState() {
    super.initState();
    _tick();
  }

  @override
  void didUpdateWidget(StandbyClock old) {
    super.didUpdateWidget(old);
    if (old.now != widget.now || old.settings.seconds != widget.settings.seconds) _tick();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// Wakes just after the next second (seconds shown) or minute turns: never
  /// more often than the display changes.
  void _tick() {
    _timer?.cancel();
    if (widget.now case final fixed?) {
      _now = fixed;
      return;
    }
    _now = DateTime.now();
    final ms = widget.settings.seconds ? 1000 - _now.millisecond : (60 - _now.second) * 1000 - _now.millisecond;
    _timer = Timer(Duration(milliseconds: ms + 5), () {
      if (mounted) setState(_tick);
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.settings;
    final night = s.isNight(_now);
    final accent = widget.colors ?? s.colors;
    final use24h = MediaQuery.alwaysUse24HourFormatOf(context);
    final (hm, sec, ampm) = DigitalClock.formatTime(_now, use24h: use24h);
    final [hours, minutes] = hm.split(':');
    final weight = s.fontWeight.toDouble();

    TextStyle style(double size, {double? w, double spacing = 0}) => TextStyle(
      fontFamily: s.font.family,
      fontSize: size,
      fontWeight: FontWeight.values[((w ?? weight) ~/ 100 - 1).clamp(0, 8)],
      fontVariations: [FontVariation('wght', w ?? weight)],
      fontFeatures: const [FontFeature.tabularFigures()],
      letterSpacing: spacing,
      height: 1,
      leadingDistribution: TextLeadingDistribution.even,
    );

    // Material: a text style to inherit, wherever the clock is put.
    // The colours fade to new ones (a song's cover) over a second.
    return TweenAnimationBuilder<List<Color>>(
      tween: _ColorsTween(end: accent),
      duration: _live ? const Duration(milliseconds: 1200) : Duration.zero,
      curve: Curves.easeInOut,
      builder: (context, colors, _) {
        final palette = night ? _Palette.night : _Palette.of(colors);
        return TweenAnimationBuilder<double>(
          tween: Tween(end: widget.footer == null ? 0 : StandbyMediaTile.extent),
          duration: _live ? const Duration(milliseconds: 650) : Duration.zero,
          curve: Curves.easeInOutCubic,
          builder: (context, reserve, _) => Material(
            color: Colors.black,
            child: LayoutBuilder(
              builder: (context, box) {
                final size = box.biggest;
                // Left above the footer.
                final bodyHeight = size.height - reserve;
                final landscape = size.width >= size.height;
                // Text and gaps scale with the shorter side.
                final unit = size.shortestSide;
                final labelWeight = math.max(s.font.minWeight, 400).toDouble();
                final label = style(unit * 0.042, w: labelWeight, spacing: unit * 0.008);

                final date = Text(
                  DigitalClock.formatDate(_now, DateLength.long).toUpperCase(),
                  maxLines: 1,
                  style: label.copyWith(color: palette.soft, letterSpacing: unit * 0.014),
                );

                const digitBase = 200.0;
                // Drawn white, then filled with the gradient by _Filled.
                final digits = style(digitBase).copyWith(color: Colors.white);
                final hourText = _Digits(text: hours, style: digits, animate: _live);
                final minuteText = _Digits(text: minutes, style: digits, animate: _live);
                final colon = Padding(
                  padding: const EdgeInsets.symmetric(horizontal: digitBase * 0.02),
                  // Nudged up: most fonts sit the colon low for prose.
                  child: Transform.translate(
                    offset: const Offset(0, -digitBase * 0.04),
                    child: Text(':', style: digits.copyWith(color: Colors.white.withValues(alpha: 0.8))),
                  ),
                );

                // AM/PM up top, the seconds down by the minutes' feet.
                final suffix = ampm.isEmpty
                    ? null
                    : Text(
                        ampm,
                        style: style(
                          digitBase * 0.15,
                          w: labelWeight,
                          spacing: digitBase * 0.02,
                        ).copyWith(color: palette.soft),
                      );
                final seconds = s.seconds
                    ? _Filled(
                        colors: palette.time,
                        child: Text(
                          sec,
                          style: style(digitBase * 0.3).copyWith(color: Colors.white.withValues(alpha: 0.85)),
                        ),
                      )
                    : null;
                Widget? side;
                if (suffix != null || seconds != null) {
                  side = Padding(
                    padding: const EdgeInsets.only(
                      left: digitBase * 0.06,
                      top: digitBase * 0.16,
                      bottom: digitBase * 0.1,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [suffix ?? const SizedBox.shrink(), seconds ?? const SizedBox.shrink()],
                    ),
                  );
                }

                final Widget time;
                if (landscape) {
                  time = SizedBox(
                    width: size.width * 0.84,
                    height: math.min(size.height * 0.52, bodyHeight * 0.6),
                    child: FittedBox(
                      child: IntrinsicHeight(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _Filled(
                              colors: palette.time,
                              beats: night ? null : widget.beats,
                              child: Row(mainAxisSize: MainAxisSize.min, children: [hourText, colon, minuteText]),
                            ),
                            ?side,
                          ],
                        ),
                      ),
                    ),
                  );
                } else {
                  // Hours over minutes, the seconds beside the minutes.
                  Widget line(Widget child) => SizedBox(
                    width: size.width * 0.78,
                    height: math.min(size.height * 0.26, bodyHeight * 0.3),
                    child: FittedBox(child: child),
                  );
                  time = Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      line(_Filled(colors: palette.time, beats: night ? null : widget.beats, child: hourText)),
                      line(
                        IntrinsicHeight(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _Filled(colors: palette.time, beats: night ? null : widget.beats, child: minuteText),
                              ?side,
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                }

                final alarm = widget.status?.nextAlarm;
                final alarmRow = s.alarm && alarm != null
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.alarm_rounded, size: label.fontSize! * 1.25, color: palette.soft),
                          SizedBox(width: label.fontSize! * 0.4),
                          Text(
                            _alarmLabel(alarm, use24h: use24h),
                            style: label.copyWith(color: palette.soft),
                          ),
                        ],
                      )
                    : null;

                final content = Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    date,
                    SizedBox(height: unit * (landscape ? 0.03 : 0.05)),
                    time,
                    if (alarmRow != null) ...[SizedBox(height: unit * 0.06), alarmRow],
                  ],
                );

                return AnimatedOpacity(
                  opacity: night ? 0.6 : 1,
                  duration: const Duration(seconds: 2),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // Moved with the time each minute, so it never sits still for hours.
                      _ArtGlow(art: night ? null : widget.art, artKey: widget.artKey, offset: _driftFor(_now, unit)),
                      // Its own layer so the ticking never repaints it.
                      if (!night && s.glow)
                        RepaintBoundary(
                          // While the music's hits come, the steady glow fades
                          // out and they light a dark screen; it comes back
                          // when they stop.
                          child: ValueListenableBuilder<bool>(
                            valueListenable: widget.beats?.live ?? _never,
                            builder: (context, live, _) => TweenAnimationBuilder<double>(
                              tween: Tween(end: live ? 0 : 1),
                              duration: const Duration(milliseconds: 1600),
                              curve: Curves.easeInOut,
                              builder: (context, base, _) =>
                                  CustomPaint(painter: _Glow(palette.time, widget.beats, base: base)),
                            ),
                          ),
                        ),
                      Padding(
                        padding: EdgeInsets.only(bottom: reserve),
                        child: Center(
                          child: _Drift(offset: _driftFor(_now, unit), animate: _live, child: content),
                        ),
                      ),
                      if (widget.footer case final footer?)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: StandbyMediaTile.bottomMargin,
                          child: Opacity(
                            opacity: (reserve / StandbyMediaTile.extent).clamp(0.0, 1.0),
                            child: Transform.translate(
                              offset: Offset(0, StandbyMediaTile.extent - reserve),
                              child: Center(
                                // Sideways only: a few pixels each minute, against burn-in.
                                child: _Drift(
                                  offset: Offset(_driftFor(_now, unit).dx, 0),
                                  animate: _live,
                                  child: footer(
                                    context,
                                    landscape ? (size.width * 0.62).clamp(320.0, 620.0) : size.width - 24,
                                    palette.time,
                                    night,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  /// A few pixels' shift, different each minute, so no pixel is lit for hours.
  static Offset _driftFor(DateTime t, double unit) {
    final m = t.hour * 60 + t.minute;
    return Offset(math.sin(m * 0.9) * unit * 0.03, math.cos(m * 1.3) * unit * 0.02);
  }

  /// "7:00 AM", with the day when it isn't within the next day.
  String _alarmLabel(DateTime t, {required bool use24h}) {
    final (hm, _, ampm) = DigitalClock.formatTime(t, use24h: use24h);
    final time = ampm.isEmpty ? hm : '$hm $ampm';
    if (t.difference(_now) < const Duration(hours: 23)) return time;
    return '${DigitalClock.formatDate(t, DateLength.short).split(' ').first.toUpperCase()} $time';
  }
}

/// Fades between two gradients (any lengths; both made two colours).
class _ColorsTween extends Tween<List<Color>> {
  _ColorsTween({required List<Color> end}) : super(end: end);

  static List<Color> _two(List<Color> c) => c.length >= 2 ? [c.first, c.last] : [c.first, c.first];

  @override
  List<Color> lerp(double t) {
    final a = _two(begin ?? end!);
    final b = _two(end!);
    return [Color.lerp(a[0], b[0], t)!, Color.lerp(a[1], b[1], t)!];
  }
}

/// The colours of one look.
class _Palette {
  const _Palette({required this.time, required this.soft});

  factory _Palette.of(List<Color> accent) => _Palette(time: accent, soft: Colors.white.withValues(alpha: 0.55));

  /// Deep red only: kind to dark-adapted eyes.
  static const night = _Palette(time: [Color(0xFFFF453A), Color(0xFFC4251C)], soft: Color(0x99FF453A));

  /// The time's gradient.
  final List<Color> time;

  /// Date, AM/PM and alarm.
  final Color soft;
}

/// [child] (drawn white) filled with a gradient of [colors], top-left to
/// bottom-right across its whole width; the child's transparency is kept.
class _Filled extends StatelessWidget {
  const _Filled({required this.colors, required this.child, this.beats});

  final List<Color> colors;
  final Widget child;

  /// While the music's hits come ([BeatDriver.live]), the digits turn
  /// lightly glassy: a sheen across their top, a faint reflection at the
  /// foot, and a soft halo of their own colours; the sheen and halo
  /// brighten a touch on each hit. Faded in and out with the beat glow.
  final BeatDriver? beats;

  @override
  Widget build(BuildContext context) {
    final fill = ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: LinearGradient(
        colors: colors.length >= 2 ? colors : [colors.first, colors.first],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader,
      child: child,
    );
    final b = beats;
    if (b == null) return fill;
    return ValueListenableBuilder<bool>(
      valueListenable: b.live,
      builder: (context, live, _) => TweenAnimationBuilder<double>(
        tween: Tween(end: live ? 1 : 0),
        duration: const Duration(milliseconds: 1600),
        curve: Curves.easeInOut,
        builder: (context, glass, _) {
          if (glass == 0) return fill;
          return Stack(
            clipBehavior: Clip.none,
            children: [
              // The halo: the digits' own colours, blurred, behind them.
              IgnorePointer(
                child: AnimatedBuilder(
                  animation: b,
                  builder: (context, halo) =>
                      Opacity(opacity: (glass * (0.18 + 0.4 * b.energy)).clamp(0.0, 1.0), child: halo),
                  child: ImageFiltered(imageFilter: ImageFilter.blur(sigmaX: 9, sigmaY: 9), child: fill),
                ),
              ),
              fill,
              // The glass: light on the top half with a crisp edge at the
              // middle, as on a curved pane, and a faint glint at the foot.
              IgnorePointer(
                child: AnimatedBuilder(
                  animation: b,
                  builder: (context, _) {
                    final top = glass * (0.32 + 0.18 * b.energy);
                    return ShaderMask(
                      blendMode: BlendMode.srcIn,
                      shaderCallback: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.white.withValues(alpha: top),
                          Colors.white.withValues(alpha: top * 0.35),
                          Colors.white.withValues(alpha: 0),
                          Colors.white.withValues(alpha: 0),
                          Colors.white.withValues(alpha: glass * 0.12),
                        ],
                        stops: const [0, 0.48, 0.5, 0.82, 1],
                      ).createShader,
                      child: child,
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// A row of digits, each rolling up into place when it changes.
class _Digits extends StatelessWidget {
  const _Digits({required this.text, required this.style, required this.animate});

  final String text;
  final TextStyle style;
  final bool animate;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      // Keyed from the right so the ones digit stays itself as the hours
      // gain a digit (9 → 10).
      for (var i = 0; i < text.length; i++)
        _RollingDigit(key: ValueKey(text.length - i), digit: text[i], style: style, animate: animate),
    ],
  );
}

class _RollingDigit extends StatelessWidget {
  const _RollingDigit({super.key, required this.digit, required this.style, required this.animate});

  final String digit;
  final TextStyle style;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: animate ? const Duration(milliseconds: 700) : Duration.zero,
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      layoutBuilder: (current, previous) =>
          Stack(alignment: Alignment.center, clipBehavior: Clip.none, children: [...previous, ?current]),
      // A new closure each build, so the outgoing digit is rebuilt as
      // outgoing and leaves upwards while the new one rises from below.
      transitionBuilder: (child, animation) {
        final incoming = child.key == ValueKey(digit);
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween(begin: Offset(0, incoming ? 0.4 : -0.4), end: Offset.zero).animate(animation),
            child: child,
          ),
        );
      },
      child: Text(digit, key: ValueKey(digit), style: style),
    );
  }
}

/// Eases its child to [offset] whenever that changes (once a minute).
class _Drift extends StatelessWidget {
  const _Drift({required this.offset, required this.animate, required this.child});

  final Offset offset;
  final bool animate;
  final Widget child;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<Offset>(
    tween: Tween(begin: offset, end: offset),
    duration: animate ? const Duration(milliseconds: 700) : Duration.zero,
    curve: Curves.easeInOut,
    builder: (_, o, child) => Transform.translate(offset: o, child: child),
    child: child,
  );
}

/// The song's cover, dim and heavily blurred, filling the screen behind
/// everything; a new cover crossfades in. Decoded small (a blur needs no
/// detail) and blurred once into its own layer, so it costs nothing per
/// frame. Its middle is darkened, so the time stays crisp in front of it.
class _ArtGlow extends StatelessWidget {
  const _ArtGlow({required this.art, required this.artKey, required this.offset});

  final Uint8List? art;
  final Object? artKey;
  final Offset offset;

  /// How strongly the cover shows: dim, a backdrop, not a picture.
  static const opacity = 0.26;

  @override
  Widget build(BuildContext context) {
    final a = art;
    return IgnorePointer(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 1400),
        switchInCurve: Curves.easeInOut,
        switchOutCurve: Curves.easeInOut,
        layoutBuilder: (current, previous) => Stack(fit: StackFit.expand, children: [...previous, ?current]),
        child: a == null
            ? const SizedBox.expand(key: ValueKey(_ArtGlow))
            : Transform.translate(
                key: ValueKey(artKey ?? a),
                offset: offset,
                child: RepaintBoundary(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Opacity(
                        opacity: opacity,
                        // Larger than the screen: blurred edges fade, and these stay off it.
                        child: Transform.scale(
                          scale: 1.3,
                          child: ImageFiltered(
                            imageFilter: ImageFilter.blur(sigmaX: 36, sigmaY: 36, tileMode: TileMode.clamp),
                            child: Image.memory(
                              a,
                              cacheWidth: 48,
                              fit: BoxFit.cover,
                              filterQuality: FilterQuality.medium,
                              gaplessPlayback: true,
                            ),
                          ),
                        ),
                      ),
                      const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: RadialGradient(
                            radius: 0.9,
                            colors: [Color(0x99000000), Color(0x33000000), Color(0x00000000)],
                            stops: [0, 0.6, 1],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}

/// Never live: the glow's steady state without a beat pulse.
final ValueNotifier<bool> _never = ValueNotifier(false);

/// Two faint, still pools of the accent colours behind the time; with the
/// beat pulse, patches of it flash with the music, each band in its own
/// place: treble on the left, mids in the middle, bass on the right.
class _Glow extends CustomPainter {
  _Glow(this.colors, this.beats, {this.base = 1}) : super(repaint: beats);

  final List<Color> colors;

  /// How much of the steady glow shows, 0 to 1.
  final double base;

  /// The beat pulse, per band.
  final BeatDriver? beats;

  @override
  void paint(Canvas canvas, Size size) {
    void pool(Offset c, Color color, double alpha, double r) => canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = RadialGradient(
          colors: [
            color.withValues(alpha: alpha),
            color.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromCircle(center: c, radius: r)),
    );
    final r = size.longestSide * 0.5;
    if (base > 0) {
      pool(Offset(size.width * 0.3, size.height * 0.35), colors.first, 0.12 * base, r);
      pool(Offset(size.width * 0.72, size.height * 0.7), colors.last, 0.09 * base, r);
    }

    final b = beats;
    if (b == null) return;
    for (final (spot, (home, t)) in _spots.indexed) {
      final p = b.pulses[spot];
      if (p <= 0) continue;
      final at = home + b.drift[spot];
      final c = Offset(size.width * at.dx, size.height * at.dy);
      final base = _along(colors, t);
      final heat = b.heat[spot];
      // Harder hits glow warmer and brighter: the hue turns a little and
      // lightens, so a song's big moments read in colour, not just size.
      final hot = _heated(base, heat);
      final r = size.longestSide * (0.22 + 0.06 * p);
      // A wide soft halo in the band's colour...
      pool(c, Color.lerp(base, hot, 0.5)!, 0.28 * p, r);
      // ...and, on harder hits, a smaller brighter core in the heated colour.
      if (heat > 0.3) pool(c, hot, 0.16 * p * (heat - 0.3) / 0.7, r * 0.45);
    }
  }

  /// Each glow point's home and its colour along the gradient, in
  /// [BeatDriver.spotCount] order (two per band): bass on the right, mids
  /// above and below the time, treble on the left.
  static const _spots = [
    (Offset(0.86, 0.28), 1.0),
    (Offset(0.8, 0.74), 0.85),
    (Offset(0.4, 0.16), 0.55),
    (Offset(0.6, 0.84), 0.45),
    (Offset(0.14, 0.68), 0.0),
    (Offset(0.2, 0.24), 0.15),
  ];

  /// The colour [t] (0 to 1) of the way along [colors].
  static Color _along(List<Color> colors, double t) {
    if (colors.length == 1) return colors.first;
    final x = t * (colors.length - 1);
    final i = x.floor().clamp(0, colors.length - 2);
    return Color.lerp(colors[i], colors[i + 1], x - i)!;
  }

  /// [c] warmed by [heat] (0 to 1): hue turned up to 40°, lighter, richer.
  static Color _heated(Color c, double heat) {
    final hsl = HSLColor.fromColor(c);
    return hsl
        .withHue((hsl.hue + 40 * heat) % 360)
        .withLightness((hsl.lightness + 0.18 * heat).clamp(0.0, 0.85))
        .withSaturation((hsl.saturation + 0.15 * heat).clamp(0.0, 1.0))
        .toColor();
  }

  @override
  bool shouldRepaint(_Glow old) => old.colors != colors || old.beats != beats || old.base != base;
}
