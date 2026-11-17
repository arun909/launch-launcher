import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/models/app_info.dart';
import '../../core/models/icon_shape.dart';
import '../../core/theme/home_grid.dart';
import '../../core/theme/spacing.dart';
import '../../core/widgets/app_icon.dart';
import '../app_actions/app_actions_sheet.dart';
import '../dock/dock_controller.dart';
import '../hidden_apps/visible_apps.dart';
import '../widgets/home_widget_view.dart';
import '../widgets/launcher_widgets.dart';
import '../widgets/widget_actions_sheet.dart' show reconfigureHomeWidget, removeHomeWidget;
import 'app_container_tile.dart';
import 'container_sheets.dart';
import 'corner_shapes.dart';
import 'frame_handles.dart';
import 'home_layout.dart';
import 'home_layout_controller.dart';

/// Standard-mode home: every app on swipeable pages of a 4-column grid, with
/// folders, containers and widgets, each at a fixed spot.
///
/// In edit mode, hold and drag an item: a ghost outline shows where it will
/// land, and anything there moves aside. Dropping an app on the middle of
/// another app makes a folder; on a folder or container, it goes inside.
/// An app dragged out of an open folder / container lands the same way (see
/// [showContainer]).
/// Holding at the left / right edge flips pages; an extra empty page at the
/// end takes items onto a new page.
class StandardHome extends StatefulWidget {
  const StandardHome({super.key});

  /// Space from the screen edges to the grid, for [grid] on a screen
  /// [width] wide: half the gap between two icons, so each edge icon is a
  /// full gap from the screen edge and the icons are evenly spaced across
  /// (edge, gap, gap, gap, edge all equal). A fixed padding made the edges
  /// a few dp narrower than the gaps (43.5 vs 47.1dp at 4 × 8).
  static double sidePaddingFor(HomeGrid grid, double width) =>
      math.max(0.0, (width - grid.columns * grid.iconSize) / (grid.columns + 1) / 2);

  /// Space above the first row, below the status bar / edit bar.
  static const topPadding = Spacing.halfGutter;

  /// Height of the page-dots strip under the grid.
  static const dotsHeight = 20.0;

  @override
  State<StandardHome> createState() => _StandardHomeState();
}

class _StandardHomeState extends State<StandardHome> {
  final _pages = PageController();
  int _page = 0;
  Timer? _edgeFlip;

  @override
  void dispose() {
    _pages.dispose();
    _edgeFlip?.cancel();
    super.dispose();
  }

  /// The layout as drawn: hidden, uninstalled and dock apps left out (they
  /// keep their place in the stored layout), empty containers skipped.
  List<HomeItem> _shownItems(BuildContext context) {
    final visible = context.watch<VisibleApps>();
    final docked = context.watch<DockController>().ids.toSet();
    bool shows(String id) => visible.byId(id) != null && !docked.contains(id);

    return [
      for (final item in context.watch<HomeLayoutController>().items)
        switch (item) {
          AppItem(:final appId) => shows(appId) ? item : null,
          AppContainer(:final appIds) => appIds.any(shows) ? item : null,
          WidgetItem() => item,
        },
    ].whereType<HomeItem>().toList();
  }

  void _flipFromEdge(int direction, int pageCount) {
    if (_edgeFlip != null) return;
    _edgeFlip = Timer(const Duration(milliseconds: 550), () {
      _edgeFlip = null;
      final target = (_page + direction).clamp(0, pageCount - 1);
      if (target != _page) {
        _pages.animateToPage(target, duration: const Duration(milliseconds: 260), curve: Curves.easeOutCubic);
      }
    });
  }

  void _cancelEdgeFlip() {
    _edgeFlip?.cancel();
    _edgeFlip = null;
  }

