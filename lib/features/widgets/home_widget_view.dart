import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/platform/app_widgets_platform.dart';
import '../../core/models/icon_shape.dart';
import '../../core/theme/home_grid.dart';
import '../standard_home/app_container_tile.dart';
import '../standard_home/home_layout.dart';
import 'launcher_widgets.dart';

/// A home-screen widget in the box of its cells: an app widget (drawn by
/// Android) or a launcher widget, in exactly its [frameIn].
class HomeWidgetView extends StatelessWidget {
  const HomeWidgetView({
    super.key,
    required this.item,
    required this.grid,
    required this.cols,
    required this.rows,
    this.editing = false,
    this.iconShape = IconShape.system,
  });

  final WidgetItem item;
  final HomeGrid grid;

  /// The span it's drawn at (its own, unless clamped to the grid).
  final int cols;
  final int rows;

  /// While arranging, touches go to the home screen, not into the widget.
  final bool editing;

  /// The app icons' shape: round icons get rounder widget corners.
  final IconShape iconShape;

  /// Space between a widget and the edges of its cells, as OriginOS leaves
  /// it: 8dp with 4 columns, a little less with the denser grids (OriginOS's
  /// 5-column grid uses 5–6dp).
  static double inset(HomeGrid grid) => 32 / grid.columns;

  /// Where a widget is drawn within a box of its [cols] × [rows] cells: the
  /// whole of its cells but for a small [inset] all round, as on OriginOS
  /// (and Android's own launcher). App widgets are designed for about that
  /// much room; lining them up with the icons instead took ~37dp off their
  /// width and ~15dp off their height, and their content got cut off.
  /// Fractional spans give the sizes in between while resizing.
  static Rect frameIn(HomeGrid grid, Size box, double cols, double rows) => (Offset.zero & box).deflate(inset(grid));

  /// One OriginOS home-grid row and the gap under it on this phone
  /// (BBKLauncher2: workspace_cell_height, back_cell_height_gap_4X6 for
  /// sw420dp), and one column (cell_width_4_6, sw392dp). App widgets are
  /// designed for rows about this tall, taller than ours (square cells, so
  /// more rows fit).
  static const _refRow = 87.4, _refRowGap = 42.0, _refColumn = 89.28;

  /// The size a [cols] × [rows] app widget gets on OriginOS: what it lays
  /// itself out for.
  static Size referenceSizeOf(HomeGrid grid, int cols, int rows) =>
      Size(cols * _refColumn - 2 * inset(grid), rows * _refRow + (rows - 1) * _refRowGap - 2 * inset(grid));

  /// How much an app widget of [frame] size ([cols] × [rows]) is scaled
  /// down: it lays itself out at the size OriginOS would give it (so its
  /// content fits as designed, nothing cut off) and is drawn smaller to fit
  /// our shorter rows, as Android's own launcher does when its cells are
  /// smaller than a widget expects. 1 when it already has that much room.
  static double scaleFor(HomeGrid grid, Size frame, int cols, int rows) {
    final ref = referenceSizeOf(grid, cols, rows);
    return [1.0, frame.width / ref.width, frame.height / ref.height].reduce(math.min);
  }

  /// The size an app widget of [frame] lays itself out at (see [scaleFor]).
  static Size layoutSizeOf(HomeGrid grid, Size frame, int cols, int rows) => frame / scaleFor(grid, frame, cols, rows);

  /// Width and height of a [cols] × [rows] widget on cells of [cell].
  static Size sizeOf(HomeGrid grid, Size cell, int cols, int rows) =>
      frameIn(grid, Size(cell.width * cols, cell.height * rows), cols.toDouble(), rows.toDouble()).size;

  /// The fewest cells a widget needs to be at least [dp] wide / high, on
  /// cells of [cell]; see [sizeOf].
  static (int, int) cellsFor(HomeGrid grid, Size cell, double widthDp, double heightDp) {
    final first = sizeOf(grid, cell, 1, 1);
    int cells(double dp, double firstExtent, double step) => math.max(1, ((dp - firstExtent) / step - 0.01).ceil() + 1);
    return (cells(widthDp, first.width, cell.width), cells(heightDp, first.height, cell.height));
  }

