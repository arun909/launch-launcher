import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/apps/apps_controller.dart';
import '../../../core/platform/standby_platform.dart';
import '../../../core/widgets/media_glyph.dart';
import '../../app_actions/app_actions_sheet.dart';
import '../../standard_home/home_layout.dart';
import '../../standard_home/home_layout_controller.dart';
import '../../standby/standby_media_tile.dart';
import '../launcher_widgets.dart';
import 'now_playing_controller.dart';

/// The music widget: what's playing on the phone, or on a computer through a
/// link app (Phone Link, KDE Connect…). Two sizes, both the full width of
/// the home screen (narrower grids clamp the 6 columns to theirs):
/// - 6 × 2: a small cover, title, artist (and album) and the app, the glass
///   track line with its times, and previous / play-pause / next: the same
///   parts as the lock screen's media tile (StandbyMediaTile);
/// - 6 × 1: a strip: cover, title and artist, and the controls.
const musicKind = LauncherWidgetKind(
  name: 'music',
  label: 'Music',
  description: 'What’s playing, from any app or a connected computer, with controls',
  icon: Icons.music_note_rounded,
  size: (6, 2),
  // Fits any grid: wider than a 4- or 5-column page, it takes the full width.
  min: (4, 1),
  max: (6, 2),
  sizes: [(6, 1), (6, 2)],
  build: _build,
  customise: showMusicSettings,
  styleOf: _style,
  backdrop: _backdrop,
  interactive: true,
);

Widget _build(BuildContext context, Map<String, dynamic> settings) =>
    MusicWidget(settings: MusicSettings.fromJson(settings));

GroupStyle _style(Map<String, dynamic> settings) => MusicSettings.fromJson(settings).style;

Widget _backdrop(BuildContext context, Map<String, dynamic> settings) {
  final s = MusicSettings.fromJson(settings);
  return s.matchArt ? _ArtTint(light: s.style.isLightSurface) : const SizedBox.shrink();
}

/// One music widget's options (WidgetItem.settings).
@immutable
class MusicSettings {
  const MusicSettings({this.style = GroupStyle.glass, this.matchArt = false, this.showAlbum = true});

  factory MusicSettings.fromJson(Map<String, dynamic> json) => MusicSettings(
    style: panelStyleFrom(json['style']),
    matchArt: json['matchArt'] == true,
    showAlbum: json['showAlbum'] != false,
  );

  /// Its panel: light, dark, glass blur or Material (dark or light), as a
  /// group's.
  final GroupStyle style;

  /// The panel tinted with the cover's colours.
  final bool matchArt;

  /// The album beside the artist.
  final bool showAlbum;

  Map<String, dynamic> toJson() => {'style': style.name, 'matchArt': matchArt, 'showAlbum': showAlbum};

  MusicSettings copyWith({GroupStyle? style, bool? matchArt, bool? showAlbum}) => MusicSettings(
    style: style ?? this.style,
    matchArt: matchArt ?? this.matchArt,
    showAlbum: showAlbum ?? this.showAlbum,
  );
}

/// The track line's colours without a coloured cover: soft white glass.
const _plainAccent = [Color(0xFFFFFFFF), Color(0xFFD9E0EE)];

/// The track line's colours without a coloured cover, on a light panel.
const _plainAccentLight = [Color(0xFF1B1C20), Color(0xFF55585F)];

/// [accent] as drawn on a light panel: each colour a deep shade of itself,
/// so it reads on the pale surface.
List<Color> _accentFor(BuildContext context, List<Color>? art) {
  if (!PanelInk.lightOf(context)) return art ?? _plainAccent;
  if (art == null) return _plainAccentLight;
  return [
    for (final c in art) HSLColor.fromColor(c).withLightness(math.min(HSLColor.fromColor(c).lightness, 0.38)).toColor(),
  ];
}

/// The widget's content, inside its panel's padding.
class MusicWidget extends StatefulWidget {
  const MusicWidget({super.key, this.settings = const MusicSettings()});

  final MusicSettings settings;

  @override
  State<MusicWidget> createState() => _MusicWidgetState();
}

