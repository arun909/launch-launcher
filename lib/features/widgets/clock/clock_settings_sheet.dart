import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/platform/window_blur_platform.dart';
import '../../../core/widgets/color_wheel.dart';
import '../../standard_home/app_container_tile.dart';
import '../../standard_home/home_layout.dart';
import '../../standard_home/home_layout_controller.dart';
import '../home_widget_view.dart';
import '../launcher_widgets.dart';
import '../widget_placement.dart';
import 'digital_clock.dart';
import 'wallpaper_colors.dart';
import 'weather.dart';

/// One clock's options: font, weight, colour, size, 12/24-hour, seconds,
/// date, alignment and its glass panel. Every change shows at once, on the
/// preview and on the home screen behind (the barrier is light for that).
Future<void> showClockSettings(BuildContext context, WidgetItem item) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    barrierColor: Colors.black26,
    builder: (_) => _ClockSettingsSheet(id: item.id),
  );
}

class _ClockSettingsSheet extends StatelessWidget {
  const _ClockSettingsSheet({required this.id});

  final String id;

  @override
  Widget build(BuildContext context) {
    final layout = context.watch<HomeLayoutController>();
    final item = layout.findWidget(id);
    if (item == null) return const SizedBox.shrink();
    final s = ClockSettings.fromJson(item.settings);
    void set(ClockSettings next) => layout.updateWidgetSettings(id, next.toJson());
    final theme = Theme.of(context);
    final system24h = MediaQuery.alwaysUse24HourFormatOf(context);

    // Above the keyboard while a hex value is typed.
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: _Preview(item: item, layout: layout),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.only(bottom: 16),
                  children: [
                    const _Heading('Font'),
                    SizedBox(
                      height: 96,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        children: [
                          for (final f in ClockFont.values)
                            _FontChoice(
                              font: f,
                              weight: s.weight,
                              selected: f == s.font,
                              onTap: () => set(s.copyWith(font: f)),
                            ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                      child: Text(s.font.note, style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70)),
                    ),
                    _SliderRow(
                      label: 'Weight',
                      value: s.fontWeight.toDouble(),
                      min: s.font.minWeight.toDouble(),
                      max: s.font.maxWeight.toDouble(),
                      divisions: (s.font.maxWeight - s.font.minWeight) ~/ 100,
                      text: _weightName(s.fontWeight),
                      onChanged: (v) => set(s.copyWith(weight: v.round())),
                      onDrag: layout.setInteracting,
                    ),
                    _SliderRow(
                      label: 'Size',
                      value: s.scale,
                      min: ClockSettings.minScale,
                      max: 1,
                      divisions: 12,
                      text: '${(s.scale * 100).round()}%',
                      onChanged: (v) => set(s.copyWith(scale: v)),
                      onDrag: layout.setInteracting,
                    ),
                    const _Heading('Colour'),
                    _ColourSection(settings: s, onChanged: set, onDrag: layout.setInteracting),
                    const _Heading('Tap'),
                    SwitchListTile(
                      title: const Text('Open the Clock app'),
                      subtitle: const Text('Tapping the clock opens your alarms, timers and stopwatch'),
                      value: s.tapOpensClock,
                      onChanged: (v) => set(s.copyWith(tapOpensClock: v)),
                    ),
                    const _Heading('Time'),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: SegmentedButton<ClockHours>(
                        showSelectedIcon: false,
                        segments: [
                          ButtonSegment(value: ClockHours.system, label: Text('Phone (${system24h ? '24h' : '12h'})')),
                          const ButtonSegment(value: ClockHours.h12, label: Text('12-hour')),
                          const ButtonSegment(value: ClockHours.h24, label: Text('24-hour')),
                        ],
                        selected: {s.hourFormat},
                        onSelectionChanged: (v) => set(s.copyWith(hourFormat: v.first)),
                      ),
                    ),
                    SwitchListTile(
                      title: const Text('Seconds'),
                      value: s.seconds,
                      onChanged: (v) => set(s.copyWith(seconds: v)),
                    ),
                    if (!s.use24h(context))
                      SwitchListTile(
                        title: const Text('AM / PM'),
                        value: s.amPm,
                        onChanged: (v) => set(s.copyWith(amPm: v)),
                      ),
                    SwitchListTile(
                      title: const Text('Date'),
                      subtitle: const Text(
                        'As much as fits: “Tue 27” on a small clock, “Tuesday, 27 October” on a wide one',
                      ),
                      value: s.date,
                      onChanged: (v) => set(s.copyWith(date: v)),
                    ),
                    SwitchListTile(
                      title: const Text('Weather'),
                      subtitle: const Text('Its icon and temperature after the date'),
                      value: s.weather,
                      onChanged: (v) {
                        set(s.copyWith(weather: v));
                        if (v) _askLocationIfNeeded(context);
                      },
                    ),
                    if (s.weather) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: SegmentedButton<bool>(
                          showSelectedIcon: false,
                          segments: const [
                            ButtonSegment(value: false, label: Text('°C')),
                            ButtonSegment(value: true, label: Text('°F')),
                          ],
                          selected: {s.fahrenheit},
                          onSelectionChanged: (v) => set(s.copyWith(fahrenheit: v.first)),
                        ),
                      ),
                      const _WeatherPlaceTile(),
                    ],
                    const _Heading('Layout'),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: SegmentedButton<ClockAlign>(
                        showSelectedIcon: false,
                        segments: const [
                          ButtonSegment(
                            value: ClockAlign.start,
                            icon: Icon(Icons.format_align_left_rounded),
                            label: Text('Left'),
                          ),
                          ButtonSegment(
                            value: ClockAlign.center,
                            icon: Icon(Icons.format_align_center_rounded),
                            label: Text('Centre'),
                          ),
                          ButtonSegment(
                            value: ClockAlign.end,
                            icon: Icon(Icons.format_align_right_rounded),
                            label: Text('Right'),
                          ),
                        ],
                        selected: {s.align},
                        onSelectionChanged: (v) => set(s.copyWith(align: v.first)),
                      ),
                    ),
                    const ListTile(
                      title: Text('Background'),
                      subtitle: Text('As a group’s. None: the clock sits on the wallpaper'),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: PanelStylePicker(
                        allowNone: true,
                        value: s.panel ? s.panelStyle : null,
                        onChanged: (v) =>
                            set(v == null ? s.copyWith(panel: false) : s.copyWith(panel: true, panelStyle: v)),
                      ),
                    ),
                    if (s != const ClockSettings())
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                        child: OutlinedButton.icon(
                          onPressed: () => layout.updateWidgetSettings(id, const {}),
                          icon: const Icon(Icons.restart_alt_rounded),
                          label: const Text('Reset to default'),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _weightName(int w) => switch (w) {
    <= 100 => 'Thin',
    <= 200 => 'Extra light',
    <= 300 => 'Light',
    <= 400 => 'Regular',
    <= 500 => 'Medium',
    <= 600 => 'Semibold',
    <= 700 => 'Bold',
    <= 800 => 'Extra bold',
    _ => 'Black',
  };
}

