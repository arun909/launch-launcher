import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/platform/standby_platform.dart';
import '../standby_settings.dart';
import 'deck_controls.dart';
import 'eq_display.dart';
import 'record_player.dart';
import 'seven_segment.dart';
import 'spectrum_driver.dart';
import 'vu_meter.dart';

/// The "Deck" standby style: a vintage hi-fi faceplate. Two VU meters flank
/// a 7-segment clock up top; below, a record spinning the song's cover, the
/// track with its transport, and a 10-band spectrum.
///
/// Laid out once at [design] size and scaled to fit, so every phone gets the
/// same proportions. The frame is warm amber (see [DeckInk.amber]); the
/// clock, the progress, the record label and the glass transport buttons
/// take the song's cover colours (amber without them). With night mode, from 10 PM to 6 AM it all turns red and
/// a little dimmer. It shifts a pixel or two each minute against burn-in.
class DeckView extends StatefulWidget {
  const DeckView({
    super.key,
    required this.settings,
    this.status,
    this.media,
    this.spectrum,
    this.colors,
    this.now,
    this.onCommand,
  });

  final StandbySettings settings;
  final StandbyStatus? status;
  final NowPlaying? media;
  final SpectrumDriver? spectrum;

  /// Instead of the settings' colours (the song's cover colours).
  final List<Color>? colors;

  /// A fixed time (tests, previews): nothing moves.
  final DateTime? now;
  final void Function(String command, {Duration? position})? onCommand;

  static const design = Size(880, 396);

  @override
  State<DeckView> createState() => _DeckViewState();
}

class _DeckViewState extends State<DeckView> {
  Timer? _timer;
  late DateTime _now;

  bool get _live => widget.now == null;

  @override
  void initState() {
    super.initState();
    _tick();
  }

  @override
  void didUpdateWidget(DeckView old) {
    super.didUpdateWidget(old);
    if (old.now != widget.now) _tick();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// Every second: the colon blinks and the song's time counts.
  void _tick() {
    _timer?.cancel();
    if (widget.now case final fixed?) {
      _now = fixed;
      return;
    }
    _now = DateTime.now();
    _timer = Timer(Duration(milliseconds: 1000 - _now.millisecond + 5), () {
      if (mounted) setState(_tick);
    });
  }

  /// The song's colours (amber without them), faded to over a second when
  /// the song changes.
  @override
  Widget build(BuildContext context) {
    final target = widget.colors ?? DeckInk.amber;
    final fade = _live ? const Duration(milliseconds: 900) : Duration.zero;
    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: target.first),
      duration: fade,
      builder: (context, a, _) => TweenAnimationBuilder<Color?>(
        tween: ColorTween(end: target.last),
        duration: fade,
        builder: (context, b, _) => _deck(context, [a ?? target.first, b ?? target.last]),
      ),
    );
  }

  Widget _deck(BuildContext context, List<Color> track) {
    final s = widget.settings;
    final media = widget.media;
    final position = media?.positionAt(_now);
    final night = s.isNight(_now);

    Widget deck = SizedBox.fromSize(
      size: DeckView.design,
      child: Stack(
        children: [
          Positioned(
            left: 18,
            top: 18,
            width: 210,
            height: 136,
            child: VuMeter(driver: widget.spectrum, channel: 0, label: 'L', tint: track.first),
          ),
          Positioned(
            left: 242,
            top: 18,
            width: 396,
            height: 136,
            child: _ClockPanel(
              now: _now,
              accent: track,
              seconds: s.seconds,
              alarm: s.alarm ? widget.status?.nextAlarm : null,
              playing: media?.playing ?? false,
            ),
          ),
          Positioned(
            left: 652,
            top: 18,
            width: 210,
            height: 136,
            child: VuMeter(driver: widget.spectrum, channel: 1, label: 'R', tint: track.first),
          ),
          Positioned(
            left: 22,
            top: 170,
            width: 236,
            height: 208,
            child: RecordPlayer(
              playing: media?.playing ?? false,
              art: media?.art,
              artKey: media?.artKey ?? media?.title,
              accent: track,
              animate: _live,
            ),
          ),
          // Same top and height as the record and the spectrum beside it.
          Positioned(
            left: 272,
            top: 170,
            width: 338,
            height: 208,
            child: _Console(
              media: media,
              position: position,
              track: track,
              onCommand: widget.onCommand ?? (_, {position}) {},
            ),
          ),
          Positioned(
            left: 624,
            top: 170,
            width: 238,
            height: 208,
            child: DeckWindow(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Text('SPECTRUM', style: DeckInk.label(8.5)),
                      const Spacer(),
                      Text('10 BAND · HZ', style: DeckInk.label(8.5, spacing: 1.2)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Expanded(child: EqDisplay(driver: widget.spectrum)),
                ],
              ),
            ),
          ),
        ],
      ),
    );

    if (night) {
      deck = Opacity(
        opacity: 0.75,
        child: ColorFiltered(
          // Everything as shades of red: kind to dark-adapted eyes.
          colorFilter: const ColorFilter.matrix([
            0.5, 0.5, 0.12, 0, 0, //
            0.05, 0.05, 0.012, 0, 0,
            0.035, 0.035, 0.01, 0, 0,
            0, 0, 0, 1, 0,
          ]),
          child: deck,
        ),
      );
    }

    // A pixel or two each minute, so nothing burns in.
    final m = _now.minute;
    final shift = Offset((m % 5 - 2).toDouble(), ((m ~/ 5) % 3 - 1).toDouble());

    return Material(
      color: Colors.black,
      child: Center(
        child: FittedBox(
          child: Transform.translate(offset: shift, child: deck),
        ),
      ),
    );
  }
}

