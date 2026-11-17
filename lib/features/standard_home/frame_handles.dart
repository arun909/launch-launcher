import 'dart:math' as math;
import 'dart:ui' show PathMetric;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/models/icon_shape.dart';
import '../../core/theme/home_grid.dart';
import '../widgets/home_widget_view.dart';
import '../widgets/launcher_widgets.dart';

import 'app_container_tile.dart';
import 'corner_shapes.dart';
import 'home_layout.dart';

/// Direct-manipulation handles around a selected folder / container, laid
/// over a grid of [cell]-sized cells (fill the grid's Stack with it).
///
/// - Edge and corner grips resize it. The outline follows the finger
///   continuously; the group itself snaps to whole cells underneath, live,
///   and shows as many apps as its new size fits. Shrunk to 1 × 1 it becomes
///   a folder; grown from a folder, a container.
/// - A dot inside the top-left corner sets the corner radius: drag it in to
///   round more, out to square up. It snaps to the Material 3 shape scale
///   (see [CornerShapes]) with a tick of haptic feedback, and shows the step.
///
/// Positions come from global pointer positions converted into this widget's
/// own space, so it also works over a scaled-down grid (pass [scale]).
class FrameHandles extends StatefulWidget {
  const FrameHandles({
    super.key,
    required this.container,
    required this.grid,
    required this.cell,
    required this.gridColumns,
    required this.gridRows,
    required this.slot,
    required this.cols,
    required this.rows,
    required this.onChanged,
    this.edgesMoveOrigin = true,
    this.onInteraction,
    this.scale = 1,
    this.iconShape = IconShape.system,
  });

  final AppContainer container;
  final HomeGrid grid;
  final Size cell;
  final int gridColumns;
  final int gridRows;
  final GridSlot slot;

  /// The span it has on the grid (see PlacedItem): its own, clamped to the
  /// grid, so a group saved wider than this grid (from a denser one) is
  /// outlined where it's drawn, not past the screen edge.
  final int cols;
  final int rows;

  /// A new size / position (from a grip) or radius (from the dot).
  final void Function(GridSlot slot, AppContainer updated) onChanged;

  /// Whether the left / top grips exist (they move the group's origin).
  final bool edgesMoveOrigin;

  /// True while a handle is held, false when let go.
  final ValueChanged<bool>? onInteraction;

  /// How much smaller than true size the grid is drawn ([cell] is already
  /// scaled).
  final double scale;

  /// The app icons' shape: the corners round only as far as they still fit
  /// (see AppContainerTile.fitRadius).
  final IconShape iconShape;

  static const maxSpan = AppContainer.maxSpan;

  @override
  State<FrameHandles> createState() => _FrameHandlesState();
}

/// Which sides a grip moves: -1 left/top, 1 right/bottom, 0 neither.
typedef _Sides = (int, int);

/// Vibration while resizing, kept light: a selection tick per new size (at
/// most one every [_gap], so a quick drag across several cells doesn't
/// buzz), one soft bump when the finger first pulls past a limit (none
/// again until it comes back), and one firmer knock per size that's refused.
class _ResizeHaptics {
  static const _gap = Duration(milliseconds: 45);
  final _clock = Stopwatch()..start();
  Duration? _last;
  bool _atLimit = false;
  Object? _refused;

  void reset() {
    _last = null;
    _atLimit = false;
    _refused = null;
  }

  void step() {
    _refused = null;
    final now = _clock.elapsed;
    if (_last != null && now - _last! < _gap) return;
    _last = now;
    HapticFeedback.selectionClick();
  }

  void limit(bool at) {
    if (at && !_atLimit) HapticFeedback.lightImpact();
    _atLimit = at;
  }

  void refused(Object size) {
    if (_refused != size) HapticFeedback.mediumImpact();
    _refused = size;
  }
}

class _FrameHandlesState extends State<FrameHandles> {
  // Frame and pointer when the current resize began.
  late GridSlot _startSlot;
  late int _startCols;
  late int _startRows;
  Offset _startPointer = Offset.zero;

  /// While a grip is held: the frame exactly under the finger (not snapped).
  Rect? _liveFrame;

  bool _radiusHeld = false;

  final _haptics = _ResizeHaptics();

  AppContainer get _c => widget.container;

  /// Radius as drawn (true size), and the most it can be: as round as the
  /// icons inside still fit.
  double get _radius => AppContainerTile.radiusOf(_c, widget.grid, widget.iconShape);
  double get _full => _c.isFolder
      ? AppContainerTile.folderMaxRadius(widget.grid, widget.iconShape)
      : AppContainerTile.containerMaxRadius(widget.grid, widget.iconShape);

  /// Folders scale the stored radius to their icon size; see [AppContainer.radiusAt].
  double get _folderFull => widget.grid.iconSize / 2;