/// Weather for the phone's location (no city picked): ask for location
/// the first time.
Future<void> _askLocationIfNeeded(BuildContext context) async {
  final weather = context.read<WeatherController?>();
  if (weather == null || weather.city != null) return;
  if (!await weather.hasLocation()) await weather.requestLocation();
}

/// Where the weather is for: the phone's location or a town; tap to change.
class _WeatherPlaceTile extends StatelessWidget {
  const _WeatherPlaceTile();

  @override
  Widget build(BuildContext context) {
    final weather = context.watch<WeatherController?>();
    if (weather == null) return const SizedBox.shrink();
    final now = weather.weather;
    final city = weather.city;
    final place = city?.name ?? (now?.place == null ? 'Current location' : 'Current location · ${now!.place}');
    final status = switch (weather.problem) {
      WeatherProblem.noLocation => 'Location is off or not allowed: tap to allow it, or pick a city',
      WeatherProblem.offline => 'Couldn’t reach the weather service; will try again',
      null => now == null ? 'Loading…' : '${now.description}, ${now.temperature()} · Open-Meteo',
    };
    return ListTile(
      leading: Icon(city == null ? Icons.my_location_rounded : Icons.location_city_rounded),
      title: Text(place),
      subtitle: Text(status),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: () => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => ChangeNotifierProvider.value(value: weather, child: const _WeatherPlaceSheet()),
      ),
    );
  }
}

