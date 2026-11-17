import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../standard_home/home_layout.dart';
import '../../standard_home/home_layout_controller.dart';
import '../launcher_widgets.dart';

/// The brightness and volume widgets' shared look: monochrome and minimal,
/// on the launcher's glass, dark or Material panel. Their parts (pill
/// sliders, round buttons) are a darkening of the panel, and solid white
/// with black content when switched on. No borders, no labels.
///
/// On a [light] panel (Material light, PanelInk.lightOf) it's the other way
/// round: dark-inked content, and switched-on parts solid ink with white
/// content, so they still stand out.
abstract final class TileLook {
  static const motion = Duration(milliseconds: 200);

  static final _ink = GroupStyle.materialLight.ink;

  /// Content on a part: on its switched-on fill ([onWhite]), or not.
  static Color content(bool onWhite, {bool light = false}) =>
      light ? (onWhite ? Colors.white : _ink) : (onWhite ? Colors.black : Colors.white);

  /// Silent, when on.
  static const alert = Color(0xFFE5484D);

  static final _on = Colors.white.withValues(alpha: 0.95);

  /// A part's fill: switched [on], or not; on the [dark] panel or glass, or
  /// a [light] one.
  static Color part(bool on, bool dark, {bool light = false}) => light
      ? (on ? _ink : Colors.black.withValues(alpha: 0.07))
      : on
      ? _on
      : (dark ? Colors.white.withValues(alpha: 0.09) : Colors.black.withValues(alpha: 0.16));
}

/// The panels these widgets come on: glass blur (the default), dark, or
/// Material dark or light. Not the see-through light one: their white parts
/// need a darker panel, and Material light has its own dark-inked parts.
const controlsStyles = [GroupStyle.glass, GroupStyle.dark, GroupStyle.material, GroupStyle.materialLight];

/// Its panel (WidgetItem.settings['style']); anything else is glass.
GroupStyle controlsStyleOf(Map<String, dynamic> settings) => panelStyleFrom(settings['style'], styles: controlsStyles);

/// On a dark panel (dark or Material dark), its parts a lightening of it.
bool controlsDark(Map<String, dynamic> settings) =>
    const [GroupStyle.dark, GroupStyle.material].contains(controlsStyleOf(settings));

/// Their options: the panel (see [controlsStyles]).
Future<void> showControlsSettings(BuildContext context, WidgetItem item) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  barrierColor: Colors.black26,
  builder: (_) => _ControlsSettingsSheet(id: item.id),
);

class _ControlsSettingsSheet extends StatelessWidget {
  const _ControlsSettingsSheet({required this.id});

  final String id;

  @override
  Widget build(BuildContext context) {
    final layout = context.watch<HomeLayoutController>();
    final item = layout.findWidget(id);
    if (item == null) return const SizedBox.shrink();
    final style = controlsStyleOf(item.settings);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Background', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            PanelStylePicker(
              value: style,
              styles: controlsStyles,
              onChanged: (s) =>
                  layout.updateWidgetSettings(id, {...item.settings, 'style': (s ?? GroupStyle.glass).name}),
            ),
          ],
        ),
      ),
    );
  }
}

/// A round on/off button in these widgets: just its icon. Its name is for
/// screen readers.
class RoundButton extends StatelessWidget {
  const RoundButton({
    super.key,
    required this.icon,
    required this.label,
    required this.active,
    required this.dark,
    required this.size,
    required this.onTap,
    this.activeColor,
  });

  /// When on: this fill, with a white icon, instead of white with black
  /// (ink with white on a light panel).
  final Color? activeColor;

  final IconData icon;
  final String label;
  final bool active;
  final bool dark;
  final double size;

  /// Null: not available on this phone (shown faded).
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final light = PanelInk.lightOf(context);
    final color = active && activeColor != null ? Colors.white : TileLook.content(active, light: light);
    return Semantics(
      button: true,
      toggled: active,
      label: label,
      excludeSemantics: true,
      child: Opacity(
        opacity: onTap == null ? 0.4 : 1,
        child: AnimatedContainer(
          duration: TileLook.motion,
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: active && activeColor != null ? activeColor : TileLook.part(active, dark, light: light),
          ),
          child: Material(
            type: MaterialType.transparency,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: Center(
                child: AnimatedSwitcher(
                  duration: TileLook.motion,
                  child: Icon(icon, key: ValueKey((icon, active)), size: size * 0.56, color: color),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