  /// Which of the three roundnesses this folder or container has.
  String get _radiusName {
    final radii = AppContainerTile.radiiFor(_c.isFolder, widget.grid, widget.iconShape);
    return AppContainerTile.radiusNames[radii.indexOf(_radius).clamp(0, radii.length - 1)];
  }

  /// Space between the panel and its selection outline.
  static const _outset = 4.0;

  /// Radius of the selection outline: concentric with the panel's corners.
  double _outlineRadius(double radius) => CornerShapes.concentric(radius * widget.scale, _outset);

  /// The grip being held, drawn a little bolder.
  _Sides? _heldGrip;

  /// The visible panel of a group drawn over [frame] (its cells, at this
  /// scale): a folder's icon, or a container's panel. While resizing,
  /// [frame] is fractional cells, and the panel grows with it in between.
  Rect _panelIn(Rect frame, {required bool folder}) {
    final s = widget.scale;
    final cell = widget.cell / s;
    if (folder) return _scaled(AppContainerTile.iconRect(widget.grid, cell, 0, 0), s).shift(frame.topLeft);
    final cols = frame.width / widget.cell.width, rows = frame.height / widget.cell.height;
    return _scaled(AppContainerTile.panelRect(widget.grid, frame.size / s, cols, rows), s).shift(frame.topLeft);
  }

  static Rect _scaled(Rect r, double s) => Rect.fromLTRB(r.left * s, r.top * s, r.right * s, r.bottom * s);

  /// The group's shape on the home screen, for its outline (see
  /// AppContainerTile.decoration); null for a rounded one.
  ShapeBorder? _shapeBorder(double side) {
    final n = _c.appIds.length;
    final shape = _c.isFolder ? _c.folderShape : AppContainerTile.shapeOf(_c, n);
    int petals() {
      if (_c.isFolder) return AppContainerTile.petalsFor(n.clamp(1, 5));
      final box = Offset.zero & Size.square(side);
      final (spots, _) = AppContainerTile.shapeLayout(shape, box, n, widget.grid);
      return AppContainerTile.petalsAround(box.center, spots);
    }

    return switch (shape) {
      FolderShape.rounded => null,
      FolderShape.circle => const CircleBorder(),
      FolderShape.flower => FlowerBorder(petals: petals(), depth: AppContainerTile.flowerDepth),
      FolderShape.triangle => RoundedTriangleBorder(optical: _c.isFolder, cornerFraction: _c.isFolder ? 0.16 : 0.1),
    };
  }

  Offset _local(Offset global) => (context.findRenderObject()! as RenderBox).globalToLocal(global);

  Rect _frameOf(GridSlot slot, int cols, int rows) => Rect.fromLTWH(
    slot.col * widget.cell.width,
    slot.row * widget.cell.height,
    cols * widget.cell.width,
    rows * widget.cell.height,
  );

  void _interaction(bool active) => widget.onInteraction?.call(active);

  void _resizeStart(DragStartDetails d) {
    _startSlot = widget.slot;
    _startCols = widget.cols;
    _startRows = widget.rows;
    _startPointer = _local(d.globalPosition);
    _haptics.reset();
    _interaction(true);
  }

