import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/apps/apps_controller.dart';
import '../../core/models/app_info.dart';
import '../../core/models/icon_shape.dart';
import '../../core/models/icon_style.dart';
import '../../core/platform/launcher_platform.dart';
import '../../core/widgets/app_icon.dart';
import '../dock/dock_controller.dart';
import '../hidden_apps/visible_apps.dart';
import 'appearance_controller.dart';

/// Settings for how app icons look: source (pack), plate, colour, line
/// weight, size, shape, and what unmatched apps get. A live preview of real
/// apps sits on top; slider drags only re-render the preview, and the whole
/// icon set is re-rendered when a value is let go.
class IconsScreen extends StatefulWidget {
  const IconsScreen({super.key});

  @override
  State<IconsScreen> createState() => _IconsScreenState();
}

class _IconsScreenState extends State<IconsScreen> {
  static const _previewCount = 5;
  static const _sampleCount = 3;

  late final AppearanceController _appearance = context.read<AppearanceController>();
  late final AppsController _apps = context.read<AppsController>();

  /// What the preview shows. Equal to the applied values except mid-drag.
  late IconStyle _style = _appearance.iconStyle;
  late IconShape _shape = _appearance.iconShape;

  List<AppInfo> _samples = const [];
  Map<String, Uint8List> _preview = const {};
  Map<IconSource, Map<String, Uint8List>> _sourceSamples = const {};
  Timer? _debounce;
  int _generation = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_samples.isEmpty) {
      _samples = _pickSamples();
      if (_samples.isNotEmpty) _renderPreviews();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  /// Dock apps first (the ones seen most), then the rest A–Z.
  List<AppInfo> _pickSamples() {
    final visible = context.read<VisibleApps>();
    final apps = visible.apps.where((a) => a.packageName != LauncherPlatform.selfPackage);
    final dock = context.read<DockController>().ids.map(visible.byId).whereType<AppInfo>();
    return {...dock, ...apps}.take(_previewCount).toList();
  }

  // --- preview and apply ---------------------------------------------------------

  void _update({IconStyle? style, IconShape? shape, bool apply = true}) {
    setState(() {
      _style = style ?? _style;
      _shape = shape ?? _shape;
    });
    if (apply) {
      _appearance.setIconStyle(_style);
      _appearance.setIconShape(_shape);
    }
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 40), () => _renderPreviews(samples: apply));
  }

  Future<void> _renderPreviews({bool samples = true}) async {
    final generation = ++_generation;
    final size = (56 * MediaQuery.devicePixelRatioOf(context)).round();
    final ids = _samples.map((a) => a.id).toList();
    final style = _style;
    final shape = _shape;

    final preview = await _apps.previewIcons(ids, shape: shape, style: style, sizePx: size);
    if (!mounted || generation != _generation) return;
    setState(() => _preview = preview);

    if (!samples) return;
    final sampleIds = ids.take(_sampleCount).toList();
    final results = await Future.wait([
      for (final source in IconSource.values)
        _apps.previewIcons(
          sampleIds,
          shape: shape,
          style: style.copyWith(source: source),
          sizePx: size,
        ),
    ]);
    if (!mounted || generation != _generation) return;
    setState(() => _sourceSamples = {for (final (i, s) in IconSource.values.indexed) s: results[i]});
  }

  Future<void> _confirmReset() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset icons?'),
        content: const Text(
          'Back to each app\'s own icon in the phone\'s shape. Icons you picked for single apps stay.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Reset')),
        ],
      ),
    );
    if (ok == true) _update(style: IconStyle.defaults, shape: IconShape.system);
  }

  // --- layout ----------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final overrides = context.select<AppearanceController, int>((a) => a.iconOverrides.length);
    final glyphs = !_style.isOriginal;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Icons'),
        actions: [IconButton(tooltip: 'Reset icons', icon: const Icon(Icons.restart_alt), onPressed: _confirmReset)],
      ),
      body: Column(
        children: [
          _PreviewStrip(apps: _samples, icons: _preview),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 32),
              children: [
                const _Header('Icon pack'),
                _SourceGrid(
                  selected: _style.source,
                  samples: _sourceSamples,
                  sampleApps: _samples.take(_sampleCount).toList(),
                  onSelected: (s) => _update(style: _style.copyWith(source: s)),
                ),
                if (glyphs)
                  SwitchListTile(
                    title: const Text('Fill in missing icons'),
                    subtitle: Text(
                      _style.source == IconSource.themed
                          ? 'Use Lawnicons or Arcticons for apps without a monochrome icon'
                          : 'Use the other pack or Android\'s monochrome icon when ${_style.source.label} has none',
                    ),
                    value: _style.fillGaps,
                    onChanged: (v) => _update(style: _style.copyWith(fillGaps: v)),
                  ),
                _Collapsible(
                  visible: glyphs,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const _Header('Style'),
                      _Label('Background'),
                      _ChipRow<IconBackground>(
                        values: IconBackground.values,
                        selected: _style.background,
                        label: (b) => b.label,
                        onSelected: (b) => _update(style: _style.copyWith(background: b)),
                      ),
                      _Label('Colour'),
                      _ColourRow(
                        style: _style,
                        onColour: (c) => _update(style: _style.copyWith(color: c, appColor: false)),
                        onAppColour: () => _update(style: _style.copyWith(appColor: true)),
                      ),
                      _SliderRow(
                        label: 'Line weight',
                        valueLabel: '${(_style.lineWeight * 100).round()}%',
                        min: IconStyle.minLineWeight,
                        max: IconStyle.maxLineWeight,
                        divisions: 10,
                        value: _style.lineWeight,
                        startHint: 'Thin',
                        endHint: 'Bold',
                        onChanged: (v) => _update(style: _style.copyWith(lineWeight: v), apply: false),
                        onChangeEnd: (v) => _update(style: _style.copyWith(lineWeight: v)),
                      ),
                      _SliderRow(
                        label: 'Icon size',
                        valueLabel: '${(_style.glyphScale * 100).round()}%',
                        min: IconStyle.minGlyphScale,
                        max: IconStyle.maxGlyphScale,
                        divisions: 7,
                        value: _style.glyphScale,
                        startHint: 'Small',
                        endHint: 'Large',
                        onChanged: (v) => _update(style: _style.copyWith(glyphScale: v), apply: false),
                        onChangeEnd: (v) => _update(style: _style.copyWith(glyphScale: v)),
                      ),
                    ],
                  ),
                ),

                const _Header('App icons'),
                if (glyphs)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                    child: Text(
                      'For apps shown with their own icon (no pack icon, or set to Original).',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                _Label('Icons that don\'t fill the shape'),
                _ChipRow<LegacyBackground>(
                  values: LegacyBackground.values,
                  selected: _style.legacyBackground,
                  label: (b) => b.label,
                  onSelected: (b) => _update(style: _style.copyWith(legacyBackground: b)),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                  child: Text(
                    '${_style.legacyBackground.description}. Older icons that already have a round or square shape '
                    'are scaled to fill it.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),

                const _Header('Shape'),
                _ShapePicker(
                  shape: _shape,
                  customRadius: _appearance.customRadius,
                  onDrag: (s) => _update(shape: s, apply: false),
                  onChanged: (s) => _update(shape: s),
                ),

                _Collapsible(
                  visible: glyphs,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const _Header('Apps without an icon'),
                      _ChipRow<IconFallback>(
                        values: IconFallback.values,
                        selected: _style.fallback,
                        label: (f) => f.label,
                        onSelected: (f) => _update(style: _style.copyWith(fallback: f)),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                        child: Text(_style.fallback.description, style: Theme.of(context).textTheme.bodySmall),
                      ),
                    ],
                  ),
                ),

                const _Header('Single apps'),
                ListTile(
                  leading: const Icon(Icons.touch_app_outlined),
                  title: const Text('Change one app\'s icon'),
                  subtitle: const Text('Long-press an app, then Change icon'),
                ),
                if (overrides > 0)
                  ListTile(
                    leading: const Icon(Icons.layers_clear_outlined),
                    title: Text('Reset $overrides custom ${overrides == 1 ? 'icon' : 'icons'}'),
                    onTap: () {
                      _appearance.clearIconOverrides().then((_) => _renderPreviews());
                    },
                  ),

                const _Credits(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The sample apps on a wallpaper-like backdrop, as the preview renders them.
class _PreviewStrip extends StatelessWidget {
  const _PreviewStrip({required this.apps, required this.icons});

  final List<AppInfo> apps;
  final Map<String, Uint8List> icons;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2B3440), Color(0xFF14181E), Color(0xFF241C2C)],
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          for (final app in apps)
            SizedBox(
              width: 60,
              child: Column(
                children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 150),
                    child: icons[app.id] != null
                        ? Image.memory(
                            icons[app.id]!,
                            key: ValueKey(icons[app.id].hashCode),
                            width: 52,
                            height: 52,
                            gaplessPlayback: true,
                            filterQuality: FilterQuality.medium,
                          )
                        : AppIcon(app: app, size: 52),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    app.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 11),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Two-by-two cards, each showing the sample apps in that source.
class _SourceGrid extends StatelessWidget {
  const _SourceGrid({
    required this.selected,
    required this.samples,
    required this.sampleApps,
    required this.onSelected,
  });

  final IconSource selected;
  final Map<IconSource, Map<String, Uint8List>> samples;
  final List<AppInfo> sampleApps;
  final ValueChanged<IconSource> onSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        childAspectRatio: 1.45,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        children: [
          for (final source in IconSource.values)
            _SourceCard(
              source: source,
              selected: source == selected,
              icons: [for (final app in sampleApps) samples[source]?[app.id]],
              onTap: () => onSelected(source),
            ),
        ],
      ),
    );
  }
}