class _MusicWidgetState extends State<MusicWidget> {
  NowPlayingController? _controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Nullable: absent in tests.
    final c = Provider.of<NowPlayingController?>(context, listen: false);
    if (c == _controller) return;
    _controller?.detach();
    _controller = c?..attach();
  }

  @override
  void dispose() {
    _controller?.detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<NowPlayingController?>();
    final media = c?.media;
    final access = c?.hasAccess ?? true;
    final cover = media?.art == null ? null : MemoryImage(media!.art!);
    void command(String name, {Duration? position}) => c?.command(name, position: position);

    return LayoutBuilder(
      builder: (context, box) {
        final size = box.biggest;
        final Widget body;
        if (!access) {
          body = const _Message(title: 'Show what’s playing', subtitle: 'Tap to allow notification access');
        } else if (media == null) {
          body = _Message(
            title: 'Not playing',
            subtitle: 'Play to resume the last player',
            action: _GlassPlay(playing: false, size: math.min(50, size.height), onTap: () => command('play')),
          );
        } else if (size.height < 84) {
          body = _Strip(media: media, cover: cover, onCommand: command);
        } else {
          body = _Player(
            media: media,
            cover: cover,
            accent: _accentFor(context, c?.artPalette),
            album: widget.settings.showAlbum,
            onCommand: command,
          );
        }
        final content = GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: !access ? c?.openAccess : (media == null ? null : () => _openPlayer(context, media)),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: KeyedSubtree(key: ValueKey(body.runtimeType), child: body),
          ),
        );
        if (c == null || !access) return content;
        return _VolumeEdge(controller: c, child: content);
      },
    );
  }

  /// Its app, or the link app for a computer's player.
  void _openPlayer(BuildContext context, NowPlaying media) {
    final apps = Provider.of<AppsController?>(context, listen: false)?.apps ?? const [];
    final app = apps.where((a) => a.packageName == media.package).firstOrNull;
    if (app != null) openApp(context, app);
  }
}

typedef _Command = void Function(String command, {Duration? position});

/// 6 × 2: the cover and the lock screen tile's details (title, artist · app,
/// the glass track line with its times; drag across to move through the
/// song) on top, its glass controls along the foot. Where two rows are
/// short (the denser grids), all in one row, exactly like the lock screen's
/// tile.
class _Player extends StatelessWidget {
  const _Player({
    required this.media,
    required this.cover,
    required this.accent,
    required this.album,
    required this.onCommand,
  });

  final NowPlaying media;
  final ImageProvider? cover;
  final List<Color> accent;
  final bool album;
  final _Command onCommand;

  /// Height from which the controls get a row of their own.
  static const twoRows = 124.0;

  /// The least room the one-row layout takes: in less it's drawn scaled down
  /// evenly rather than squeezed.
  static const least = Size(320, 64);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        if (box.maxHeight >= twoRows) return _stacked(context);
        final w = math.max(box.maxWidth, least.width), h = math.max(box.maxHeight, least.height);
        final row = SizedBox(width: w, height: h, child: _row(context));
        if (w == box.maxWidth && h == box.maxHeight) return row;
        return FittedBox(child: row);
      },
    );
  }

  Widget _row(BuildContext context) {
    return Row(
      children: [
        _Art(cover: cover, size: 56, keyName: media.artKey ?? media.title),
        const SizedBox(width: 12),
        Expanded(
          child: MediaDetails(media: media, accent: accent, onCommand: onCommand, album: album, compact: true),
        ),
        const SizedBox(width: 4),
        MediaControls(media: media, onCommand: onCommand),
      ],
    );
  }

  Widget _stacked(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: Row(
            children: [
              _Art(cover: cover, size: 64, keyName: media.artKey ?? media.title),
              const SizedBox(width: 14),
              Expanded(
                child: MediaDetails(media: media, accent: accent, onCommand: onCommand, album: album, compact: true),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        MediaControls(media: media, onCommand: onCommand),
      ],
    );
  }
}

/// Slide up or down along the widget's right edge to turn the volume up or
/// down: the song's own (a computer's, through a link app) or the phone's
/// music volume. A slim glass gauge shows the level while sliding.
class _VolumeEdge extends StatefulWidget {
  const _VolumeEdge({required this.controller, required this.child});

  final NowPlayingController controller;
  final Widget child;

  /// How wide the strip along the right edge that takes the slide is.
  static const strip = 44.0;

  @override
  State<_VolumeEdge> createState() => _VolumeEdgeState();
}

class _VolumeEdgeState extends State<_VolumeEdge> {
  /// The level as the slide goes, 0 to 1; null when not shown.
  double? _level;
  int _max = 0;
  int _sent = -1;