  /// The most cells whose size stays within [widthDp] / [heightDp] (at
  /// least one); see [sizeOf].
  static (int, int) mostCellsWithin(HomeGrid grid, Size cell, double widthDp, double heightDp) {
    final (c, r) = cellsFor(grid, cell, widthDp, heightDp);
    final size = sizeOf(grid, cell, c, r);
    return (math.max(1, size.width > widthDp + 0.5 ? c - 1 : c), math.max(1, size.height > heightDp + 0.5 ? r - 1 : r));
  }

  /// An app widget's cell limits worked out for cells of [cell] from the dp
  /// sizes its app asked for, its span kept within them: it never gets less
  /// room than it needs, nor more than it allows. A fixed-size one (least =
  /// most) always takes exactly the cells that fit that size. Launcher
  /// widgets (no dp sizes) come back as they are.
  static WidgetItem fitTo(WidgetItem w, HomeGrid grid, Size cell) {
    if (w.minWidthDp <= 0 && w.minHeightDp <= 0) return w;
    final (minCols, minRows) = cellsFor(grid, cell, w.minWidthDp, w.minHeightDp);
    final (mostCols, mostRows) = mostCellsWithin(grid, cell, w.maxWidthDp, w.maxHeightDp);
    final fixedW = w.maxWidthDp > 0 && w.maxWidthDp == w.minWidthDp;
    final fixedH = w.maxHeightDp > 0 && w.maxHeightDp == w.minHeightDp;
    int most(double maxDp, int least, int fits) => maxDp <= 0 ? WidgetItem.maxSpan : math.max(least, fits);
    return w.copyWith(
      minCols: minCols,
      minRows: minRows,
      maxCols: fixedW ? minCols : most(w.maxWidthDp, minCols, mostCols),
      maxRows: fixedH ? minRows : most(w.maxHeightDp, minRows, mostRows),
    );
  }

  /// Corner radius of a [cols] × [rows] widget, from OriginOS's own table
  /// (BBKLauncher2's *_size_widget_radius_4_6_direct dimens): small (one
  /// row) 13dp, normal (2 × 2) 15.3dp, large (wide, two rows) 17dp, big
  /// (three rows or more) 16.5dp; and its "circle" set, 18–23dp, with round
  /// icons. Never more than half the widget's shorter side.
  static double radiusFor(int cols, int rows, Size frame, {IconShape iconShape = IconShape.system}) {
    final round = (iconShape.radius ?? 0) >= 40;
    final (direct, circle) = switch ((cols, rows)) {
      (_, 1) => (13.0, 18.0),
      (<= 2, _) => (15.3, 21.0),
      (_, 2) => (17.0, 23.0),
      _ => (16.5, 22.0),
    };
    return math.min(round ? circle : direct, frame.shortestSide / 2);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final frame = frameIn(grid, box.biggest, cols.toDouble(), rows.toDouble());
        final radius = radiusFor(cols, rows, frame.size, iconShape: iconShape);
        final Widget content;
        if (item.appWidgetId case final id?) {
          // Rounded natively, on the widget's own background (see
          // AppWidgetView): a Flutter clip over an Android view has jagged,
          // un-antialiased edges.
          content = AbsorbPointer(
            absorbing: editing,
            child: _PixelSnapped(
              child: AppWidgetView(
                appWidgetId: id,
                editing: editing,
                radius: radius,
                scale: scaleFor(grid, frame.size, cols, rows),
              ),
            ),
          );
        } else if (LauncherWidgetKind.fromName(item.launcherKind) case final kind?) {
          // Takes the touch itself (for long press / drag); an interactive
          // one's buttons get taps too, but not while arranging.
          content = AbsorbPointer(
            absorbing: editing || !kind.interactive,
            child: LauncherWidgetView(
              kind: kind,
              radius: launcherWidgetRadius(item.settings, frame.size, radius),
              padding: AppContainerTile.pad(grid),
              settings: item.settings,
            ),
          );
        } else {
          content = WidgetPlaceholder(radius: radius, label: 'Unknown widget');
        }
        return Stack(
          clipBehavior: Clip.none,
          children: [Positioned.fromRect(rect: frame, child: content)],
        );
      },
    );
  }
}

/// A plain panel standing in for a widget (while it's dragged: an app
/// widget can only be shown in one place at a time).
class WidgetPlaceholder extends StatelessWidget {
  const WidgetPlaceholder({super.key, required this.radius, this.label});

  final double radius;
  final String? label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: AppContainerTile.decoration(radius),
      child: Center(
        child: label == null
            ? const Icon(Icons.widgets_outlined, color: Colors.white70)
            : Text(label!, style: const TextStyle(color: Colors.white70)),
      ),
    );
  }
}