class _SourceCard extends StatelessWidget {
  const _SourceCard({required this.source, required this.selected, required this.icons, required this.onTap});

  final IconSource source;
  final bool selected;
  final List<Uint8List?> icons;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Material(
      color: selected ? scheme.secondaryContainer : scheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: selected ? scheme.primary : Colors.transparent, width: 1.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  for (final icon in icons)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: icon == null
                          ? Container(
                              width: 30,
                              height: 30,
                              decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(15)),
                            )
                          : Image.memory(icon, width: 30, height: 30, gaplessPlayback: true),
                    ),
                  const Spacer(),
                  if (selected) Icon(Icons.check_circle, color: scheme.primary, size: 20),
                ],
              ),
              const Spacer(),
              Text(source.label, style: text.titleSmall),
              Text(
                source.description,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Swatches for the line colour, with "App colour" first.
class _ColourRow extends StatelessWidget {
  const _ColourRow({required this.style, required this.onColour, required this.onAppColour});

  final IconStyle style;
  final ValueChanged<int> onColour;
  final VoidCallback onAppColour;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: [
          _Swatch(
            tooltip: 'App colour',
            selected: style.appColor,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: SweepGradient(
                colors: [
                  Color(0xFFFF9EB5),
                  Color(0xFFF2E38C),
                  Color(0xFF8FE3C6),
                  Color(0xFF8EC9FF),
                  Color(0xFFC3B2FF),
                  Color(0xFFFF9EB5),
                ],
              ),
            ),
            onTap: onAppColour,
          ),
          for (final c in IconStyle.palette)
            _Swatch(
              tooltip: '#${(c & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}',
              selected: !style.appColor && style.color == c,
              decoration: BoxDecoration(shape: BoxShape.circle, color: Color(c)),
              onTap: () => onColour(c),
            ),
        ],
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.tooltip, required this.selected, required this.decoration, required this.onTap});

  final String tooltip;
  final bool selected;
  final BoxDecoration decoration;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ring = Theme.of(context).colorScheme.primary;
    return Tooltip(
      message: tooltip,
      child: InkResponse(
        onTap: onTap,
        radius: 24,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 44,
          height: 44,
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: selected ? ring : Colors.transparent, width: 2),
          ),
          child: DecoratedBox(
            decoration: decoration,
            child: selected ? const Icon(Icons.check, size: 18, color: Colors.black87) : null,
          ),
        ),
      ),
    );
  }
}

