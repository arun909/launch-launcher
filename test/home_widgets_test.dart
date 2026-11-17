import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minimal_launcher/core/models/icon_shape.dart';
import 'package:minimal_launcher/core/platform/app_widgets_platform.dart';
import 'package:minimal_launcher/core/theme/home_grid.dart';
import 'package:minimal_launcher/features/standard_home/home_layout.dart';
import 'package:minimal_launcher/features/widgets/home_widget_view.dart';
import 'package:minimal_launcher/features/widgets/launcher_widgets.dart';
import 'package:minimal_launcher/features/widgets/widget_placement.dart';

/// A phone-like large grid: 4 columns of ~93dp, cells as tall as wide.
const _grid = HomeGrid.large;
const _cell = Size(92.75, 92.75);

AppWidgetProvider _provider({
  int minW = 110,
  int minH = 110,
  int resizeW = 0,
  int resizeH = 0,
  bool h = false,
  bool v = false,
  int maxW = 0,
}) => AppWidgetProvider(
  provider: 'p.kg/.W',
  packageName: 'p.kg',
  label: 'W',
  appLabel: 'P',
  minWidthDp: minW,
  minHeightDp: minH,
  minResizeWidthDp: resizeW,
  minResizeHeightDp: resizeH,
  resizeHorizontal: h,
  resizeVertical: v,
  maxResizeWidthDp: maxW,
);

/// A launcher widget for tests.
final _testKind = LauncherWidgetKind(
  name: 'test',
  label: 'Test',
  description: 'For tests',
  icon: const IconData(0),
  size: (4, 2),
  min: (2, 1),
  max: (6, 3),
  build: (_, _) => const SizedBox(),
);

