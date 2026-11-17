import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/platform/launcher_platform.dart';
import '../../../core/platform/window_blur_platform.dart';
import '../../standard_home/home_layout.dart';
import '../launcher_widgets.dart';
import 'clock_settings_sheet.dart';
import 'wallpaper_colors.dart';
import 'weather.dart';

/// The digital clock: one entry in LauncherWidgetKind.values. Each clock on
/// the home screen has its own [ClockSettings].
///
/// From two cells across and one down, to the whole width and two rows (a
/// quarter of the 8-row grid's height): the most a clock widget takes on
/// Pixel and One UI home screens.
const digitalClockKind = LauncherWidgetKind(
  name: 'digitalClock',
  label: 'Digital clock',
  description: 'Time and date, in your choice of font, colour and size',
  icon: Icons.schedule_rounded,
  group: 'Clocks',
  size: (4, 2),
  min: (2, 1),
  max: (6, 2),
  build: _build,
  customise: showClockSettings,
  panelOf: _hasPanel,
  styleOf: _panelStyle,
  // Takes taps itself, to open the clock app (when that's on).
  interactive: true,
);

Widget _build(BuildContext context, Map<String, dynamic> settings) {
  final s = ClockSettings.fromJson(settings);
  final clock = DigitalClock(settings: s);
  if (!s.tapOpensClock) return clock;
  return Semantics(
    button: true,
    hint: 'Opens the clock app',
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => context.read<LauncherPlatform?>()?.openClock(),
      child: clock,
    ),
  );
}

bool _hasPanel(Map<String, dynamic> settings) => ClockSettings.fromJson(settings).panel;

GroupStyle _panelStyle(Map<String, dynamic> settings) => ClockSettings.fromJson(settings).panelStyle;

/// Clock fonts: open-licence (OFL) fonts bundled with the launcher, each the
/// one or the nearest free match to a clock face on iPhone and on premium
/// Android phones. (Apple's SF fonts and Samsung's and Nothing's own can't be
/// shipped in an app.)
enum ClockFont {
  googleSans('ClockGoogleSans', 'Google Sans', 'Pixel’s own font'),
  inter('ClockInter', 'Inter', 'Close to iPhone’s SF Pro'),
  rounded('ClockNunito', 'Nunito', 'Close to iPhone’s SF Rounded'),
  serif('ClockSourceSerif', 'Source Serif', 'Close to iPhone’s New York'),
  condensed('ClockOswald', 'Oswald', 'Tall, like the iPhone lock screen', minWeight: 200, maxWeight: 700),
  geometric('ClockOutfit', 'Outfit', 'Close to Samsung’s One UI clock'),
  grotesk('ClockSpaceGrotesk', 'Space Grotesk', 'Close to OnePlus’s clock', minWeight: 300, maxWeight: 700),
  dots('ClockDoto', 'Doto', 'Dot matrix, like Nothing phones');

  const ClockFont(this.family, this.label, this.note, {this.minWeight = 100, this.maxWeight = 900});

  final String family;
  final String label;

  /// What it looks like.
  final String note;

  /// The weights it comes in (variable fonts: any in between).
  final int minWeight;
  final int maxWeight;

  static ClockFont fromName(String? name) => values.asNameMap()[name] ?? googleSans;
}

/// Ready-made clock gradients, picked to read well on a wallpaper: metals,
/// skies and neon, light enough to stand out on dark backgrounds.
const clockGradients = <(String, List<Color>)>[
  ('Gold', [Color(0xFFBF953F), Color(0xFFFCF6BA), Color(0xFFB38728)]),
  ('Rose gold', [Color(0xFFF7CAC9), Color(0xFFE8A0A8), Color(0xFFB76E79)]),
  ('Titanium', [Color(0xFFEEF2F3), Color(0xFF8E9EAB)]),
  ('Holo', [Color(0xFFA8EDEA), Color(0xFFC3B1F7), Color(0xFFFED6E3)]),
  ('Aurora', [Color(0xFF00C9FF), Color(0xFF92FE9D)]),
  ('Sunset', [Color(0xFFFF7E5F), Color(0xFFFEB47B)]),
  ('Lavender', [Color(0xFFA18CD1), Color(0xFFFBC2EB)]),
  ('Neon', [Color(0xFFFF3CAC), Color(0xFF784BA0), Color(0xFF2B86C5)]),
  ('Ocean', [Color(0xFF2193B0), Color(0xFF6DD5ED)]),
  ('Mango', [Color(0xFFFFE259), Color(0xFFFFA751)]),
  ('Mint', [Color(0xFF43E97B), Color(0xFF38F9D7)]),
  ('Fire', [Color(0xFFF12711), Color(0xFFF5AF19)]),
];

