import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/apps/apps_controller.dart';
import '../../../core/models/app_info.dart';
import '../../../core/platform/device_stats_platform.dart';
import '../../../core/platform/window_blur_platform.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/color_wheel.dart';
import '../../standard_home/home_layout.dart';
import '../../standard_home/home_layout_controller.dart';
import '../clock/wallpaper_colors.dart';
import '../launcher_widgets.dart';
import '../stats/device_stats_controller.dart';

/// The activity widget: today's screen time and unlocks, and the most used
/// apps (all restart at midnight), on two pages swiped sideways:
/// 1. screen time as a gradient ring (of the daily limit, or of the day so
///    far when there's none) with the unlocks beside or under it;
/// 2. the four most used apps as a readout: rank, icon, name, a bar of lit
///    display segments and the time.
///
/// Behind both, a layered wave rises with the usage and rolls faster as it
/// nears the limit; amber from 80% of a limit, red past it.
///
/// Flat, vivid two-colour palettes (a preset, any colour from the wheel, or
/// the wallpaper's), on a neutral dark or light surface or the launcher's
/// panel. Any size from 2 × 1 to 6 × 3: one row is a strip, a wide one has
/// the ring beside its figures, anything squarer the ring centred.
const activityKind = LauncherWidgetKind(
  name: 'activity',
  label: 'Activity',
  description: 'Screen time as a ring with a daily limit, unlocks and your most used apps',
  icon: Icons.data_usage_rounded,
  size: (4, 2),
  min: (2, 1),
  max: (6, 3),
  build: _build,
  customise: showActivitySettings,
  panelOf: _isGlass,
  styleOf: _panelStyleOf,
  backdrop: _backdrop,
  interactive: true,
);

/// Its own surface, or the launcher's panel ([_panelStyleOf]: glass blur
/// unless picked otherwise). Stored as 'glass', its name when the panel was
/// always glass.
enum ActivitySurface { dark, light, glass }

/// Where its colours come from (settings['colourMode']).
enum ActivityColourMode { palette, custom, wallpaper }

/// Stored as 'surface'; older instances kept a 'light' flag.
ActivitySurface _surfaceOf(Map<String, dynamic> settings) =>
    ActivitySurface.values.asNameMap()[settings['surface']] ??
    (settings['light'] == true ? ActivitySurface.light : ActivitySurface.dark);

bool _isGlass(Map<String, dynamic> settings) => _surfaceOf(settings) == ActivitySurface.glass;

/// The panel it sits on with [ActivitySurface.glass] (WidgetItem.settings['style']):
/// any of [panelStyles], glass blur by default.
GroupStyle _panelStyleOf(Map<String, dynamic> settings) => panelStyleFrom(settings['style']);

/// The daily screen-time limit (settings['limitMinutes']); null: none.
Duration? _limitOf(Map<String, dynamic> settings) => switch (settings['limitMinutes']) {
  final int m when m > 0 => Duration(minutes: m),
  _ => null,
};

/// The background wave (settings['wave']); on by default.
bool _waveOf(Map<String, dynamic> settings) => settings['wave'] != false;

/// One flat colour instead of the gradient (settings['single']).
bool _singleOf(Map<String, dynamic> settings) => settings['single'] == true;

ActivityColourMode _modeOf(Map<String, dynamic> settings) =>
    ActivityColourMode.values.asNameMap()[settings['colourMode']] ?? ActivityColourMode.palette;

/// Vivid, flat two-colour palettes: the ring sweeps from the first to the
/// second. Names shared with the old single-colour seeds, so a widget keeps
/// its hue ('seed').
const _palettes = <String, (Color, Color)>{
  'aqua': (Color(0xFF00E5FF), Color(0xFF2979FF)),
  'teal': (Color(0xFF1DE9B6), Color(0xFF00B8D4)),
  'green': (Color(0xFFC6FF00), Color(0xFF00E676)),
  'amber': (Color(0xFFFFD740), Color(0xFFFF6D00)),
  'rose': (Color(0xFFFF4081), Color(0xFFFF9E80)),
  'violet': (Color(0xFFD500F9), Color(0xFF651FFF)),
  'blue': (Color(0xFF448AFF), Color(0xFF7C4DFF)),
  'ice': (Color(0xFFE0F7FA), Color(0xFF80D8FF)),
};

/// The colours for these settings, given the wallpaper's (null while
/// unknown or colourless: then the palette's).
(Color, Color) _coloursOf(Map<String, dynamic> settings, List<Color>? wallpaper) {
  final pair = _pairOf(settings, wallpaper);
  return _singleOf(settings) ? (pair.$1, pair.$1) : pair;
}

/// The gradient's two colours for these settings.
(Color, Color) _pairOf(Map<String, dynamic> settings, List<Color>? wallpaper) {
  final palette = _palettes[settings['seed']] ?? _palettes['aqua']!;
  switch (_modeOf(settings)) {
    case ActivityColourMode.palette:
      return palette;
    case ActivityColourMode.custom:
      final c = switch (settings['color']) {
        final int v => Color(v),
        _ => palette.$1,
      };
      return (c, _partner(c));
    case ActivityColourMode.wallpaper:
      if (wallpaper == null || wallpaper.isEmpty) return palette;
      return (wallpaper.first, wallpaper.length > 1 ? wallpaper[1] : _partner(wallpaper.first));
  }
}

/// A second colour for one: its hue turned a little, as vivid.
Color _partner(Color c) {
  final hsv = HSVColor.fromColor(c);
  return hsv.withHue((hsv.hue + 38) % 360).withSaturation(math.min(1, hsv.saturation + 0.1)).toColor();
}

/// The wallpaper's main colours when [settings] use them, then [builder].
/// They're worked out once per wallpaper and shared (wallpaperColors).
Widget _withWallpaper(
  BuildContext context,
  Map<String, dynamic> settings,
  Widget Function(List<Color>? wallpaper) builder,
) {
  if (_modeOf(settings) != ActivityColourMode.wallpaper) return builder(null);
  final image = context.select<WindowBlurPlatform?, ui.Image?>((p) => p?.wallpaper);
  if (image == null) return builder(null);
  return FutureBuilder<List<Color>?>(future: wallpaperColors(image), builder: (context, snap) => builder(snap.data));
}

Widget _build(BuildContext context, Map<String, dynamic> settings) => _withWallpaper(
  context,
  settings,
  (wallpaper) => ActivityWidget(
    colours: _coloursOf(settings, wallpaper),
    surface: _surfaceOf(settings),
    limit: _limitOf(settings),
    wave: _waveOf(settings),
  ),
);

