import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/models/app_info.dart';
import '../../core/models/icon_shape.dart';
import '../../core/platform/window_blur_platform.dart';
import '../../core/theme/home_grid.dart';
import '../../core/widgets/app_icon.dart';
import '../app_actions/app_actions_sheet.dart';
import '../appearance/wallpaper_blur.dart';
import '../appearance/wallpaper_glass.dart';
import '../hidden_apps/visible_apps.dart';
import 'app_container_tile.dart';
import 'home_layout.dart';
import 'home_layout_controller.dart';

/// The container's apps that are visible (not hidden, still installed).
List<AppInfo> visibleAppsOf(BuildContext context, AppContainer container) {
  final visible = context.watch<VisibleApps>();
  return container.appIds.map(visible.byId).whereType<AppInfo>().toList();
}

/// Opens a container: all its apps in a rounded panel over the home screen.
///
/// Hold an app and drag it past the panel's edge to take it out, as on
/// OriginOS and iOS: the panel closes, the home screen comes back in edit
/// mode, and the app goes on with the finger, landing like any dragged app
/// (on a cell, or into another app / folder). Held without dragging, its menu.
///
/// [context] is the tapped folder / container's own: the panel opens over
/// it (as far as the screen allows) and grows out of it.
Future<void> showContainer(BuildContext context, String containerId) {
  final box = context.findRenderObject() as RenderBox?;
  final origin = box != null && box.hasSize ? box.localToGlobal(Offset.zero) & box.size : null;
  final screen = MediaQuery.sizeOf(context);
  final grow = origin == null || screen.isEmpty
      ? Alignment.center
      : Alignment(origin.center.dx / screen.width * 2 - 1, origin.center.dy / screen.height * 2 - 1);
  return Navigator.of(context, rootNavigator: true).push(
    _ContainerRoute(
      barrierDismissible: true,
      barrierLabel: 'Close',
      // The blur and tint are _Backdrop's, which sits outside the
      // panel's scaling; the barrier just catches taps outside the panel.
      barrierColor: Colors.transparent,
      // Opening pops (springs past its size and settles); closing is quick.
      transitionDuration: const Duration(milliseconds: 420),
      reverseDuration: const Duration(milliseconds: 200),
      pageBuilder: (_, _, _) => _OpenContainer(containerId: containerId, origin: origin),
      transitionBuilder: (_, animation, _, child) {
        final pop = CurvedAnimation(parent: animation, curve: _popCurve, reverseCurve: Curves.easeInCubic);
        final fade = CurvedAnimation(
          parent: animation,
          curve: const Interval(0, 0.35, curve: Curves.easeOut),
          reverseCurve: Curves.easeIn,
        );
        return FadeTransition(
          opacity: fade,
          child: ScaleTransition(alignment: grow, scale: Tween(begin: 0.3, end: 1.0).animate(pop), child: child),
        );
      },
    ),
  );
}

/// Out of the folder, a little past full size, and back: a pop.
const _popCurve = Cubic(0.34, 1.4, 0.64, 1);

/// One app in an opened group popping in after the one before it, as the
/// panel opens; still while it closes.
class _PopIn extends StatelessWidget {
  const _PopIn({super.key, required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final route = ModalRoute.of(context)?.animation;
    if (route == null) return child;
    final start = math.min(index * 0.035, 0.35);
    final curve = Interval(start, math.min(start + 0.55, 1), curve: _popCurve);
    final fade = Interval(start, math.min(start + 0.25, 1));
    return AnimatedBuilder(
      animation: route,
      child: child,
      builder: (context, child) {
        if (route.status != AnimationStatus.forward) return child!;
        final t = route.value;
        return Opacity(
          opacity: fade.transform(t),
          child: Transform.scale(scale: 0.4 + 0.6 * curve.transform(t), child: child),
        );
      },
    );
  }
}

/// The open container's route. An app dragged out of it can't simply pop it:
/// the navigator cancels every active pointer when a route leaves, which
/// would end the drag. So it [hideForDrag]s instead, and leaves once the
/// finger is up.
class _ContainerRoute extends RawDialogRoute<void> {
  _ContainerRoute({
    required super.pageBuilder,
    required super.transitionBuilder,
    super.barrierDismissible,
    super.barrierLabel,
    super.barrierColor,
    super.transitionDuration,
    this.reverseDuration,
  });