/// Which way a clock's gradient runs.
enum GradientDirection {
  across(Alignment.centerLeft, Alignment.centerRight, Icons.east_rounded),
  diagonalDown(Alignment.topLeft, Alignment.bottomRight, Icons.south_east_rounded),
  down(Alignment.topCenter, Alignment.bottomCenter, Icons.south_rounded),
  diagonalUp(Alignment.bottomLeft, Alignment.topRight, Icons.north_east_rounded);

  const GradientDirection(this.begin, this.end, this.icon);

  final Alignment begin;
  final Alignment end;
  final IconData icon;
}

/// 12- or 24-hour time; [system] follows the phone's setting.
enum ClockHours { system, h12, h24 }

/// Where the time sits across the widget.
enum ClockAlign { start, center, end }

/// One clock's options. Stored in its WidgetItem.settings; anything missing
/// is the default.
@immutable
class ClockSettings {
  const ClockSettings({
    this.font = ClockFont.googleSans,
    this.weight = 400,
    this.color = 0xFFFFFFFF,
    this.gradient,
    this.gradientDirection = GradientDirection.diagonalDown,
    this.scale = 1,
    this.hourFormat = ClockHours.system,
    this.seconds = false,
    this.amPm = true,
    this.date = true,
    this.align = ClockAlign.center,
    this.panel = true,
    this.panelStyle = GroupStyle.glass,
    this.weather = false,
    this.fahrenheit = false,
    this.wallpaperColors = false,
    this.tapOpensClock = true,
  });

  final ClockFont font;

  /// 100 (thin) to 900 (black), kept within what [font] has.
  final int weight;

  /// The solid colour (ARGB), when there's no [gradient].
  final int color;

  /// Colours (ARGB, two or more) the clock is filled with, instead of
  /// [color]; null for a solid colour.
  final List<int>? gradient;
  final GradientDirection gradientDirection;

  /// Most colours a gradient has.
  static const maxStops = 4;

  /// How much of the widget the clock fills, [minScale] to 1.
  final double scale;
  final ClockHours hourFormat;
  final bool seconds;

  /// AM / PM after a 12-hour time.
  final bool amPm;

  /// The date, as much of it as the widget's size has room for.
  final bool date;
  final ClockAlign align;

  /// On frosted glass like a folder's; off: straight on the wallpaper.
  final bool panel;

  /// The panel's look, when there is one: light, dark or glass, as a group's.
  final GroupStyle panelStyle;

  /// The weather now (icon and temperature) beside the date.
  final bool weather;

  /// Its temperature in °F; else °C.
  final bool fahrenheit;

  /// Filled with a gradient of the wallpaper's main colours (in
  /// [gradientDirection]), instead of [color] / [gradient]; those are kept
  /// for when it's turned off, or the wallpaper has no colour to speak of.
  final bool wallpaperColors;

  /// A tap opens the phone's clock app.
  final bool tapOpensClock;

  static const minScale = 0.4;

  /// What it's filled with: [wallpaper] (its main colours) when
  /// [wallpaperColors] is on and they're known, else [gradient]; null for
  /// the solid [color].
  LinearGradient? shader({List<Color>? wallpaper}) =>
      switch (wallpaperColors && wallpaper != null ? [for (final c in wallpaper) c.toARGB32()] : gradient) {
        final g? when g.length >= 2 => LinearGradient(
          colors: [for (final c in g) Color(c)],
          begin: gradientDirection.begin,
          end: gradientDirection.end,
        ),
        _ => null,
      };

