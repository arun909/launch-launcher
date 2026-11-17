import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/models/app_info.dart';
import '../../core/widgets/app_icon.dart';
import '../app_actions/app_actions_sheet.dart';
import '../hidden_apps/visible_apps.dart';
import '../appearance/wallpaper_glass.dart';
import '../standard_home/app_container_tile.dart';
import '../standard_home/corner_shapes.dart';
import '../standard_home/home_layout.dart';
import '../standard_home/home_layout_controller.dart';
import '../widgets/launcher_widgets.dart';
import 'dock_controller.dart';

/// Frosted bar of label-less app icons at the bottom of the home screen.
///
/// Spacing follows the home grid, as Android's own launcher does with its
/// hotseat: the dock is as wide as the grid, and each app sits centred in a
/// slot one grid column wide, so with as many apps as columns they line up
/// under the home icons with the same gaps between them. More apps than
/// columns are spaced evenly: the gaps at the bar's ends equal the gaps
/// between icons. The bar's padding above and below the icons is 16dp, a
/// Material 3 spacing step.
///
/// Drag and drop: hold an app and drag it along the dock to reorder, or out
/// onto the home screen (into a cell, folder or onto an app). Apps dragged in
/// from the home screen or a folder join the dock where they're dropped;
/// into a full dock, they trade places with the app they're dropped on,
/// which goes back to the home screen. While anything is dragged, an empty
/// dock shows where to drop.
class Dock extends StatefulWidget {
  const Dock({super.key});

  /// Space above and below the icons.
  static const verticalPadding = 16.0;

  @override
  State<Dock> createState() => _DockState();
}

class _DockState extends State<Dock> {
  /// The app being dragged over the dock, and where it would go.
  String? _incoming;
  int? _at;

  static String? _appIdOf(String key) => key.startsWith('app:') ? key.substring(4) : null;

  void _clear() {
    if (_incoming != null || _at != null) {
      setState(() {
        _incoming = null;
        _at = null;
      });
    }
  }

  /// Slot width for [count] apps of [icon] size across [width]: a grid
  /// column, or with more apps than columns, an icon plus an even gap (the
  /// row is centred, so the ends get a full gap too).
  double _slot(double width, int count, int columns, double icon) =>
      count > columns ? icon + (width - count * icon) / (count + 1) : width / math.max(math.max(count, 1), columns);

  Future<void> _accept(String key, List<String> shown) async {
    final id = _appIdOf(key);
    final at = _at;
    _clear();
    if (id == null) return;
    final layout = context.read<HomeLayoutController>();
    final dock = context.read<DockController>();
    final wasDocked = dock.isPinned(id);
    final from = layout.slots[key];
    final inFolder = layout.containerOf(id) != null;
    HapticFeedback.lightImpact();
    final replaced = await dock.placeAt(id, at ?? shown.length, shown);
    // Out of its folder: the dock is where it lives now.
    if (inFolder) layout.removeFromContainer(id);
    // Swapped with a home app: the one it replaced takes its spot.
    if (replaced != null && !wasDocked && !inFolder && from != null) layout.place('app:$replaced', from);
  }