/// System mask, or a custom corner radius.
class _ShapePicker extends StatefulWidget {
  const _ShapePicker({required this.shape, required this.customRadius, required this.onDrag, required this.onChanged});

  final IconShape shape;
  final int customRadius;
  final ValueChanged<IconShape> onDrag;
  final ValueChanged<IconShape> onChanged;

  @override
  State<_ShapePicker> createState() => _ShapePickerState();
}

class _ShapePickerState extends State<_ShapePicker> {
  late int _lastRadius = widget.shape.radius ?? widget.customRadius;

  @override
  Widget build(BuildContext context) {
    final radius = widget.shape.radius;
    if (radius != null) _lastRadius = radius;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: true, label: Text('Phone default'), icon: Icon(Icons.smartphone_outlined)),
              ButtonSegment(value: false, label: Text('Custom'), icon: Icon(Icons.rounded_corner)),
            ],
            selected: {radius == null},
            onSelectionChanged: (s) => widget.onChanged(s.single ? IconShape.system : IconShape.rounded(_lastRadius)),
          ),
        ),
        _Collapsible(
          visible: radius != null,
          child: _SliderRow(
            label: 'Corners',
            valueLabel: IconShape.rounded(_lastRadius).label,
            min: 0,
            max: IconShape.maxRadius.toDouble(),
            divisions: IconShape.maxRadius ~/ 5,
            value: _lastRadius.toDouble(),
            startHint: 'Square',
            endHint: 'Round',
            onChanged: (v) => widget.onDrag(IconShape.rounded(v.round())),
            onChangeEnd: (v) => widget.onChanged(IconShape.rounded(v.round())),
          ),
        ),
      ],
    );
  }
}