  int get fontWeight => weight.clamp(font.minWeight, font.maxWeight);

  /// 24-hour time, from [hourFormat] or the phone's setting.
  bool use24h(BuildContext context) => switch (hourFormat) {
    ClockHours.h12 => false,
    ClockHours.h24 => true,
    ClockHours.system => MediaQuery.alwaysUse24HourFormatOf(context),
  };

  ClockSettings copyWith({
    ClockFont? font,
    int? weight,
    int? color,
    List<int>? Function()? gradient,
    GradientDirection? gradientDirection,
    double? scale,
    ClockHours? hourFormat,
    bool? seconds,
    bool? amPm,
    bool? date,
    ClockAlign? align,
    bool? panel,
    GroupStyle? panelStyle,
    bool? weather,
    bool? fahrenheit,
    bool? wallpaperColors,
    bool? tapOpensClock,
  }) => ClockSettings(
    font: font ?? this.font,
    weight: weight ?? this.weight,
    color: color ?? this.color,
    gradient: gradient != null ? gradient() : this.gradient,
    gradientDirection: gradientDirection ?? this.gradientDirection,
    scale: scale ?? this.scale,
    hourFormat: hourFormat ?? this.hourFormat,
    seconds: seconds ?? this.seconds,
    amPm: amPm ?? this.amPm,
    date: date ?? this.date,
    align: align ?? this.align,
    panel: panel ?? this.panel,
    panelStyle: panelStyle ?? this.panelStyle,
    weather: weather ?? this.weather,
    fahrenheit: fahrenheit ?? this.fahrenheit,
    wallpaperColors: wallpaperColors ?? this.wallpaperColors,
    tapOpensClock: tapOpensClock ?? this.tapOpensClock,
  );

  Map<String, dynamic> toJson() => {
    'font': font.name,
    'weight': weight,
    'color': color,
    'gradient': ?gradient,
    'gradientDir': gradientDirection.name,
    'scale': scale,
    'hours': hourFormat.name,
    'seconds': seconds,
    'amPm': amPm,
    'date': date,
    'align': align.name,
    'panel': panel,
    'panelStyle': panelStyle.name,
    'weather': weather,
    'fahrenheit': fahrenheit,
    'wallColors': wallpaperColors,
    'tapOpens': tapOpensClock,
  };