/// Pick where the weather is for: the phone's location, or a town by name.
class _WeatherPlaceSheet extends StatefulWidget {
  const _WeatherPlaceSheet();

  @override
  State<_WeatherPlaceSheet> createState() => _WeatherPlaceSheetState();
}

class _WeatherPlaceSheetState extends State<_WeatherPlaceSheet> {
  List<WeatherCity> _results = const [];
  String _query = '';
  bool _searching = false;

  Future<void> _search(String q) async {
    _query = q;
    if (q.trim().length < 2) {
      setState(() => _results = const []);
      return;
    }
    setState(() => _searching = true);
    final found = await context.read<WeatherController>().searchCities(q);
    // A newer search came meanwhile: that one wins.
    if (!mounted || q != _query) return;
    setState(() {
      _results = found;
      _searching = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final weather = context.watch<WeatherController>();
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.my_location_rounded),
                title: const Text('Current location'),
                subtitle: const Text('Approximate, from the phone'),
                trailing: weather.city == null ? const Icon(Icons.check_rounded) : null,
                onTap: () async {
                  final nav = Navigator.of(context);
                  if (!await weather.hasLocation()) await weather.requestLocation();
                  await weather.useLocation();
                  nav.pop();
                },
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'Search for a city',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _searching
                        ? const Padding(
                            padding: EdgeInsets.all(14),
                            child: SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                          )
                        : null,
                    border: const OutlineInputBorder(),
                  ),
                  textInputAction: TextInputAction.search,
                  onChanged: _search,
                  onSubmitted: _search,
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final c in _results)
                      ListTile(
                        leading: const Icon(Icons.location_city_rounded),
                        title: Text(c.name),
                        subtitle: c.detail == null || c.detail!.isEmpty ? null : Text(c.detail!),
                        trailing: weather.city?.name == c.name && weather.city?.lat == c.lat
                            ? const Icon(Icons.check_rounded)
                            : null,
                        onTap: () {
                          weather.useCity(c);
                          Navigator.of(context).pop();
                        },
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The clock at its size on the home screen, scaled down only if it's
/// wider than the sheet.
class _Preview extends StatelessWidget {
  const _Preview({required this.item, required this.layout});

  final WidgetItem item;
  final HomeLayoutController layout;

  @override
  Widget build(BuildContext context) {
    final grid = layout.grid;
    final cols = item.cols.clamp(1, grid.columns), rows = item.rows;
    final size = HomeWidgetView.sizeOf(grid, homeCell(context, grid), cols, rows);
    return Container(
      height: 150,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        // Dark, like a wallpaper, so a white clock shows.
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF3A3F55), Color(0xFF1C1E26)],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: SizedBox.fromSize(
          size: size,
          // Not a way into the clock app here.
          child: IgnorePointer(
            child: LauncherWidgetView(
              kind: digitalClockKind,
              radius: HomeWidgetView.radiusFor(cols, rows, size, iconShape: layout.iconShape),
              padding: AppContainerTile.pad(grid),
              settings: item.settings,
            ),
          ),
        ),
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
    child: Text(text, style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Colors.white70)),
  );
}

/// "12:45" in [font], with its name under it.
class _FontChoice extends StatelessWidget {
  const _FontChoice({required this.font, required this.weight, required this.selected, required this.onTap});

  final ClockFont font;
  final int weight;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final w = weight.clamp(font.minWeight, font.maxWeight);
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: Material(
        color: selected ? scheme.primaryContainer : scheme.surfaceContainerHigh,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: selected ? BorderSide(color: scheme.primary, width: 2) : BorderSide.none,
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: 96,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '12:45',
                  style: TextStyle(
                    fontFamily: font.family,
                    fontSize: 28,
                    height: 1.1,
                    fontWeight: FontWeight.values[(w ~/ 100 - 1).clamp(0, 8)],
                    fontVariations: [FontVariation('wght', w.toDouble())],
                  ),
                ),
                const SizedBox(height: 6),
                Text(font.label, style: Theme.of(context).textTheme.labelSmall, maxLines: 1),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "Size  [——●——]  80%".
class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.text,
    required this.onChanged,
    this.onDrag,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String text;
  final ValueChanged<double> onChanged;