  /// Distance slid before the volume was read.
  double _pending = 0;
  bool _reading = false;
  Timer? _hide;

  Future<void> _start(DragStartDetails _) async {
    _hide?.cancel();
    _pending = 0;
    _reading = true;
    final (current, max) = await widget.controller.volume();
    _reading = false;
    if (!mounted || max <= 0) return;
    _max = max;
    _sent = current;
    setState(() => _level = current / max);
    _move(_pending);
  }

  void _update(DragUpdateDetails d, double height) {
    // Up is louder; the whole height spans the whole range.
    final delta = -d.delta.dy / math.max(height, 60);
    if (_reading || _level == null) {
      _pending += delta;
      return;
    }
    _move(delta);
  }

  void _move(double delta) {
    final level = ((_level ?? 0) + delta).clamp(0.0, 1.0);
    final step = (level * _max).round();
    if (step != _sent) {
      _sent = step;
      widget.controller.setVolume(step);
      HapticFeedback.selectionClick();
    }
    setState(() => _level = level);
  }

  void _end() {
    _hide?.cancel();
    _hide = Timer(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _level = null);
    });
  }

  @override
  void dispose() {
    _hide?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final level = _level;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(child: widget.child),
            Positioned(
              top: 0,
              bottom: 0,
              right: 0,
              width: math.min(_VolumeEdge.strip, box.maxWidth * 0.4),
              child: GestureDetector(
                // Taps still reach what's under it.
                behavior: HitTestBehavior.translucent,
                onVerticalDragStart: _start,
                onVerticalDragUpdate: (d) => _update(d, box.maxHeight),
                onVerticalDragEnd: (_) => _end(),
                onVerticalDragCancel: _end,
              ),
            ),
            Positioned(
              top: 0,
              bottom: 0,
              right: -2,
              child: IgnorePointer(
                child: AnimatedOpacity(
                  opacity: level == null ? 0 : 1,
                  duration: const Duration(milliseconds: 200),
                  child: Center(
                    child: _VolumeGauge(level: level ?? 0, height: box.maxHeight * 0.86),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// A slim glass capsule filling from the bottom, a speaker above it.
class _VolumeGauge extends StatelessWidget {
  const _VolumeGauge({required this.level, required this.height});

  final double level;
  final double height;

  @override
  Widget build(BuildContext context) {
    final icon = level <= 0
        ? Glyph.volumeOff
        : level < 0.5
        ? Glyph.volumeLow
        : Glyph.volumeHigh;
    final bar = math.max(24.0, height - 22);
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          width: 22,
          height: height,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.28),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: 0.2), width: 0.8),
          ),
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Column(
            children: [
              MediaGlyph(icon, size: 13, color: Colors.white.withValues(alpha: 0.9)),
              const SizedBox(height: 3),
              Expanded(
                child: SizedBox(
                  width: 6,
                  height: bar,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: FractionallySizedBox(
                        heightFactor: level.clamp(0.0, 1.0),
                        widthFactor: 1,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.92),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 6 × 1: the cover, title and artist (one line when short), and
/// previous / play-pause / next.
class _Strip extends StatelessWidget {
  const _Strip({required this.media, required this.cover, required this.onCommand});

  final NowPlaying media;
  final ImageProvider? cover;
  final _Command onCommand;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final h = box.maxHeight;
        final art = math.min(h, 56.0);
        final button = math.min(h, 44.0);
        final twoLines = h >= 44;
        final artist = media.artist?.trim() ?? '';
        final sub = [if (artist.isNotEmpty) artist, ?media.app].join('  ·  ');
        final ink = PanelInk.of(context);
        final title = TextStyle(color: ink, fontSize: 14, fontWeight: FontWeight.w600, height: 1.2);
        final dim = TextStyle(color: ink.withValues(alpha: 0.6), fontSize: 12, height: 1.25);
        final Widget text = twoLines
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(media.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: title),
                  if (sub.isNotEmpty) Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: dim),
                ],
              )
            : Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: media.title, style: title),
                    if (artist.isNotEmpty) TextSpan(text: '  ·  $artist', style: dim),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              );
        return Row(
          children: [
            _Art(cover: cover, size: art, keyName: media.artKey ?? media.title),
            const SizedBox(width: 12),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                layoutBuilder: (current, previous) =>
                    Stack(alignment: Alignment.centerLeft, children: [...previous, ?current]),
                child: KeyedSubtree(key: ValueKey(media.title), child: text),
              ),
            ),
            const SizedBox(width: 6),
            _GlyphButton(
              glyph: Glyph.previous,
              size: button,
              enabled: media.canPrevious,
              onTap: () => onCommand('previous'),
            ),
            _GlassPlay(playing: media.playing, size: button, onTap: () => onCommand(media.playing ? 'pause' : 'play')),
            _GlyphButton(glyph: Glyph.next, size: button, enabled: media.canNext, onTap: () => onCommand('next')),
          ],
        );
      },
    );
  }
}

