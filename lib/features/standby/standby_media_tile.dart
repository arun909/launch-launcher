import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/platform/standby_platform.dart';
import '../../core/widgets/media_glyph.dart';
import '../widgets/launcher_widgets.dart' show PanelInk;

/// What's playing, in a small frosted-glass tile along the bottom of the
/// standby clock: the cover, title and artist, where it's at, and previous /
/// play-pause / next.
///
/// The glass is the cover itself, blurred and darkened behind the tile, so
/// it takes the colour of the track. Only the progress line redraws, once a
/// second and only while playing.
class StandbyMediaTile extends StatelessWidget {
  const StandbyMediaTile({
    super.key,
    required this.media,
    required this.accent,
    required this.onCommand,
    required this.width,
    this.night = false,
    this.now,
  });

  /// Room the tile takes, its margin under it included.
  static const extent = height + bottomMargin + 12;
  static const height = 84.0;
  static const bottomMargin = 14.0;

  final NowPlaying media;

  final double width;

  /// The clock's gradient, for the progress line.
  final List<Color> accent;

  /// Red only and no cover colours: kind to dark-adapted eyes.
  final bool night;

  /// play, pause, next, previous, or seek (with a position).
  final void Function(String command, {Duration? position}) onCommand;

  /// A fixed time instead of the real one (tests): the progress doesn't move.
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final art = media.art;
    final cover = art == null ? null : MemoryImage(art);

    Widget tile = Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 30, offset: Offset(0, 10))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // The glass: the cover, small, stretched and blurred. Its own
            // layer so the progress ticking never repaints it.
            RepaintBoundary(
              child: _Glass(cover: cover, fallback: accent),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.white.withValues(alpha: 0.10), Colors.white.withValues(alpha: 0.02)],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
              child: Row(
                children: [
                  _Cover(cover: cover, keyName: media.artKey ?? media.title),
                  const SizedBox(width: 14),
                  Expanded(
                    child: MediaDetails(media: media, accent: accent, onCommand: onCommand, now: now),
                  ),
                  const SizedBox(width: 6),
                  MediaControls(media: media, onCommand: onCommand),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    if (night) {
      // Luminance into red, a little into green/blue: dim warm red.
      tile = ColorFiltered(
        colorFilter: const ColorFilter.matrix([
          0.30, 0.59, 0.11, 0, 0, //
          0.07, 0.14, 0.03, 0, 0,
          0.05, 0.10, 0.02, 0, 0,
          0, 0, 0, 1, 0,
        ]),
        child: tile,
      );
    }

    // Taps on the tile (not its buttons) don't close the clock.
    return GestureDetector(behavior: HitTestBehavior.opaque, onTap: () {}, child: tile);
  }
}

class _Glass extends StatelessWidget {
  const _Glass({required this.cover, required this.fallback});

  final ImageProvider? cover;
  final List<Color> fallback;

  @override
  Widget build(BuildContext context) {
    final tint = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [Colors.black.withValues(alpha: 0.35), Colors.black.withValues(alpha: 0.6)]),
      ),
    );
    final Widget base = cover == null
        ? DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [fallback.first.withValues(alpha: 0.35), fallback.last.withValues(alpha: 0.18)],
              ),
            ),
          )
        : ImageFiltered(
            imageFilter: ui.ImageFilter.blur(sigmaX: 28, sigmaY: 28, tileMode: TileMode.mirror),
            // Decoded tiny: it's blurred to nothing anyway.
            child: Image(
              image: ResizeImage(cover!, width: 48, height: 48),
              fit: BoxFit.cover,
              filterQuality: FilterQuality.medium,
              gaplessPlayback: true,
            ),
          );
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 600),
      child: Stack(
        key: ValueKey(cover),
        fit: StackFit.expand,
        children: [
          ColoredBox(color: const Color(0xFF111114)),
          base,
          tint,
        ],
      ),
    );
  }
}

class _Cover extends StatelessWidget {
  const _Cover({required this.cover, required this.keyName});

  final ImageProvider? cover;
  final String keyName;

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: const Duration(milliseconds: 450),
    switchInCurve: Curves.easeOutCubic,
    transitionBuilder: (child, a) => FadeTransition(
      opacity: a,
      child: ScaleTransition(scale: Tween(begin: 0.85, end: 1.0).animate(a), child: child),
    ),
    child: Container(
      key: ValueKey('$keyName${cover != null}'),
      width: 60,
      height: 60,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: Colors.white.withValues(alpha: 0.08),
        boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 12, offset: Offset(0, 4))],
        image: cover == null
            ? null
            : DecorationImage(image: ResizeImage(cover!, width: 180, height: 180), fit: BoxFit.cover),
      ),
      child: cover == null
          ? Icon(Icons.music_note_rounded, color: Colors.white.withValues(alpha: 0.6), size: 28)
          : null,
    ),
  );
}

