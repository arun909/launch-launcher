import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/platform/window_blur_platform.dart';
import '../appearance/wallpaper_glass.dart';
import '../standard_home/app_container_tile.dart';
import '../standard_home/home_layout.dart';
import 'activity/activity_widget.dart';
import 'chrome/chrome_widget.dart';
import 'clock/analog_clock.dart';
import 'clock/digital_clock.dart';
import 'clock/futuristic_clock.dart';
import 'controls/brightness_widget.dart';
import 'controls/volume_widget.dart';
import 'instant/instant_widget.dart';
import 'music/music_widget.dart';

/// Builds a launcher widget's content from one instance's settings
/// (WidgetItem.settings).
typedef LauncherWidgetBuilder = Widget Function(BuildContext context, Map<String, dynamic> settings);

/// One of the launcher's own widgets: drawn in Flutter, nothing to bind or
/// allow. A new one = a const entry in [values] with a [build] function.
///
/// Each has the size it starts at and the range it can be resized in, in
/// cells: below its least size its content wouldn't fit cleanly.
@immutable
class LauncherWidgetKind {
  const LauncherWidgetKind({
    required this.name,
    required this.label,
    required this.description,
    required this.icon,
    required this.size,
    required this.min,
    required this.max,
    required this.build,
    this.customise,
    this.panelOf = _alwaysPanel,
    this.styleOf = _glass,
    this.interactive = false,
    this.backdrop,
    this.sizes,
    this.group,
  });

  static bool _alwaysPanel(Map<String, dynamic> settings) => true;
  static GroupStyle _glass(Map<String, dynamic> settings) => GroupStyle.glass;

  /// Stored in the layout (WidgetItem.launcherKind); never change it.
  final String name;
  final String label;
  final String description;
  final IconData icon;

  /// (cols, rows) it starts at, and its limits.
  final (int, int) size;
  final (int, int) min;
  final (int, int) max;

  /// Its content, filling the panel inside the padding.
  final LauncherWidgetBuilder build;

  /// Opens its options for one instance; null if it has none.
  final Future<void> Function(BuildContext context, WidgetItem item)? customise;

  /// Whether an instance with these settings sits on a glass panel (else
  /// its content is drawn straight on the wallpaper).
  final bool Function(Map<String, dynamic> settings) panelOf;

  /// Its content takes taps (buttons) on the home screen; else the whole
  /// widget is one touch target (long press / drag only). Long press still
  /// moves and resizes it either way, and nothing inside gets touches while
  /// arranging.
  final bool interactive;

  /// The look of an instance's panel: light, dark or glass, as a group's
  /// ([panelStyles]).
  final GroupStyle Function(Map<String, dynamic> settings) styleOf;

  /// Drawn across the whole panel, over its background and under the
  /// content (e.g. a tint taken from what's shown); null for none.
  final LauncherWidgetBuilder? backdrop;

  /// The picker's section it's listed under with its kin (e.g. 'Clocks');
  /// null: on its own.
  final String? group;

  /// The only spans it comes in, (cols, rows), when not every size within
  /// [min]–[max] makes sense; resizing snaps to the nearest. Null: any.
  final List<(int, int)>? sizes;

  /// [cols] × [rows] as this kind allows it: the nearest of [sizes] (by
  /// cells), else as it is. On a grid of [gridColumns], a size wider than
  /// it means the grid's full width (a 6-wide one is 5 wide on 5 columns).
  (int, int) snap(int cols, int rows, {int? gridColumns}) {
    final all = sizes;
    if (all == null || all.isEmpty) return (cols, rows);
    final g = gridColumns;
    final s = g == null ? all : {for (final (c, r) in all) (c < g ? c : g, r)}.toList();
    int d((int, int) o) => (o.$1 - cols) * (o.$1 - cols) + (o.$2 - rows) * (o.$2 - rows);
    return s.reduce((a, b) => d(b) < d(a) ? b : a);
  }