  @override
  Widget build(BuildContext context) {
    final visible = context.watch<VisibleApps>();
    final dock = context.watch<DockController>();
    final apps = dock.ids
        .map(visible.byId) // hidden or uninstalled -> null -> dropped
        .whereType<AppInfo>()
        .toList();
    final layout = context.watch<HomeLayoutController>();
    final dragging = layout.dragging && layout.mode == HomeMode.standard;
    if (apps.isEmpty && !dragging) return const SizedBox.shrink();
    // Same icon size and columns as the home grid (HomeGrid).
    final grid = layout.grid;
    final cell = layout.cellSize;
    final shown = [for (final a in apps) a.id];

    return LayoutBuilder(
      builder: (context, box) {
        final width = box.maxWidth;
        final incoming = _incoming;
        // A new app into a full dock replaces one; otherwise it makes room.
        final replacing = incoming != null && !shown.contains(incoming) && dock.isFull;
        final order = [...shown];
        if (incoming != null && !replacing) {
          order.remove(incoming);
          order.insert((_at ?? order.length).clamp(0, order.length), incoming);
        }
        final slot = _slot(width, order.length, grid.columns, grid.iconSize);
        // Fitted: just its slots, plus enough at the ends that the edge gap
        // is at least the padding above and below.
        final edge = math.max(0.0, Dock.verticalPadding - (slot - grid.iconSize) / 2);
        final barWidth = dock.fitToApps ? math.min(width, math.max(1, order.length) * slot + 2 * edge) : width;

        void hover(DragTargetDetails<String> d) {
          final id = _appIdOf(d.data);
          if (id == null) return;
          final rowBox = context.findRenderObject() as RenderBox?;
          if (rowBox == null) return;
          // Dragged items are carried centred on a home cell's middle.
          final x = rowBox.globalToLocal(d.offset + Offset(cell.width / 2, cell.height / 2)).dx;
          final replace = !shown.contains(id) && dock.isFull;
          final count = replace || shown.contains(id) ? shown.length : shown.length + 1;
          final s = _slot(width, count, grid.columns, grid.iconSize);
          final start = (width - count * s) / 2;
          final at = ((x - start) / s).floor().clamp(0, math.max(0, count - 1)).toInt();
          if (id != _incoming || at != _at) {
            if (at != _at) HapticFeedback.selectionClick();
            setState(() {
              _incoming = id;
              _at = at;
            });
          }
        }

        final byId = {for (final a in apps) a.id: a};
        return DragTarget<String>(
          onWillAcceptWithDetails: (d) => _appIdOf(d.data) != null,
          onMove: hover,
          onLeave: (_) => _clear(),
          onAcceptWithDetails: (d) => _accept(d.data, shown),
          // The drop area is the dock's whole width, even when the bar is
          // fitted narrower, so apps can be dropped past its ends.
          builder: (context, _, _) => Align(
            heightFactor: 1,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              width: barWidth,
              child: _DockBackground(
                style: dock.style,
                highlighted: incoming != null,
                onLongPress: () => showDockStyle(context),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: Dock.verticalPadding),
                  child: SizedBox(
                    height: grid.iconSize,
                    // Fitted, the row is wider than the bar while it animates;
                    // it stays centred and is clipped by the panel.
                    child: OverflowBox(
                      maxWidth: width,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          for (final (i, id) in order.indexed)
                            AnimatedContainer(
                              key: ValueKey(id),
                              duration: const Duration(milliseconds: 180),
                              curve: Curves.easeOutCubic,
                              width: slot,
                              child: Center(
                                child: switch (byId[id]) {
                                  final app? => _DockTile(
                                    app: app,
                                    size: grid.iconSize,
                                    cell: cell,
                                    replacing: replacing && i == _at,
                                  ),
                                  // An app coming in: where it will go.
                                  null => _DropSpot(size: grid.iconSize),
                                },
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The bar's panel in the dock's [style], as a group's: light, dark, or
/// glass (the wallpaper behind it blurred, see WallpaperGlass; a plain
/// BackdropFilter can't reach Android's wallpaper). [highlighted] while an
/// app is dragged over it. A long press on its empty space picks the style.
///
/// The outline is drawn in front, not in the decoration: a border there
/// would inset the row and shift the icons off the grid's columns.
class _DockBackground extends StatelessWidget {
  const _DockBackground({
    required this.style,
    required this.highlighted,
    required this.onLongPress,
    required this.child,
  });

  final GroupStyle style;
  final bool highlighted;
  final VoidCallback onLongPress;
  final Widget child;

  static const radius = 28.0;

  @override
  Widget build(BuildContext context) {
    final look = AppContainerTile.decoration(radius, style);
    final lift = highlighted ? 0.08 : 0.0;
    final fill = look.color!;
    final shape = CornerShapes.shape(radius);
    final panel = Stack(
      children: [
        // Behind the icons: a long press here (not on an app) opens the
        // style sheet.
        Positioned.fill(
          child: GestureDetector(behavior: HitTestBehavior.opaque, onLongPress: onLongPress),
        ),
        child,
      ],
    );
    final body = DecoratedBox(
      decoration: ShapeDecoration(
        shape: shape,
        color: fill.withValues(alpha: (fill.a + lift).clamp(0.0, 1.0)),
      ),
      position: DecorationPosition.background,
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: ShapeDecoration(
          shape: CornerShapes.shape(
            radius,
            side: BorderSide(
              color: highlighted
                  ? style.ink.withValues(alpha: 0.4)
                  : (look.shape as OutlinedBorder).side.color,
            ),
          ),
        ),
        child: panel,
      ),
    );
    if (style != GroupStyle.glass) {
      return ClipPath(
        clipper: ShapeBorderClipper(shape: shape),
        child: body,
      );
    }
    return WallpaperGlass(shape: shape, child: body);
  }
}

/// The dock's background: Light, Dark, Glass blur or Material dark / light, as a group's.
Future<void> showDockStyle(BuildContext context) {
  HapticFeedback.mediumImpact();
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    barrierColor: Colors.black26,
    builder: (sheetContext) {
      final dock = sheetContext.watch<DockController>();
      final theme = Theme.of(sheetContext);
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Dock', style: theme.textTheme.titleLarge),
              const SizedBox(height: 16),
              Text('Background', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              PanelStylePicker(value: dock.style, onChanged: (v) => dock.setStyle(v ?? GroupStyle.light)),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Fit to apps'),
                subtitle: const Text('The dock is only as wide as its apps, and grows and shrinks with them'),
                value: dock.fitToApps,
                onChanged: dock.setFitToApps,
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// Where an app dragged in will land.
class _DropSpot extends StatelessWidget {
  const _DropSpot({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: Colors.white.withValues(alpha: 0.10),
      border: Border.all(color: Colors.white.withValues(alpha: 0.55), width: 1.5),
    ),
  );
}

/// A dock app: tap to open, hold for its menu, hold and drag to move it.
class _DockTile extends StatefulWidget {
  const _DockTile({required this.app, required this.size, required this.cell, required this.replacing});

  final AppInfo app;
  final double size;

  /// A home cell: what the app is carried as while dragged.
  final Size cell;

  /// An app dropped here would take its place.
  final bool replacing;

  @override
  State<_DockTile> createState() => _DockTileState();
}

class _DockTileState extends State<_DockTile> {
  double _moved = 0;

  /// Moving less than this before letting go is a long press: the app's menu.
  static const _dragSlop = 12.0;

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final cell = widget.cell;
    final icon = Tooltip(
      message: app.label,
      child: AppIcon(app: app, size: widget.size),
    );
    return LongPressDraggable<String>(
      data: 'app:${app.id}',
      delay: const Duration(milliseconds: 400),
      hapticFeedbackOnStart: true,
      dragAnchorStrategy: (_, _, _) => Offset(cell.width / 2, cell.height / 2),
      onDragStarted: () {
        _moved = 0;
        // Dropped on the home screen, this tile leaves the dock mid-drag.
        context.read<HomeLayoutController>()
          ..beginDrag()
          ..endDragOnRelease();
      },
      onDragUpdate: (d) => _moved += d.delta.distance,
      onDragEnd: (_) {
        if (_moved < _dragSlop) showAppActions(context, app);
      },
      feedback: Material(
        type: MaterialType.transparency,
        child: SizedBox.fromSize(
          size: cell,
          child: Center(
            child: AppIcon(app: app, size: widget.size * 1.06),
          ),
        ),
      ),
      // Its spot in the dock, kept while it's dragged.
      childWhenDragging: _DropSpot(size: widget.size),
      child: AnimatedOpacity(
        opacity: widget.replacing ? 0.45 : 1,
        duration: const Duration(milliseconds: 150),
        child: Stack(
          alignment: Alignment.center,
          children: [
            GestureDetector(behavior: HitTestBehavior.opaque, onTap: () => openApp(context, app), child: icon),
            if (widget.replacing)
              const IgnorePointer(child: Icon(Icons.swap_horiz_rounded, color: Colors.white, size: 28)),
          ],
        ),
      ),
    );
  }
}