void main() {
  group('geometry', () {
    test('a widget fills its cells but for a small inset all round, as on OriginOS', () {
      const cols = 4, rows = 2;
      final box = Size(_cell.width * cols, _cell.height * rows);
      final frame = HomeWidgetView.frameIn(_grid, box, cols.toDouble(), rows.toDouble());
      expect(HomeWidgetView.inset(_grid), 8);
      expect(frame, (Offset.zero & box).deflate(8));
      // Denser grids leave a little less, like OriginOS's 5-column grid.
      expect(HomeWidgetView.inset(HomeGrid.compact), lessThan(7));
    });

    test('a widget is at least as big as an icon cell less its inset', () {
      expect(HomeWidgetView.sizeOf(_grid, _cell, 1, 1), Size(_cell.width - 16, _cell.height - 16));
    });

    test('cells are the fewest that give the size asked for', () {
      for (final dp in [40.0, 110.0, 180.0, 250.0, 320.0]) {
        final (c, r) = HomeWidgetView.cellsFor(_grid, _cell, dp, dp);
        expect(HomeWidgetView.sizeOf(_grid, _cell, c, 1).width, greaterThanOrEqualTo(dp - 0.01));
        if (c > 1) expect(HomeWidgetView.sizeOf(_grid, _cell, c - 1, 1).width, lessThan(dp));
        expect(HomeWidgetView.sizeOf(_grid, _cell, 1, r).height, greaterThanOrEqualTo(dp - 0.01));
        if (r > 1) expect(HomeWidgetView.sizeOf(_grid, _cell, 1, r - 1).height, lessThan(dp));
      }
    });

    test('a widget lays out at its OriginOS size and is scaled down to fit shorter rows', () {
      // 2 x 2: OriginOS rows are 87.4dp plus a 42dp gap; ours are ~93dp, no gap.
      final frame = HomeWidgetView.sizeOf(_grid, _cell, 2, 2);
      final ref = HomeWidgetView.referenceSizeOf(_grid, 2, 2);
      expect(ref.height, closeTo(2 * 87.4 + 42 - 16, 0.001));
      final scale = HomeWidgetView.scaleFor(_grid, frame, 2, 2);
      expect(scale, closeTo(frame.height / ref.height, 0.001));
      expect(HomeWidgetView.layoutSizeOf(_grid, frame, 2, 2).height, closeTo(ref.height, 0.001));
      // One row is already as tall as OriginOS's: drawn at full size.
      expect(HomeWidgetView.scaleFor(_grid, HomeWidgetView.sizeOf(_grid, _cell, 3, 1), 3, 1), 1);
    });

    test('corners follow OriginOS\'s table by size, rounder with round icons', () {
      const big = Size(400, 400);
      expect(HomeWidgetView.radiusFor(4, 1, big), 13);
      expect(HomeWidgetView.radiusFor(2, 2, big), 15.3);
      expect(HomeWidgetView.radiusFor(4, 2, big), 17);
      expect(HomeWidgetView.radiusFor(4, 4, big), 16.5);
      expect(HomeWidgetView.radiusFor(2, 2, big, iconShape: IconShape.circle), 21);
      // Never more than half the shorter side.
      expect(HomeWidgetView.radiusFor(1, 1, const Size(20, 20)), 10);
    });
  });

  group('sizes and limits', () {
    test('a widget that can\'t be resized keeps its size', () {
      final w = appWidgetItem(_provider(minW: 300), grid: _grid, cell: _cell);
      expect((w.cols, w.rows, w.resizable), (4, 2, false));
      expect(w.copyWith(cols: 2, rows: 5), w);
    });

    test('a resizable widget goes down to its least size and up to its most', () {
      final w = appWidgetItem(_provider(minW: 300, resizeW: 110, h: true, maxW: 400), grid: _grid, cell: _cell);
      expect((w.cols, w.minCols, w.maxCols), (4, 2, 4)); // 5 cells would be wider than 400dp
      expect((w.minRows, w.maxRows), (2, 2)); // not resizable up and down
      expect(w.copyWith(cols: 1).cols, 2);
      expect(w.copyWith(cols: 6).cols, 4);
    });

    test('no stated maximum: grows as far as the grid allows', () {
      final w = appWidgetItem(_provider(h: true, v: true), grid: _grid, cell: _cell);
      expect((w.maxCols, w.maxRows), (WidgetItem.maxSpan, WidgetItem.maxSpan));
    });

    test('the cells an app asks for are kept, as a fixed size if it can\'t be resized', () {
      const p = AppWidgetProvider(
        provider: 'p.kg/.W',
        packageName: 'p.kg',
        label: 'W',
        appLabel: 'P',
        minWidthDp: 110,
        minHeightDp: 40,
        targetCellWidth: 4,
        targetCellHeight: 2,
      );
      final w = appWidgetItem(p, grid: _grid, cell: _cell);
      expect((w.cols, w.rows, w.resizable), (4, 2, false));
    });

    test('on a denser grid a widget takes more cells to keep its size, and fewer again after', () {
      final w = appWidgetItem(_provider(minW: 250, minH: 110), grid: _grid, cell: _cell); // fixed 4 x 2
      const denseCell = Size(61.8, 61.8);
      final dense = HomeWidgetView.fitTo(w, HomeGrid.compact, denseCell);
      final size = HomeWidgetView.sizeOf(HomeGrid.compact, denseCell, dense.cols, dense.rows);
      expect(size.width, greaterThanOrEqualTo(250));
      expect(size.height, greaterThanOrEqualTo(110));
      expect(dense.cols, greaterThan(4));
      expect(HomeWidgetView.fitTo(dense, _grid, _cell), w);
    });

    test('a resizable widget below its new least size grows to it; launcher widgets are left alone', () {
      final w = appWidgetItem(_provider(minW: 110, resizeW: 110, h: true, v: true), grid: _grid, cell: _cell);
      const denseCell = Size(61.8, 61.8);
      final dense = HomeWidgetView.fitTo(w, HomeGrid.compact, denseCell);
      expect(HomeWidgetView.sizeOf(HomeGrid.compact, denseCell, dense.cols, 1).width, greaterThanOrEqualTo(110));
      final clock = launcherWidgetItem(_testKind);
      expect(HomeWidgetView.fitTo(clock, HomeGrid.compact, denseCell), clock);
    });

    test('an app widget\'s dp sizes and settings flag survive a save and load', () {
      final w = appWidgetItem(
        _provider(minW: 250, resizeW: 110, h: true, maxW: 400),
        grid: _grid,
        cell: _cell,
        appWidgetId: 9,
      );
      expect(decodeLayout(encodeLayout([w])), [w]);
      expect((w.minWidthDp, w.maxWidthDp, w.minHeightDp, w.maxHeightDp), (110.0, 400.0, 110.0, 110.0));
    });

    test('launcher widgets carry their limits, which survive a save and load', () {
      final w = launcherWidgetItem(_testKind);
      expect((w.cols, w.rows, w.minCols, w.minRows, w.maxCols, w.maxRows), (4, 2, 2, 1, 6, 3));
      expect(w.launcherKind, 'test');
      expect(decodeLayout(encodeLayout([w])), [w]);
    });
  });

  group('room', () {
    // Page 0: a 4 x 2 block on top, an app at (0, 3). Page 1: one app at (0, 0).
    final items = <HomeItem>[const WidgetItem(id: 'big', cols: 4, rows: 2), const AppItem('a'), const AppItem('b')];
    final arrangement = arrange(
      items,
      {'widget:big': const GridSlot(0, 0, 0), 'app:a': const GridSlot(0, 0, 3), 'app:b': const GridSlot(1, 0, 0)},
      columns: 4,
      rows: 4,
    );

    test('free cells on the page on screen come first', () {
      expect(freeSpot(arrangement, cols: 2, rows: 1, columns: 4, gridRows: 4), const GridSlot(0, 0, 2));
      expect(freeSpot(arrangement, cols: 2, rows: 1, columns: 4, gridRows: 4, page: 1), const GridSlot(1, 1, 0));
    });

    test('otherwise another page with room, otherwise a new page', () {
      expect(freeSpot(arrangement, cols: 4, rows: 3, columns: 4, gridRows: 4), const GridSlot(1, 0, 1));
      expect(freeSpot(arrangement, cols: 4, rows: 4, columns: 4, gridRows: 4), const GridSlot(2, 0, 0));
    });

    test('bigger than a page: no spot at all', () {
      expect(freeSpot(arrangement, cols: 5, rows: 1, columns: 4, gridRows: 4), isNull);
      expect(freeSpot(arrangement, cols: 1, rows: 5, columns: 4, gridRows: 4), isNull);
    });

    test('a change that pushes items onto the next page is caught', () {
      // Growing the widget to the full page leaves 'a' no room on page 0.
      final grown = arrange(
        [const WidgetItem(id: 'big', cols: 4, rows: 4), ...items.skip(1)],
        {...arrangement.slots},
        columns: 4,
        rows: 4,
        priority: 'widget:big',
      );
      expect(spilled(arrangement, grown, moved: 'widget:big'), ['app:a']);
      // Three rows still leave 'a' a spot on page 0.
      final taller = arrange(
        [const WidgetItem(id: 'big', cols: 4, rows: 3), ...items.skip(1)],
        {...arrangement.slots},
        columns: 4,
        rows: 4,
        priority: 'widget:big',
      );
      expect(spilled(arrangement, taller, moved: 'widget:big'), isEmpty);
    });
  });
}