  /// Every launcher widget.
  static const values = <LauncherWidgetKind>[
    digitalClockKind,
    analogClockKind,
    futuristicClockKind,
    musicKind,
    instantKind,
    chromeKind,
    activityKind,
    brightnessKind,
    volumeKind,
  ];

  static LauncherWidgetKind? fromName(String? name) => values.where((k) => k.name == name).firstOrNull;
}

/// A launcher widget filling its frame, on frosted glass like a folder's.
class LauncherWidgetView extends StatelessWidget {
  const LauncherWidgetView({
    super.key,
    required this.kind,
    required this.radius,
    required this.padding,
    this.settings = const {},
  });

  final LauncherWidgetKind kind;

  /// This instance's options (WidgetItem.settings).
  final Map<String, dynamic> settings;

  /// Corner radius of its panel.
  final double radius;

  /// Space inside the panel: the same as a container's around its icons.
  final double padding;

  @override
  Widget build(BuildContext context) {
    final onPanel = kind.panelOf(settings);
    final style = kind.styleOf(settings);
    // Without a panel it's on the wallpaper: white, whatever the style.
    final content = PanelInk(
      style: onPanel ? style : GroupStyle.glass,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: padding + 4, vertical: padding),
        child: Builder(builder: (context) => kind.build(context, settings)),
      ),
    );
    if (!onPanel) return content;
    final decoration = AppContainerTile.decoration(radius, style);
    final backdrop = kind.backdrop;
    final panel = DecoratedBox(
      decoration: decoration,
      child: backdrop == null
          ? content
          : Stack(
              fit: StackFit.expand,
              children: [
                Positioned.fill(
                  child: ClipPath(
                    clipper: ShapeBorderClipper(shape: decoration.shape),
                    child: Builder(builder: (context) => backdrop(context, settings)),
                  ),
                ),
                content,
              ],
            ),
    );
    if (style != GroupStyle.glass) return panel;
    return WallpaperGlass(shape: decoration.shape, child: panel);
  }
}

/// The panel looks a launcher widget offers: the same as a group's
/// backgrounds (bar its colours).
const panelStyles = [
  GroupStyle.light,
  GroupStyle.dark,
  GroupStyle.glass,
  GroupStyle.material,
  GroupStyle.materialLight,
];

/// What a launcher widget's content is drawn on, so it can pick its colours:
/// white on the see-through and dark panels, dark on a light one
/// ([GroupStyle.materialLight]). Also sets the default text and icon colour.
class PanelInk extends InheritedWidget {
  PanelInk({super.key, required this.style, required Widget child})
    : super(
        child: DefaultTextStyle.merge(
          style: TextStyle(color: style.ink),
          child: IconTheme.merge(data: IconThemeData(color: style.ink), child: child),
        ),
      );

  final GroupStyle style;

  /// The panel's style; glass (white content) outside any panel.
  static GroupStyle styleOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PanelInk>()?.style ?? GroupStyle.glass;

  /// The panel's content is drawn dark.
  static bool lightOf(BuildContext context) => styleOf(context).isLightSurface;

  /// Text and glyphs: white, or near-black on a light panel. Use it where
  /// the content would be Colors.white, keeping the alpha:
  /// `PanelInk.of(context).withValues(alpha: 0.6)`.
  static Color of(BuildContext context) => styleOf(context).ink;

  @override
  bool updateShouldNotify(PanelInk old) => old.style != style;
}

/// A stored panel style ([GroupStyle.name]); [fallback] if unset or unknown.
/// [styles]: the looks this widget offers (default [panelStyles]).
GroupStyle panelStyleFrom(Object? name, {GroupStyle fallback = GroupStyle.glass, List<GroupStyle> styles = panelStyles}) =>
    styles.where((s) => s.name == name).firstOrNull ?? fallback;

/// Light / Dark / Glass blur, as a group's backgrounds are labelled; with
/// [allowNone], also "None" (null): straight on the wallpaper.
class PanelStylePicker extends StatelessWidget {
  const PanelStylePicker({
    super.key,
    required this.value,
    required this.onChanged,
    this.allowNone = false,
    this.styles = panelStyles,
  });