/// The 7-segment time, its seconds, AM/PM lamps, the date and indicators.
class _ClockPanel extends StatelessWidget {
  const _ClockPanel({
    required this.now,
    required this.accent,
    required this.seconds,
    required this.alarm,
    required this.playing,
  });

  final DateTime now;
  final List<Color> accent;
  final bool seconds;
  final DateTime? alarm;
  final bool playing;

  static const _days = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
  static const _months = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];

  @override
  Widget build(BuildContext context) {
    final use24h = MediaQuery.alwaysUse24HourFormatOf(context);
    String two(int v) => v.toString().padLeft(2, '0');
    final hour = use24h ? two(now.hour) : (now.hour % 12 == 0 ? 12 : now.hour % 12).toString().padLeft(2, ' ');
    final pm = now.hour >= 12;
    final a = alarm;
    final alarmText = a == null
        ? '--:--'
        : use24h
        ? '${two(a.hour)}:${two(a.minute)}'
        : '${a.hour % 12 == 0 ? 12 : a.hour % 12}:${two(a.minute)} ${a.hour < 12 ? 'AM' : 'PM'}';

    return DeckWindow(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      child: Column(
        children: [
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                SevenSegment(
                  text: '$hour:${two(now.minute)}',
                  colors: accent,
                  height: 74,
                  // Blinks with the seconds; steady without them.
                  colonLit: !seconds || now.second.isEven,
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height: 74,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      if (!use24h)
                        Row(
                          children: [
                            _Lamp('AM', on: !pm, accent: accent),
                            const SizedBox(width: 6),
                            _Lamp('PM', on: pm, accent: accent),
                          ],
                        )
                      else
                        _Lamp('24H', on: true, accent: accent),
                      SevenSegment(text: seconds ? two(now.second) : '  ', colors: accent, height: 32),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _Lamp(
                '${_days[now.weekday - 1]}  ${two(now.day)} ${_months[now.month - 1]}',
                on: true,
                accent: accent,
                size: 11,
              ),
              const Spacer(),
              _Lamp('ALARM', on: a != null, accent: accent),
              const SizedBox(width: 6),
              _Lamp(alarmText, on: a != null, accent: accent, size: 10),
              const SizedBox(width: 14),
              _Lamp('STEREO', on: playing, accent: accent),
            ],
          ),
        ],
      ),
    );
  }
}

/// An indicator printed on the display glass: glowing when on, a faint
/// ghost when off.
class _Lamp extends StatelessWidget {
  const _Lamp(this.text, {required this.on, required this.accent, this.size = 8.5});

  final String text;
  final bool on;
  final List<Color> accent;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = accent.first;
    return Text(
      text,
      style: DeckInk.label(
        size,
        color: on ? c : c.withValues(alpha: 0.1),
        spacing: 1.6,
      ).copyWith(shadows: on ? [Shadow(color: c.withValues(alpha: 0.8), blurRadius: 6)] : null),
    );
  }
}

/// Track details, its progress and the transport: the label row lines up
/// with the spectrum's, the rest is centred in the space below.
class _Console extends StatelessWidget {
  const _Console({required this.media, required this.position, required this.track, required this.onCommand});