/// Title, artist and where it's at. Drag sideways across any of it to move
/// through the song (when the player allows): from the line, the dot jumps to
/// the finger; from the text, it moves on from where it was. While dragging,
/// the title gives way to a large readout of the time and how far it moved.
///
/// Shared with the home screen's music widget, so both look the same.
class MediaDetails extends StatefulWidget {
  const MediaDetails({
    super.key,
    required this.media,
    required this.accent,
    required this.onCommand,
    this.now,
    this.album = false,
    this.compact = false,
  });

  final NowPlaying media;
  final List<Color> accent;
  final void Function(String command, {Duration? position}) onCommand;
  final DateTime? now;

  /// The album too, between the artist and the app.
  final bool album;

  /// The home widget's track line: a thicker capsule, with narrower times
  /// beside it.
  final bool compact;

  @override
  State<MediaDetails> createState() => _MediaDetailsState();
}

class _MediaDetailsState extends State<MediaDetails> {
  final _lineKey = GlobalKey();

  /// While dragging: where it'll go, 0 to 1, and where it was, 0 to 1.
  double? _scrub;
  double _from = 0;

  /// Last 10% mark passed, for a tick.
  int _tick = 0;

  Duration? get _total => widget.media.duration;

  bool get _canSeek => widget.media.canSeek && (_total?.inMilliseconds ?? 0) > 0;

  double _played() {
    final total = _total;
    if (total == null || total.inMilliseconds == 0) return 0;
    return (widget.media.positionAt(widget.now ?? DateTime.now()).inMilliseconds / total.inMilliseconds).clamp(
      0.0,
      1.0,
    );
  }

  /// The line's left edge and width, in global coordinates.
  (double, double)? _lineBox() {
    final box = _lineKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize || box.size.width == 0) return null;
    return (box.localToGlobal(Offset.zero).dx, box.size.width);
  }

  void _start(DragStartDetails d) {
    final now = _played();
    var at = now;
    // Started on the line: the dot jumps to the finger.
    final line = _lineKey.currentContext?.findRenderObject() as RenderBox?;
    if (line != null && line.hasSize) {
      final local = line.globalToLocal(d.globalPosition);
      if (local.dy >= -8 && local.dy <= line.size.height + 8) at = (local.dx / line.size.width).clamp(0.0, 1.0);
    }
    HapticFeedback.selectionClick();
    setState(() {
      _from = now;
      _scrub = at;
      _tick = (at * 10).floor();
    });
  }

  void _update(DragUpdateDetails d) {
    final box = _lineBox();
    if (box == null || _scrub == null) return;
    final next = (_scrub! + d.delta.dx / box.$2).clamp(0.0, 1.0);
    final tick = (next * 10).floor();
    if (tick != _tick) HapticFeedback.selectionClick();
    setState(() {
      _scrub = next;
      _tick = tick;
    });
  }

  void _end() {
    final to = _scrub;
    final total = _total;
    setState(() => _scrub = null);
    if (to == null || total == null) return;
    HapticFeedback.lightImpact();
    widget.onCommand('seek', position: total * to);
  }

  void _tapLine(TapUpDetails d) {
    final total = _total;
    final box = _lineBox();
    if (total == null || box == null) return;
    HapticFeedback.lightImpact();
    widget.onCommand('seek', position: total * ((d.globalPosition.dx - box.$1) / box.$2).clamp(0.0, 1.0));
  }

  @override
  Widget build(BuildContext context) {
    final media = widget.media;
    final sub = [
      media.artist,
      if (widget.album && media.album != media.title) media.album,
      media.app,
    ].whereType<String>().where((s) => s.isNotEmpty).join('  ·  ');
    final scrub = _scrub;

    final Widget heading;
    if (scrub != null && _total != null) {
      heading = _ScrubReadout(
        key: const ValueKey('scrub'),
        at: _total! * scrub,
        total: _total!,
        moved: _total! * (scrub - _from),
        accent: widget.accent,
      );
    } else {
      heading = Column(
        key: const ValueKey('title'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            layoutBuilder: (current, previous) =>
                Stack(alignment: Alignment.centerLeft, children: [...previous, ?current]),
            child: Text(
              media.title,
              key: ValueKey(media.title),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: PanelInk.of(context), fontSize: 15, fontWeight: FontWeight.w600, height: 1.2),
            ),
          ),
          if (sub.isNotEmpty || media.connected)
            Row(
              children: [
                // Playing on the laptop, not the phone.
                if (media.connected) ...[
                  Icon(Icons.laptop_rounded, size: 13, color: PanelInk.of(context).withValues(alpha: 0.6)),
                  const SizedBox(width: 5),
                ],
                Flexible(
                  child: Text(
                    sub.isEmpty ? 'Laptop' : sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: PanelInk.of(context).withValues(alpha: 0.6), fontSize: 12.5, height: 1.3),
                  ),
                ),
              ],
            ),
        ],
      );
    }

    final content = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Both kept the same height, so nothing jumps.
        SizedBox(
          height: 35,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            layoutBuilder: (current, previous) =>
                Stack(alignment: Alignment.centerLeft, children: [...previous, ?current]),
            child: heading,
          ),
        ),
        SizedBox(height: widget.compact ? 2 : 5),
        _Progress(
          compact: widget.compact,
          media: media,
          accent: widget.accent,
          scrub: scrub,
          lineKey: _lineKey,
          onTapLine: _canSeek ? _tapLine : null,
          now: widget.now,
        ),
      ],
    );

    if (!_canSeek) return content;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragStart: _start,
      onHorizontalDragUpdate: _update,
      onHorizontalDragEnd: (_) => _end(),
      onHorizontalDragCancel: () => setState(() => _scrub = null),
      child: content,
    );
  }
}