  final Duration? reverseDuration;

  @override
  Duration get reverseTransitionDuration => reverseDuration ?? transitionDuration;

  bool _hidden = false;

  /// Plays the closing animation without leaving the navigator. The barrier
  /// lets touches through once it isn't showing; the panel, from now on, too.
  void hideForDrag() {
    if (_hidden) return;
    _hidden = true;
    changedInternalState();
    controller?.reverse();
  }

  /// After [hideForDrag], once the drag is over.
  void close() {
    if (isActive) navigator?.removeRoute(this);
  }

  // Here, not in buildPage: the page is built once, transitions every frame.
  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => IgnorePointer(
    ignoring: _hidden,
    child: Stack(
      fit: StackFit.expand,
      children: [
        IgnorePointer(child: _Backdrop(animation: animation)),
        super.buildTransitions(context, animation, secondaryAnimation, child),
      ],
    ),
  );
}

/// Over the home screen, behind an opened group, whatever its style: everything
/// behind it blurred, home screen and wallpaper alike, under a light tint, so
/// the panel stands out; in step with the route's animation.
///
/// Android draws the wallpaper, so where the phone can't blur behind the
/// window (WindowBlurPlatform.isSupported; e.g. vivo's) the wallpaper is our
/// own blurred copy of it, covering the home screen once open.
class _Backdrop extends StatelessWidget {
  const _Backdrop({required this.animation});

  final Animation<double> animation;

  static const _sigma = 20.0;

  @override
  Widget build(BuildContext context) {
    // Nullable: absent in tests, which have no platform.
    final native = context.select<WindowBlurPlatform?, bool>((p) => p?.isSupported ?? false);
    final wallpaper = context.select<WindowBlurPlatform?, ui.Image?>((p) => p?.wallpaper);
    final ownWallpaper = !native && wallpaper != null;
    return AnimatedBuilder(
      animation: animation,
      // Blurred once; only its opacity changes as it opens / closes.
      child: ownWallpaper
          ? RepaintBoundary(
              child: ImageFiltered(
                imageFilter: ui.ImageFilter.blur(sigmaX: _sigma, sigmaY: _sigma, tileMode: TileMode.clamp),
                child: RawImage(image: wallpaper, fit: BoxFit.fill, filterQuality: FilterQuality.low),
              ),
            )
          : null,
      builder: (context, wallpaperLayer) {
        // As the barrier would.
        final t = Curves.ease.transform(animation.value);
        if (t == 0) return const SizedBox.shrink();
        final tint = ColoredBox(color: Colors.black.withValues(alpha: 0.2 * t));
        return Stack(
          fit: StackFit.expand,
          children: [
            // The home screen's icons (and Android's own wallpaper blur).
            BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: _sigma * t, sigmaY: _sigma * t),
              child: const SizedBox.expand(),
            ),
            if (wallpaperLayer != null) Opacity(opacity: t, child: wallpaperLayer),
            tint,
          ],
        );
      },
    );
  }
}

/// Spacing of an opened folder / container: the gap between icons, and
/// from the panel's edges to them, is one and the same all round (the rule
/// containers on the home screen follow too; see AppContainerTile).
///
/// Across, [columns] icons and [columns] + 1 equal gaps share the panel's
/// width. Down, rows are that gap apart as well: from one row's names (or
/// icons, with names hidden) to the next row's icons, and at the top and
/// bottom edges.
@immutable
class OpenPanelSpacing {
  factory OpenPanelSpacing(HomeGrid grid, double width, {required bool names}) {
    final icon = grid.iconSize;
    final cell = (width + icon) / (grid.columns + 1);
    final gap = cell - icon;
    // With names: icon, the 6dp gap, the name's line, then the gap.
    final cellHeight = names ? icon + 6 + HomeGrid.labelLineHeight + gap : cell;
    return OpenPanelSpacing._(grid.columns, cell, cellHeight, gap);
  }

  const OpenPanelSpacing._(this.columns, this.cellWidth, this.cellHeight, this.gap);