  @override
  Widget build(BuildContext context) {
    final layout = context.watch<HomeLayoutController>();
    final editing = layout.editing;
    final items = _shownItems(context);

    return LayoutBuilder(
      builder: (context, box) {
        const dotsHeight = StandardHome.dotsHeight;
        // Columns from the chosen grid preset; rows either fixed and sharing
        // the height, or cells as tall as wide (equal spacing down and
        // across) and as many rows as fit, from the top (see HomeGrid).
        final spec = layout.grid;
        final sidePadding = StandardHome.sidePaddingFor(spec, box.maxWidth);
        final gridWidth = box.maxWidth - sidePadding * 2;
        final cellWidth = gridWidth / spec.columns;
        final gridHeight = box.maxHeight - dotsHeight - StandardHome.topPadding;
        final rows = spec.rowsFor(gridHeight, cellWidth);
        final cellHeight = spec.cellHeightIn(gridHeight, cellWidth);
        final grid = _Grid(spec, rows, Size(cellWidth, cellHeight));
        final keyboardUp = MediaQuery.viewInsetsOf(context).bottom > 0;
        final arrangement = arrange(
          items,
          layout.slots,
          columns: grid.columns,
          rows: grid.rows,
          priority: layout.priority,
        );
        // Fix the resolved positions (new apps, items moved aside) in place.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          layout.cellSize = grid.cell;
          layout.gridArea = Size(gridWidth, gridHeight);
          layout.arrangement = arrangement;
          layout.gridRows = grid.rows;
          // A widget was just added to another page: go there.
          if (layout.pageRequest case final page? when _pages.hasClients) {
            layout.pageRequest = null;
            if (page != _page) {
              _pages.animateToPage(page, duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic);
            }
          }
          // Not while a resize handle is held: shrinking back lets neighbours return.
          if (layout.interacting) return;
          // Not in landscape: its fewer rows push items aside, and saving
          // that would reshuffle the portrait layout on rotating back.
          if (box.maxWidth > box.maxHeight) return;
          // Nor while the keyboard is up (quick search on top): it can cut
          // rows too, and saving that moves items lower down for good.
          if (keyboardUp) return;
          // App widgets keep the room they need on these cells (portrait only,
          // like the slots, so rotating doesn't resize them for good).
          // A widget that changed size lays the page out again first.
          if (layout.fitWidgetsTo(grid.cell)) return;
          if (layout.priority != null || !_sameSlots(arrangement.slots, layout.slots)) {
            layout.commitSlots(arrangement.slots);
          }
        });

        // While editing, one extra empty page to drag items onto.
        final pageCount = arrangement.pages.length + (editing ? 1 : 0);
        if (_page >= pageCount) _page = pageCount - 1;
        layout.currentPage = _page;

        // A drag carried to another page outlives the page it started on,
        // and Flutter then skips that item's drag-end callback; the finger
        // lifting always ends the drag, so clear it here too.
        void endDrag(PointerEvent _) {
          if (layout.dragging) WidgetsBinding.instance.addPostFrameCallback((_) => layout.endDrag());
        }

        return Listener(
          onPointerUp: endDrag,
          onPointerCancel: endDrag,
          child: Column(
            children: [
              const SizedBox(height: StandardHome.topPadding),
              Expanded(
                child: Stack(
                  children: [
                    PageView.builder(
                      controller: _pages,
                      // Page swipes would fight the resize handles.
                      physics: layout.selected != null ? const NeverScrollableScrollPhysics() : null,
                      itemCount: pageCount,
                      onPageChanged: (p) => setState(() => _page = p),
                      itemBuilder: (context, p) => _Page(
                        index: p,
                        sidePadding: sidePadding,
                        items: items,
                        placed: p < arrangement.pages.length ? arrangement.pages[p] : const [],
                        arrangement: arrangement,
                        grid: grid,
                        editing: editing,
                      ),
                    ),
                    _EdgeZone(
                      alignment: Alignment.centerLeft,
                      visible: layout.dragging,
                      onHover: () => _flipFromEdge(-1, pageCount),
                      onLeave: _cancelEdgeFlip,
                    ),
                    _EdgeZone(
                      alignment: Alignment.centerRight,
                      visible: layout.dragging,
                      onHover: () => _flipFromEdge(1, pageCount),
                      onLeave: _cancelEdgeFlip,
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: dotsHeight,
                child: pageCount < 2
                    ? null
                    : _PageScrubber(
                        count: pageCount,
                        current: _page,
                        // Not while arranging a selected item (as swipes).
                        enabled: layout.selected == null,
                        onPage: (p) {
                          if (!_pages.hasClients) return;
                          setState(() => _page = p);
                          _pages.animateToPage(
                            p,
                            duration: const Duration(milliseconds: 240),
                            curve: Curves.easeOutCubic,
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  static bool _sameSlots(Map<String, GridSlot> resolved, Map<String, GridSlot> saved) =>
      resolved.entries.every((e) => saved[e.key] == e.value);
}

/// Grid geometry of a page.
class _Grid {
  const _Grid(this.spec, this.rows, this.cell);

  /// The preset: columns, icon and label sizes.
  final HomeGrid spec;
  final int rows;
  final Size cell;

  int get columns => spec.columns;

  Rect rectOf(int col, int row, int cols, int rows) =>
      Rect.fromLTWH(col * cell.width, row * cell.height, cols * cell.width, rows * cell.height);
}

/// One page: items at their slots. While editing, the whole page is the drop
/// target, so items can be dropped on any cell, empty or not.
class _Page extends StatefulWidget {
  const _Page({
    required this.index,
    required this.sidePadding,
    required this.items,
    required this.placed,
    required this.arrangement,
    required this.grid,
    required this.editing,
  });

  final int index;

  /// Space from the screen edges to the grid (see StandardHome.sidePaddingFor).
  final double sidePadding;

  /// Everything on the home pages, as drawn (for trying out changes).
  final List<HomeItem> items;
  final List<PlacedItem> placed;
  final Arrangement arrangement;
  final _Grid grid;
  final bool editing;

  @override
  State<_Page> createState() => _PageState();
}

class _PageState extends State<_Page> {
  /// The grid itself, inside the page's side padding; drop positions are
  /// measured from its top-left.
  final _gridKey = GlobalKey();

  /// Where the dragged item would land, or null.
  GridSlot? _ghost;

  /// The dragged item and its span, for the ghost's shape.
  HomeItem? _ghostItem;
  (int, int) _ghostSpan = (1, 1);

  /// The item the dragged app would merge into, or null.
  String? _mergeInto;

  /// The one item under the ghost that would trade places with the dragged
  /// item (it fits in the spot the dragged item leaves), or null.
  PlacedItem? _swapWith;

  static String? _appIdOf(String key) => key.startsWith('app:') ? key.substring(4) : null;

  void _hover(DragTargetDetails<String> d) {
    final box = _gridKey.currentContext?.findRenderObject() as RenderBox?;
    final dragged = widget.arrangement.find(d.data);
    // Not on the page: an app dragged out of a folder / container, one cell.
    if (box == null || (dragged == null && _appIdOf(d.data) == null)) return;
    final grid = widget.grid;
    // The dragged item stays where it was grabbed relative to the finger;
    // [d.offset] is its top-left.
    final (w, h) = dragged == null ? (1, 1) : (dragged.cols, dragged.rows);
    final topLeft = box.globalToLocal(d.offset);
    final center = topLeft + Offset(w * grid.cell.width / 2, h * grid.cell.height / 2);

    // With its middle over the middle of another item, an app merges into it.
    String? merge;
    if (_appIdOf(d.data) != null) {
      final (cx, cy) = ((center.dx / grid.cell.width).floor(), (center.dy / grid.cell.height).floor());
      for (final p in widget.placed) {
        if (p.item.key == d.data || !p.covers(cx, cy)) continue;
        final rect = grid.rectOf(p.col, p.row, p.cols, p.rows);
        if (rect.deflate(math.min(rect.width, rect.height) * 0.22).contains(center)) merge = p.item.key;
      }
    }

    // Otherwise: the cells nearest to where it is now.
    final ghost = merge != null
        ? null
        : GridSlot(
            widget.index,
            (topLeft.dx / grid.cell.width).round().clamp(0, grid.columns - w),
            (topLeft.dy / grid.cell.height).round().clamp(0, grid.rows - h),
          );
    // Exactly one item under the ghost, small enough for the dragged item's
    // old spot: they swap. Otherwise what's under it moves aside.
    PlacedItem? swap;
    if (ghost != null) {
      final target = grid.rectOf(ghost.col, ghost.row, w, h).deflate(1);
      final under = [
        for (final p in widget.placed)
          if (p.item.key != d.data && grid.rectOf(p.col, p.row, p.cols, p.rows).overlaps(target)) p,
      ];
      if (under.length == 1 && under.single.cols <= w && under.single.rows <= h) swap = under.single;
    }
    if (ghost != _ghost || merge != _mergeInto || swap?.item.key != _swapWith?.item.key) {
      setState(() {
        _ghost = ghost;
        _ghostSpan = (w, h);
        _ghostItem = dragged?.item ?? AppItem(_appIdOf(d.data)!);
        _mergeInto = merge;
        _swapWith = swap;
      });
    }
  }

  void _clear() {
    if (_ghost != null || _mergeInto != null || _swapWith != null) {
      setState(() {
        _ghost = null;
        _mergeInto = null;
        _swapWith = null;
      });
    }
  }

  /// The pages if [key] were put at [slot] (with [swapKey] going to
  /// [swapTo]), as [HomeLayoutController.place] would.
  Arrangement _tryPlace(String key, GridSlot slot, {HomeItem? updated, String? swapKey, GridSlot? swapTo}) {
    final layout = context.read<HomeLayoutController>();
    return arrange(
      [for (final i in widget.items) i.key == key && updated != null ? updated : i],
      {...layout.slots, key: slot, if (swapKey != null && swapTo != null) swapKey: swapTo},
      columns: widget.grid.columns,
      rows: widget.grid.rows,
      priority: key,
    );
  }

  /// A widget's new position / size from its handles, if what it pushes
  /// aside still fits on this page; false (nothing changes) if not.
  bool _reshapeWidget(GridSlot slot, WidgetItem updated) {
    final after = _tryPlace(updated.key, slot, updated: updated);
    if (spilled(widget.arrangement, after, moved: updated.key).isNotEmpty) return false;
    context.read<HomeLayoutController>().reshapeWidget(slot, updated);
    return true;
  }

  void _noRoom() {
    HapticFeedback.heavyImpact();
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Not enough room on this page. Move some apps away, or put the widget on another page.'),
        ),
      );
  }

  void _drop(String key) {
    final layout = context.read<HomeLayoutController>();
    final dragged = _appIdOf(key);
    final target = _mergeInto;
    // From the dock: it lives on the home screen again.
    final dock = context.read<DockController>();
    if (dragged != null && dock.isPinned(dragged) && (target != null || _ghost != null)) dock.unpin(dragged);
    if (target != null && dragged != null) {
      if (target.startsWith('app:')) {
        layout.createFolder(target.substring(4), dragged);
      } else if (widget.arrangement.find(target)?.item case AppContainer(:final id, :final appIds)) {
        // Dropped back on its own folder: it stays as it was.
        if (!appIds.contains(dragged)) layout.addToContainer(id, dragged);
      }
    } else if (_ghost case final slot? when slot != widget.arrangement.find(key)?.slot) {
      final from = widget.arrangement.find(key);
      final swapKey = _swapWith != null && from != null ? _swapWith!.item.key : null;
      // Widgets never get squeezed onto another page: a widget dropped where
      // what it covers can't move aside on this page, or a drop that would
      // push a widget off its page, is refused.
      final pushed = spilled(
        widget.arrangement,
        _tryPlace(key, slot, swapKey: swapKey, swapTo: from?.slot),
        moved: key,
      );
      if (pushed.isNotEmpty && (key.startsWith('widget:') || pushed.any((k) => k.startsWith('widget:')))) {
        _noRoom();
        _clear();
        return;
      }
      layout.place(key, slot, swapKey: swapKey, swapTo: from?.slot);
    }
    HapticFeedback.lightImpact();
    _clear();
  }

  @override
  Widget build(BuildContext context) {
    final grid = widget.grid;
    final layout = context.watch<HomeLayoutController>();
    final selected = widget.editing ? widget.placed.where((p) => p.item.key == layout.selected).firstOrNull : null;
    final gridStack = Stack(
      key: _gridKey,
      clipBehavior: Clip.none,
      children: [
        // Where icons sit, only while something is dragged over this page.
        if (_ghost != null || _mergeInto != null) Positioned.fill(child: _CellGuides(grid)),
        // Where it will land: its own shape (icon, folder or panel), there.
        if ((_ghost, _ghostItem) case (final g?, final item?))
          () {
            final cells = grid.rectOf(g.col, g.row, _ghostSpan.$1, _ghostSpan.$2);
            final (shape, radius) = visualOf(item, cells.size, _ghostSpan, grid.spec, layout.iconShape);
            return AnimatedPositioned.fromRect(
              duration: const Duration(milliseconds: 140),
              curve: Curves.easeOutCubic,
              rect: shape.shift(cells.topLeft),
              child: _Ghost(radius: radius),
            );
          }(),
        for (final p in widget.placed)
          AnimatedPositioned(
            key: ValueKey(p.item.key),
            duration: AppContainerTile.resizeDuration,
            curve: AppContainerTile.resizeCurve,
            left: p.col * grid.cell.width,
            top: p.row * grid.cell.height,
            width: p.cols * grid.cell.width,
            height: p.rows * grid.cell.height,
            child: _HomeItemView(
              placed: p,
              grid: grid.spec,
              cell: grid.cell,
              editing: widget.editing,
              merging: _mergeInto == p.item.key,
              swapping: _swapWith?.item.key == p.item.key,
            ),
          ),
        if (selected != null && selected.item is AppContainer) _handlesFor(selected, layout),
        if (selected != null && selected.item is WidgetItem) _widgetHandlesFor(selected, layout),
      ],
    );
    final page = Padding(
      padding: EdgeInsets.symmetric(horizontal: widget.sidePadding),
      child: gridStack,
    );
    // Always a drop target, even outside edit mode: a long-press drag starts
    // before edit mode has rebuilt the page, and the tree mustn't change
    // shape under it (that would cancel the drag).
    return GestureDetector(
      // Tapping empty space finishes editing (there is no Done button).
      behavior: HitTestBehavior.translucent,
      onTap: widget.editing ? () => layout.setEditing(false) : null,
      child: DragTarget<String>(
        onWillAcceptWithDetails: (_) => true,
        onMove: _hover,
        onLeave: (_) => _clear(),
        onAcceptWithDetails: (d) => _drop(d.data),
        builder: (_, _, _) => page,
      ),
    );
  }

  /// Resize and corner-radius handles for the selected folder / container.
  Widget _handlesFor(PlacedItem p, HomeLayoutController layout) {
    final grid = widget.grid;
    return Positioned.fill(
      child: FrameHandles(
        container: p.item as AppContainer,
        grid: grid.spec,
        cell: grid.cell,
        gridColumns: grid.columns,
        gridRows: grid.rows,
        slot: p.slot,
        cols: p.cols,
        rows: p.rows,
        onChanged: layout.reshape,
        onInteraction: layout.setInteracting,
        iconShape: layout.iconShape,
      ),
    );
  }

  /// Resize handles and a remove button for the selected widget.
  Widget _widgetHandlesFor(PlacedItem p, HomeLayoutController layout) {
    final grid = widget.grid;
    final item = p.item as WidgetItem;
    return Positioned.fill(
      child: WidgetHandles(
        widgetItem: item,
        grid: grid.spec,
        cell: grid.cell,
        gridColumns: grid.columns,
        gridRows: grid.rows,
        slot: p.slot,
        cols: p.cols,
        rows: p.rows,
        onChanged: _reshapeWidget,
        onInteraction: layout.setInteracting,
        iconShape: layout.iconShape,
        onRemove: () => removeHomeWidget(context, item),
        onSettings: switch (LauncherWidgetKind.fromName(item.launcherKind)?.customise) {
          final customise? => () => customise(context, item),
          _ => item.reconfigurable ? () => reconfigureHomeWidget(context, item) : null,
        },
      ),
    );
  }
}

/// A faint dot where each icon sits, so the grid items snap to is visible
/// without boxing every cell in.
class _CellGuides extends StatelessWidget {
  const _CellGuides(this.grid);

  final _Grid grid;

  @override
  Widget build(BuildContext context) => IgnorePointer(child: CustomPaint(painter: _CellGuidesPainter(grid)));
}

class _CellGuidesPainter extends CustomPainter {
  _CellGuidesPainter(this.grid);

  final _Grid grid;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white.withValues(alpha: 0.28);
    for (var r = 0; r < grid.rows; r++) {
      for (var c = 0; c < grid.columns; c++) {
        canvas.drawCircle(AppContainerTile.iconRect(grid.spec, grid.cell, c, r).center, 2, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_CellGuidesPainter old) =>
      old.grid.cell != grid.cell || old.grid.rows != grid.rows || old.grid.columns != grid.columns;
}

/// What an item looks like within a box of its cells ([span] of them): its
/// icon (an app or folder) or its panel (a container), and that shape's
/// corner radius. Ghosts and highlights take exactly this shape.
(Rect, double) visualOf(HomeItem item, Size box, (int, int) span, HomeGrid spec, IconShape shape) {
  final cell = Size(box.width / span.$1, box.height / span.$2);
  return switch (item) {
    AppItem() => (AppContainerTile.iconRect(spec, cell, 0, 0), spec.iconSize * AppContainerTile.iconRoundness(shape)),
    AppContainer(isFolder: true) => (
      AppContainerTile.iconRect(spec, cell, 0, 0),
      AppContainerTile.radiusOf(item, spec, shape),
    ),
    AppContainer() => (
      AppContainerTile.panelRect(spec, box, span.$1.toDouble(), span.$2.toDouble()),
      AppContainerTile.radiusOf(item, spec, shape),
    ),
    WidgetItem() => () {
      final frame = HomeWidgetView.frameIn(spec, box, span.$1.toDouble(), span.$2.toDouble());
      return (frame, HomeWidgetView.radiusFor(span.$1, span.$2, frame.size, iconShape: shape));
    }(),
  };
}

/// Where a dragged item will land: an outline of its own shape.
class _Ghost extends StatelessWidget {
  const _Ghost({required this.radius});

  final double radius;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: Colors.white.withValues(alpha: 0.10),
          shape: CornerShapes.shape(radius, side: BorderSide(color: Colors.white.withValues(alpha: 0.7), width: 1.5)),
        ),
      ),
    );
  }
}

class _HomeItemView extends StatelessWidget {
  const _HomeItemView({
    required this.placed,
    required this.grid,
    required this.cell,
    required this.editing,
    required this.merging,
    required this.swapping,
  });

  final PlacedItem placed;
  final HomeGrid grid;

  /// One home cell: with [placed]'s span, the size it's animating to.
  final Size cell;
  final bool editing;

  /// A dragged app is over this item's middle and would go into it.
  final bool merging;

  /// The dragged item would trade places with this one.
  final bool swapping;

  @override
  Widget build(BuildContext context) {
    final item = placed.item;
    final view = switch (item) {
      AppItem() => _appView(context, item),
      AppContainer() => _containerView(context, item),
      WidgetItem() => GestureDetector(
        // Editing: a tap selects it for resizing (taps don't reach it then).
        onTap: editing ? () => context.read<HomeLayoutController>().select(item.key) : null,
        child: HomeWidgetView(
          item: item,
          grid: grid,
          cols: placed.cols,
          rows: placed.rows,
          editing: editing,
          iconShape: context.select<HomeLayoutController, IconShape>((l) => l.iconShape),
        ),
      ),
    };
    if (view == null) return const SizedBox.shrink();
    final iconShape = context.select<HomeLayoutController, IconShape>((l) => l.iconShape);
    return _Draggable(
      itemKey: item.key,
      shapeOf: (box) => visualOf(item, box, (placed.cols, placed.rows), grid, iconShape),
      editing: editing,
      merging: merging,
      swapping: swapping,
      selected: context.select<HomeLayoutController, bool>((l) => l.selected == item.key),
      // An app widget can only be drawn in one place: a stand-in while dragged.
      feedback: item is WidgetItem ? WidgetDragFeedback(grid: grid, cols: placed.cols, rows: placed.rows) : null,
      // A long press without dragging: the app's menu, or select a group.
      onPlainLongPress: switch (item) {
        AppItem(:final appId) => () {
          // Edit mode as it is now: the drag that the long press began has
          // just ended (and turned off the edit mode it switched on), but
          // this view was last built while it was on.
          if (!context.read<HomeLayoutController>().editing) {
            if (context.read<VisibleApps>().byId(appId) case final app?) showAppActions(context, app);
          }
        },
        // Straight to its resize / corner handles.
        AppContainer() =>
          () => context.read<HomeLayoutController>()
            ..setEditing(true)
            ..select(item.key),
        // Like a group: straight to its resize handles (and its remove button).
        WidgetItem() =>
          () => context.read<HomeLayoutController>()
            ..setEditing(true)
            ..select(item.key),
      },
      child: view,
    );
  }

  Widget? _appView(BuildContext context, AppItem item) {
    final app = context.watch<VisibleApps>().byId(item.appId);
    if (app == null) return null;
    return Center(
      child: AppTile(
        app: app,
        iconSize: grid.iconSize,
        labelSize: grid.labelSize,
        showLabel: context.select<HomeLayoutController, bool>((l) => l.showLabels),
        onTap: editing ? () => context.read<HomeLayoutController>().select(null) : () => openApp(context, app),
      ),
    );
  }

  Widget _containerView(BuildContext context, AppContainer c) {
    // Group names come and go with app names (Settings › App names).
    final showNames = context.select<HomeLayoutController, bool>((l) => l.showLabels);
    final docked = context.watch<DockController>().ids.toSet();
    final apps = visibleAppsOf(context, c).where((a) => !docked.contains(a.id)).toList();
    final layout = context.read<HomeLayoutController>();
    // Editing: tap selects it for resizing. Otherwise: tap opens it. (Long
    // press is the drag; see [_Draggable].)
    // [tile]: the folder / container's own context, so it opens over it.
    VoidCallback onOpen(BuildContext tile) => editing ? () => layout.select(c.key) : () => showContainer(tile, c.id);
    if (c.isFolder) {
      return Center(
        child: Builder(
          builder: (tile) => FolderTile(
            folder: c,
            apps: apps,
            grid: grid,
            iconShape: layout.iconShape,
            showName: showNames,
            onOpen: onOpen(tile),
          ),
        ),
      );
    }
    return Builder(
      builder: (tile) => AppContainerTile(
        container: c,
        apps: apps,
        grid: grid,
        iconShape: layout.iconShape,
        showName: showNames,
        settledSize: Size(cell.width * placed.cols, cell.height * placed.rows),
        onOpen: onOpen(tile),
        onLaunch: editing ? null : (AppInfo app) => openApp(context, app),
      ),
    );
  }
}

/// Long-press and drag to move an item, as on any launcher: edit mode is on
/// while it's dragged (and stays only if it was on before); in edit mode the
/// hold is shorter.
/// A long press released without dragging is [onPlainLongPress] instead.
/// The page underneath decides where it lands (see [_PageState]).
class _Draggable extends StatefulWidget {
  const _Draggable({
    required this.itemKey,
    required this.shapeOf,
    required this.editing,
    required this.merging,
    required this.swapping,
    required this.selected,
    required this.onPlainLongPress,
    required this.child,
    this.feedback,
  });

  final String itemKey;

  /// What follows the finger while dragged; a lifted copy of [child] if null.
  final Widget? feedback;

  /// Its icon / panel within a box of its cells, and that shape's radius:
  /// highlights hug exactly this.
  final (Rect, double) Function(Size box) shapeOf;
  final bool editing;
  final bool merging;
  final bool swapping;

  /// Selected for resizing (its handles are around it).
  final bool selected;
  final VoidCallback onPlainLongPress;
  final Widget child;

  @override
  State<_Draggable> createState() => _DraggableState();
}

class _DraggableState extends State<_Draggable> {
  /// How far the finger has moved since the drag began.
  double _moved = 0;
  late final HomeLayoutController _layout = context.read<HomeLayoutController>();

  /// Moving less than this between press and release counts as a plain
  /// long press, not a drag.
  static const _dragSlop = 12.0;

  /// Space between an icon and the ring around it.
  static const _ringGap = 5.0;

  void _started() {
    _moved = 0;
    _layout.beginDrag();
  }

  void _ended() {
    _layout.endDrag();
    if (_moved < _dragSlop) widget.onPlainLongPress();
  }

  @override
  Widget build(BuildContext context) {
    final child = widget.child;
    final editing = widget.editing;
    final merging = widget.merging;
    return LayoutBuilder(
      builder: (context, box) {
        final (shape, radius) = widget.shapeOf(box.biggest);
        return LongPressDraggable<String>(
          data: widget.itemKey,
          // Normal long press outside edit mode; quicker once arranging.
          delay: editing ? const Duration(milliseconds: 150) : const Duration(milliseconds: 400),
          hapticFeedbackOnStart: true,
          // The item stays where it was grabbed, relative to the finger.
          dragAnchorStrategy: childDragAnchorStrategy,
          onDragStarted: _started,
          onDragUpdate: (d) => _moved += d.delta.distance,
          onDragEnd: (_) => _ended(),
          // Lifted slightly. (No Opacity: it would need an offscreen layer
          // redrawn on every frame of the drag.)
          feedback: Material(
            type: MaterialType.transparency,
            child: SizedBox(
              width: box.maxWidth,
              height: box.maxHeight,
              child: Transform.scale(scale: 1.06, child: widget.feedback ?? child),
            ),
          ),
          // Its spot is left empty; the ghost shows where it's going.
          childWhenDragging: const SizedBox.expand(),
          child: AnimatedScale(
            // Selected for resizing: true size, so its handles' outline fits it.
            scale: merging ? 1.05 : (editing && !widget.selected ? 0.94 : 1),
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
            child: Stack(
              fit: StackFit.expand,
              clipBehavior: Clip.none,
              children: [
                // An app dropped on it would join it: a ring of its own shape
                // around its icon / panel. (A selected group has just its
                // handles' outline; see FrameHandles.)
                Positioned.fromRect(
                  rect: shape.inflate(_ringGap),
                  child: IgnorePointer(
                    child: AnimatedOpacity(
                      opacity: merging ? 1 : 0,
                      duration: const Duration(milliseconds: 150),
                      child: DecoratedBox(
                        decoration: ShapeDecoration(
                          color: Colors.white.withValues(alpha: 0.14),
                          shape: CornerShapes.shape(
                            CornerShapes.concentric(radius, _ringGap),
                            side: const BorderSide(color: Colors.white, width: 2),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                AnimatedOpacity(
                  opacity: widget.swapping ? 0.45 : 1,
                  duration: const Duration(milliseconds: 150),
                  child: child,
                ),
                // It would trade places with the dragged item.
                if (widget.swapping)
                  Positioned.fromRect(
                    rect: shape,
                    child: const IgnorePointer(
                      child: Center(child: Icon(Icons.swap_horiz_rounded, color: Colors.white, size: 28)),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Strip at a screen edge: holding a dragged item over it flips pages. While
/// anything is dragged it shows a faint arrow; held over, it lights up.
class _EdgeZone extends StatefulWidget {
  const _EdgeZone({required this.alignment, required this.visible, required this.onHover, required this.onLeave});

  final Alignment alignment;
  final bool visible;
  final VoidCallback onHover;
  final VoidCallback onLeave;

  @override
  State<_EdgeZone> createState() => _EdgeZoneState();
}

class _EdgeZoneState extends State<_EdgeZone> {
  bool _held = false;

  void _hover() {
    if (!_held) setState(() => _held = true);
    widget.onHover();
  }

  void _leave() {
    if (_held) setState(() => _held = false);
    widget.onLeave();
  }

  @override
  Widget build(BuildContext context) {
    final left = widget.alignment.x < 0;
    return Align(
      alignment: widget.alignment,
      child: SizedBox(
        // Wide, and at the real screen edge, where a dragging finger ends up.
        width: 40,
        child: DragTarget<String>(
          onWillAcceptWithDetails: (_) {
            _hover();
            return false;
          },
          onMove: (_) => _hover(),
          onLeave: (_) => _leave(),
          builder: (_, _, _) => IgnorePointer(
            child: AnimatedOpacity(
              opacity: widget.visible ? (_held ? 1 : 0.5) : 0,
              duration: const Duration(milliseconds: 150),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: left ? Alignment.centerLeft : Alignment.centerRight,
                    end: left ? Alignment.centerRight : Alignment.centerLeft,
                    colors: [
                      Colors.white.withValues(alpha: _held ? 0.35 : 0.12),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: Center(
                  child: Icon(
                    left ? Icons.chevron_left_rounded : Icons.chevron_right_rounded,
                    color: Colors.white,
                    size: 32,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The page dots, and a way through the pages: slide a finger along the
/// strip and the pages follow, one per [_step], each with a crisp tick (and
/// a firmer bump on pulling past the first or last). A tap beside the dots
/// steps one page that way. While held, the dots sit on a pill and grow.
class _PageScrubber extends StatefulWidget {
  const _PageScrubber({required this.count, required this.current, required this.enabled, required this.onPage});

  final int count;
  final int current;
  final bool enabled;
  final ValueChanged<int> onPage;

  @override
  State<_PageScrubber> createState() => _PageScrubberState();
}

class _PageScrubberState extends State<_PageScrubber> {
  /// Finger travel per page.
  static const _step = 44.0;

  bool _held = false;
  double _startX = 0;
  int _startPage = 0;
  int _target = 0;
  bool _atEdge = false;

  void _go(int page) {
    if (page == _target) return;
    _target = page;
    HapticFeedback.lightImpact();
    widget.onPage(page);
  }

  void _start(DragStartDetails d) {
    setState(() => _held = true);
    _startX = d.localPosition.dx;
    _startPage = _target = widget.current;
    _atEdge = false;
    HapticFeedback.selectionClick();
  }

  void _update(DragUpdateDetails d) {
    final wanted = _startPage + ((d.localPosition.dx - _startX) / _step).round();
    final page = wanted.clamp(0, widget.count - 1);
    // Pulled past the first or last page: one bump, until it comes back.
    final edge = wanted != page;
    if (edge && !_atEdge) HapticFeedback.mediumImpact();
    _atEdge = edge;
    _go(page);
  }

  void _end() => setState(() => _held = false);

  void _tap(TapUpDetails d, double width) {
    final side = d.localPosition.dx < width / 2 ? -1 : 1;
    _target = widget.current;
    final page = (widget.current + side).clamp(0, widget.count - 1);
    if (page == widget.current) {
      HapticFeedback.mediumImpact();
    } else {
      _go(page);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dots = AnimatedScale(
      scale: _held ? 1.3 : 1,
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOutBack,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: _held ? 0.18 : 0),
          borderRadius: BorderRadius.circular(10),
        ),
        child: _PageDots(count: widget.count, current: widget.current),
      ),
    );
    if (!widget.enabled) return Center(child: dots);
    return LayoutBuilder(
      builder: (context, box) => Semantics(
        label: 'Page ${widget.current + 1} of ${widget.count}',
        hint: 'Slide along to move between pages',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: _start,
          onHorizontalDragUpdate: _update,
          onHorizontalDragEnd: (_) => _end(),
          onHorizontalDragCancel: _end,
          onTapUp: (d) => _tap(d, box.maxWidth),
          child: Center(child: dots),
        ),
      ),
    );
  }
}

class _PageDots extends StatelessWidget {
  const _PageDots({required this.count, required this.current});

  final int count;
  final int current;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: i == current ? 16 : 6,
            height: 6,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: i == current ? 0.9 : 0.4),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
      ],
    );
  }
}