  /// True when a drag starts, false when it ends.
  final ValueChanged<bool>? onDrag;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        children: [
          SizedBox(width: 64, child: Text(label)),
          Expanded(
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
              onChangeStart: (_) => onDrag?.call(true),
              onChangeEnd: (_) => onDrag?.call(false),
            ),
          ),
          SizedBox(width: 84, child: Text(text, textAlign: TextAlign.end)),
        ],
      ),
    );
  }
}

/// Solid or gradient; a ready-made gradient or one's own colours, and
/// which way it runs; every colour picked on a wheel or typed as hex.
class _ColourSection extends StatefulWidget {
  const _ColourSection({required this.settings, required this.onChanged, required this.onDrag});

  final ClockSettings settings;
  final ValueChanged<ClockSettings> onChanged;

  /// True while the wheel or a slider is held (saved once let go).
  final ValueChanged<bool> onDrag;

  @override
  State<_ColourSection> createState() => _ColourSectionState();
}

class _ColourSectionState extends State<_ColourSection> {
  /// The gradient colour the wheel edits.
  int _stop = 0;

  ClockSettings get _s => widget.settings;

  void _setGradient(List<int> colors) => widget.onChanged(_s.copyWith(gradient: () => colors));

  @override
  Widget build(BuildContext context) {
    final gradient = _s.gradient;
    final stop = gradient == null ? 0 : _stop.clamp(0, gradient.length - 1);
    final editing = Color(gradient == null ? _s.color : gradient[stop]);
    final mode = _s.wallpaperColors
        ? _ColourMode.wallpaper
        : (gradient == null ? _ColourMode.solid : _ColourMode.gradient);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<_ColourMode>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: _ColourMode.solid, icon: Icon(Icons.circle), label: Text('Solid')),
              ButtonSegment(value: _ColourMode.gradient, icon: Icon(Icons.gradient_rounded), label: Text('Gradient')),
              ButtonSegment(
                value: _ColourMode.wallpaper,
                icon: Icon(Icons.wallpaper_rounded),
                label: Text('Wallpaper'),
              ),
            ],
            selected: {mode},
            onSelectionChanged: (v) {
              switch (v.first) {
                case _ColourMode.solid:
                  widget.onChanged(_s.copyWith(wallpaperColors: false, gradient: () => null));
                case _ColourMode.gradient:
                  widget.onChanged(
                    _s.copyWith(
                      wallpaperColors: false,
                      gradient: () => gradient ?? [for (final c in clockGradients.first.$2) c.toARGB32()],
                    ),
                  );
                case _ColourMode.wallpaper:
                  // Its real colours need the wallpaper image itself.
                  context.read<WindowBlurPlatform?>()?.requestWallpaperAccess();
                  widget.onChanged(_s.copyWith(wallpaperColors: true));
              }
            },
          ),
          if (mode == _ColourMode.wallpaper) ...[
            const SizedBox(height: 12),
            const _WallpaperSwatches(),
            const SizedBox(height: 8),
            _DirectionRow(
              value: _s.gradientDirection,
              onChanged: (d) => widget.onChanged(_s.copyWith(gradientDirection: d)),
            ),
          ] else if (gradient != null) ...[
            const SizedBox(height: 16),
            SizedBox(
              height: 64,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final (name, colors) in clockGradients)
                    _GradientChoice(
                      name: name,
                      colors: colors,
                      direction: _s.gradientDirection,
                      selected: listEquals(gradient, [for (final c in colors) c.toARGB32()]),
                      onTap: () {
                        setState(() => _stop = 0);
                        _setGradient([for (final c in colors) c.toARGB32()]);
                      },
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Text('Colours'),
                const SizedBox(width: 12),
                for (final (i, c) in gradient.indexed)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _StopDot(color: Color(c), selected: i == stop, onTap: () => setState(() => _stop = i)),
                  ),
                if (gradient.length < ClockSettings.maxStops)
                  IconButton(
                    tooltip: 'Add a colour',
                    onPressed: () {
                      setState(() => _stop = gradient.length);
                      _setGradient([...gradient, gradient.last]);
                    },
                    icon: const Icon(Icons.add_circle_outline_rounded),
                  ),
                if (gradient.length > 2)
                  IconButton(
                    tooltip: 'Remove this colour',
                    onPressed: () {
                      setState(() => _stop = (stop - 1).clamp(0, gradient.length - 2));
                      _setGradient([...gradient]..removeAt(stop));
                    },
                    icon: const Icon(Icons.remove_circle_outline_rounded),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            _DirectionRow(
              value: _s.gradientDirection,
              onChanged: (d) => widget.onChanged(_s.copyWith(gradientDirection: d)),
            ),
          ],
          if (mode != _ColourMode.wallpaper) ...[
            const SizedBox(height: 16),
            Center(
              child: ColorWheel(
                color: editing,
                onChangeStart: () => widget.onDrag(true),
                onChangeEnd: () => widget.onDrag(false),
                onChanged: (c) {
                  if (gradient == null) {
                    widget.onChanged(_s.copyWith(color: c.toARGB32()));
                  } else {
                    _setGradient([...gradient]..[stop] = c.toARGB32());
                  }
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// How a clock is coloured.
enum _ColourMode { solid, gradient, wallpaper }

/// "Direction  [→ ↘ ↓ ↗]": which way a gradient runs.
class _DirectionRow extends StatelessWidget {
  const _DirectionRow({required this.value, required this.onChanged});

  final GradientDirection value;
  final ValueChanged<GradientDirection> onChanged;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      const Text('Direction'),
      const SizedBox(width: 12),
      Expanded(
        child: SegmentedButton<GradientDirection>(
          showSelectedIcon: false,
          segments: [for (final d in GradientDirection.values) ButtonSegment(value: d, icon: Icon(d.icon))],
          selected: {value},
          onSelectionChanged: (v) => onChanged(v.first),
        ),
      ),
    ],
  );
}

/// The colours found in the wallpaper, or why there are none. Follows the
/// wallpaper when it changes.
class _WallpaperSwatches extends StatelessWidget {
  const _WallpaperSwatches();

  @override
  Widget build(BuildContext context) {
    final image = context.select<WindowBlurPlatform?, ui.Image?>((p) => p?.wallpaper);
    final note = Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white70);
    if (image == null) return Text('Waiting for the wallpaper…', style: note);
    return FutureBuilder<List<Color>?>(
      future: wallpaperColors(image),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) return Text('Reading the wallpaper…', style: note);
        final colors = snap.data;
        if (colors == null) {
          return Text('The wallpaper has little colour, so the clock keeps its own colours', style: note);
        }
        return Row(
          children: [
            const Text('Colours'),
            const SizedBox(width: 12),
            for (final c in colors)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _StopDot(color: c, selected: false, onTap: () {}),
              ),
            const SizedBox(width: 4),
            Expanded(child: Text('From your wallpaper; they change with it', style: note)),
          ],
        );
      },
    );
  }
}

/// A ready-made gradient: "9:41" in it, its name under it.
class _GradientChoice extends StatelessWidget {
  const _GradientChoice({
    required this.name,
    required this.colors,
    required this.direction,
    required this.selected,
    required this.onTap,
  });

  final String name;
  final List<Color> colors;
  final GradientDirection direction;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: scheme.surfaceContainerHigh,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: selected ? BorderSide(color: scheme.primary, width: 2) : BorderSide.none,
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: 76,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ShaderMask(
                  blendMode: BlendMode.srcIn,
                  shaderCallback: LinearGradient(
                    colors: colors,
                    begin: direction.begin,
                    end: direction.end,
                  ).createShader,
                  child: const Text('9:41', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, height: 1.1)),
                ),
                const SizedBox(height: 2),
                Text(name, style: Theme.of(context).textTheme.labelSmall, maxLines: 1),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One of a gradient's colours; tap to edit it on the wheel.
class _StopDot extends StatelessWidget {
  const _StopDot({required this.color, required this.selected, required this.onTap});

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: '#${ColorWheel.hexOf(color)}',
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? Theme.of(context).colorScheme.primary : Colors.white24,
              width: selected ? 3 : 1,
            ),
          ),
        ),
      ),
    );
  }
}