/// A bare glyph that dips when pressed; dimmed when not [enabled].
class _GlyphButton extends StatefulWidget {
  const _GlyphButton({required this.glyph, required this.size, required this.onTap, this.enabled = true});

  final Glyph glyph;
  final double size;
  final VoidCallback onTap;
  final bool enabled;

  @override
  State<_GlyphButton> createState() => _GlyphButtonState();
}

class _GlyphButtonState extends State<_GlyphButton> {
  bool _down = false;

  void _set(bool down) {
    if (down != _down) setState(() => _down = down);
  }

  @override
  Widget build(BuildContext context) {
    final on = widget.enabled;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: on ? (_) => _set(true) : null,
      onTapUp: on ? (_) => _set(false) : null,
      onTapCancel: () => _set(false),
      onTap: on ? widget.onTap : null,
      child: AnimatedScale(
        scale: _down ? 0.86 : 1,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: SizedBox.square(
          dimension: widget.size,
          child: Center(
            child: MediaGlyph(
              widget.glyph,
              size: widget.size * 0.5,
              color: PanelInk.of(context).withValues(alpha: on ? 0.92 : 0.3),
            ),
          ),
        ),
      ),
    );
  }
}

/// A note, a line or two, and maybe a button, sized to the widget's height.
class _Message extends StatelessWidget {
  const _Message({required this.title, required this.subtitle, this.action});

  final String title;
  final String subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final h = box.maxHeight;
        final twoLines = h >= 44;
        final ink = PanelInk.of(context);
        return Row(
          children: [
            _Art(cover: null, size: math.min(h, 64)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: ink, fontSize: 15, fontWeight: FontWeight.w600, height: 1.2),
                  ),
                  if (twoLines) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: ink.withValues(alpha: 0.6), fontSize: 12.5, height: 1.3),
                    ),
                  ],
                ],
              ),
            ),
            if (action != null) ...[const SizedBox(width: 8), action!],
          ],
        );
      },
    );
  }
}

/// The cover, small and rounded with a fine glass rim, swapped with a short
/// fade when the song changes; a note on frosted glass when there's none.
class _Art extends StatelessWidget {
  const _Art({required this.cover, required this.size, this.keyName = ''});

  final ImageProvider? cover;
  final double size;
  final String keyName;

  @override
  Widget build(BuildContext context) {
    // Decoded at exactly the pixels it's drawn at: crisp, no resampling blur.
    final px = (size * MediaQuery.devicePixelRatioOf(context)).round().clamp(1, 1024);
    final radius = BorderRadius.circular((size * 0.25).clamp(8.0, 16.0));
    final ink = PanelInk.of(context);
    return SizedBox.square(
      dimension: size,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 450),
        switchInCurve: Curves.easeOutCubic,
        transitionBuilder: (child, a) => FadeTransition(
          opacity: a,
          child: ScaleTransition(scale: Tween(begin: 0.9, end: 1.0).animate(a), child: child),
        ),
        child: Container(
          key: ValueKey('$keyName${cover != null}'),
          decoration: BoxDecoration(
            borderRadius: radius,
            color: cover == null ? ink.withValues(alpha: 0.10) : null,
            boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 12, offset: Offset(0, 4))],
            image: cover == null
                ? null
                : DecorationImage(
                    image: ResizeImage(cover!, width: px, height: px),
                    fit: BoxFit.cover,
                    filterQuality: FilterQuality.medium,
                  ),
          ),
          foregroundDecoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(color: ink.withValues(alpha: 0.16), width: 0.8),
          ),
          child: cover == null
              ? Icon(Icons.music_note_rounded, size: size * 0.44, color: ink.withValues(alpha: 0.6))
              : null,
        ),
      ),
    );
  }
}