  void _resizeUpdate(DragUpdateDetails d, _Sides sides) {
    final cell = widget.cell;
    final delta = _local(d.globalPosition) - _startPointer;
    final maxRows = math.min(FrameHandles.maxSpan, widget.gridRows);
    final start = _frameOf(_startSlot, _startCols, _startRows);

    // The live outline: the start frame stretched by the finger, at least
    // one cell, at most the span limit, inside the grid, and with at least
    // one app in every row and column (see AppContainer.fitted): at most as
    // many columns as apps, and rows only while the last one still gets an
    // app. Dragging one side keeps the other dimension, so its limit follows.
    double l = start.left, t = start.top, r = start.right, b = start.bottom;
    final n = math.max(1, _c.appIds.length);
    // A circle, flower or triangle container is any square up to the grid's
    // width; its apps spread to fill it (so not limited by their count).
    final shapedGroup = !_c.isFolder && _c.folderShape != FolderShape.rounded;
    final colsLimit = shapedGroup
        ? widget.gridColumns
        : sides.$2 == 0 && _startRows > 1
        ? math.max(1, (n - 1) ~/ (_startRows - 1))
        : n;
    final maxW =
        [FrameHandles.maxSpan, widget.gridColumns, colsLimit, shapedGroup ? 99 : n].reduce(math.min) * cell.width;
    var maxH =
        (shapedGroup
            ? maxRows
            : [maxRows, sides.$1 == 0 ? AppContainer.rowsFilled(n, _startCols) : n].reduce(math.min)) *
        cell.height;
    final gridW = widget.gridColumns * cell.width, gridH = widget.gridRows * cell.height;
    if (sides.$1 == 1) r = (start.right + delta.dx).clamp(l + cell.width, math.min(gridW, l + maxW));
    if (sides.$1 == -1) l = (start.left + delta.dx).clamp(math.max(0, r - maxW), r - cell.width);
    // A corner: rows are limited by how many apps fill the columns chosen.
    if (sides.$1 != 0 && sides.$2 != 0 && !shapedGroup) {
      final colsNow = math.max(1, ((r - l) / cell.width).round());
      maxH = math.min(maxH, AppContainer.rowsFilled(n, colsNow) * cell.height);
    }
    if (sides.$2 == 1) b = (start.bottom + delta.dy).clamp(t + cell.height, math.min(gridH, t + maxH));
    if (sides.$2 == -1) t = (start.top + delta.dy).clamp(math.max(0, b - maxH), b - cell.height);
    // A shaped group's live frame is a square, sized by the finger along
    // whichever side moved more, grown from the corner held still, within
    // the grid: the outline is its exact shape the whole way.
    if (shapedGroup) {
      final most = [widget.gridColumns, maxRows, FrameHandles.maxSpan].reduce(math.min);
      final gridW = widget.gridColumns * cell.width, gridH = widget.gridRows * cell.height;
      final w = r - l, h = b - t;
      final grow = math.max(w / cell.width, h / cell.height).clamp(2.0, most.toDouble());
      final side = (width: grow * cell.width, height: grow * cell.height);
      if (sides.$1 == -1) {
        l = math.max(0, r - side.width);
      } else {
        r = math.min(gridW, l + side.width);
      }
      if (sides.$2 == -1) {
        t = math.max(0, b - side.height);
      } else {
        b = math.min(gridH, t + side.height);
      }
    }
    setState(() => _liveFrame = Rect.fromLTRB(l, t, r, b));
    // The finger pulled well past the outline: it's as big / small as it goes.
    final pull = <double>[
      if (sides.$1 == 1) start.right + delta.dx - r,
      if (sides.$1 == -1) l - (start.left + delta.dx),
      if (sides.$2 == 1) start.bottom + delta.dy - b,
      if (sides.$2 == -1) t - (start.top + delta.dy),
    ].map((d) => d.abs());
    _haptics.limit(shapedGroup ? pull.reduce(math.min) > 24 : pull.any((d) => d > 24));

    // The group snaps to the nearest whole cells.
    final col = (l / cell.width).round();
    final row = (t / cell.height).round();
    final wantCols = math.max(1, (r / cell.width).round() - col),
        wantRows = math.max(1, (b / cell.height).round() - row);
    final most = [widget.gridColumns, maxRows, FrameHandles.maxSpan].reduce(math.min);
    final square = math.max(wantCols, wantRows).clamp(2, math.max(2, most)).toInt();
    final fit = shapedGroup
        ? _c.copyWith(cols: square, rows: square)
        : _c.copyWith(cols: wantCols, rows: wantRows).fitted();
    final (cols, rows) = (fit.cols, fit.rows);
    if (cols != widget.cols || rows != widget.rows || col != widget.slot.col || row != widget.slot.row) {
      // A tick for a new size; sliding along without resizing is silent.
      if (cols != widget.cols || rows != widget.rows) _haptics.step();
      widget.onChanged(GridSlot(_startSlot.page, col, row), _c.copyWith(cols: cols, rows: rows));
    }
  }

  void _resizeEnd() {
    setState(() => _liveFrame = null);
    _interaction(false);
  }

  void _radiusUpdate(Offset global, Rect outline) {
    final p = _local(global) - outline.topLeft;
    // The knob rides the outline's corner curve: from how far in along the
    // diagonal the finger is, back to the radius whose curve passes there.
    final along = (p.dx + p.dy) / 2;
    final outlineRadius = (along - _OutlinePainter.stroke / 2) / _OutlinePainter.diagonal;
    final raw = ((outlineRadius - _outset) / widget.scale).clamp(0.0, _full);
    // Three roundnesses only; a click on each step.
    final step = AppContainerTile.nearestRadius(raw, _c.isFolder, widget.grid, widget.iconShape);
    if (step != _radius) {
      HapticFeedback.selectionClick();
      final stored = _c.isFolder ? step / _folderFull * AppContainer.maxCornerRadius : step;
      widget.onChanged(widget.slot, _c.copyWith(cornerRadius: stored));
    }
  }