/// On the launcher's panel the wave fills the whole panel, under the
/// padding, so it's drawn here rather than by the widget.
Widget _backdrop(BuildContext context, Map<String, dynamic> settings) {
  if (!_isGlass(settings) || !_waveOf(settings)) return const SizedBox.shrink();
  final stats = context.watch<DeviceStatsController?>()?.stats;
  final usage = _Usage(stats: stats, limit: _limitOf(settings));
  if (!usage.known) return const SizedBox.shrink();
  return _withWallpaper(context, settings, (wallpaper) {
    final (a, b) = usage.colours(_coloursOf(settings, wallpaper));
    return _Wave(level: usage.level, a: a, b: b, over: usage.over, light: _panelStyleOf(settings).isLightSurface);
  });
}

/// The numerals' typeface: geometric, with even figures.
const _numerals = 'ClockOutfit';

class ActivityWidget extends StatefulWidget {
  const ActivityWidget({
    super.key,
    this.colours = (const Color(0xFF00E5FF), const Color(0xFF2979FF)),
    this.surface = ActivitySurface.dark,
    this.limit,
    this.wave = true,
    this.stats,
    this.now,
  });

  /// The ring's gradient, first to second (before the limit's warning
  /// colours take over).
  final (Color, Color) colours;

  /// Dark or light, or on the launcher's panel (which draws the panel and,
  /// through the kind's backdrop, the wave).
  final ActivitySurface surface;

  /// The daily screen-time limit; null: none.
  final Duration? limit;

  /// The background wave.
  final bool wave;

  /// Fixed stats instead of the phone's (previews, tests).
  final DeviceStats? stats;

  /// Fixed time of day (tests).
  final DateTime? now;

  @override
  State<ActivityWidget> createState() => _ActivityWidgetState();
}

class _ActivityWidgetState extends State<ActivityWidget> {
  DeviceStatsController? _controller;
  final _pages = PageController();
  int _page = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final c = widget.stats != null ? null : Provider.of<DeviceStatsController?>(context, listen: false);
    if (c == _controller) return;
    _controller?.detach();
    _controller = c?..attach();
  }

  @override
  void dispose() {
    _controller?.detach();
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.stats != null ? null : context.watch<DeviceStatsController?>();
    final stats = widget.stats ?? controller?.stats;
    final apps = context.watch<AppsController?>();
    final glass = widget.surface == ActivitySurface.glass;
    final light = glass ? PanelInk.lightOf(context) : widget.surface == ActivitySurface.light;
    final ink = glass ? PanelInk.of(context) : (light ? const Color(0xFF14161A) : Colors.white);

    final byPackage = <String, AppInfo>{};
    for (final a in apps?.apps ?? const <AppInfo>[]) {
      byPackage.putIfAbsent(a.packageName, () => a);
    }
    final top = <(AppInfo, Duration)>[
      for (final u in stats?.topApps ?? const <AppUsage>[])
        if (byPackage[u.package] case final app?) (app, u.time),
    ].take(4).toList();

    final usage = _Usage(stats: stats, limit: widget.limit, now: widget.now);
    final (a, b) = usage.colours(widget.colours);
    final look = _Look(a: a, b: b, ink: ink, light: light);
    final data = _Data(
      usage: usage,
      look: look,
      top: top,
      onAllow: controller?.openUsageAccess,
      onOpen: apps == null
          ? null
          : (app) {
              HapticFeedback.selectionClick();
              apps.launch(app);
            },
    );
    final theme = Theme.of(context).copyWith(
      colorScheme: ColorScheme.fromSeed(seedColor: a, brightness: light ? Brightness.light : Brightness.dark),
    );

    return Theme(
      data: theme,
      child: LayoutBuilder(
        builder: (context, box) {
          final w = box.maxWidth, h = box.maxHeight;
          final strip = h < 84;
          // Squarer than ~1.6 : 1 (2 × 2, 3 × 2, 2 × 3, 4 × 3…): the ring centred.
          final square = !strip && (w < 250 || w / h < 1.6);
          final radius = strip ? h / 2 : (h * 0.16).clamp(18.0, 28.0);
          final pad = strip ? 8.0 : (h * 0.08).clamp(10.0, 14.0);

          final pages = PageView(
            controller: _pages,
            onPageChanged: (i) {
              HapticFeedback.selectionClick();
              setState(() => _page = i);
            },
            children: [
              _OverviewPage(data: data, strip: strip, square: square),
              _AppsPage(data: data, strip: strip),
            ],
          );
          final dots = _Dots(page: _page, look: look, vertical: strip);
          Widget frame(Widget pages, Widget dots) => strip
              ? Row(
                  children: [
                    Expanded(child: pages),
                    const SizedBox(width: 6),
                    dots,
                  ],
                )
              : Column(
                  children: [
                    Expanded(child: pages),
                    const SizedBox(height: 6),
                    dots,
                  ],
                );
          final body = frame(pages, dots);

          // What the wave covers on the first page, in the accent: the same
          // page, tinted, moving with the pages as they're swiped.
          final tinted = _Data(usage: usage, look: look.submerged, top: top, onAllow: null, onOpen: null);
          final underWave = frame(
            ClipRect(
              child: LayoutBuilder(
                builder: (context, page) => AnimatedBuilder(
                  animation: _pages,
                  builder: (context, child) {
                    final at = _pages.hasClients && _pages.position.haveDimensions
                        ? _pages.page ?? 0
                        : _page.toDouble();
                    return Transform.translate(offset: Offset(-at * page.maxWidth, 0), child: child);
                  },
                  child: _OverviewPage(data: tinted, strip: strip, square: square),
                ),
              ),
            ),
            Opacity(opacity: 0, child: dots),
          );

          // The launcher draws the panel (and the wave, as its backdrop).
          if (glass) return body;

          // On the home screen: fill the same frame as a container (its
          // corners, reaching out over its padding), so it lines up with
          // folders and containers. Elsewhere (previews): its own inset box.
          final fits = LauncherWidgetFrame.maybeOf(context);
          final insets = fits?.insets ?? EdgeInsets.all(pad);
          final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(fits?.radius ?? radius));
          final surface = DecoratedBox(
            decoration: ShapeDecoration(
              color: light ? const Color(0xFFF6F7F9) : const Color(0xFF0E1013),
              shape: shape,
              shadows: const [BoxShadow(color: Color(0x33000000), blurRadius: 12, offset: Offset(0, 4))],
            ),
            child: ClipPath(
              clipper: ShapeBorderClipper(shape: shape),
              child: widget.wave && usage.known
                  ? _Wave(
                      level: usage.level,
                      a: a,
                      b: b,
                      over: usage.over,
                      light: light,
                      content: Padding(padding: insets, child: body),
                      submerged: Padding(padding: insets, child: underWave),
                    )
                  : Padding(padding: insets, child: body),
            ),
          );
          if (fits == null) return surface;
          return Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: -insets.left,
                top: -insets.top,
                right: -insets.right,
                bottom: -insets.bottom,
                child: surface,
              ),
            ],
          );
        },
      ),
    );
  }
}