/// What follows the finger while a widget is dragged: its panel, in its
/// frame within [box].
class WidgetDragFeedback extends StatelessWidget {
  const WidgetDragFeedback({super.key, required this.grid, required this.cols, required this.rows});

  final HomeGrid grid;
  final int cols;
  final int rows;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final frame = HomeWidgetView.frameIn(grid, box.biggest, cols.toDouble(), rows.toDouble());
        return Stack(
          children: [
            Positioned.fromRect(
              rect: frame,
              child: WidgetPlaceholder(radius: HomeWidgetView.radiusFor(cols, rows, frame.size)),
            ),
          ],
        );
      },
    );
  }
}

/// One Android app widget, drawn natively (see AppWidgetPlatformView.kt).
///
/// Taps reach the widget; long presses stay with the home screen (moving
/// the widget). Swipes up and down do too (opening the drawer, search,
/// notifications), unless the widget holds a list or grid: then it gets
/// them, to scroll it.
///
/// Its corners are rounded by Android, as Android's own launcher does it
/// (Launcher3's RoundedCornerEnforcement): on the widget's background view
/// with [radius], unless the widget rounds itself.
class AppWidgetView extends StatelessWidget {
  const AppWidgetView({super.key, required this.appWidgetId, this.editing = false, this.radius = 0, this.scale = 1});

  final int appWidgetId;
  final bool editing;

  /// Corner radius in dp, as drawn.
  final double radius;

  /// How much smaller than its layout size it's drawn (see
  /// HomeWidgetView.scaleFor).
  final double scale;

  static final _scroll = <Factory<OneSequenceGestureRecognizer>>{
    Factory<VerticalDragGestureRecognizer>(VerticalDragGestureRecognizer.new),
  };

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform != TargetPlatform.android) return WidgetPlaceholder(radius: radius);
    final platform = context.read<AppWidgetsPlatform>();
    // A view already showing picks up a new radius / scale (after a resize) here.
    platform.setLook(appWidgetId, radius: radius, scale: scale);
    final scrollable = platform.scrollable;
    return ValueListenableBuilder<Set<int>>(
      valueListenable: scrollable,
      builder: (context, ids, _) => _view(context, scrolls: !editing && ids.contains(appWidgetId)),
    );
  }

  Widget _view(BuildContext context, {required bool scrolls}) {
    return AndroidView(
      // A new view when the widget changes, not a reused one.
      key: ValueKey(appWidgetId),
      viewType: AppWidgetsPlatform.viewType,
      layoutDirection: Directionality.of(context),
      creationParams: {'appWidgetId': appWidgetId, 'radius': radius, 'scale': scale},
      creationParamsCodec: const StandardMessageCodec(),
      gestureRecognizers: scrolls ? _scroll : const <Factory<OneSequenceGestureRecognizer>>{},
    );
  }
}

/// Draws its child on whole physical pixels. An Android view is shown as a
/// texture; at a fractional position or size Flutter resamples it, which
/// softens every edge. Home-grid cells are rarely whole pixels.
class _PixelSnapped extends SingleChildRenderObjectWidget {
  const _PixelSnapped({required super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderPixelSnapped(MediaQuery.devicePixelRatioOf(context));

  @override
  void updateRenderObject(BuildContext context, _RenderPixelSnapped renderObject) =>
      renderObject.devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
}

class _RenderPixelSnapped extends RenderProxyBox {
  _RenderPixelSnapped(this._dpr);

  double _dpr;
  set devicePixelRatio(double value) {
    if (value == _dpr) return;
    _dpr = value;
    markNeedsLayout();
  }

  double _floor(double v) => (v * _dpr).floorToDouble() / _dpr;

  @override
  void performLayout() {
    // Whole pixels, never bigger than the space given.
    final size = constraints.biggest;
    child!.layout(BoxConstraints.tight(Size(_floor(size.width), _floor(size.height))));
    this.size = constraints.constrain(size);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    // Where it lands on screen, moved onto the pixel grid. (Mid-animation or
    // mid-swipe it's between pixels anyway; at rest it's exact.)
    final global = localToGlobal(Offset.zero);
    final snapped = Offset((global.dx * _dpr).roundToDouble() / _dpr, (global.dy * _dpr).roundToDouble() / _dpr);
    context.paintChild(child!, offset + (snapped - global));
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      child!.hitTest(result, position: position);
}