  @override
  Widget build(BuildContext context) {
    final live = _liveFrame;
    final frame = live ?? _frameOf(widget.slot, widget.cols, widget.rows);
    // While resizing, the outline hugs the finger: container insets, no
    // animation. At rest it matches the real panel (folder or container).
    final panel = _panelIn(frame, folder: live == null && _c.isFolder);
    const outset = _outset;
    final outline = panel.inflate(outset);
    // A circle folder is outlined as a circle, a circle or triangle
    // container round its square; a triangle folder, as its box. None has a
    // corner knob.
    final pill = !_c.isFolder && _c.folderShape != FolderShape.rounded;
    final shaped = pill || (_c.isFolder && live == null && _c.folderShape != FolderShape.rounded);
    final outlineRadius = pill
        ? CornerShapes.concentric(panel.shortestSide / 2, _outset)
        : _outlineRadius(shaped && _c.folderShape != FolderShape.triangle ? _folderFull : _radius);
    // On the outline's top-left curve, where it crosses the diagonal.
    final along = _OutlinePainter.stroke / 2 + outlineRadius * _OutlinePainter.diagonal;
    final knob = outline.topLeft + Offset(along, along);
    // The outline of a circle, flower or triangle follows its shape (in its
    // panel's largest square), grips and all.
    final outlineShape = shaped ? _shapeBorder(panel.shortestSide / widget.scale) : null;
    final shapeRect = Rect.fromCenter(
      center: (Offset.zero & outline.size).center,
      width: panel.shortestSide + 2 * outset,
      height: panel.shortestSide + 2 * outset,
    );
    final shapePath = outlineShape?.getOuterPath(shapeRect);
    final animation = live != null ? Duration.zero : const Duration(milliseconds: 180);
    var grips = <(_Sides, Offset)>[
      ((1, 0), Offset(outline.right, panel.center.dy)),
      ((0, 1), Offset(panel.center.dx, outline.bottom)),
      ((1, 1), outline.bottomRight),
      if (widget.edgesMoveOrigin) ...[
        ((-1, 0), Offset(outline.left, panel.center.dy)),
        ((0, -1), Offset(panel.center.dx, outline.top)),
      ],
    ];
    // On a shape, each grip sits on the outline nearest where it would be.
    if (shapePath != null) {
      grips = [
        for (final (sides, at) in grips)
          (sides, outline.topLeft + _OutlinePainter.nearestOn(shapePath, at - outline.topLeft)),
      ];
    }

    // Touch areas only; the grips are drawn as part of the outline.
    Widget grip(_Sides sides, Offset at) {
      const hit = 44.0;
      return AnimatedPositioned(
        duration: animation,
        curve: Curves.easeOutCubic,
        left: at.dx - hit / 2,
        top: at.dy - hit / 2,
        width: hit,
        height: hit,
        child: _Handle(
          onStart: (d) {
            setState(() => _heldGrip = sides);
            _resizeStart(d);
          },
          onUpdate: (d) => _resizeUpdate(d, sides),
          onEnd: () {
            setState(() => _heldGrip = null);
            _resizeEnd();
          },
          child: const SizedBox.expand(),
        ),
      );
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [
        // Selection outline, concentric with the panel, with its grips as
        // bolder stretches of the line itself.
        AnimatedPositioned(
          duration: animation,
          curve: Curves.easeOutCubic,
          left: outline.left,
          top: outline.top,
          width: outline.width,
          height: outline.height,
          child: IgnorePointer(
            child: CustomPaint(
              painter: _OutlinePainter(
                radius: outlineRadius,
                grips: [for (final (sides, _) in grips) sides],
                held: _heldGrip,
                filled: live != null,
                shape: outlineShape,
                shapeRect: shapeRect,
              ),
            ),
          ),
        ),
        for (final (sides, at) in grips) grip(sides, at),
        // Corner-radius knob, on the outline's curve: drag it in to round
        // more, out to square up. (Circle and triangle folders have none.)
        if (!shaped)
          AnimatedPositioned(
            duration: _radiusHeld ? Duration.zero : animation,
            curve: Curves.easeOutCubic,
            left: knob.dx - 18,
            top: knob.dy - 18,
            width: 36,
            height: 36,
            child: _Handle(
              onStart: (_) {
                setState(() => _radiusHeld = true);
                _interaction(true);
              },
              onUpdate: (d) => _radiusUpdate(d.globalPosition, outline),
              onEnd: () {
                setState(() => _radiusHeld = false);
                _interaction(false);
              },
              child: Center(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  width: _radiusHeld ? 16 : 12,
                  height: _radiusHeld ? 16 : 12,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                    boxShadow: [BoxShadow(color: Colors.black38, blurRadius: 4)],
                  ),
                ),
              ),
            ),
          ),
        if (_radiusHeld || live != null)
          Positioned(
            left: panel.left,
            top: _noteTop(panel, outline),
            child: IgnorePointer(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(20)),
                child: Text(
                  _radiusHeld
                      ? _radiusName
                      : _c.isFolder
                      ? 'Folder'
                      : '${widget.cols} × ${widget.rows} · ${_c.appIds.length} apps',
                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Handles around a selected widget, like [FrameHandles] for a container:
/// edge and corner grips resize it (within its least and most size, and
/// the grid), the outline following the finger while the widget snaps to
/// whole cells underneath.
///
/// Each new size goes through [onChanged], which returns false if it can't
/// be had: the apps and widgets it would push aside have no room left on
/// the page. The widget then stays as it was and the outline turns amber
/// with a "No room" note, rather than shoving things onto another page.
///
/// A × at its top-right corner removes it.
class WidgetHandles extends StatefulWidget {
  const WidgetHandles({
    super.key,
    required this.widgetItem,
    required this.grid,
    required this.cell,
    required this.gridColumns,
    required this.gridRows,
    required this.slot,
    required this.cols,
    required this.rows,
    required this.onChanged,
    required this.onRemove,
    this.onSettings,
    this.onInteraction,
    this.iconShape = IconShape.system,
  });

  final WidgetItem widgetItem;

  /// The app icons' shape, which picks the widget's corner radius.
  final IconShape iconShape;
  final HomeGrid grid;
  final Size cell;
  final int gridColumns;
  final int gridRows;
  final GridSlot slot;

  /// The span it has on the grid: its own, clamped to the grid (see
  /// FrameHandles.cols).
  final int cols;
  final int rows;

  /// A new position and size; false if there's no room for it.
  final bool Function(GridSlot slot, WidgetItem updated) onChanged;
  final VoidCallback onRemove;

  /// Reopens an app widget's settings; null if it has none to reopen.
  final VoidCallback? onSettings;

  /// True while a grip is held, false when let go.
  final ValueChanged<bool>? onInteraction;

  @override
  State<WidgetHandles> createState() => _WidgetHandlesState();
}

class _WidgetHandlesState extends State<WidgetHandles> {
  late GridSlot _startSlot;
  late int _startCols;
  late int _startRows;
  Offset _startPointer = Offset.zero;

  /// While a grip is held: the frame exactly under the finger (not snapped).
  Rect? _liveFrame;
  _Sides? _heldGrip;

  /// The size last asked for had no room.
  bool _blocked = false;

  /// The span last refused, so the warning buzzes once per refusal.
  final _haptics = _ResizeHaptics();

  /// The corner knob is held (launcher widgets only).
  bool _radiusHeld = false;

  /// A launcher widget: its corners can be rounded with the knob.
  bool get _roundable => _w.launcherKind != null;

  static const _outset = 4.0;
  static const _warning = Color(0xFFFFB74D);

  WidgetItem get _w => widget.widgetItem;

  Offset _local(Offset global) => (context.findRenderObject()! as RenderBox).globalToLocal(global);

  Rect _frameOf(GridSlot slot, int cols, int rows) => Rect.fromLTWH(
    slot.col * widget.cell.width,
    slot.row * widget.cell.height,
    cols * widget.cell.width,
    rows * widget.cell.height,
  );

  Rect _panelIn(Rect frame) => HomeWidgetView.frameIn(
    widget.grid,
    frame.size,
    frame.width / widget.cell.width,
    frame.height / widget.cell.height,
  ).shift(frame.topLeft);

  void _start(DragStartDetails d) {
    _startSlot = widget.slot;
    _startCols = widget.cols;
    _startRows = widget.rows;
    _startPointer = _local(d.globalPosition);
    _haptics.reset();
    widget.onInteraction?.call(true);
  }

  void _update(DragUpdateDetails d, _Sides sides) {
    final cell = widget.cell;
    final delta = _local(d.globalPosition) - _startPointer;
    final start = _frameOf(_startSlot, _startCols, _startRows);
    final minW = _w.minCols * cell.width, minH = _w.minRows * cell.height;
    final maxW = math.min(_w.maxCols, widget.gridColumns) * cell.width;
    final maxH = math.min(_w.maxRows, widget.gridRows) * cell.height;
    final gridW = widget.gridColumns * cell.width, gridH = widget.gridRows * cell.height;
    double l = start.left, t = start.top, r = start.right, b = start.bottom;
    if (sides.$1 == 1) r = (start.right + delta.dx).clamp(l + minW, math.min(gridW, l + maxW));
    if (sides.$1 == -1) l = (start.left + delta.dx).clamp(math.max(0, r - maxW), r - minW);
    if (sides.$2 == 1) b = (start.bottom + delta.dy).clamp(t + minH, math.min(gridH, t + maxH));
    if (sides.$2 == -1) t = (start.top + delta.dy).clamp(math.max(0, b - maxH), b - minH);
    setState(() => _liveFrame = Rect.fromLTRB(l, t, r, b));
    _haptics.limit(
      [
        if (sides.$1 == 1) start.right + delta.dx - r,
        if (sides.$1 == -1) l - (start.left + delta.dx),
        if (sides.$2 == 1) start.bottom + delta.dy - b,
        if (sides.$2 == -1) t - (start.top + delta.dy),
      ].any((d) => d.abs() > 24),
    );

    var col = (l / cell.width).round(), row = (t / cell.height).round();
    final right = (r / cell.width).round(), bottom = (b / cell.height).round();
    // A widget that only comes in some sizes takes the nearest, growing
    // from the side that's held still.
    final (cols, rows) = snapSpan(
      _w,
      math.max(1, right - col),
      math.max(1, bottom - row),
      gridColumns: widget.gridColumns,
    );
    if (sides.$1 == -1) col = math.max(0, right - cols);
    if (sides.$2 == -1) row = math.max(0, bottom - rows);
    final slot = GridSlot(_startSlot.page, col, row);
    if (cols == widget.cols && rows == widget.rows && slot == widget.slot) {
      if (_blocked) setState(() => _blocked = false);
      return;
    }
    if (widget.onChanged(slot, _w.copyWith(cols: cols, rows: rows))) {
      if (cols != widget.cols || rows != widget.rows) _haptics.step();
      setState(() => _blocked = false);
    } else {
      _haptics.refused((slot, cols, rows));
      setState(() => _blocked = true);
    }
  }

  void _end() {
    setState(() {
      _liveFrame = null;
      _heldGrip = null;
      _blocked = false;
    });
    widget.onInteraction?.call(false);
  }

  @override
  Widget build(BuildContext context) {
    final live = _liveFrame;
    final panel = _panelIn(live ?? _frameOf(widget.slot, widget.cols, widget.rows));
    final outline = panel.inflate(_outset);
    final radius = HomeWidgetView.radiusFor(
      (panel.width / widget.cell.width).round().clamp(1, WidgetItem.maxSpan),
      (panel.height / widget.cell.height).round().clamp(1, WidgetItem.maxSpan),
      panel.size,
      iconShape: widget.iconShape,
    );
    final drawn = _roundable ? launcherWidgetRadius(_w.settings, panel.size, radius) : radius;
    final outlineRadius = CornerShapes.concentric(drawn, _outset);
    final animation = live != null ? Duration.zero : const Duration(milliseconds: 180);
    // On the outline's top-left curve, where it crosses the diagonal.
    final along = _OutlinePainter.stroke / 2 + outlineRadius * _OutlinePainter.diagonal;
    final knob = outline.topLeft + Offset(along, along);
    final steps = widgetRadii(panel.size);
    final step = steps.reduce((a, b) => (drawn - a).abs() <= (drawn - b).abs() ? a : b);
    final wide = _w.minCols < _w.maxCols, tall = _w.minRows < _w.maxRows;
    final grips = <(_Sides, Offset)>[
      if (wide) ((1, 0), Offset(outline.right, panel.center.dy)),
      if (tall) ((0, 1), Offset(panel.center.dx, outline.bottom)),
      if (wide && tall) ((1, 1), outline.bottomRight),
      if (wide) ((-1, 0), Offset(outline.left, panel.center.dy)),
      if (tall) ((0, -1), Offset(panel.center.dx, outline.top)),
    ];
    final color = _blocked ? _warning : Colors.white;

    Widget grip(_Sides sides, Offset at) {
      const hit = 44.0;
      return AnimatedPositioned(
        duration: animation,
        curve: Curves.easeOutCubic,
        left: at.dx - hit / 2,
        top: at.dy - hit / 2,
        width: hit,
        height: hit,
        child: _Handle(
          onStart: (d) {
            setState(() => _heldGrip = sides);
            _start(d);
          },
          onUpdate: (d) => _update(d, sides),
          onEnd: _end,
          child: const SizedBox.expand(),
        ),
      );
    }

    // A round button on the outline (remove, settings).
    Widget badge(Offset at, IconData icon, VoidCallback onTap) => AnimatedPositioned(
      duration: animation,
      curve: Curves.easeOutCubic,
      left: at.dx - 22,
      top: at.dy - 22,
      width: 44,
      height: 44,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Center(
          child: Container(
            width: 24,
            height: 24,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              boxShadow: [BoxShadow(color: Colors.black38, blurRadius: 4)],
            ),
            child: Icon(icon, size: 16, color: Colors.black87),
          ),
        ),
      ),
    );

    final note = _blocked
        ? 'No room on this page'
        : _radiusHeld
        ? AppContainerTile.radiusNames[steps.indexOf(step).clamp(0, 2)]
        : live != null
        ? '${widget.cols} × ${widget.rows}'
        : (_w.resizable ? null : 'Fixed size');
    return Stack(
      clipBehavior: Clip.none,
      children: [
        AnimatedPositioned(
          duration: animation,
          curve: Curves.easeOutCubic,
          left: outline.left,
          top: outline.top,
          width: outline.width,
          height: outline.height,
          child: IgnorePointer(
            child: CustomPaint(
              painter: _OutlinePainter(
                radius: outlineRadius,
                grips: [for (final (sides, _) in grips) sides],
                held: _heldGrip,
                filled: live != null,
                color: color,
              ),
            ),
          ),
        ),
        for (final (sides, at) in grips) grip(sides, at),
        if (live == null) badge(Offset(outline.right, outline.top), Icons.close_rounded, widget.onRemove),
        // Corner-radius knob, as a container's: drag it in to round more,
        // out to square up; three steps.
        if (_roundable && live == null)
          AnimatedPositioned(
            duration: _radiusHeld ? Duration.zero : animation,
            curve: Curves.easeOutCubic,
            left: knob.dx - 18,
            top: knob.dy - 18,
            width: 36,
            height: 36,
            child: _Handle(
              onStart: (_) {
                setState(() => _radiusHeld = true);
                widget.onInteraction?.call(true);
              },
              onUpdate: (d) {
                final p = _local(d.globalPosition) - outline.topLeft;
                final r = ((p.dx + p.dy) / 2 - _OutlinePainter.stroke / 2) / _OutlinePainter.diagonal - _outset;
                final next = steps.reduce((a, b) => (r - a).abs() <= (r - b).abs() ? a : b);
                if (next != step) {
                  HapticFeedback.selectionClick();
                  widget.onChanged(widget.slot, _w.copyWith(settings: {..._w.settings, 'radius': next}));
                }
              },
              onEnd: () {
                setState(() => _radiusHeld = false);
                widget.onInteraction?.call(false);
              },
              child: Center(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  width: _radiusHeld ? 16 : 12,
                  height: _radiusHeld ? 16 : 12,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                    boxShadow: [BoxShadow(color: Colors.black38, blurRadius: 4)],
                  ),
                ),
              ),
            ),
          ),
        if (live == null && widget.onSettings != null)
          badge(Offset(outline.right - 34, outline.top), Icons.settings_rounded, widget.onSettings!),
        if (note != null)
          Positioned(
            left: panel.left,
            top: _noteTop(panel, outline),
            child: IgnorePointer(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: _blocked ? _warning : Colors.black87,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  note,
                  style: TextStyle(
                    color: _blocked ? Colors.black : Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Top of the note over a selected item's [panel]: just above it, or just
/// below its [outline] in the top row, where above would be off the page.
double _noteTop(Rect panel, Rect outline) => panel.top >= 34 ? panel.top - 34 : outline.bottom + 8;

/// The selection outline: a thin line around the panel, concentric with its
/// corners, and the resize grips as short, bolder stretches of that same
/// line (at the middle of each edge that has one, and around the bottom
/// right corner, following its curve), so the handles read as part of the
/// frame rather than objects on top of it.
class _OutlinePainter extends CustomPainter {
  _OutlinePainter({
    required this.radius,
    required this.grips,
    required this.held,
    required this.filled,
    this.color = Colors.white,
    this.shape,
    this.shapeRect,
  });

  final double radius;

  /// A circle, flower or triangle to outline instead, in [shapeRect]; its
  /// grips are stretches of it nearest where a rectangle's would be.
  final ShapeBorder? shape;
  final Rect? shapeRect;

  /// The point on [path] nearest [to].
  static Offset nearestOn(Path path, Offset to) {
    var best = to;
    var bestD = double.infinity;
    for (final m in path.computeMetrics()) {
      for (var d = 0.0; d <= m.length; d += 2) {
        final p = m.getTangentForOffset(d)!.position;
        final dd = (p - to).distanceSquared;
        if (dd < bestD) (best, bestD) = (p, dd);
      }
    }
    return best;
  }

  /// Where grip [sides] would be on a [size] rectangle.
  static Offset _anchor(_Sides sides, Size size) => Offset(
    switch (sides.$1) {
      1 => size.width,
      -1 => 0,
      _ => size.width / 2,
    },
    switch (sides.$2) {
      1 => size.height,
      -1 => 0,
      _ => size.height / 2,
    },
  );

  /// The line's colour: white, or a warning colour when a resize can't go on.
  final Color color;
  final List<_Sides> grips;
  final _Sides? held;

  /// A faint fill, while resizing.
  final bool filled;

  /// Width of the outline.
  static const stroke = 2.0;

  /// Length of an edge grip, and how far a corner grip reaches past its curve.
  static const _gripLength = 28.0;
  static const _cornerLeg = 12.0;

  /// How far in from the corner, as a share of the radius, the shape's
  /// corner curve crosses the diagonal (1 - 1/√2 for a circular arc; a
  /// little less for these continuous corners). Measured once.
  static final double diagonal = () {
    const r = 100.0;
    final path = CornerShapes.shape(r).getOuterPath(Offset.zero & const Size(400, 400));
    var (lo, hi) = (0.0, r);
    for (var i = 0; i < 30; i++) {
      final mid = (lo + hi) / 2;
      path.contains(Offset(mid, mid)) ? hi = mid : lo = mid;
    }
    return hi / r;
  }();

  /// Where a grip's stretch of the outline lies, in a [size] outline.
  static Rect _region(_Sides sides, Size size) {
    final (w, h) = (size.width, size.height);
    const t = 10.0; // across the line
    const half = _gripLength / 2;
    return switch (sides) {
      (1, 0) => Rect.fromLTRB(w - t, h / 2 - half, w + t, h / 2 + half),
      (-1, 0) => Rect.fromLTRB(-t, h / 2 - half, t, h / 2 + half),
      (0, 1) => Rect.fromLTRB(w / 2 - half, h - t, w / 2 + half, h + t),
      (0, -1) => Rect.fromLTRB(w / 2 - half, -t, w / 2 + half, t),
      _ => Rect.fromLTRB(w - t, h - t, w + t, h + t),
    };
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (shape != null) return _paintShape(canvas, size);
    final path = CornerShapes.shape(radius).getOuterPath((Offset.zero & size).deflate(stroke / 2));
    if (filled) canvas.drawPath(path, Paint()..color = color.withValues(alpha: 0.06));
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = color,
    );

    final metrics = path.computeMetrics().toList();
    for (final sides in grips) {
      var region = _region(sides, size);
      if (sides == (1, 1)) {
        // The whole corner curve and a little of each side, short of the
        // edge grips.
        final reach = radius + _cornerLeg;
        region = Rect.fromLTRB(
          math.max(size.width - reach, size.width / 2 + _gripLength / 2 + 6),
          math.max(size.height - reach, size.height / 2 + _gripLength / 2 + 6),
          region.right,
          region.bottom,
        );
      }
      final width = sides == held ? 6.0 : 4.5;
      final shadow = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round
        ..color = Colors.black26
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
      final line = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round
        ..color = color;
      for (final m in metrics) {
        for (final (from, to) in _inside(m, region)) {
          final part = m.extractPath(from, to);
          canvas
            ..drawPath(part, shadow)
            ..drawPath(part, line);
        }
      }
    }
  }

  /// The outline of [shape], each grip a bolder stretch of it centred on the
  /// point nearest where a rectangle's grip would be.
  void _paintShape(Canvas canvas, Size size) {
    final path = shape!.getOuterPath(shapeRect!.deflate(stroke / 2));
    if (filled) canvas.drawPath(path, Paint()..color = color.withValues(alpha: 0.06));
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = color,
    );
    final metrics = path.computeMetrics().toList();
    for (final sides in grips) {
      final to = _anchor(sides, size);
      PathMetric? on;
      var at = 0.0, bestD = double.infinity;
      for (final m in metrics) {
        for (var d = 0.0; d <= m.length; d += 2) {
          final dd = (m.getTangentForOffset(d)!.position - to).distanceSquared;
          if (dd < bestD) (on, at, bestD) = (m, d, dd);
        }
      }
      if (on == null) continue;
      final half = (sides.$1 != 0 && sides.$2 != 0 ? _gripLength * 1.4 : _gripLength) / 2;
      final width = sides == held ? 6.0 : 4.5;
      final shadow = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round
        ..color = Colors.black26
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
      final line = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round
        ..color = color;
      // A closed outline: a stretch across its start wraps round.
      final len = on.length;
      final parts = [
        if (at - half < 0) (len + at - half, len),
        (math.max(0.0, at - half), math.min(len, at + half)),
        if (at + half > len) (0.0, at + half - len),
      ];
      for (final (from, to) in parts) {
        final part = on.extractPath(from, to);
        canvas
          ..drawPath(part, shadow)
          ..drawPath(part, line);
      }
    }
  }

  /// Stretches of [m] that lie in [region], as (start, end) distances.
  static List<(double, double)> _inside(PathMetric m, Rect region) {
    final parts = <(double, double)>[];
    double? start;
    const step = 1.0;
    for (var d = 0.0; d <= m.length; d += step) {
      final inside = region.contains(m.getTangentForOffset(d)!.position);
      if (inside && start == null) start = d;
      if (!inside && start != null) {
        parts.add((start, d - step));
        start = null;
      }
    }
    if (start != null) parts.add((start, m.length));
    return parts;
  }

  @override
  bool shouldRepaint(_OutlinePainter old) =>
      old.radius != radius ||
      old.held != held ||
      old.filled != filled ||
      old.color != color ||
      old.shape != shape ||
      old.shapeRect != shapeRect ||
      !listEquals(old.grips, grips);
}

/// A pan recognizer that wins the gesture arena as soon as the finger lands,
/// so a handle never loses its drag to swipes / scrolling around it.
class _EagerPan extends PanGestureRecognizer {
  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    resolve(GestureDisposition.accepted);
  }
}

/// [GestureDetector]-like pan handling with [_EagerPan].
class _Handle extends StatelessWidget {
  const _Handle({required this.onStart, required this.onUpdate, required this.onEnd, required this.child});

  final GestureDragStartCallback onStart;
  final GestureDragUpdateCallback onUpdate;
  final VoidCallback onEnd;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return RawGestureDetector(
      behavior: HitTestBehavior.opaque,
      gestures: {
        _EagerPan: GestureRecognizerFactoryWithHandlers<_EagerPan>(
          _EagerPan.new,
          (r) => r
            ..dragStartBehavior = DragStartBehavior.down
            ..onStart = onStart
            ..onUpdate = onUpdate
            ..onEnd = ((_) => onEnd())
            ..onCancel = onEnd,
        ),
      },
      child: child,
    );
  }
}