/// While dragging: "2:41 / 3:33", and how far it moves, "+0:42".
class _ScrubReadout extends StatelessWidget {
  const _ScrubReadout({super.key, required this.at, required this.total, required this.moved, required this.accent});

  final Duration at;
  final Duration total;
  final Duration moved;
  final List<Color> accent;

  @override
  Widget build(BuildContext context) {
    const figures = [FontFeature.tabularFigures()];
    final sign = moved.isNegative ? '−' : '+';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          _formatTime(at),
          style: TextStyle(
            color: PanelInk.of(context),
            fontSize: 24,
            fontWeight: FontWeight.w600,
            height: 1,
            fontFeatures: figures,
          ),
        ),
        Text(
          ' / ${_formatTime(total)}',
          style: TextStyle(
            color: PanelInk.of(context).withValues(alpha: 0.45),
            fontSize: 13,
            height: 1,
            fontFeatures: figures,
          ),
        ),
        const SizedBox(width: 10),
        ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: LinearGradient(colors: accent.length >= 2 ? accent : [accent.first, accent.first])
              .createShader,
          child: Text(
            '$sign${_formatTime(moved.abs())}',
            style: TextStyle(
              color: PanelInk.of(context),
              fontSize: 14,
              fontWeight: FontWeight.w600,
              fontFeatures: figures,
            ),
          ),
        ),
      ],
    );
  }
}

String _formatTime(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes % 60;
  final s = (d.inSeconds % 60).toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$s' : '$m:$s';
}

/// The time played, a small glass capsule filling up, and the length. Its own layer:
/// it's what ticks.
class _Progress extends StatefulWidget {
  const _Progress({
    required this.media,
    required this.accent,
    required this.lineKey,
    this.scrub,
    this.onTapLine,
    this.now,
    this.compact = false,
  });

  final NowPlaying media;
  final List<Color> accent;
  final Key lineKey;
  final bool compact;

  /// While dragging, where it'll go (0 to 1).
  final double? scrub;
  final GestureTapUpCallback? onTapLine;
  final DateTime? now;

  @override
  State<_Progress> createState() => _ProgressState();
}

