import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/platform/app_widgets_platform.dart';
import '../../core/theme/home_grid.dart';
import '../standard_home/home_layout.dart';
import '../standard_home/home_layout_controller.dart';
import '../standard_home/standard_home.dart';
import 'home_widget_view.dart';
import 'launcher_widgets.dart';

/// Size of one home-grid cell on this screen: the grid spans the width
/// inside the safe area, less the standard-mode side padding (drawer-mode
/// widgets use the same insets), cells as HomeGrid shapes them. In standard
/// mode, the cells as last laid out (their height depends on the grid's
/// height with fixed rows).
Size homeCell(BuildContext context, HomeGrid grid) {
  final media = MediaQuery.of(context);
  final full = media.size.width - media.padding.horizontal;
  final width = full - StandardHome.sidePaddingFor(grid, full) * 2;
  final cellWidth = width / grid.columns;
  final layout = context.read<HomeLayoutController>();
  if (layout.mode == HomeMode.standard && (layout.cellSize.width - cellWidth).abs() < 0.5) return layout.cellSize;
  return Size(cellWidth, grid.cellHeightFor(cellWidth));
}

/// [p] as a home-screen widget on cells of [cell]: it starts at the cells
/// its app asks for (or the fewest that give its default size), and keeps
/// the dp sizes it can be resized between, so its cell limits always give
/// it the room it needs (see HomeWidgetView.fitTo).
WidgetItem appWidgetItem(AppWidgetProvider p, {required HomeGrid grid, required Size cell, int? appWidgetId}) {
  double least(int resize, int min) => (resize > 0 ? math.min(resize, min) : min).toDouble();
  final (fitCols, fitRows) = HomeWidgetView.cellsFor(grid, cell, p.minWidthDp.toDouble(), p.minHeightDp.toDouble());
  final cols = p.targetCellWidth > 0 ? p.targetCellWidth : fitCols;
  final rows = p.targetCellHeight > 0 ? p.targetCellHeight : fitRows;
  // Not resizable one way: fixed at the size it starts at that way.
  final start = HomeWidgetView.sizeOf(grid, cell, cols, rows);
  final fixedW = math.max(p.minWidthDp.toDouble(), p.targetCellWidth > 0 ? start.width : 0.0);
  final fixedH = math.max(p.minHeightDp.toDouble(), p.targetCellHeight > 0 ? start.height : 0.0);
  final item = WidgetItem(
    id: HomeLayoutController.newId(),
    appWidgetId: appWidgetId,
    provider: p.provider,
    cols: cols.clamp(1, WidgetItem.maxSpan),
    rows: rows.clamp(1, WidgetItem.maxSpan),
    minWidthDp: p.resizeHorizontal ? least(p.minResizeWidthDp, p.minWidthDp) : fixedW,
    minHeightDp: p.resizeVertical ? least(p.minResizeHeightDp, p.minHeightDp) : fixedH,
    maxWidthDp: p.resizeHorizontal ? p.maxResizeWidthDp.toDouble() : fixedW,
    maxHeightDp: p.resizeVertical ? p.maxResizeHeightDp.toDouble() : fixedH,
    reconfigurable: p.reconfigurable,
  );
  return HomeWidgetView.fitTo(item, grid, cell);
}

/// A new launcher widget of [kind].
WidgetItem launcherWidgetItem(LauncherWidgetKind kind) => WidgetItem(
  id: HomeLayoutController.newId(),
  launcherKind: kind.name,
  cols: kind.size.$1,
  rows: kind.size.$2,
  minCols: kind.min.$1,
  minRows: kind.min.$2,
  maxCols: kind.max.$1,
  maxRows: kind.max.$2,
);

/// Where a new widget goes, and at what size.
class WidgetPlacement {
  const WidgetPlacement(this.item, this.slot);

  final WidgetItem item;

  /// Null in drawer mode, where widgets simply stack.
  final GridSlot? slot;
}

/// Finds clean room for [item] on the home screen: free cells on the page
/// on screen, at its size, moving nothing. Widgets are never squeezed in:
///
/// - Too big for a page even at its least size: says so, and adds nothing.
/// - Bigger than a page, but able to shrink to fit: shrinks to the page.
/// - No room on this page: asks, offering the smallest size it can take
///   that does fit here (if any), or the first page with room (or a new one).
///
/// Returns null if it shouldn't be added.
Future<WidgetPlacement?> findRoom(BuildContext context, WidgetItem item) async {
  final layout = context.read<HomeLayoutController>();
  if (layout.mode != HomeMode.standard) return WidgetPlacement(item, null);
  final columns = layout.grid.columns, rows = layout.gridRows;

  if (item.minCols > columns || item.minRows > rows) {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded),
        title: const Text('Too big for your home screen'),
        content: Text(
          'This widget needs at least ${item.minCols} × ${item.minRows} cells, and your pages are '
          '$columns × $rows. Try a grid with more columns (Settings › Home grid).',
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
      ),
    );
    return null;
  }

  final w = item.copyWith(cols: math.min(item.cols, columns), rows: math.min(item.rows, rows));
  final here = layout.currentPage;
  final slot = layout.roomFor(w.cols, w.rows)!;
  if (slot.page == here) return WidgetPlacement(w, slot);

  // The smallest size it allows, if that fits on this page.
  WidgetPlacement? smaller;
  if (w.minCols < w.cols || w.minRows < w.rows) {
    final least = w.copyWith(cols: w.minCols, rows: w.minRows);
    if (layout.roomFor(least.cols, least.rows) case final s? when s.page == here) smaller = WidgetPlacement(least, s);
  }
  final pageCount = layout.arrangement?.pages.length ?? 1;
  final elsewhere = slot.page >= pageCount ? 'a new page' : 'page ${slot.page + 1}';
  if (!context.mounted) return null;
  return showDialog<WidgetPlacement>(
    context: context,
    builder: (context) => AlertDialog(
      icon: const Icon(Icons.grid_off_rounded),
      title: const Text('No room on this page'),
      content: Text(
        'A ${w.cols} × ${w.rows} widget doesn\'t fit in the free space on this page. '
        'It won\'t be squeezed in or push your apps around.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        if (smaller != null)
          TextButton(
            onPressed: () => Navigator.pop(context, smaller),
            child: Text('Add here at ${smaller.item.cols} × ${smaller.item.rows}'),
          ),
        FilledButton(
          onPressed: () => Navigator.pop(context, WidgetPlacement(w, slot)),
          child: Text('Add to $elsewhere'),
        ),
      ],
    ),
  );
}