/// The colours everything is drawn in.
class _Look {
  const _Look({required this.a, required this.b, required this.ink, required this.light});

  /// The ring's gradient.
  final Color a, b;

  /// Text: white, or near-black on a light surface.
  final Color ink;
  final bool light;

  Color get sub => ink.withValues(alpha: 0.6);
  Color get track => ink.withValues(alpha: light ? 0.09 : 0.1);

  /// The look under the wave: type and tracks in the accent (lifted towards
  /// white on dark, deepened on light), so what's covered takes its colour.
  _Look get submerged {
    final hsl = HSLColor.fromColor(Color.lerp(a, b, 0.35)!);
    final inked = light
        ? hsl.withLightness(math.min(hsl.lightness, 0.34)).toColor()
        : Color.lerp(hsl.withLightness(math.max(hsl.lightness, 0.62)).toColor(), Colors.white, 0.25)!;
    return _Look(a: a, b: b, ink: inked, light: light);
  }

  /// [a] made to read as text: deepened on a light surface.
  Color get accentText {
    if (!light) return a;
    final hsl = HSLColor.fromColor(a);
    return hsl.withLightness(math.min(hsl.lightness, 0.42)).toColor();
  }
}

/// Today's screen time against the limit, or against the day so far.
class _Usage {
  _Usage({required DeviceStats? stats, required this.limit, DateTime? now})
    : screen = stats != null && stats.usageAccess ? stats.screenOn : null,
      unlocks = stats != null && stats.usageAccess ? stats.unlocks : null,
      access = stats == null || stats.usageAccess,
      _now = now ?? DateTime.now();

  final Duration? screen;
  final int? unlocks;
  final bool access;
  final Duration? limit;
  final DateTime _now;

  bool get known => screen != null;

  Duration get _sinceMidnight {
    final d = _now.difference(DateTime(_now.year, _now.month, _now.day));
    return d < const Duration(minutes: 1) ? const Duration(minutes: 1) : d;
  }

  /// Screen time over the limit (can pass 1), else over the day so far.
  double get level {
    final s = screen;
    if (s == null) return 0;
    final of = limit ?? _sinceMidnight;
    return s.inSeconds / of.inSeconds;
  }

  /// Past the limit.
  bool get over => limit != null && level >= 1;

  /// [level] as a whole percentage, at most 100 without a limit.
  int get percent => limit == null ? (level * 100).round().clamp(0, 100) : (level * 100).round();

  /// [own] colours, or amber from 80% of a limit and red past it.
  /// A single colour ([own]'s two the same) keeps to one in the warnings too.
  (Color, Color) colours((Color, Color) own) {
    if (limit == null || level < 0.8) return own;
    final single = own.$1 == own.$2;
    if (level < 1) {
      return single
          ? (const Color(0xFFFFAB00), const Color(0xFFFFAB00))
          : (const Color(0xFFFFD740), const Color(0xFFFF9100));
    }
    return single
        ? (const Color(0xFFFF2E55), const Color(0xFFFF2E55))
        : (const Color(0xFFFF5370), const Color(0xFFFF1744));
  }

  /// How far from the limit, either way; null without a limit.
  Duration? get gap {
    final l = limit, s = screen;
    if (l == null || s == null) return null;
    return (l - s).abs();
  }
}

/// What both pages draw from.
class _Data {
  const _Data({
    required this.usage,
    required this.look,
    required this.top,
    required this.onAllow,
    required this.onOpen,
  });

  final _Usage usage;
  final _Look look;
  final List<(AppInfo, Duration)> top;
  final Future<void> Function()? onAllow;
  final void Function(AppInfo app)? onOpen;

  String get unlocksText => usage.access ? (usage.unlocks?.toString() ?? '—') : '—';
}

/// "3d 4h", "5h 12m", "42m"; "—" when unknown.
String formatDuration(Duration? d) {
  if (d == null) return '—';
  if (d.inDays > 0) return '${d.inDays}d ${d.inHours % 24}h';
  return _durationText(d);
}

/// "1h 12m", "2h", "45m".
String _durationText(Duration d) {
  final h = d.inHours, m = d.inMinutes % 60;
  if (h == 0) return '${m}m';
  return m == 0 ? '${h}h' : '${h}h ${m}m';
}

const _tabular = [FontFeature.tabularFigures()];

/// A duration with big numbers and small units: "2h 14m" as 2 h 14 m.
class _Time extends StatelessWidget {
  const _Time(this.duration, {required this.size, required this.color, this.unitColor});

  final Duration? duration;
  final double size;
  final Color color;
  final Color? unitColor;

  @override
  Widget build(BuildContext context) {
    final big = TextStyle(
      fontFamily: _numerals,
      fontSize: size,
      fontWeight: FontWeight.w600,
      height: 1,
      letterSpacing: -size * 0.03,
      color: color,
      fontFeatures: _tabular,
    );
    final small = big.copyWith(
      fontSize: size * 0.64,
      fontWeight: FontWeight.w500,
      color: unitColor ?? color,
      letterSpacing: 0,
    );
    // A hair of room between a figure and its unit.
    final hair = big.copyWith(fontSize: size * 0.12);
    final d = duration;
    final List<InlineSpan> spans;
    if (d == null) {
      spans = [TextSpan(text: '—', style: big)];
    } else {
      final h = d.inHours, m = d.inMinutes % 60;
      spans = [
        if (h > 0) ...[
          TextSpan(text: '$h', style: big),
          TextSpan(text: ' ', style: hair),
          TextSpan(text: 'h', style: small),
          if (m > 0) TextSpan(text: '  ', style: small),
        ],
        if (h == 0 || m > 0) ...[
          TextSpan(text: h > 0 ? m.toString().padLeft(2, '0') : '$m', style: big),
          TextSpan(text: ' ', style: hair),
          TextSpan(text: 'm', style: small),
        ],
      ];
    }
    return Text.rich(TextSpan(children: spans), maxLines: 1, textScaler: TextScaler.noScaling);
  }
}

/// A small label in the widget's secondary ink.
TextStyle _labelStyle(_Look look, double size) => TextStyle(
  fontFamily: _numerals,
  fontSize: size,
  fontWeight: FontWeight.w500,
  height: 1.15,
  letterSpacing: 0.2,
  color: look.sub,
);