class _ProgressState extends State<_Progress> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void didUpdateWidget(_Progress old) {
    super.didUpdateWidget(old);
    _schedule();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// Wakes as the played time's next whole second turns, only while playing.
  void _schedule() {
    _timer?.cancel();
    final m = widget.media;
    if (!m.playing || widget.now != null || m.speed <= 0) return;
    final ms = m.positionAt(DateTime.now()).inMilliseconds % 1000;
    _timer = Timer(Duration(milliseconds: ((1000 - ms) / m.speed).round() + 5), () {
      if (mounted) setState(_schedule);
    });
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.media;
    final total = m.duration;
    final at = m.positionAt(widget.now ?? DateTime.now());
    final scrub = widget.scrub;
    final fraction =
        scrub ?? (total == null || total.inMilliseconds == 0 ? 0.0 : at.inMilliseconds / total.inMilliseconds);
    final shown = scrub != null && total != null ? total * scrub : at;

    final label = TextStyle(
      color: PanelInk.of(context).withValues(alpha: 0.55),
      fontSize: widget.compact ? 9.5 : 10.5,
      fontFeatures: const [FontFeature.tabularFigures()],
      height: 1,
    );

    if (total == null) {
      // A live stream, or a player that doesn't say: no line, just a dot.
      return Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(shape: BoxShape.circle, color: widget.accent.first),
          ),
          const SizedBox(width: 6),
          Text(m.playing ? 'LIVE' : 'PAUSED', style: label.copyWith(letterSpacing: 1.2)),
        ],
      );
    }

    final line = _Line(
      key: widget.lineKey,
      fraction: fraction.clamp(0.0, 1.0),
      colors: widget.accent,
      active: scrub != null,
      seekable: widget.onTapLine != null,
      compact: widget.compact,
    );
    return RepaintBoundary(
      child: Row(
        children: [
          SizedBox(
            width: widget.compact ? 28 : 34,
            child: Text(_formatTime(shown), style: label),
          ),
          Expanded(
            child: widget.onTapLine == null
                ? line
                : GestureDetector(behavior: HitTestBehavior.opaque, onTapUp: widget.onTapLine, child: line),
          ),
          SizedBox(
            width: widget.compact ? 30 : 38,
            child: Text(_formatTime(total), textAlign: TextAlign.right, style: label),
          ),
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({
    super.key,
    required this.fraction,
    required this.colors,
    required this.active,
    required this.seekable,
    this.compact = false,
  });

  final double fraction;
  final List<Color> colors;
  final bool active;
  final bool seekable;
  final bool compact;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: compact ? 20 : 18,
    // Swells and shows its notches smoothly as a drag starts and ends.
    child: TweenAnimationBuilder<double>(
      tween: Tween(end: active ? 1 : 0),
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
      builder: (context, t, _) => CustomPaint(
        painter: _LinePainter(fraction, colors, t, seekable, base: compact ? 11 : 8, ink: PanelInk.of(context)),
      ),
    ),
  );
}

/// A small glass capsule, filled from inside with the clock's gradient up to
/// where the song is: a glossy top, and a glowing tip with a bright cap at the
/// fill's edge. While dragging ([t] → 1) it swells and shows faint notches
/// every 10%. Drawn once per change: nothing animates on its own.
class _LinePainter extends CustomPainter {
  _LinePainter(this.fraction, this.colors, this.t, this.seekable, {this.base = 8, this.ink = Colors.white});

  /// Its glass and cap: white, or dark on a light panel (see PanelInk).
  final Color ink;

  /// The capsule's height at rest.
  final double base;

  final double fraction;
  final List<Color> colors;

  /// 0 at rest, 1 while dragging.
  final double t;

  /// A bright cap at the fill's edge, to grab, only when it can be dragged.
  final bool seekable;

  @override
  void paint(Canvas canvas, Size size) {
    final cy = size.height / 2;
    final h = base + 5.0 * t;
    final outer = RRect.fromRectAndRadius(Rect.fromLTWH(0, cy - h / 2, size.width, h), Radius.circular(h / 2));

    // The glass body: faint fill, a darker inside edge, a hairline rim.
    canvas.drawRRect(outer, Paint()..color = ink.withValues(alpha: 0.07 + 0.03 * t));
    canvas.drawRRect(
      outer.deflate(0.5),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black.withValues(alpha: 0.35), Colors.transparent],
        ).createShader(outer.outerRect),
    );
    canvas.drawRRect(
      outer,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..color = ink.withValues(alpha: 0.18 + 0.1 * t),
    );

    // Notches every 10% while dragging.
    if (t > 0) {
      final notch = Paint()
        ..color = ink.withValues(alpha: 0.18 * t)
        ..strokeWidth = 1;
      for (var i = 1; i < 10; i++) {
        final x = size.width * i / 10;
        canvas.drawLine(Offset(x, cy - h * 0.22), Offset(x, cy + h * 0.22), notch);
      }
    }

    if (fraction <= 0) return;
    const inset = 1.6;
    final inner = outer.deflate(inset);
    final innerH = inner.height;
    // At least round at the start, never past the end.
    final fillW = (inner.width * fraction).clamp(innerH, inner.width);
    final fillRect = Rect.fromLTWH(inner.left, inner.top, fillW, innerH);
    final fill = RRect.fromRectAndRadius(fillRect, Radius.circular(innerH / 2));
    final gradient = colors.length >= 2 ? colors : [colors.first, colors.first];

    canvas.save();
    canvas.clipRRect(fill);
    // The whole gradient spans the capsule: the fill reveals it as it grows.
    canvas.drawRect(fillRect, Paint()..shader = LinearGradient(colors: gradient).createShader(inner.outerRect));
    // Gloss: light along the top half.
    canvas.drawRect(
      Rect.fromLTWH(fillRect.left, fillRect.top, fillRect.width, innerH * 0.55),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [ink.withValues(alpha: 0.45), ink.withValues(alpha: 0)],
        ).createShader(Rect.fromLTWH(fillRect.left, fillRect.top, fillRect.width, innerH * 0.55)),
    );
    // Brighter toward the tip, as if lit from the leading edge.
    canvas.drawRect(
      fillRect,
      Paint()
        ..shader = LinearGradient(
          colors: [Colors.transparent, ink.withValues(alpha: 0.22)],
          stops: const [0.55, 1],
        ).createShader(fillRect),
    );
    canvas.restore();

    // The tip: a soft glow spilling out of the capsule, and a bright cap.
    final tip = Offset(fillRect.right - innerH / 2, cy);
    canvas.drawCircle(
      tip,
      h * (1.1 + 0.4 * t),
      Paint()
        ..color = gradient.last.withValues(alpha: 0.45 + 0.2 * t)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, h * 0.6),
    );
    if (seekable) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(fillRect.right - 2.2, cy), width: 2.4 + 1.2 * t, height: innerH * 0.7),
          const Radius.circular(2),
        ),
        Paint()..color = ink.withValues(alpha: 0.95),
      );
    }
  }

  @override
  bool shouldRepaint(_LinePainter old) =>
      old.fraction != fraction ||
      old.t != t ||
      old.colors != colors ||
      old.seekable != seekable ||
      old.base != base ||
      old.ink != ink;
}