  final int columns;
  final double cellWidth;
  final double cellHeight;

  /// Between icons, and from the edges.
  final double gap;

  /// The panel's padding: each cell already holds half a gap around its
  /// icon, so half a gap more makes a whole one at the edges.
  double get padding => gap / 2;

  /// The same cells, [n] across: a panel only as wide as its apps need.
  OpenPanelSpacing withColumns(int n) => OpenPanelSpacing._(n, cellWidth, cellHeight, gap);

  SliverGridDelegate get delegate =>
      SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: columns, mainAxisExtent: cellHeight);
}

class _OpenContainer extends StatefulWidget {
  const _OpenContainer({required this.containerId, this.origin});

  final String containerId;

  /// Where the tapped folder / container is on screen; null: centred.
  final Rect? origin;

  @override
  State<_OpenContainer> createState() => _OpenContainerState();
}

class _OpenContainerState extends State<_OpenContainer> {
  final _panelKey = GlobalKey();
  final _gridKey = GlobalKey();
  final _scroll = ScrollController();

  /// While an app is dragged around inside: the order the apps show in.
  List<String>? _preview;

  /// Height of a grid cell, as last laid out.
  double? _cellHeight;

  /// Icons across, as last laid out: as many as it has apps, up to the
  /// home grid's columns.
  int? _perRow;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// The dragged app moves to the cell under the finger; the rest shift.
  void _hover(DragTargetDetails<String> d, List<String> ids, HomeGrid grid) {
    final id = d.data.startsWith('app:') ? d.data.substring(4) : null;
    final box = _gridKey.currentContext?.findRenderObject() as RenderBox?;
    if (id == null || !ids.contains(id) || box == null) return;
    // Dragged apps are carried centred on a home cell's middle.
    final cell = context.read<HomeLayoutController>().cellSize;
    final at = box.globalToLocal(d.offset + Offset(cell.width / 2, cell.height / 2));
    final across = _perRow ?? grid.columns;
    final w = box.size.width / across;
    final h = _cellHeight ?? grid.cellHeightFor(w);
    final col = (at.dx / w).floor().clamp(0, across - 1);
    final row = math.max(0, ((at.dy + _scroll.offset) / h).floor());
    final index = math.min(row * across + col, ids.length - 1);
    final order = [...(_preview ?? ids)]
      ..remove(id)
      ..insert(index, id);
    if (!listEquals(order, _preview)) {
      if (_preview != null) HapticFeedback.selectionClick();
      setState(() => _preview = order);
    }
  }

  void _drop() {
    final order = _preview;
    if (order == null) return;
    context.read<HomeLayoutController>().reorderContainer(widget.containerId, order);
    HapticFeedback.lightImpact();
    setState(() => _preview = null);
  }