/// A plain figure ("42") in the numerals' face.
TextStyle _figureStyle(Color color, double size) => TextStyle(
  fontFamily: _numerals,
  fontSize: size,
  fontWeight: FontWeight.w600,
  height: 1,
  color: color,
  fontFeatures: _tabular,
);

// ---- Page 1: screen time and unlocks ---------------------------------------

class _OverviewPage extends StatelessWidget {
  const _OverviewPage({required this.data, required this.strip, required this.square});

  final _Data data;
  final bool strip;
  final bool square;

  @override
  Widget build(BuildContext context) {
    final u = data.usage;
    final look = data.look;
    if (!u.access) return _AllowButton(onAllow: data.onAllow);

    if (strip) {
      return LayoutBuilder(
        builder: (context, box) {
          final h = box.maxHeight;
          final big = (h * 0.4).clamp(16.0, 22.0);
          return Row(
            children: [
              SizedBox.square(
                dimension: h,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _Ring(progress: u.level, a: look.a, b: look.b, track: look.track),
                    Center(
                      child: Text(
                        '${u.percent}%',
                        textScaler: TextScaler.noScaling,
                        style: _hudStyle(look.ink, (h * 0.2).clamp(8.0, 11.0), weight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _Stat(
                  value: _Time(u.screen, size: big, color: look.ink, unitColor: look.sub),
                  caption: u.limit == null ? 'SCREEN TIME' : _limitCaption(u),
                  look: look,
                  captionColor: u.over ? look.accentText : null,
                ),
              ),
              // A narrow strip (2 × 1, 3 × 1) keeps to the time.
              if (box.maxWidth >= 230) ...[
                _Stat(
                  value: Text(data.unlocksText, textScaler: TextScaler.noScaling, style: _figureStyle(look.ink, big)),
                  caption: 'UNLOCKS',
                  look: look,
                  end: true,
                ),
                const SizedBox(width: 6),
              ],
            ],
          );
        },
      );
    }

    final dial = _TimeDial(data: data);
    if (square) {
      return Column(
        children: [
          Expanded(child: dial),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(data.unlocksText, textScaler: TextScaler.noScaling, style: _figureStyle(look.ink, 15)),
                const SizedBox(width: 6),
                Text('UNLOCKS', textScaler: TextScaler.noScaling, style: _hudStyle(look.sub, 10)),
              ],
            ),
          ),
        ],
      );
    }

    // Wide: the dial on the left; unlocks and the limit (or the share of the
    // day) beside it.
    return LayoutBuilder(
      builder: (context, box) {
        final size = (box.maxHeight * 0.22).clamp(20.0, 30.0);
        return Row(
          children: [
            AspectRatio(aspectRatio: 1, child: dial),
            SizedBox(width: box.maxWidth * 0.08),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Stat(
                    value: Text(
                      data.unlocksText,
                      textScaler: TextScaler.noScaling,
                      style: _figureStyle(look.ink, size),
                    ),
                    caption: 'UNLOCKS',
                    look: look,
                  ),
                  SizedBox(height: box.maxHeight * 0.12),
                  if (u.gap == null)
                    _Stat(
                      value: Text(
                        '${u.percent}%',
                        textScaler: TextScaler.noScaling,
                        style: _figureStyle(look.ink, size),
                      ),
                      caption: 'OF YOUR DAY',
                      look: look,
                    )
                  else
                    _Stat(
                      value: _Time(u.gap, size: size, color: u.over ? look.accentText : look.ink, unitColor: look.sub),
                      caption: _limitCaption(u),
                      look: look,
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// "LEFT OF 3H" / "OVER 3H LIMIT".
String _limitCaption(_Usage u) {
  final l = _durationText(u.limit!).toUpperCase();
  return u.over ? 'OVER $l LIMIT' : 'LEFT OF $l';
}

/// The screen-time ring with the time and a caption inside.
class _TimeDial extends StatelessWidget {
  const _TimeDial({required this.data});

  final _Data data;

  @override
  Widget build(BuildContext context) {
    final u = data.usage;
    final look = data.look;
    final caption = switch (u.limit) {
      final l? => 'OF ${_durationText(l).toUpperCase()}',
      null => 'SCREEN TIME',
    };
    return Semantics(
      label: 'Screen time today: ${formatDuration(u.screen)}, ${caption.toLowerCase()}',
      child: LayoutBuilder(
        builder: (context, box) {
          final d = math.min(box.maxWidth, box.maxHeight);
          return Center(
            child: SizedBox.square(
              dimension: d,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _Ring(progress: u.level, a: look.a, b: look.b, track: look.track),
                  Padding(
                    padding: EdgeInsets.all(d * 0.17),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: _Time(u.screen, size: d * 0.2, color: look.ink, unitColor: look.sub),
                        ),
                        SizedBox(height: d * 0.055),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            caption,
                            maxLines: 1,
                            textScaler: TextScaler.noScaling,
                            style: _hudStyle(look.sub, (d * 0.07).clamp(8.0, 11.0)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// A figure over a small spaced-capitals caption.
class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.caption, required this.look, this.captionColor, this.end = false});

  final Widget value;
  final String caption;
  final _Look look;
  final Color? captionColor;

  /// Aligned to the right.
  final bool end;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: caption.toLowerCase(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: end ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          FittedBox(fit: BoxFit.scaleDown, child: value),
          const SizedBox(height: 6),
          Text(
            caption,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.fade,
            textScaler: TextScaler.noScaling,
            style: _hudStyle(captionColor ?? look.sub, 10),
          ),
        ],
      ),
    );
  }
}

// ---- Page 2: most used apps ------------------------------------------------

class _AppsPage extends StatelessWidget {
  const _AppsPage({required this.data, required this.strip});

  final _Data data;
  final bool strip;

  @override
  Widget build(BuildContext context) {
    if (!data.usage.access) return _AllowButton(onAllow: data.onAllow);
    if (data.top.isEmpty) return _Empty(look: data.look);
    final look = data.look;
    // Bars against the most used app, so the leader is a full bar.
    final most = data.top.first.$2.inSeconds.clamp(1, 1 << 30);
    return LayoutBuilder(
      builder: (context, box) {
        if (strip) {
          final fit = (box.maxWidth / 84).floor().clamp(1, 4);
          return Row(
            children: [
              for (final (app, time) in data.top.take(fit))
                Expanded(
                  child: _StripApp(app: app, time: time, fill: time.inSeconds / most, look: look, onOpen: data.onOpen),
                ),
            ],
          );
        }
        final header = box.maxHeight >= 150;
        // Rows at least ~32dp so the icons stay big: a short widget shows
        // three (or fewer) apps rather than squeeze four. At most 44dp each,
        // centred as a block.
        final room = box.maxHeight - (header ? 22 : 0);
        final rows = (room / 32).floor().clamp(1, data.top.length);
        final rowH = math.min(room / rows, 44.0);
        // The faint ranks go when the longest name wouldn't fit beside them.
        var longest = 0.0;
        for (final (app, _) in data.top.take(rows)) {
          final tp = TextPainter(
            text: TextSpan(text: app.label.toUpperCase(), style: _hudStyle(look.ink, _AppRow.textFor(rowH))),
            textDirection: TextDirection.ltr,
            textScaler: TextScaler.noScaling,
            maxLines: 1,
          )..layout();
          longest = math.max(longest, tp.width);
          tp.dispose();
        }
        final numbered = box.maxWidth - _AppRow.fixedWidth(rowH, numbered: true) >= longest;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (header) ...[_Header(look: look, total: data.usage.screen), const SizedBox(height: 10)],
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (i, (app, time)) in data.top.take(rows).indexed)
                    SizedBox(
                      height: rowH,
                      child: _AppRow(
                        rank: i + 1,
                        app: app,
                        time: time,
                        fill: time.inSeconds / most,
                        look: look,
                        name: box.maxWidth >= 230,
                        numbered: numbered,
                        onOpen: data.onOpen,
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// "MOST USED ───────── 2h 30m": a HUD caption with a hairline rule.
class _Header extends StatelessWidget {
  const _Header({required this.look, required this.total});

  final _Look look;
  final Duration? total;

  @override
  Widget build(BuildContext context) {
    final style = _hudStyle(look.sub, 10);
    return Row(
      children: [
        Text('MOST USED', style: style, textScaler: TextScaler.noScaling),
        const SizedBox(width: 8),
        Expanded(child: Container(height: 1, color: look.track)),
        if (total != null) ...[
          const SizedBox(width: 8),
          Text(formatDuration(total).toUpperCase(), style: style, textScaler: TextScaler.noScaling),
        ],
      ],
    );
  }
}

/// The page's lettering: Space Grotesk in spaced capitals, like a readout.
TextStyle _hudStyle(Color color, double size, {FontWeight weight = FontWeight.w500}) => TextStyle(
  fontFamily: 'ClockSpaceGrotesk',
  fontSize: size,
  fontWeight: weight,
  height: 1,
  letterSpacing: size * 0.1,
  color: color,
  fontFeatures: _tabular,
);

/// One app as a readout line: rank, icon, name, a segment bar and its time.
/// Narrower widgets drop the name, then the rank. Tap opens the app.
class _AppRow extends StatelessWidget {
  const _AppRow({
    required this.rank,
    required this.app,
    required this.time,
    required this.fill,
    required this.look,
    required this.name,
    required this.numbered,
    required this.onOpen,
  });

  /// The lettering's size in a row [h] tall.
  static double textFor(double h) => (h * 0.3).clamp(10.0, 12.5);

  /// The icon's size in a row [h] tall.
  static double iconFor(double h) => (h * 0.84).clamp(18.0, 38.0);

  /// The ten-dot bar's width with lettering [text].
  static double barFor(double text) => (text * 7.8).clamp(78.0, 96.0);

  /// Everything in a named row but the name: rank (when [numbered]), icon,
  /// gaps, bar and time.
  static double fixedWidth(double h, {required bool numbered}) {
    final text = textFor(h), icon = iconFor(h);
    return (numbered ? text * 2.2 : 0) + icon * 1.45 + 10 + barFor(text) + 12 + text * 4.8;
  }

  final int rank;
  final AppInfo app;
  final Duration time;

  /// Its time over the most used app's, 0–1.
  final double fill;
  final _Look look;
  final bool name;
  final bool numbered;

  final void Function(AppInfo app)? onOpen;

  @override
  Widget build(BuildContext context) {
    return _Tappable(
      onTap: onOpen == null ? null : () => onOpen!(app),
      label: '${app.label}: ${_durationText(time)}',
      radius: 8,
      child: LayoutBuilder(
        builder: (context, box) {
          final h = box.maxHeight;
          final icon = iconFor(h);
          final text = textFor(h);
          // Ten dots, ~7dp apart: the same short bar on every row.
          final bar = SizedBox(
            width: barFor(text),
            height: 5.5,
            child: _Segments(fill: fill, look: look),
          );
          return Row(
            children: [
              if (numbered)
                SizedBox(
                  width: text * 2.2,
                  child: Text(
                    rank.toString().padLeft(2, '0'),
                    textScaler: TextScaler.noScaling,
                    style: _hudStyle(look.ink.withValues(alpha: 0.35), text * 0.9),
                  ),
                ),
              AppIcon(app: app, size: icon),
              SizedBox(width: icon * 0.45),
              if (name) ...[
                Expanded(
                  child: Text(
                    app.label.toUpperCase(),
                    maxLines: 1,
                    softWrap: false,
                    // The readout face has no "…".
                    overflow: TextOverflow.fade,
                    textScaler: TextScaler.noScaling,
                    style: _hudStyle(look.ink.withValues(alpha: 0.86), text),
                  ),
                ),
                const SizedBox(width: 10),
                bar,
              ] else
                // No name (a narrow widget): the bar shrinks to the room left.
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, room) => Align(
                      alignment: Alignment.centerRight,
                      child: SizedBox(
                        width: math.min(room.maxWidth, barFor(text)),
                        height: 5.5,
                        child: _Segments(fill: fill, look: look),
                      ),
                    ),
                  ),
                ),
              const SizedBox(width: 12),
              SizedBox(
                width: text * 4.8,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: _Time(time, size: text * 1.2, color: look.ink, unitColor: look.sub),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// A strip's app: the icon, its time over a short segment bar.
class _StripApp extends StatelessWidget {
  const _StripApp({
    required this.app,
    required this.time,
    required this.fill,
    required this.look,
    required this.onOpen,
  });

  final AppInfo app;
  final Duration time;
  final double fill;
  final _Look look;
  final void Function(AppInfo app)? onOpen;

  @override
  Widget build(BuildContext context) {
    return _Tappable(
      onTap: onOpen == null ? null : () => onOpen!(app),
      label: '${app.label}: ${_durationText(time)}',
      radius: 12,
      child: LayoutBuilder(
        builder: (context, box) {
          final icon = (box.maxHeight * 0.82).clamp(20.0, 42.0);
          return Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppIcon(app: app, size: icon),
                  const SizedBox(width: 7),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _Time(time, size: 14, color: look.ink, unitColor: look.sub),
                      const SizedBox(height: 4),
                      SizedBox(
                        width: 56,
                        height: 4,
                        child: _Segments(fill: fill, look: look),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// A bar of display segments, the first [fill] (0–1) of them lit in the
/// gradient's colours, the rest dim. They light up in turn when it's shown
/// or changes. Flat, crisp, no glow.
class _Segments extends StatelessWidget {
  const _Segments({required this.fill, required this.look});

  final double fill;
  final _Look look;

  /// How many dots, whatever the width.
  static const count = 10;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: fill.clamp(0.0, 1.0)),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      builder: (context, f, _) => CustomPaint(painter: _SegmentsPainter(f, look.a, look.b, look.track, count)),
    );
  }
}

class _SegmentsPainter extends CustomPainter {
  _SegmentsPainter(this.fill, this.a, this.b, this.dim, this.count);

  final double fill;
  final Color a, b, dim;
  final int count;

  @override
  void paint(Canvas canvas, Size size) {
    // Exactly [count] round dots as tall as the bar, spread evenly across it.
    // Smaller on a short bar, so they never run together.
    final pitch = count == 1 ? size.width : size.width / (count - 0.4);
    final d = math.min(size.height, pitch * 0.6);
    final step = count == 1 ? 0.0 : (size.width - d) / (count - 1);
    // At least one lit, so the least used app still shows.
    final lit = fill <= 0 ? 0 : math.max(1, (fill * count).round());
    final paint = Paint();
    for (var i = 0; i < count; i++) {
      paint.color = i < lit ? Color.lerp(a, b, count == 1 ? 0 : i / (count - 1))! : dim;
      canvas.drawCircle(Offset(d / 2 + i * step, size.height / 2), d / 2, paint);
    }
  }

  @override
  bool shouldRepaint(_SegmentsPainter old) =>
      old.fill != fill || old.a != a || old.b != b || old.dim != dim || old.count != count;
}

// ---- Drawing ---------------------------------------------------------------

/// A progress ring from twelve o'clock, round-capped, sweeping from [a] to
/// [b], easing to [progress] (0–1; past 1 is a full ring).
class _Ring extends StatelessWidget {
  const _Ring({required this.progress, required this.a, required this.b, required this.track});

  final double progress;
  final Color a, b;
  final Color track;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(end: progress.clamp(0.0, 1.0)),
      duration: const Duration(milliseconds: 1100),
      curve: Curves.easeOutQuart,
      builder: (context, p, _) => CustomPaint(painter: _RingPainter(p, a, b, track)),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.progress, this.a, this.b, this.track);

  final double progress;
  final Color a, b;
  final Color track;

  /// A dial of fine radial ticks, the first [progress] of them lit in the
  /// gradient (each tick its own flat colour), the rest dim; a hairline
  /// circle inside, and a longer tick at each quarter for reading it.
  @override
  void paint(Canvas canvas, Size size) {
    final d = size.shortestSide;
    final c = size.center(Offset.zero);
    final outer = d / 2 - 1;
    final len = (d * 0.075).clamp(4.0, 10.0);
    // A tick every ~4.5dp of the rim: 60 on a big dial, fewer on a small one.
    final count = ((math.pi * d) / 4.5).round().clamp(24, 72) ~/ 4 * 4;
    final width = ((math.pi * d) / count * 0.42).clamp(1.2, 2.6);
    final lit = progress <= 0 ? 0 : math.max(1, (progress.clamp(0.0, 1.0) * count).round());
    final paint = Paint()
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < count; i++) {
      final quarter = i % (count ~/ 4) == 0;
      final angle = -math.pi / 2 + math.pi * 2 * i / count;
      final dir = Offset(math.cos(angle), math.sin(angle));
      final inner = outer - (quarter ? len * 1.35 : len);
      paint.color = i < lit
          ? Color.lerp(a, b, count == 1 ? 0 : i / (count - 1))!
          : track.withValues(alpha: track.a * 1.6);
      canvas.drawLine(c + dir * inner, c + dir * outer, paint);
    }
    // The hairline inside the ticks.
    canvas.drawCircle(
      c,
      outer - len * 1.35 - math.max(2.0, d * 0.02),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = track,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.progress != progress || old.a != a || old.b != b || old.track != track;
}

/// The background: three soft waves filled from the bottom up to [level]
/// (of the limit, or of the day), in the gradient's colours, with a crisp
/// crest line; rolling faster and higher as it rises, and fastest past the
/// limit ([over]). Eases to a new level and colour.
class _Wave extends StatefulWidget {
  const _Wave({
    required this.level,
    required this.a,
    required this.b,
    required this.over,
    this.light = false,
    this.content,
    this.submerged,
  });

  /// Drawn over the wave.
  final Widget? content;

  /// Drawn over [content] where the wave covers it (a tinted copy), so what
  /// the wave fills takes its colour; follows the moving surface.
  final Widget? submerged;

  final double level;
  final Color a, b;
  final bool over;

  /// On a light surface: fainter, as colour shows more on white.
  final bool light;

  @override
  State<_Wave> createState() => _WaveState();
}

class _WaveState extends State<_Wave> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);
  late final _frame = _WaveFrame(widget.level.clamp(0.0, 1.0), widget.a, widget.b);
  Duration _last = Duration.zero;

  @override
  void initState() {
    super.initState();
    _ticker.start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _frame.dispose();
    super.dispose();
  }

  void _tick(Duration elapsed) {
    final dt = (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    final target = widget.level.clamp(0.0, 1.0);
    final speed = widget.over ? 1.9 : 0.35 + 1.05 * target;
    _frame.advance(dt, speed, target, widget.a, widget.b);
  }

  @override
  Widget build(BuildContext context) {
    final wave = RepaintBoundary(
      child: CustomPaint(painter: _WavePainter(_frame, widget.light ? 0.55 : 1), size: Size.infinite),
    );
    final content = widget.content;
    if (content == null) return wave;
    final submerged = widget.submerged;
    return Stack(
      fit: StackFit.expand,
      children: [
        wave,
        content,
        if (submerged != null)
          IgnorePointer(
            child: ClipPath(
              clipper: _UnderWave(_frame),
              child: RepaintBoundary(child: submerged),
            ),
          ),
      ],
    );
  }
}

/// The wave's moving state, repainting the painter without a rebuild.
class _WaveFrame extends ChangeNotifier {
  _WaveFrame(this.level, this.a, this.b);

  double phase = 0;
  double time = 0;
  double level;
  Color a, b;

  void advance(double dt, double speed, double target, Color toA, Color toB) {
    phase = (phase + dt * speed) % (math.pi * 400);
    time += dt;
    final t = math.min(1.0, dt * 1.2);
    level += (target - level) * t;
    a = Color.lerp(a, toA, t)!;
    b = Color.lerp(b, toB, t)!;
    notifyListeners();
  }
}

/// The wave's surface at this frame: its resting line and swell, and the
/// path of one crest. Shared by the painter and the clip of what's under it.
class _WaveShape {
  _WaveShape(this.size, this.frame) {
    // Breathes a little around its level, so it's never still. Never above
    // ~80% of the height, so the top stays clear for the figures.
    final level = 0.06 + 0.74 * (frame.level + 0.012 * math.sin(frame.time * 0.8)).clamp(0.0, 1.0);
    base = size.height * (1 - level);
    amp = size.height * (0.018 + 0.03 * level);
  }

  final Size size;
  final _WaveFrame frame;
  late final double base;
  late final double amp;

  Path crest(double shift, double cycles, double ampScale) {
    final w = size.width;
    final path = Path();
    for (var x = 0.0; x <= w + 3; x += 3) {
      final t = x / w * math.pi * 2 * cycles;
      final wobble = math.sin(t + frame.phase + shift) * 0.75 + math.sin(t * 2.1 - frame.phase * 1.3 + shift) * 0.25;
      final y = base + amp * ampScale * wobble;
      if (x == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    return path;
  }

  /// The front crest, the one with the line.
  Path get front => crest(0, 1.05, 0.65);

  /// Everything under [top].
  Path filled(Path top) => Path.from(top)
    ..lineTo(size.width + 3, size.height)
    ..lineTo(0, size.height)
    ..close();
}

/// Clips to what's under the front wave, following it every frame.
class _UnderWave extends CustomClipper<Path> {
  _UnderWave(this.frame) : super(reclip: frame);

  final _WaveFrame frame;

  @override
  Path getClip(Size size) {
    final shape = _WaveShape(size, frame);
    return shape.filled(shape.front);
  }

  @override
  bool shouldReclip(_UnderWave old) => old.frame != frame;
}

class _WavePainter extends CustomPainter {
  _WavePainter(this.frame, this.strength) : super(repaint: frame);

  final _WaveFrame frame;

  /// Scales every fill's opacity.
  final double strength;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final shape = _WaveShape(size, frame);
    final base = shape.base, amp = shape.amp;
    final crest = shape.crest;
    final filled = shape.filled;

    Paint fill(Alignment begin, Alignment end, Color top, Color bottom) => Paint()
      ..shader = LinearGradient(
        begin: begin,
        end: end,
        colors: [
          top.withValues(alpha: top.a * strength),
          bottom.withValues(alpha: bottom.a * strength),
        ],
      ).createShader(Rect.fromLTRB(0, base - amp, w, h));

    // Back to front: the farthest the faintest.
    canvas.drawPath(
      filled(crest(2.4, 0.8, 0.8)),
      fill(
        Alignment.topCenter,
        Alignment.bottomCenter,
        frame.b.withValues(alpha: 0.16),
        frame.b.withValues(alpha: 0.04),
      ),
    );
    canvas.drawPath(
      filled(crest(1.1, 1.3, 1)),
      fill(Alignment.topLeft, Alignment.bottomRight, frame.a.withValues(alpha: 0.2), frame.b.withValues(alpha: 0.08)),
    );
    final front = shape.front;
    canvas.drawPath(
      filled(front),
      fill(
        Alignment.topCenter,
        Alignment.bottomCenter,
        frame.a.withValues(alpha: 0.14),
        frame.a.withValues(alpha: 0.02),
      ),
    );
    // The crest: a fine, crisp line along the front wave.
    canvas.drawPath(
      front,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..shader = LinearGradient(
          colors: [
            frame.a.withValues(alpha: 0.6 * strength),
            frame.b.withValues(alpha: 0.6 * strength),
          ],
        ).createShader(Rect.fromLTWH(0, 0, w, h)),
    );
  }

  @override
  bool shouldRepaint(_WavePainter old) => old.frame != frame || old.strength != strength;
}

/// Which of the two pages shows.
class _Dots extends StatelessWidget {
  const _Dots({required this.page, required this.look, required this.vertical});

  final int page;
  final _Look look;
  final bool vertical;

  @override
  Widget build(BuildContext context) {
    final dots = [
      for (var i = 0; i < 2; i++)
        AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          margin: const EdgeInsets.all(2),
          width: vertical ? 4 : (i == page ? 14 : 4),
          height: vertical ? (i == page ? 14 : 4) : 4,
          decoration: BoxDecoration(
            color: i == page ? look.a : look.ink.withValues(alpha: 0.25),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
    ];
    return vertical
        ? Column(mainAxisAlignment: MainAxisAlignment.center, children: dots)
        : Row(mainAxisAlignment: MainAxisAlignment.center, children: dots);
  }
}

// ---- Parts -----------------------------------------------------------------

class _AllowButton extends StatelessWidget {
  const _AllowButton({required this.onAllow});

  final Future<void> Function()? onAllow;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: FilledButton.tonalIcon(
          onPressed: onAllow == null
              ? null
              : () {
                  HapticFeedback.selectionClick();
                  onAllow!();
                },
          icon: const Icon(Icons.query_stats_rounded, size: 18),
          label: const Text('Allow usage access'),
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.look});

  final _Look look;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text('No apps used yet today', textAlign: TextAlign.center, style: _labelStyle(look, 13)),
    );
  }
}

/// A Material ink ripple, when it does anything.
class _Tappable extends StatelessWidget {
  const _Tappable({required this.onTap, required this.label, required this.radius, required this.child});

  final VoidCallback? onTap;
  final String label;
  final double radius;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      button: onTap != null,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(radius), child: child),
      ),
    );
  }
}

// ---- Options ---------------------------------------------------------------

/// The daily limits offered, in minutes; 0 is none.
const _limits = [0, 60, 120, 180, 240, 300, 360, 480];

/// The widget's options: the daily limit, the wave, its colours (a palette,
/// the wheel or the wallpaper), its surface (dark, light, or the launcher's
/// panel, and then which panel) and Usage access.
Future<void> showActivitySettings(BuildContext context, WidgetItem item) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  barrierColor: Colors.black26,
  builder: (_) => _ActivitySettingsSheet(id: item.id),
);

class _ActivitySettingsSheet extends StatelessWidget {
  const _ActivitySettingsSheet({required this.id});

  final String id;

  @override
  Widget build(BuildContext context) {
    final layout = context.watch<HomeLayoutController>();
    final item = layout.findWidget(id);
    if (item == null) return const SizedBox.shrink();
    final controller = context.watch<DeviceStatsController?>();
    final stats = controller?.stats;
    final theme = Theme.of(context);
    final note = theme.textTheme.bodySmall?.copyWith(color: Colors.white70);
    final s = item.settings;
    final palette = s['seed'] as String? ?? 'aqua';
    final mode = _modeOf(s);
    final surface = _surfaceOf(s);
    final panel = _panelStyleOf(s);
    final limit = _limitOf(s)?.inMinutes ?? 0;
    void set(String key, Object value) => layout.updateWidgetSettings(id, {...item.settings, key: value});
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      builder: (context, scroll) => SafeArea(
        child: ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            Text('Activity', style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              'Screen time, unlocks and most used apps start again at midnight. '
              'Swipe the widget sideways for your most used apps.',
              style: note,
            ),
            const SizedBox(height: 20),
            Text('Daily screen-time limit', style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              limit == 0
                  ? 'Without one, the ring shows how much of today you\'ve spent on the phone.'
                  : 'The ring fills towards it, turning amber at 80% and red past it.',
              style: note,
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final m in _limits)
                  ChoiceChip(
                    label: Text(m == 0 ? 'Off' : _durationText(Duration(minutes: m))),
                    selected: m == limit,
                    onSelected: (_) => set('limitMinutes', m),
                  ),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Background animation'),
              subtitle: const Text('A wave that rises with your screen time'),
              value: _waveOf(s),
              onChanged: (v) => set('wave', v),
            ),
            const SizedBox(height: 8),
            Text('Colour', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            SegmentedButton<ActivityColourMode>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(
                  value: ActivityColourMode.palette,
                  icon: Icon(Icons.palette_outlined),
                  label: Text('Palette'),
                ),
                ButtonSegment(
                  value: ActivityColourMode.custom,
                  icon: Icon(Icons.colorize_rounded),
                  label: Text('Custom'),
                ),
                ButtonSegment(
                  value: ActivityColourMode.wallpaper,
                  icon: Icon(Icons.wallpaper_rounded),
                  label: Text('Wallpaper'),
                ),
              ],
              selected: {mode},
              onSelectionChanged: (v) {
                // Its colours need the wallpaper image.
                if (v.first == ActivityColourMode.wallpaper) {
                  context.read<WindowBlurPlatform?>()?.requestWallpaperAccess();
                }
                set('colourMode', v.first.name);
              },
            ),
            const SizedBox(height: 10),
            SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: true, icon: Icon(Icons.circle), label: Text('Single')),
                ButtonSegment(value: false, icon: Icon(Icons.gradient_rounded), label: Text('Gradient')),
              ],
              selected: {_singleOf(s)},
              onSelectionChanged: (v) => set('single', v.first),
            ),
            const SizedBox(height: 14),
            switch (mode) {
              ActivityColourMode.palette => Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final MapEntry(key: name, value: colours) in _palettes.entries)
                    _Swatch(
                      colours: _singleOf(s) ? (colours.$1, colours.$1) : colours,
                      selected: name == palette,
                      onTap: () => set('seed', name),
                    ),
                ],
              ),
              ActivityColourMode.custom => Center(
                child: ColorWheel(
                  size: 200,
                  color: _coloursOf(s, null).$1,
                  onChanged: (c) => set('color', c.toARGB32()),
                ),
              ),
              ActivityColourMode.wallpaper => _WallpaperSwatches(id: id, note: note),
            },
            const SizedBox(height: 16),
            Text('Surface', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            SegmentedButton<ActivitySurface>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: ActivitySurface.dark, icon: Icon(Icons.dark_mode_outlined), label: Text('Dark')),
                ButtonSegment(
                  value: ActivitySurface.light,
                  icon: Icon(Icons.light_mode_outlined),
                  label: Text('Light'),
                ),
                ButtonSegment(value: ActivitySurface.glass, icon: Icon(Icons.blur_on), label: Text('Panel')),
              ],
              selected: {surface},
              onSelectionChanged: (v) {
                // Glass needs the wallpaper image.
                if (v.first == ActivitySurface.glass && panel == GroupStyle.glass) {
                  context.read<WindowBlurPlatform?>()?.requestWallpaperAccess();
                }
                set('surface', v.first.name);
              },
            ),
            // On the launcher's panel: which one.
            if (surface == ActivitySurface.glass) ...[
              const SizedBox(height: 16),
              Text('Panel background', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              PanelStylePicker(value: panel, onChanged: (p) => set('style', (p ?? GroupStyle.glass).name)),
            ],
            const SizedBox(height: 16),
            Text('Access', style: theme.textTheme.titleSmall),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Usage access'),
              subtitle: const Text('For screen time, unlocks and most used apps'),
              trailing: stats?.usageAccess ?? false
                  ? const Icon(Icons.check_rounded)
                  : TextButton(onPressed: controller?.openUsageAccess, child: const Text('Allow')),
            ),
          ],
        ),
      ),
    );
  }
}

/// The wallpaper's colours as the widget will use them, or why there are
/// none. Follows the wallpaper when it changes.
class _WallpaperSwatches extends StatelessWidget {
  const _WallpaperSwatches({required this.id, required this.note});

  /// The widget it's for (its settings: one colour or the gradient).
  final String id;
  final TextStyle? note;

  @override
  Widget build(BuildContext context) {
    final image = context.select<WindowBlurPlatform?, ui.Image?>((p) => p?.wallpaper);
    final settings = context.watch<HomeLayoutController>().findWidget(id)?.settings ?? const <String, dynamic>{};
    if (image == null) return Text('Waiting for the wallpaper…', style: note);
    return FutureBuilder<List<Color>?>(
      future: wallpaperColors(image),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) return Text('Reading the wallpaper…', style: note);
        final colors = snap.data;
        if (colors == null || colors.isEmpty) {
          return Text('The wallpaper has little colour, so the widget keeps its palette', style: note);
        }
        final pair = _coloursOf(settings, colors);
        return Row(
          children: [
            _Swatch(colours: pair, selected: true, onTap: () {}),
            const SizedBox(width: 12),
            Expanded(child: Text('From your wallpaper; they change with it', style: note)),
          ],
        );
      },
    );
  }
}

/// A palette: a disc of its gradient.
class _Swatch extends StatelessWidget {
  const _Swatch({required this.colours, required this.selected, required this.onTap});

  final (Color, Color) colours;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 44,
        height: 44,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: selected ? Colors.white : Colors.transparent, width: 2),
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [colours.$1, colours.$2],
            ),
          ),
        ),
      ),
    );
  }
}