// --- small building blocks -----------------------------------------------------------

class _Header extends StatelessWidget {
  const _Header(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(color: Theme.of(context).colorScheme.primary),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
      child: Text(text, style: Theme.of(context).textTheme.titleSmall),
    );
  }
}

class _ChipRow<T> extends StatelessWidget {
  const _ChipRow({required this.values, required this.selected, required this.label, required this.onSelected});

  final List<T> values;
  final T selected;
  final String Function(T) label;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          for (final v in values)
            ChoiceChip(label: Text(label(v)), selected: v == selected, onSelected: (_) => onSelected(v)),
        ],
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.valueLabel,
    required this.min,
    required this.max,
    required this.divisions,
    required this.value,
    required this.startHint,
    required this.endHint,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final String label;
  final String valueLabel;
  final double min;
  final double max;
  final int divisions;
  final double value;
  final String startHint;
  final String endHint;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hint = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(label, style: theme.textTheme.titleSmall),
              const Spacer(),
              Text(valueLabel, style: hint),
            ],
          ),
          Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
            onChangeEnd: onChangeEnd,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(startHint, style: hint),
                Text(endHint, style: hint),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Animates [child] in and out of the list.
class _Collapsible extends StatelessWidget {
  const _Collapsible({required this.visible, required this.child});

  final bool visible;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: visible ? child : const SizedBox(width: double.infinity),
    );
  }
}

class _Credits extends StatelessWidget {
  const _Credits();

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 32, 16, 0),
      child: Text(
        'Lawnicons by the Lawnchair team, Apache 2.0.\n'
        'Arcticons by the Arcticons team, CC BY-SA 4.0; recoloured and resized here.\n'
        'Generated monochrome icons use AOSP Launcher3 code, Apache 2.0.',
        style: style,
      ),
    );
  }
}