/// Play / pause on a round glass button, as on the lock screen's tile.
class _GlassPlay extends StatefulWidget {
  const _GlassPlay({required this.playing, required this.size, required this.onTap});

  final bool playing;
  final double size;
  final VoidCallback onTap;

  @override
  State<_GlassPlay> createState() => _GlassPlayState();
}

class _GlassPlayState extends State<_GlassPlay> {
  bool _down = false;

  void _set(bool down) {
    if (down != _down) setState(() => _down = down);
  }

  @override
  Widget build(BuildContext context) {
    final icon = widget.playing ? Glyph.pause : Glyph.play;
    final s = widget.size;
    final ink = PanelInk.of(context);
    final fill = ink.withValues(alpha: _down ? 0.28 : 0.18);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _set(true),
      onTapUp: (_) => _set(false),
      onTapCancel: () => _set(false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _down ? 0.86 : 1,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: ClipOval(
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 6, sigmaY: 6),
            child: Container(
              width: s,
              height: s,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: fill,
                border: Border.all(color: ink.withValues(alpha: 0.22)),
              ),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                transitionBuilder: (child, a) => ScaleTransition(scale: a, child: child),
                child: Center(
                  key: ValueKey(icon),
                  child: MediaGlyph(icon, size: s * 0.5, color: ink.withValues(alpha: 0.92)),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The "Match album colours" tint: the cover's two main colours, deepened,
/// as a soft gradient over the panel; it eases from song to song.
class _ArtTint extends StatelessWidget {
  const _ArtTint({this.light = false});

  /// On a light panel: pale instead of deepened, so its dark text stays
  /// clear.
  final bool light;

  /// See-through and darker, so white text stays clear on it.
  static Color _deepen(Color c, [double value = 0.42]) {
    final hsv = HSVColor.fromColor(c);
    return hsv.withValue(math.min(hsv.value, value)).toColor().withValues(alpha: 0.62);
  }

  /// See-through, soft and light, for dark text.
  static Color _pale(Color c, [double saturation = 0.35]) {
    final hsv = HSVColor.fromColor(c);
    return hsv
        .withSaturation(math.min(hsv.saturation, saturation))
        .withValue(math.max(hsv.value, 0.92))
        .toColor()
        .withValues(alpha: 0.62);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.select<NowPlayingController?, List<Color>?>((n) => n?.media == null ? null : n?.artPalette);
    final from = c == null ? Colors.transparent : (light ? _pale(c.first) : _deepen(c.first));
    final to = c == null
        ? Colors.transparent
        : (light ? _pale(c.length > 1 ? c[1] : c.first, 0.25) : _deepen(c.length > 1 ? c[1] : c.first, 0.32));
    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: from),
      duration: const Duration(milliseconds: 700),
      builder: (context, a, _) => TweenAnimationBuilder<Color?>(
        tween: ColorTween(end: to),
        duration: const Duration(milliseconds: 700),
        builder: (context, b, _) => DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [a ?? Colors.transparent, b ?? Colors.transparent],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Options

/// The music widget's options, for one instance.
Future<void> showMusicSettings(BuildContext context, WidgetItem item) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    barrierColor: Colors.black26,
    builder: (_) => _MusicSettingsSheet(id: item.id),
  );
}

class _MusicSettingsSheet extends StatelessWidget {
  const _MusicSettingsSheet({required this.id});

  final String id;

  @override
  Widget build(BuildContext context) {
    final layout = context.watch<HomeLayoutController>();
    final item = layout.findWidget(id);
    if (item == null) return const SizedBox.shrink();
    final s = MusicSettings.fromJson(item.settings);
    void set(MusicSettings next) => layout.updateWidgetSettings(id, next.toJson());
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Music', style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              'Full width, in two heights: a player (2 rows) or a strip (1 row). Drag its handles to switch.',
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70),
            ),
            const SizedBox(height: 20),
            Text('Background', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            PanelStylePicker(
              value: s.style,
              onChanged: (v) => set(s.copyWith(style: v)),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Match album colours'),
              subtitle: const Text('Tints the background with the cover’s colours'),
              value: s.matchArt,
              onChanged: (v) => set(s.copyWith(matchArt: v)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Album name'),
              subtitle: const Text('Beside the artist (2 rows)'),
              value: s.showAlbum,
              onChanged: (v) => set(s.copyWith(showAlbum: v)),
            ),
          ],
        ),
      ),
    );
  }
}