  factory ClockSettings.fromJson(Map<String, dynamic> json) {
    const d = ClockSettings();
    return ClockSettings(
      font: ClockFont.fromName(json['font'] as String?),
      weight: ((json['weight'] as num?)?.toInt() ?? d.weight).clamp(100, 900),
      color: (json['color'] as num?)?.toInt() ?? d.color,
      gradient: switch (json['gradient']) {
        final List<dynamic> g when g.length >= 2 => [for (final c in g.take(maxStops)) (c as num).toInt()],
        _ => null,
      },
      gradientDirection: GradientDirection.values.asNameMap()[json['gradientDir']] ?? d.gradientDirection,
      scale: ((json['scale'] as num?)?.toDouble() ?? d.scale).clamp(minScale, 1.0),
      hourFormat: ClockHours.values.asNameMap()[json['hours']] ?? d.hourFormat,
      seconds: json['seconds'] as bool? ?? d.seconds,
      amPm: json['amPm'] as bool? ?? d.amPm,
      date: json['date'] as bool? ?? d.date,
      align: ClockAlign.values.asNameMap()[json['align']] ?? d.align,
      panel: json['panel'] as bool? ?? d.panel,
      panelStyle: panelStyleFrom(json['panelStyle']),
      weather: json['weather'] as bool? ?? d.weather,
      fahrenheit: json['fahrenheit'] as bool? ?? d.fahrenheit,
      wallpaperColors: json['wallColors'] as bool? ?? d.wallpaperColors,
      tapOpensClock: json['tapOpens'] as bool? ?? d.tapOpensClock,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ClockSettings &&
      other.font == font &&
      other.weight == weight &&
      other.color == color &&
      listEquals(other.gradient, gradient) &&
      other.gradientDirection == gradientDirection &&
      other.scale == scale &&
      other.hourFormat == hourFormat &&
      other.seconds == seconds &&
      other.amPm == amPm &&
      other.date == date &&
      other.align == align &&
      other.panel == panel &&
      other.panelStyle == panelStyle &&
      other.weather == weather &&
      other.fahrenheit == fahrenheit &&
      other.wallpaperColors == wallpaperColors &&
      other.tapOpensClock == tapOpensClock;

  @override
  int get hashCode => Object.hash(
    font,
    weight,
    color,
    gradient == null ? null : Object.hashAll(gradient!),
    gradientDirection,
    scale,
    hourFormat,
    seconds,
    amPm,
    date,
    align,
    panel,
    panelStyle,
    weather,
    fahrenheit,
    wallpaperColors,
    tapOpensClock,
  );
}

/// How much of the date a clock shows, by the room it has.
enum DateLength {
  none,

  /// "Tue 27"
  short,

  /// "Tue, 27 Oct"
  medium,

  /// "Tuesday, 27 October"
  long,
}

/// The time, and the date below it (or beside it on a one-row clock), in
/// [settings]' look, filling its box.
class DigitalClock extends StatefulWidget {
  const DigitalClock({super.key, required this.settings, this.now, this.weather});

  final ClockSettings settings;

  /// A fixed time instead of the real one (previews, tests).
  final DateTime? now;

  /// Fixed weather instead of the real one (tests); shown if
  /// [ClockSettings.weather] is on.
  final Weather? weather;

  /// One-row clocks are about this tall inside their panel, or less.
  static const _oneRow = 72.0;

  /// The date that fits a clock of [size]: beside the time on one row when
  /// it's wide enough, otherwise under it, longer the wider it is.
  static DateLength dateLengthFor(Size size) {
    if (size.height < _oneRow) return size.width >= 230 ? DateLength.medium : DateLength.none;
    if (size.width < 150) return DateLength.short;
    if (size.width < 250) return DateLength.medium;
    return DateLength.long;
  }

  static const _days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
  static const _months = [
    'January', 'February', 'March', 'April', 'May', 'June', //
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  static String formatDate(DateTime t, DateLength length) {
    final day = _days[t.weekday - 1], month = _months[t.month - 1];
    return switch (length) {
      DateLength.none => '',
      DateLength.short => '${day.substring(0, 3)} ${t.day}',
      DateLength.medium => '${day.substring(0, 3)}, ${t.day} ${month.substring(0, 3)}',
      DateLength.long => '$day, ${t.day} $month',
    };
  }

  /// "9:41" / "09:41", the seconds ("05") and "AM" / "PM" ('' in 24-hour).
  static (String, String, String) formatTime(DateTime t, {required bool use24h}) {
    String two(int v) => v.toString().padLeft(2, '0');
    final hour = use24h ? two(t.hour) : '${t.hour % 12 == 0 ? 12 : t.hour % 12}';
    return ('$hour:${two(t.minute)}', two(t.second), use24h ? '' : (t.hour < 12 ? 'AM' : 'PM'));
  }

  @override
  State<DigitalClock> createState() => _DigitalClockState();
}

class _DigitalClockState extends State<DigitalClock> {
  Timer? _timer;
  late DateTime _now;

  /// Fetching the weather while this clock shows it.
  WeatherController? _weather;

  /// The wallpaper image [_wallColors] are from, and its main colours.
  ui.Image? _wallFrom;
  List<Color>? _wallColors;

  /// Works out the wallpaper's colours when it's new (and they're wanted).
  void _watchWallpaper(ui.Image? image) {
    if (!widget.settings.wallpaperColors || identical(image, _wallFrom)) return;
    _wallFrom = image;
    if (image == null) return;
    wallpaperColors(image).then((colors) {
      if (mounted && identical(image, _wallFrom)) setState(() => _wallColors = colors);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _watchWeather();
  }

  void _watchWeather() {
    final want = widget.settings.weather && widget.weather == null;
    final c = want ? Provider.of<WeatherController?>(context, listen: false) : null;
    if (c == _weather) return;
    _weather?.detach();
    _weather = c?..attach();
  }

  @override
  void initState() {
    super.initState();
    _tick();
  }

  @override
  void didUpdateWidget(DigitalClock old) {
    super.didUpdateWidget(old);
    if (old.settings.seconds != widget.settings.seconds || old.now != widget.now) _tick();
    if (old.settings.weather != widget.settings.weather || old.weather != widget.weather) _watchWeather();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _weather?.detach();
    super.dispose();
  }

  /// Shows the time now and wakes again on the next second (seconds shown)
  /// or minute: never more often than the display changes.
  void _tick() {
    _timer?.cancel();
    if (widget.now case final fixed?) {
      _now = fixed;
      return;
    }
    _now = DateTime.now();
    final next = widget.settings.seconds ? 1000 - _now.millisecond : (60 - _now.second) * 1000 - _now.millisecond;
    _timer = Timer(Duration(milliseconds: next + 5), () {
      if (mounted) setState(_tick);
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.settings;
    // Rebuilt when the wallpaper changes, only if it's coloured by it.
    if (s.wallpaperColors) {
      _watchWallpaper(context.select<WindowBlurPlatform?, ui.Image?>((p) => p?.wallpaper));
    }
    final shader = s.shader(wallpaper: _wallColors);
    // A gradient is masked onto white text (see _filled). The default white
    // is the panel's ink (dark on a light one); a picked colour stays.
    final color = shader == null ? (s.color == 0xFFFFFFFF ? PanelInk.of(context) : Color(s.color)) : Colors.white;
    final weight = s.fontWeight;
    TextStyle style({double alpha = 1}) => TextStyle(
      fontFamily: s.font.family,
      fontWeight: FontWeight.values[(weight ~/ 100 - 1).clamp(0, 8)],
      fontVariations: [FontVariation('wght', weight.toDouble())],
      fontFeatures: const [FontFeature.tabularFigures()],
      color: color.withValues(alpha: color.a * alpha),
      height: 1,
      leadingDistribution: TextLeadingDistribution.even,
    );
    final use24h = s.use24h(context);
    final (hm, sec, ampm) = DigitalClock.formatTime(_now, use24h: use24h);
    final suffix = s.amPm ? ampm : '';
    final weather = !s.weather
        ? null
        : widget.weather ?? (_weather == null ? null : context.watch<WeatherController>().weather);

    return LayoutBuilder(
      builder: (context, box) {
        final size = box.biggest;
        final length = s.date ? DigitalClock.dateLengthFor(size) : DateLength.none;
        final date = DigitalClock.formatDate(_now, length);
        final oneRow = size.height < DigitalClock._oneRow;
        // A one-row clock too narrow for the date has no room for it either.
        final showWeather = weather != null && !(oneRow && size.width < 160);
        final align = switch (s.align) {
          ClockAlign.start => Alignment.centerLeft,
          ClockAlign.center => Alignment.center,
          ClockAlign.end => Alignment.centerRight,
        };

        final time = _filled(
          shader,
          _Time(
            hm: hm,
            seconds: s.seconds ? sec : null,
            suffix: suffix,
            // Room for two-digit hours, so 9:59 → 10:00 doesn't resize it.
            widest: use24h ? null : '00:00',
            style: style(),
            align: align,
          ),
        );
        final dateText = Text(date, maxLines: 1, style: style(alpha: 0.8).copyWith(height: 1.2));

        // Fills [scale] of the widget, the time as big as fits.
        final w = size.width * s.scale, h = size.height * s.scale;
        final Widget body;
        // The date's line: the date, and the weather after it.
        Widget line(double px) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (date.isNotEmpty) _sized(dateText, px),
            if (date.isNotEmpty && showWeather) SizedBox(width: px * 0.6),
            if (showWeather)
              _WeatherNow(weather: weather, fahrenheit: s.fahrenheit, style: style(alpha: 0.8), size: px),
          ],
        );
        if (date.isEmpty && !showWeather) {
          body = SizedBox(
            width: w,
            height: h,
            child: FittedBox(alignment: align, child: time),
          );
        } else if (oneRow) {
          // The date beside the time, about half as tall.
          body = SizedBox(
            width: w,
            height: h,
            child: FittedBox(
              alignment: align,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [time, const SizedBox(width: 20), _filled(shader, line(46))],
              ),
            ),
          );
        } else {
          // The time over three quarters of the height, the date under it.
          body = SizedBox(
            width: w,
            height: h,
            child: Column(
              crossAxisAlignment: switch (s.align) {
                ClockAlign.start => CrossAxisAlignment.start,
                ClockAlign.center => CrossAxisAlignment.center,
                ClockAlign.end => CrossAxisAlignment.end,
              },
              children: [
                Expanded(
                  flex: 3,
                  child: FittedBox(alignment: align, child: time),
                ),
                SizedBox(height: h * 0.04),
                Expanded(
                  flex: 1,
                  child: FittedBox(alignment: align, fit: BoxFit.scaleDown, child: _filled(shader, line(h * 0.2))),
                ),
              ],
            ),
          );
        }
        return Align(alignment: align, child: body);
      },
    );
  }

  /// [child] (white) filled with [gradient]; as it is if there's none.
  static Widget _filled(LinearGradient? gradient, Widget child) => gradient == null
      ? child
      : ShaderMask(blendMode: BlendMode.srcIn, shaderCallback: gradient.createShader, child: child);

  /// [text] at a font size of [px].
  Widget _sized(Text text, double px) =>
      Text(text.data!, maxLines: 1, style: text.style!.copyWith(fontSize: px.clamp(8.0, 400.0)));
}

/// The weather now: its icon and temperature, at a font size of [size].
class _WeatherNow extends StatelessWidget {
  const _WeatherNow({required this.weather, required this.fahrenheit, required this.style, required this.size});

  final Weather weather;
  final bool fahrenheit;
  final TextStyle style;
  final double size;

  @override
  Widget build(BuildContext context) {
    final px = size.clamp(8.0, 400.0);
    return Semantics(
      label: '${weather.description}, ${weather.temperature(fahrenheit: fahrenheit)}',
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(weather.icon, size: px * 1.05, color: style.color),
            SizedBox(width: px * 0.25),
            Text(
              weather.temperature(fahrenheit: fahrenheit),
              maxLines: 1,
              style: style.copyWith(fontSize: px, height: 1.2),
            ),
          ],
        ),
      ),
    );
  }
}

/// "9:41" with optional smaller ":05" seconds and "PM" on its baseline.
/// Laid out over [widest] (invisible) so the width only changes when the
/// format does, not from minute to minute.
class _Time extends StatelessWidget {
  const _Time({
    required this.hm,
    required this.seconds,
    required this.suffix,
    required this.widest,
    required this.style,
    required this.align,
  });

  final String hm;
  final String? seconds;
  final String suffix;
  final String? widest;
  final TextStyle style;
  final Alignment align;

  /// Font size the time is laid out at, before it's fitted to the widget.
  static const _base = 100.0;

  TextSpan _span(String hm) => TextSpan(
    style: style.copyWith(fontSize: _base),
    children: [
      TextSpan(text: hm),
      if (seconds != null)
        TextSpan(
          text: ':$seconds',
          style: TextStyle(fontSize: _base * 0.45),
        ),
      if (suffix.isNotEmpty)
        TextSpan(
          text: ' $suffix',
          style: TextStyle(fontSize: _base * 0.3),
        ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final shown = Text.rich(_span(hm), maxLines: 1, softWrap: false);
    if (widest == null || widest!.length <= hm.length) return shown;
    return Stack(
      alignment: align,
      children: [
        Opacity(opacity: 0, child: Text.rich(_span(widest!), maxLines: 1, softWrap: false)),
        shown,
      ],
    );
  }
}