  final NowPlaying? media;
  final Duration? position;

  /// The song's colours: progress and the play lamp.
  final List<Color> track;
  final void Function(String command, {Duration? position}) onCommand;

  static String _time(Duration d) {
    final s = d.inSeconds;
    final h = s ~/ 3600;
    final mm = (s ~/ 60) % 60;
    final ss = (s % 60).toString().padLeft(2, '0');
    return h > 0 ? '$h:${mm.toString().padLeft(2, '0')}:$ss' : '$mm:$ss';
  }

  @override
  Widget build(BuildContext context) {
    final m = media;
    final total = m?.duration;
    final pos = position ?? Duration.zero;
    final artist = [m?.artist, m?.album].whereType<String>().where((s) => s.isNotEmpty).join(' — ');

    return Padding(
      // Matches the spectrum window's border and padding, so the labels align.
      padding: const EdgeInsets.only(top: 11),
      child: Column(
        children: [
          Row(
            children: [
              Text('NOW PLAYING', style: DeckInk.label(8.5)),
              const Spacer(),
              Text(
                (m?.app ?? '').toUpperCase(),
                style: DeckInk.label(8.5, spacing: 1.6),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  m == null ? 'Nothing playing' : m.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'ClockInter',
                    fontSize: 20,
                    color: DeckInk.cream.withValues(alpha: m == null ? 0.5 : 1),
                    fontVariations: const [FontVariation('wght', 600)],
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  m == null ? 'Music from any app shows up here' : (artist.isEmpty ? ' ' : artist),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'ClockInter',
                    fontSize: 13,
                    color: DeckInk.dim,
                    fontVariations: [FontVariation('wght', 400)],
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    SizedBox(
                      width: 40,
                      child: Text(
                        m == null ? '-:--' : _time(pos),
                        style: DeckInk.label(10, color: DeckInk.dim, spacing: 0.6),
                      ),
                    ),
                    Expanded(
                      child: _Groove(
                        fraction: total == null || total <= Duration.zero
                            ? 0
                            : pos.inMilliseconds / total.inMilliseconds,
                        accent: track,
                        onSeek: m != null && m.canSeek && total != null
                            ? (f) => onCommand('seek', position: total * f)
                            : null,
                      ),
                    ),
                    SizedBox(
                      width: 40,
                      child: Text(
                        total == null ? '-:--' : '-${_time(total - pos)}',
                        textAlign: TextAlign.right,
                        style: DeckInk.label(10, color: DeckInk.dim, spacing: 0.6),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                DeckTransport(media: m, onCommand: onCommand, accent: track),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The song's progress as a lit groove; tap to seek where the player allows.
class _Groove extends StatelessWidget {
  const _Groove({required this.fraction, required this.accent, this.onSeek});

  final double fraction;
  final List<Color> accent;
  final ValueChanged<double>? onSeek;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) => GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: onSeek == null ? null : (d) => onSeek!((d.localPosition.dx / box.maxWidth).clamp(0.0, 1.0)),
      child: SizedBox(height: 18, child: CustomPaint(painter: _GroovePainter(fraction.clamp(0.0, 1.0), accent))),
    ),
  );
}

class _GroovePainter extends CustomPainter {
  _GroovePainter(this.fraction, this.accent);

  final double fraction;
  final List<Color> accent;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    final track = RRect.fromRectAndRadius(Rect.fromLTWH(0, y - 2, size.width, 4), const Radius.circular(2));
    canvas.drawRRect(track, Paint()..color = const Color(0xFF040405));
    canvas.drawRRect(
      track,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..color = const Color(0xFF2C2C30),
    );
    final w = size.width * fraction;
    if (w > 0) {
      final fill = Rect.fromLTWH(0, y - 1.5, w, 3);
      final shader = LinearGradient(colors: accent.length >= 2 ? accent : [accent.first, accent.first])
          .createShader(Rect.fromLTWH(0, 0, size.width, size.height));
      canvas.drawRect(
        fill,
        Paint()
          ..shader = shader
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
      );
      canvas.drawRect(fill, Paint()..shader = shader);
    }
    // The playhead.
    canvas.drawCircle(Offset(w, y), 4.5, Paint()..color = const Color(0xFFDADADD));
    canvas.drawCircle(Offset(w, y), 1.6, Paint()..color = const Color(0xFF3A3A3E));
  }

  @override
  bool shouldRepaint(_GroovePainter old) => old.fraction != fraction || old.accent != accent;
}