  @override
  Widget build(BuildContext context) {
    final containerId = widget.containerId;
    final container = context.watch<HomeLayoutController>().container(containerId);
    final grid = context.watch<HomeLayoutController>().grid;
    if (container == null) return const SizedBox.shrink(); // ungrouped meanwhile
    final visible = visibleAppsOf(context, container);
    final byId = {for (final a in visible) a.id: a};
    final ids = [for (final a in visible) a.id];
    final apps = [for (final id in _preview ?? ids) ?byId[id]];
    final showNames = context.select<HomeLayoutController, bool>((l) => l.showLabels);

    final shape = context.select<HomeLayoutController, IconShape>((l) => l.iconShape);
    final title = showNames && container.name.isNotEmpty;

    return CustomSingleChildLayout(
      delegate: _OverOrigin(
        origin: widget.origin,
        // Clear of the status and navigation bars, and the screen's edges.
        area: MediaQuery.paddingOf(context) + const EdgeInsets.all(24),
      ),
      child: LayoutBuilder(
        builder: (context, box) {
          // Cells sized for the full width (the same icons and gaps as
          // always), but only as many across as it has apps.
          final full = OpenPanelSpacing(grid, box.maxWidth, names: showNames);
          final spacing = full.withColumns(math.min(math.max(1, ids.length), grid.columns));
          _cellHeight = spacing.cellHeight;
          _perRow = spacing.columns;
          final pad = spacing.padding;
          final decoration = AppContainerTile.decorationOf(
            container,
            AppContainerTile.radiusOf(container.copyWith(cols: 2, rows: 2), grid, shape),
          );
          final glass = container.style == GroupStyle.glass;
          final panel = Container(
            key: _panelKey,
            width: spacing.columns * spacing.cellWidth + 2 * spacing.padding,
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
            // Opened, a folder takes a container's corners (it's no
            // longer icon-sized), limited the same way.
            decoration: decoration,
            // A whole gap above the name, if shown; half a gap around
            // the grid, whose cells hold the other half (see
            // OpenPanelSpacing). The outline is inside the panel too,
            // so it counts towards these.
            padding:
                EdgeInsets.fromLTRB(pad, title ? spacing.gap : pad, pad, pad) -
                decoration.padding.resolve(TextDirection.ltr),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Just its name (hidden with the home screen's app
                // names) and its apps.
                if (title) ...[
                  Padding(
                    // In line with the first column's icons.
                    padding: EdgeInsets.symmetric(horizontal: pad),
                    child: Text(
                      container.name,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(color: container.style.ink),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  SizedBox(height: pad),
                ],
                Flexible(
                  // Drag an app around in here to reorder; past the
                  // panel's edge, it leaves (see _DragOutTile).
                  child: DragTarget<String>(
                    onWillAcceptWithDetails: (d) =>
                        ids.contains(d.data.startsWith('app:') ? d.data.substring(4) : null),
                    onMove: (d) => _hover(d, ids, grid),
                    onLeave: (_) => setState(() => _preview = null),
                    onAcceptWithDetails: (_) => _drop(),
                    builder: (_, _, _) => GridView(
                      key: _gridKey,
                      controller: _scroll,
                      shrinkWrap: true,
                      padding: EdgeInsets.zero,
                      gridDelegate: spacing.delegate,
                      children: [
                        for (final (i, app) in apps.indexed)
                          _PopIn(
                            key: ValueKey(app.id),
                            index: i,
                            child: _DragOutTile(
                              app: app,
                              panelKey: _panelKey,
                              child: _OpenTile(
                                app: app,
                                grid: grid,
                                showName: showNames,
                                style: container.style,
                                onTap: () async {
                                  final navigator = Navigator.of(context);
                                  if (await openApp(context, app)) navigator.maybePop();
                                },
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
          return Material(
            type: MaterialType.transparency,
            // The whole wallpaper is blurred while it's open (see
            // _Backdrop): it's Android's, out of a BackdropFilter's reach.
            child: WallpaperBlur(
              radius: 18,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // Just above the panel's corner, so its even spacing
                  // stays as it is.
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Its outline on the home screen.
                        _ShapeButton(containerId: containerId),
                        const SizedBox(width: 8),
                        _StyleButton(containerId: containerId),
                      ],
                    ),
                  ),
                  Flexible(
                    child: glass ? WallpaperGlass(shape: decoration.shape, child: panel) : panel,
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

/// Lays an opened group out over [origin]: centred on it, but kept inside
/// the screen less [area]. Centred on the screen with no [origin].
class _OverOrigin extends SingleChildLayoutDelegate {
  const _OverOrigin({required this.origin, required this.area});

  final Rect? origin;
  final EdgeInsets area;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints.loose(area.deflateSize(constraints.biggest));

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final room = area.deflateRect(Offset.zero & size);
    final centre = origin?.center ?? room.center;
    double place(double c, double extent, double lo, double hi) =>
        hi - lo <= extent ? lo + (hi - lo - extent) / 2 : (c - extent / 2).clamp(lo, hi - extent);
    return Offset(
      place(centre.dx, childSize.width, room.left, room.right),
      place(centre.dy, childSize.height, room.top, room.bottom),
    );
  }

  @override
  bool shouldRelayout(_OverOrigin old) => old.origin != origin || old.area != area;
}

/// A small shape button in an opened group; its menu picks its outline on
/// the home screen (see FolderShape): rounded, circle or triangle. A
/// container becomes a square just big enough for its apps in that shape
/// (see AppContainerTile.shapedSpan); a folder keeps its tile. Open, every
/// group is a rounded panel.
class _ShapeButton extends StatelessWidget {
  const _ShapeButton({required this.containerId});

  final String containerId;

  @override
  Widget build(BuildContext context) {
    final layout = context.read<HomeLayoutController>();

    /// [c] shaped [shape] as a square just big enough for its apps;
    /// neighbours make room. A folder keeps its one tile. How its apps sit
    /// (round the edge or filling it) follows the size it's resized to.
    void apply(AppContainer c, FolderShape shape) {
      if (c.isFolder) return layout.updateContainer(c.copyWith(folderShape: shape));
      if (shape == FolderShape.rounded) return layout.updateContainer(c.copyWith(folderShape: shape).fitted());
      final span = AppContainerTile.shapedSpan(
        shape,
        c.appIds.length,
        layout.grid,
        layout.cellSize,
        math.min(layout.grid.columns, AppContainer.maxSpan),
      );
      layout.updateContainer(c.copyWith(folderShape: shape, cols: span, rows: span));
    }

    return PopupMenuButton<FolderShape>(
      tooltip: 'Shape',
      icon: const Icon(Icons.category_outlined, size: 18, color: Colors.white),
      style: IconButton.styleFrom(
        backgroundColor: Colors.white.withValues(alpha: 0.16),
        minimumSize: const Size.square(32),
        padding: EdgeInsets.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      position: PopupMenuPosition.under,
      onSelected: (choice) {
        final c = layout.container(containerId);
        if (c != null) apply(c, choice);
      },
      itemBuilder: (_) {
        final c = layout.container(containerId);
        final folder = c?.isFolder ?? false;
        final current = c?.folderShape;
        PopupMenuItem<FolderShape> option(
          FolderShape value,
          IconData icon,
          String label, {
          String? note,
          bool checked = false,
        }) => PopupMenuItem(
          value: value,
          enabled: note == null,
          child: Row(
            children: [
              Icon(icon, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: note == null
                    ? Text(label)
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(label),
                          Text(note, style: Theme.of(context).textTheme.bodySmall),
                        ],
                      ),
              ),
              if (checked && note == null) const Icon(Icons.check, size: 18),
            ],
          ),
        );
        return [
          for (final (shape, icon, label) in [
            (FolderShape.rounded, Icons.crop_square_rounded, folder ? 'Rounded square' : 'Rounded'),
            (FolderShape.circle, Icons.circle_outlined, 'Circle'),
            (FolderShape.flower, Icons.filter_vintage_outlined, 'Flower'),
          ])
            option(shape, icon, label, checked: current == shape),
          option(
            FolderShape.triangle,
            Icons.change_history_rounded,
            'Triangle',
            note: AppContainerTile.triangleFits(c?.appIds.length ?? 0) ? null : 'For 3, 6, 9… apps',
            checked: current == FolderShape.triangle,
          ),
        ];
      },
    );
  }
}

/// A small palette button in an opened group; its menu picks the group's
/// background (see GroupStyle).
class _StyleButton extends StatelessWidget {
  const _StyleButton({required this.containerId});

  final String containerId;

  static const _colors = [
    AppContainer.defaultColor, // blue
    0xFF9B6BEF, // purple
    0xFFEF6BA8, // pink
    0xFFEF5B5B, // red
    0xFFF29B4B, // orange
    0xFFE8C547, // yellow
    0xFF4FBF7F, // green
    0xFF3FB8C4, // teal
    0xFF8A8F98, // grey
  ];

  @override
  Widget build(BuildContext context) {
    final layout = context.read<HomeLayoutController>();
    final blur = context.read<WindowBlurPlatform?>();
    void apply(GroupStyle style, [int? color]) {
      final c = layout.container(containerId);
      if (c != null) layout.updateContainer(c.copyWith(style: style, color: color));
      // Glass needs the wallpaper image.
      if (style == GroupStyle.glass) blur?.requestWallpaperAccess();
    }

    return PopupMenuButton<GroupStyle>(
      tooltip: 'Background',
      icon: const Icon(Icons.palette_outlined, size: 18, color: Colors.white),
      style: IconButton.styleFrom(
        backgroundColor: Colors.white.withValues(alpha: 0.16),
        minimumSize: const Size.square(32),
        padding: EdgeInsets.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      position: PopupMenuPosition.under,
      onSelected: apply,
      itemBuilder: (_) {
        final current = layout.container(containerId);
        PopupMenuItem<GroupStyle> option(GroupStyle style, IconData icon, String label) => PopupMenuItem(
          value: style,
          child: Row(
            children: [
              Icon(icon, size: 20),
              const SizedBox(width: 12),
              Expanded(child: Text(label)),
              if (current?.style == style) const Icon(Icons.check, size: 18),
            ],
          ),
        );
        return [
          option(GroupStyle.light, Icons.light_mode_outlined, 'Light'),
          option(GroupStyle.dark, Icons.dark_mode_outlined, 'Dark'),
          option(GroupStyle.glass, Icons.blur_on, 'Glass blur'),
          option(GroupStyle.material, Icons.layers_outlined, 'Material dark'),
          option(GroupStyle.materialLight, Icons.layers, 'Material light'),
          const PopupMenuDivider(),
          // Colour swatches; a swatch's tap is handled by it, not the item.
          PopupMenuItem(
            enabled: false,
            child: SizedBox(
              width: 172,
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final color in _colors)
                    Builder(
                      builder: (menuContext) {
                        final picked = current?.style == GroupStyle.color && current?.color == color;
                        return GestureDetector(
                          onTap: () {
                            apply(GroupStyle.color, color);
                            Navigator.pop(menuContext);
                          },
                          child: Container(
                            width: 26,
                            height: 26,
                            decoration: BoxDecoration(
                              color: Color(color),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: picked ? Colors.white : Colors.white24,
                                width: picked ? 2.5 : 1,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
          ),
          const PopupMenuDivider(),
          // This group's background on every folder / container.
          PopupMenuItem(
            enabled: current != null,
            onTap: () {
              final c = layout.container(containerId);
              if (c == null) return;
              layout.styleAllContainers(c.style, c.color);
              HapticFeedback.lightImpact();
            },
            child: const Row(
              children: [
                Icon(Icons.select_all, size: 20),
                SizedBox(width: 12),
                Expanded(child: Text('Use for all folders')),
              ],
            ),
          ),
        ];
      },
    );
  }
}

/// An app in an opened folder: its icon, and its name under it unless names
/// are hidden. Centred in its cell, with nothing above or below but the
/// cell's half gaps (see OpenPanelSpacing).
class _OpenTile extends StatelessWidget {
  const _OpenTile({
    required this.app,
    required this.grid,
    required this.showName,
    required this.style,
    required this.onTap,
  });

  final AppInfo app;
  final HomeGrid grid;
  final bool showName;

  /// The panel's: a light one takes dark names.
  final GroupStyle style;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: InkResponse(
        radius: grid.iconSize * 0.7,
        onTap: onTap,
        child: Semantics(
          label: app.label,
          excludeSemantics: true,
          button: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIcon(app: app, size: grid.iconSize),
              if (showName) ...[
                const SizedBox(height: 6),
                SizedBox(
                  height: HomeGrid.labelLineHeight,
                  width: grid.iconSize + 24,
                  child: Text(
                    app.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: style.ink,
                      fontSize: grid.labelSize,
                      shadows: style.isLightSurface ? null : const [Shadow(blurRadius: 4, color: Colors.black54)],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// An app in an open container that can be dragged out onto the home screen
/// (see [showContainer]). Its drag data is the app's home key, so the home
/// pages take it like any dragged app.
class _DragOutTile extends StatefulWidget {
  const _DragOutTile({required this.app, required this.panelKey, required this.child});

  final AppInfo app;

  /// The open panel: dragged past its edge, the app leaves it.
  final GlobalKey panelKey;
  final Widget child;

  @override
  State<_DragOutTile> createState() => _DragOutTileState();
}

class _DragOutTileState extends State<_DragOutTile> {
  double _moved = 0;
  bool _out = false;

  /// Moving less than this before letting go is a long press: the app's menu.
  static const _dragSlop = 12.0;

  bool _inPanel(Offset global) {
    final box = widget.panelKey.currentContext?.findRenderObject() as RenderBox?;
    return box != null && (box.localToGlobal(Offset.zero) & box.size).contains(global);
  }

  void _update(DragUpdateDetails d) {
    _moved += d.delta.distance;
    if (_out || _inPanel(d.globalPosition)) return;
    _out = true;
    HapticFeedback.selectionClick();
    final layout = context.read<HomeLayoutController>()..beginDrag();
    final container = ModalRoute.of(context);
    // The panel goes away under the finger (see _ContainerRoute), taking
    // this tile with it.
    layout.endDragOnRelease(then: container is _ContainerRoute ? container.close : null);
    if (container is _ContainerRoute) {
      container.hideForDrag();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final grid = context.read<HomeLayoutController>().grid;
    // Carried as a home cell, centred on the finger, so where it lands
    // matches what the home screen shows under it.
    final cell = context.read<HomeLayoutController>().cellSize;
    return LongPressDraggable<String>(
      data: 'app:${widget.app.id}',
      delay: const Duration(milliseconds: 400),
      hapticFeedbackOnStart: true,
      dragAnchorStrategy: (_, _, _) => Offset(cell.width / 2, cell.height / 2),
      onDragStarted: () => _moved = 0,
      onDragUpdate: _update,
      // Only while still in the panel: let go without dragging out.
      onDragEnd: (_) {
        if (!_out && _moved < _dragSlop) showAppActions(context, widget.app);
      },
      feedback: Material(
        type: MaterialType.transparency,
        child: SizedBox.fromSize(
          size: cell,
          child: Center(
            child: AppIcon(app: widget.app, size: grid.iconSize * 1.06),
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.2, child: widget.child),
      child: widget.child,
    );
  }
}

/// Tick the apps a container should hold. Apps ticked here move out of
/// wherever they were; unticked ones go back on the home screen.
class ContainerAppPicker extends StatefulWidget {
  const ContainerAppPicker({super.key, required this.containerId});

  final String containerId;

  @override
  State<ContainerAppPicker> createState() => _ContainerAppPickerState();
}

class _ContainerAppPickerState extends State<ContainerAppPicker> {
  late final List<String> _selected = [...?context.read<HomeLayoutController>().container(widget.containerId)?.appIds];

  @override
  Widget build(BuildContext context) {
    final layout = context.watch<HomeLayoutController>();
    final apps = context.watch<VisibleApps>().apps;

    return Scaffold(
      appBar: AppBar(
        title: Text('${_selected.length} selected'),
        actions: [
          TextButton(
            onPressed: () {
              layout.setContainerApps(widget.containerId, _selected);
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
      body: ListView.builder(
        itemCount: apps.length,
        itemBuilder: (context, i) {
          final app = apps[i];
          final other = layout.containerOf(app.id);
          return CheckboxListTile(
            secondary: AppIcon(app: app, size: 36),
            title: Text(app.label),
            subtitle: other != null && other.id != widget.containerId ? Text('In "${other.name}"') : null,
            value: _selected.contains(app.id),
            onChanged: (on) => setState(() => on! ? _selected.add(app.id) : _selected.remove(app.id)),
          );
        },
      ),
    );
  }
}

/// From an app's long-press menu: put it into a new folder or container, or
/// an existing one.
Future<void> showAddToGroup(BuildContext context, AppInfo app) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) {
      final layout = sheetContext.watch<HomeLayoutController>();
      return SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              leading: const Icon(Icons.create_new_folder_outlined),
              title: const Text('New folder'),
              subtitle: const Text('Add more apps, then drag its handles to make it a container'),
              onTap: () {
                layout.createContainer(app.id, folder: true);
                Navigator.pop(sheetContext);
              },
            ),
            if (layout.containers.isNotEmpty) const Divider(),
            for (final c in layout.containers)
              ListTile(
                leading: Icon(c.isFolder ? Icons.folder_outlined : Icons.dashboard_outlined),
                title: Text(c.name.isEmpty ? 'Unnamed' : c.name),
                subtitle: Text('${c.appIds.length} apps'),
                onTap: () {
                  layout.addToContainer(c.id, app.id);
                  Navigator.pop(sheetContext);
                },
              ),
          ],
        ),
      );
    },
  );
}
