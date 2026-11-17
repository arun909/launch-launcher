import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'search_widget_controller.dart';

/// Home-screen app-search widget. Tap opens the drawer with search focused;
/// long-press offers Resize / Hide. While resizing, edge handles snap the
/// width to the home grid's columns and the top handle steps the height.
class SearchWidget extends StatelessWidget {
  const SearchWidget({super.key, required this.onOpenSearch});

  final VoidCallback onOpenSearch;

  /// Room around the bar for the resize frame and handles.
  static const _framePad = 14.0;

  @override
  Widget build(BuildContext context) {
    final c = context.watch<SearchWidgetController>();
    if (!c.isVisible) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final cell = constraints.maxWidth / SearchWidgetController.gridColumns;
        final left = c.startColumn * cell;
        final width = c.columns * cell;
        final pad = c.isResizing ? _framePad : 0.0;

        final bar = _SearchBar(
          columns: c.columns,
          height: c.height.dp,
          onTap: c.isResizing ? null : onOpenSearch,
          onLongPress: c.isResizing ? null : () => _showWidgetActions(context),
        );

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (c.isResizing)
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.tonal(onPressed: c.stopResizing, child: const Text('Done')),
              ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              height: c.height.dp + pad * 2,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 120),
                    curve: Curves.easeOutCubic,
                    left: left,
                    width: width,
                    top: pad,
                    height: c.height.dp,
                    child: bar,
                  ),
                  if (c.isResizing) ..._resizeFrame(context, c, cell, left, width, pad),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  List<Widget> _resizeFrame(
    BuildContext context,
    SearchWidgetController c,
    double cell,
    double left,
    double width,
    double pad,
  ) {
    final h = c.height.dp;
    return [
      // Outline around the widget's current span.
      Positioned(
        left: left - 4,
        width: width + 8,
        top: pad - 4,
        height: h + 8,
        child: IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white, width: 2),
              borderRadius: BorderRadius.circular(h / 2 + 4),
            ),
          ),
        ),
      ),
      // Left / right edges: snap to the nearest grid line while dragging.
      _EdgeHandle(
        centerX: left,
        centerY: pad + h / 2,
        maxX: cell * SearchWidgetController.gridColumns,
        axis: Axis.horizontal,
        start: left,
        onDrag: (x) => _snap(c.moveLeftEdge, x, cell, c),
      ),
      _EdgeHandle(
        centerX: left + width,
        centerY: pad + h / 2,
        maxX: cell * SearchWidgetController.gridColumns,
        axis: Axis.horizontal,
        start: left + width,
        onDrag: (x) => _snap(c.moveRightEdge, x, cell, c),
      ),
      // Top edge: drag up for taller, down for shorter.
      _EdgeHandle(
        centerX: left + width / 2,
        centerY: pad - 4,
        maxX: cell * SearchWidgetController.gridColumns,
        axis: Axis.vertical,
        start: 0,
        onDrag: (direction) {
          final steps = SearchWidgetHeight.values;
          final target = steps[(c.height.index - direction.toInt()).clamp(0, steps.length - 1)];
          if (target != c.height) {
            HapticFeedback.selectionClick();
            c.setHeight(target);
          }
        },
      ),
    ];
  }

  static void _snap(Future<void> Function(int) move, double x, double cell, SearchWidgetController c) {
    final before = (c.startColumn, c.columns);
    move((x / cell).round());
    if ((c.startColumn, c.columns) != before) HapticFeedback.selectionClick();
  }

  void _showWidgetActions(BuildContext context) {
    HapticFeedback.mediumImpact();
    final c = context.read<SearchWidgetController>();
    final messenger = ScaffoldMessenger.maybeOf(context);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.open_in_full),
              title: const Text('Resize'),
              subtitle: Text(c.sizeLabel),
              onTap: () {
                Navigator.pop(sheetContext);
                c.startResizing();
              },
            ),
            ListTile(
              leading: const Icon(Icons.visibility_off_outlined),
              title: const Text('Hide search bar'),
              subtitle: const Text('In drawer mode, swiping down on the lower half still opens search'),
              onTap: () {
                Navigator.pop(sheetContext);
                c.setVisible(false);
                messenger?.showSnackBar(
                  SnackBar(
                    persist: false, // with an action, Flutter otherwise keeps it until tapped
                    content: const Text('Search bar hidden'),
                    action: SnackBarAction(label: 'Undo', onPressed: () => c.setVisible(true)),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// The bar itself. Narrow spans drop the text, down to an icon-only button.
class _SearchBar extends StatelessWidget {
  const _SearchBar({required this.columns, required this.height, this.onTap, this.onLongPress});

  final int columns;
  final double height;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final iconSize = height * 0.43;
    final label = switch (columns) {
      1 => null,
      2 => 'Search',
      _ => 'Search apps',
    };

    return Material(
      color: Colors.white.withValues(alpha: 0.18),
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: label == null ? 0 : height * 0.36),
          child: Row(
            mainAxisAlignment: label == null ? MainAxisAlignment.center : MainAxisAlignment.start,
            children: [
              Icon(Icons.search, color: Colors.white70, size: iconSize),
              if (label != null) ...[
                SizedBox(width: height * 0.2),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.white70, fontSize: height * 0.29),
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

/// A round drag handle centred on ([centerX], [centerY]).
///
/// Horizontal: reports the finger's x position (drag start = [start]), for
/// snapping an edge to grid lines. Vertical: reports -1 (up) or +1 (down)
/// for every [_stepDp] dragged, for stepping through heights.
class _EdgeHandle extends StatefulWidget {
  const _EdgeHandle({
    required this.centerX,
    required this.centerY,
    required this.maxX,
    required this.axis,
    required this.start,
    required this.onDrag,
  });

  final double centerX;
  final double centerY;

  /// Right end of the area the handle lives in. Touches outside a parent's
  /// bounds are never delivered, so the touch target is kept inside
  /// [0, maxX] even when the dot sits exactly on the outer edge.
  final double maxX;
  final Axis axis;
  final double start;
  final ValueChanged<double> onDrag;

  @override
  State<_EdgeHandle> createState() => _EdgeHandleState();
}

class _EdgeHandleState extends State<_EdgeHandle> {
  static const _hitSize = 44.0;
  static const _dotSize = 18.0;
  static const _stepDp = 14.0;

  double _origin = 0;
  double _total = 0;

  @override
  Widget build(BuildContext context) {
    final horizontal = widget.axis == Axis.horizontal;
    final hitLeft = (widget.centerX - _hitSize / 2).clamp(0.0, widget.maxX - _hitSize);
    return Positioned(
      left: hitLeft,
      top: widget.centerY - _hitSize / 2,
      width: _hitSize,
      height: _hitSize,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: horizontal ? (_) => _begin() : null,
        onHorizontalDragUpdate: horizontal ? (d) => _update(d.delta.dx) : null,
        onVerticalDragStart: horizontal ? null : (_) => _begin(),
        onVerticalDragUpdate: horizontal ? null : (d) => _update(d.delta.dy),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: widget.centerX - hitLeft - _dotSize / 2,
              top: (_hitSize - _dotSize) / 2,
              child: Container(
                width: _dotSize,
                height: _dotSize,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(blurRadius: 4, color: Colors.black38)],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _begin() {
    _origin = widget.start;
    _total = 0;
  }

  void _update(double delta) {
    _total += delta;
    if (widget.axis == Axis.horizontal) {
      widget.onDrag(_origin + _total);
    } else if (_total.abs() >= _stepDp) {
      widget.onDrag(_total.sign);
      _total = 0;
    }
  }
}