/// Previous, play / pause on a round glass button, next. Shared with the
/// home screen's music widget.
class MediaControls extends StatelessWidget {
  const MediaControls({super.key, required this.media, required this.onCommand});

  final NowPlaying media;
  final void Function(String command, {Duration? position}) onCommand;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      _Button(icon: Glyph.previous, label: 'Previous', onTap: media.canPrevious ? () => onCommand('previous') : null),
      _Button(
        icon: media.playing ? Glyph.pause : Glyph.play,
        label: media.playing ? 'Pause' : 'Play',
        big: true,
        onTap: () => onCommand(media.playing ? 'pause' : 'play'),
      ),
      _Button(icon: Glyph.next, label: 'Next', onTap: media.canNext ? () => onCommand('next') : null),
    ],
  );
}

/// A round glass button that dips when pressed.
class _Button extends StatefulWidget {
  const _Button({required this.icon, required this.label, required this.onTap, this.big = false});

  final Glyph icon;
  final String label;
  final VoidCallback? onTap;
  final bool big;

  @override
  State<_Button> createState() => _ButtonState();
}

class _ButtonState extends State<_Button> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    final size = widget.big ? 50.0 : 42.0;
    return Semantics(
      button: true,
      label: widget.label,
      enabled: enabled,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => setState(() => _down = true) : null,
        onTapUp: enabled ? (_) => setState(() => _down = false) : null,
        onTapCancel: enabled ? () => setState(() => _down = false) : null,
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _down ? 0.86 : 1,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: Container(
            width: size,
            height: size,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: widget.big
                ? BoxDecoration(
                    shape: BoxShape.circle,
                    color: PanelInk.of(context).withValues(alpha: _down ? 0.28 : 0.18),
                    border: Border.all(color: PanelInk.of(context).withValues(alpha: 0.22)),
                  )
                : null,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              transitionBuilder: (child, a) => ScaleTransition(scale: a, child: child),
              child: Center(
                key: ValueKey(widget.icon),
                child: MediaGlyph(
                  widget.icon,
                  size: widget.big ? 26 : 22,
                  color: PanelInk.of(context).withValues(alpha: enabled ? 0.92 : 0.3),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