  /// The looks offered (default [panelStyles]).
  final List<GroupStyle> styles;

  /// Null: no panel.
  final GroupStyle? value;
  final ValueChanged<GroupStyle?> onChanged;
  final bool allowNone;

  static String _label(GroupStyle s) => switch (s) {
    GroupStyle.light => 'Light',
    GroupStyle.dark => 'Dark',
    GroupStyle.glass => 'Glass blur',
    GroupStyle.color => 'Colour',
    GroupStyle.material => 'Material dark',
    GroupStyle.materialLight => 'Material light',
  };

  static IconData _icon(GroupStyle s) => switch (s) {
    GroupStyle.light => Icons.light_mode_outlined,
    GroupStyle.dark => Icons.dark_mode_outlined,
    GroupStyle.glass => Icons.blur_on,
    GroupStyle.color => Icons.palette_outlined,
    GroupStyle.material => Icons.layers_outlined,
    GroupStyle.materialLight => Icons.layers,
  };

  void _pick(BuildContext context, GroupStyle? picked) {
    // Glass needs the wallpaper image.
    if (picked == GroupStyle.glass) context.read<WindowBlurPlatform?>()?.requestWallpaperAccess();
    onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    // More than fit on one line: chips, wrapping.
    if (styles.length + (allowNone ? 1 : 0) > 3) {
      Widget chip(GroupStyle? s) => ChoiceChip(
        avatar: Icon(s == null ? Icons.wallpaper_outlined : _icon(s), size: 18),
        label: Text(s == null ? 'None' : _label(s)),
        showCheckmark: false,
        selected: value == s,
        onSelected: (_) => _pick(context, s),
      );
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [if (allowNone) chip(null), for (final s in styles) chip(s)],
      );
    }
    return SegmentedButton<String>(
      showSelectedIcon: false,
      segments: [
        if (allowNone) const ButtonSegment(value: 'none', icon: Icon(Icons.wallpaper_outlined), label: Text('None')),
        // Four or more: labels only, so each still fits on one line.
        for (final s in styles)
          ButtonSegment(
            value: s.name,
            icon: Icon(_icon(s)),
            label: Text(_label(s), maxLines: 1),
          ),
      ],
      selected: {value?.name ?? 'none'},
      onSelectionChanged: (v) => _pick(context, styles.where((s) => s.name == v.first).firstOrNull),
    );
  }
}

/// [w]'s span snapped to what its launcher widget kind allows (see
/// LauncherWidgetKind.sizes); app widgets as they are.
(int, int) snapSpan(WidgetItem w, int cols, int rows, {int? gridColumns}) =>
    LauncherWidgetKind.fromName(w.launcherKind)?.snap(cols, rows, gridColumns: gridColumns) ?? (cols, rows);

/// A launcher widget's own corner roundness, set with the corner knob while
/// arranging (WidgetItem.settings['radius']), as a container's is: one of
/// [widgetRadii]. Null: the default for its size (HomeWidgetView.radiusFor).
double? widgetRadiusSetting(Map<String, dynamic> settings) => (settings['radius'] as num?)?.toDouble();

/// The three roundnesses a launcher widget comes in, as containers do
/// (AppContainerTile.radiusNames: Square, Soft, Rounded), for a panel of
/// [frame]: never more than half its shorter side.
List<double> widgetRadii(Size frame) => [
  for (final r in const [0.0, 14.0, 28.0]) r.clamp(0.0, frame.shortestSide / 2),
];

/// The radius a launcher widget with [settings] is drawn with in [frame];
/// [fallback] when it has none of its own.
double launcherWidgetRadius(Map<String, dynamic> settings, Size frame, double fallback) {
  final own = widgetRadiusSetting(settings);
  if (own == null) return fallback;
  final steps = widgetRadii(frame);
  return steps.reduce((a, b) => (own - a).abs() <= (own - b).abs() ? a : b);
}
