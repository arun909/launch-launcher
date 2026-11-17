import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minimal_launcher/core/apps/apps_controller.dart';
import 'package:minimal_launcher/core/models/app_info.dart';
import 'package:minimal_launcher/core/models/icon_shape.dart';
import 'package:minimal_launcher/core/theme/home_grid.dart';
import 'package:minimal_launcher/core/widgets/app_icon.dart';
import 'package:minimal_launcher/features/appearance/home_grid_picker.dart';
import 'package:minimal_launcher/features/dock/dock.dart';
import 'package:minimal_launcher/features/dock/dock_controller.dart';
import 'package:minimal_launcher/features/hidden_apps/visible_apps.dart';
import 'package:minimal_launcher/features/standard_home/app_container_tile.dart';
import 'package:minimal_launcher/features/standard_home/container_editor.dart';
import 'package:minimal_launcher/features/standard_home/corner_shapes.dart';
import 'package:minimal_launcher/features/standard_home/frame_handles.dart';
import 'package:minimal_launcher/features/standard_home/home_layout.dart';
import 'package:minimal_launcher/features/standard_home/standard_home.dart';
import 'package:minimal_launcher/features/widgets/home_widget_view.dart';
import 'package:provider/provider.dart';
import 'package:minimal_launcher/features/standard_home/home_layout_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeApps extends ChangeNotifier implements AppsController {
  _FakeApps(List<String> ids) : apps = [for (final id in ids) _app(id)];

  @override
  List<AppInfo> apps;

  @override
  bool get isLoaded => true;

  @override
  IconShape get iconShape => IconShape.system;

  void setInstalled(List<String> ids) {
    apps = [for (final id in ids) _app(id)];
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The test phone's width (1080px at 2.75 dpr).
const _width = 1080 / 2.75;

/// Space from the screen edge to the grid with [grid] on the test phone.
double _side([HomeGrid grid = HomeGrid.large, double width = _width]) => StandardHome.sidePaddingFor(grid, width);

/// The grid starts this far in from StandardHome's top-left.
final _top = Offset(_side(), StandardHome.topPadding);

AppInfo _app(String id) => AppInfo(id: id, label: id, packageName: id, activityName: 'Main', lastUpdateTime: 1);

/// The layout as a compact string: apps by id, containers as `[a,b]`,
/// widgets as `<id>`.
String _shape(List<HomeItem> items) => items
    .map(
      (i) => switch (i) {
        AppItem(:final appId) => appId,
        AppContainer(:final appIds) => '[${appIds.join(',')}]',
        WidgetItem(:final id) => '<$id>',
      },
    )
    .join(' ');

Future<HomeLayoutController> _controller(List<String> installed) async {
  SharedPreferences.setMockInitialValues({});
  return HomeLayoutController(await SharedPreferences.getInstance(), _FakeApps(installed));
}

void main() {
  group('arrange', () {
    Map<String, (int, int, int)> spots(Arrangement a) => {
      for (final page in a.pages)
        for (final p in page) p.item.key: (p.page, p.col, p.row),
    };

    test('new items fill pages in reading order, starting a new page when full', () {
      final items = [for (var i = 0; i < 9; i++) AppItem('$i')];
      final a = arrange(items, const {}, columns: 4, rows: 2);
      expect(a.pages.length, 2);
      expect(
        [for (final p in a.pages[0]) (p.col, p.row)],
        [(0, 0), (1, 0), (2, 0), (3, 0), (0, 1), (1, 1), (2, 1), (3, 1)],
      );
      expect(spots(a)['app:8'], (1, 0, 0));
    });

    test('saved slots are kept exactly, gaps included', () {
      final items = [const AppItem('a'), const AppItem('b')];
      final a = arrange(
        items,
        {'app:a': const GridSlot(0, 3, 2), 'app:b': const GridSlot(0, 1, 0)},
        columns: 4,
        rows: 4,
      );
      expect(spots(a), {'app:a': (0, 3, 2), 'app:b': (0, 1, 0)});
    });

    test('the priority item keeps its slot and what it overlaps moves aside', () {
      final items = <HomeItem>[
        const AppItem('a'),
        const AppContainer(id: 'c', name: '', appIds: ['x'], cols: 2, rows: 2),
      ];
      final a = arrange(
        items,
        {'app:a': const GridSlot(0, 1, 1), 'container:c': const GridSlot(0, 0, 0)},
        columns: 4,
        rows: 4,
        priority: 'container:c',
      );
      expect(spots(a), {'container:c': (0, 0, 0), 'app:a': (0, 2, 0)});
    });

    test('a grown item is pulled back inside the grid', () {
      final items = [
        const AppContainer(id: 'c', name: '', appIds: ['x'], cols: 3, rows: 2),
      ];
      final a = arrange(items, {'container:c': const GridSlot(0, 3, 3)}, columns: 4, rows: 4);
      expect(spots(a), {'container:c': (0, 1, 2)});
    });

    test('spans are clamped to the grid, and empty pages are dropped', () {
      final items = [
        const AppContainer(id: 'c', name: '', appIds: ['x'], cols: 4, rows: 4),
      ];
      final a = arrange(items, {'container:c': const GridSlot(5, 0, 0)}, columns: 4, rows: 3);
      final p = a.pages.single.single;
      expect((p.page, p.cols, p.rows), (0, 4, 3));
    });

    test('new apps go after what is already placed', () {
      final items = [const AppItem('a'), const AppItem('new')];
      final a = arrange(items, {'app:a': const GridSlot(1, 0, 0)}, columns: 2, rows: 1);
      expect(spots(a), {'app:a': (0, 0, 0), 'app:new': (0, 1, 0)});
    });
  });

  test('slots survive a save and load', () {
    final slots = {'app:a': const GridSlot(2, 1, 3)};
    expect(decodeSlots(encodeSlots(slots)), slots);
    expect(decodeSlots('not json'), isEmpty);
  });

  test('sync drops uninstalled apps and appends new ones', () {
    final items = <HomeItem>[
      const AppItem('a'),
      const AppContainer(id: 'c', name: '', appIds: ['gone', 'b']),
      const AppContainer(id: 'empty', name: '', appIds: ['gone2']),
    ];
    final synced = syncWithInstalled(items, ['a', 'b', 'new']);
    expect(_shape(synced), 'a [b] new');
    expect(identical(syncWithInstalled(synced, ['a', 'b', 'new']), synced), isTrue);
  });

  test('layout survives a save and load', () {
    final items = <HomeItem>[
      const AppItem('a'),
      const AppContainer(id: 'c', name: 'Social', appIds: ['b'], cols: 3, rows: 1, cornerRadius: 12),
    ];
    final back = decodeLayout(encodeLayout(items));
    expect(_shape(back), 'a [b]');
    final c = back[1] as AppContainer;
    expect((c.name, c.cols, c.rows, c.cornerRadius), ('Social', 3, 1, 12.0));
    // Layouts saved before folders became "1 × 1 groups" still load as folders.
    final old = decodeLayout('[{"type":"container","id":"f","name":"F","apps":["x"],"folder":true,"cols":3,"rows":2}]');
    expect((old.single as AppContainer).isFolder, isTrue);
  });

  test('a container takes a widget\'s frame and spaces its icons evenly', () {
    const cell = Size(97.7, 90.3); // this phone, 4 x 8
    final grid = HomeGrid.large;
    for (final (cols, rows) in [(4, 1), (3, 2), (4, 2), (2, 3)]) {
      final frame = Size(cols * cell.width, rows * cell.height);
      final panel = AppContainerTile.panelRect(grid, frame, cols.toDouble(), rows.toDouble());
      expect(panel, HomeWidgetView.frameIn(grid, frame, cols.toDouble(), rows.toDouble()));
      final icons = AppContainerTile.iconsIn(grid, panel, 99);
      final first = icons.rectOf(0), last = icons.rectOf(icons.capacity - 1);
      // Across: edge, gaps and edge all equal. Down likewise.
      expect(first.left - panel.left, closeTo(icons.gapX, 0.001));
      expect(panel.right - last.right, closeTo(icons.gapX, 0.001));
      if (icons.perRow > 1) expect(icons.rectOf(1).left - first.right, closeTo(icons.gapX, 0.001));
      expect(first.top - panel.top, closeTo(icons.gapY, 0.001));
      expect(panel.bottom - last.bottom, closeTo(icons.gapY, 0.001));
      expect(math.min(icons.gapX, icons.gapY), greaterThanOrEqualTo(AppContainerTile.minGap(grid) - 0.001));
    }
    // 4 x 1 holds 6 icons, ~9dp apart across and ~11dp down.
    final row = AppContainerTile.iconsIn(
      grid,
      AppContainerTile.panelRect(grid, Size(4 * cell.width, cell.height), 4, 1),
      7,
    );
    expect((row.perRow, row.rows), (6, 1));
    expect((row.gapX - row.gapY).abs(), lessThan(2.5));
  });

  test('a container with fewer apps than spots spreads them over the rows they need', () {
    final panel = AppContainerTile.panelRect(HomeGrid.large, const Size(4 * 97.7, 90.3), 4, 1);
    final three = AppContainerTile.iconsIn(HomeGrid.large, panel, 3);
    expect((three.perRow, three.rows), (3, 1));
    expect(panel.right - three.rectOf(2).right, closeTo(three.gapX, 0.001));
  });

  group('corner radius limit', () {
    const shapes = [IconShape.system, IconShape.rounded(0), IconShape.rounded(25), IconShape.circle];

    /// Every point on the outline of an icon [inset] in from the panel's
    /// top-left corner, with corners of [iconRadius], is inside the panel.
    void expectCornerIconInside(Size panel, double radius, double inset, double size, double iconRadius) {
      final path = CornerShapes.shape(radius).getOuterPath(Offset.zero & panel);
      final icon = RRect.fromRectAndRadius(Rect.fromLTWH(inset, inset, size, size), Radius.circular(iconRadius));
      // The icon's top-left corner arc, the part nearest the panel's corner.
      final c = Offset(icon.left + iconRadius, icon.top + iconRadius);
      for (var a = 180.0; a <= 270; a += 2) {
        final t = a * math.pi / 180;
        final p = c + Offset(math.cos(t), math.sin(t)) * iconRadius;
        // A hair inside, so a point exactly on the outline counts as in.
        expect(path.contains(p + const Offset(0.01, 0.01)), isTrue, reason: 'r=$radius, point $p');
      }
    }

    test('at its roundest, a folder still fits its mini icons', () {
      for (final grid in HomeGrid.values) {
        for (final shape in shapes) {
          final size = grid.iconSize;
          final r = AppContainerTile.folderMaxRadius(grid, shape);
          final tiny = FolderTile.tinySize(size);
          expectCornerIconInside(
            Size(size, size),
            r,
            FolderTile.inset,
            tiny,
            tiny * AppContainerTile.iconRoundness(shape),
          );
        }
      }
    });

    test('at its roundest, a container still fits its icons, even one row high', () {
      for (final grid in HomeGrid.values) {
        for (final shape in shapes) {
          final pad = AppContainerTile.pad(grid);
          final size = Size(grid.iconSize + pad * 2, grid.iconSize + pad * 2); // a 1 x 1 panel's worth
          final r = AppContainerTile.containerMaxRadius(grid, shape);
          expectCornerIconInside(size, r, pad, grid.iconSize, grid.iconSize * AppContainerTile.iconRoundness(shape));
        }
      }
    });

    test('the limit follows the icons: rounder icons allow rounder folders', () {
      final square = AppContainerTile.folderMaxRadius(HomeGrid.large, const IconShape.rounded(0));
      final round = AppContainerTile.folderMaxRadius(HomeGrid.large, IconShape.circle);
      expect(square, closeTo(17.1, 0.1)); // (2 + √2) x the 5dp inset
      expect(round, greaterThan(square));
      expect(round, lessThan(HomeGrid.large.iconSize / 2)); // never a full circle
    });

    test('containers round to 28dp at most, never into a pill', () {
      for (final grid in HomeGrid.values) {
        for (final shape in shapes) {
          expect(AppContainerTile.containerMaxRadius(grid, shape), 28);
        }
      }
      const round = AppContainer(id: 'c', name: '', appIds: ['a', 'b'], cols: 2, rows: 1, cornerRadius: 64);
      expect(AppContainerTile.radiusOf(round, HomeGrid.large, IconShape.circle), 28); // saved rounder: drawn at 28
      const soft = AppContainer(id: 'c', name: '', appIds: ['a', 'b'], cols: 2, rows: 1, cornerRadius: 12);
      expect(AppContainerTile.radiusOf(soft, HomeGrid.large, IconShape.circle), 14); // nearest step: Soft
    });

    test('a folder saved fully round is drawn at the limit', () {
      const folder = AppContainer(id: 'f', name: '', appIds: ['a'], cols: 1, rows: 1, cornerRadius: 64);
      for (final grid in HomeGrid.values) {
        expect(
          AppContainerTile.radiusOf(folder, grid, IconShape.system),
          AppContainerTile.folderMaxRadius(grid, IconShape.system),
        );
      }
    });

    test('folders are drawn square, soft or rounded only', () {
      for (final grid in HomeGrid.values) {
        for (final shape in shapes) {
          final [square, soft, rounded] = AppContainerTile.radiiFor(true, grid, shape);
          expect(square, 0);
          expect(rounded, AppContainerTile.folderMaxRadius(grid, shape));
          expect(soft, closeTo(rounded / 2, 0.5));
          // Any saved radius is drawn at the nearest step.
          for (var stored = 0.0; stored <= AppContainer.maxCornerRadius; stored += 4) {
            final folder = AppContainer(id: 'f', name: '', appIds: const ['a'], cols: 1, rows: 1, cornerRadius: stored);
            expect([square, soft, rounded], contains(AppContainerTile.radiusOf(folder, grid, shape)));
          }
        }
      }
    });
  });

  group('controller', () {
    test('starts with every installed app', () async {
      final layout = await _controller(['a', 'b', 'c']);
      expect(_shape(layout.items), 'a b c');
    });

    test('a new container replaces the app in its place', () async {
      final layout = await _controller(['a', 'b', 'c']);
      final id = layout.createContainer('b');
      layout.addToContainer(id, 'c');
      expect(_shape(layout.items), 'a [b,c]');
    });

    test('moving an app between containers keeps each app once', () async {
      final layout = await _controller(['a', 'b', 'c']);
      final first = layout.createContainer('a');
      final second = layout.createContainer('b');
      layout.addToContainer(first, 'c');
      layout.addToContainer(second, 'c');
      expect(_shape(layout.items), '[a] [b,c]');
      // Emptying a container removes it.
      layout.addToContainer(second, 'a');
      expect(_shape(layout.items), '[b,c,a]');
    });

    test('removing from a container puts the app right after it', () async {
      final layout = await _controller(['a', 'b', 'c', 'd']);
      final id = layout.createContainer('a');
      layout.addToContainer(id, 'b');
      layout.removeFromContainer('a');
      expect(_shape(layout.items), '[b] a c d');
      layout.ungroup(id);
      expect(_shape(layout.items), 'b a c d');
    });

    test('placing an item fixes it there; grouping hands its spot over', () async {
      final layout = await _controller(['a', 'b', 'c']);
      layout.place('app:a', const GridSlot(0, 3, 2));
      expect(layout.slots['app:a'], const GridSlot(0, 3, 2));
      expect(layout.priority, 'app:a');
      final id = layout.createContainer('a');
      expect(layout.slots['container:$id'], const GridSlot(0, 3, 2));
      expect(layout.slots.containsKey('app:a'), isFalse);
      layout.commitSlots({'container:$id': const GridSlot(0, 2, 2)});
      expect(layout.priority, isNull);
      layout.ungroup(id);
      expect(layout.slots['app:a'], const GridSlot(0, 2, 2));
    });

    test('dropping an app onto another makes a folder in its place', () async {
      final layout = await _controller(['a', 'b', 'c', 'd']);
      final id = layout.createFolder('c', 'a')!;
      expect(_shape(layout.items), 'b [c,a] d');
      final folder = layout.container(id)!;
      expect((folder.isFolder, folder.name), (true, 'Folder'));
      // Dropping onto the folder adds to it.
      layout.addToContainer(id, 'd');
      expect(_shape(layout.items), 'b [c,a,d]');
    });

    test('a group is a folder exactly while it is 1 x 1', () async {
      final layout = await _controller(['a', 'b']);
      final id = layout.createContainer('a', folder: true);
      layout.addToContainer(id, 'b');
      expect(layout.container(id)!.isFolder, isTrue);
      layout.reshape(const GridSlot(0, 0, 0), layout.container(id)!.copyWith(cols: 2));
      expect(layout.container(id)!.isFolder, isFalse);
      layout.reshape(const GridSlot(0, 0, 0), layout.container(id)!.copyWith(cols: 1, rows: 1));
      expect(layout.container(id)!.isFolder, isTrue);
    });

    test('widgets are added, resized and removed, and kept through syncs and tidy-up', () async {
      SharedPreferences.setMockInitialValues({});
      final apps = _FakeApps(['a', 'b']);
      final layout = HomeLayoutController(await SharedPreferences.getInstance(), apps);
      layout.currentPage = 1;
      layout.addWidget(const WidgetItem(id: 'w', launcherKind: 'clock', cols: 4, rows: 2));
      layout.addWidget(const WidgetItem(id: 'x', appWidgetId: 7, provider: 'p.kg/.Widget'));
      expect(_shape(layout.items), 'a b <w> <x>');
      // Goes to the first free spot from the page on screen, pushing nothing.
      expect(layout.slots['widget:w'], const GridSlot(1, 0, 0));
      expect(layout.priority, isNull);
      layout.resizeWidget('w', cols: 2, rows: 3);
      expect((layout.findWidget('w')!.cols, layout.findWidget('w')!.rows), (2, 3));
      expect(layout.priority, 'widget:w');
      apps.setInstalled(['a', 'c']);
      expect(_shape(layout.items), 'a <w> <x> c');
      layout.tidyUp();
      expect(_shape(layout.items), '<w> <x> a c');
      layout.removeWidget('w');
      expect(_shape(layout.items), '<x> a c');
      expect(layout.findWidget('x')!.providerPackage, 'p.kg');
    });

    test('tidy-up can be undone, back to the old layout and slots', () async {
      SharedPreferences.setMockInitialValues({});
      final apps = _FakeApps(['a', 'b']);
      final layout = HomeLayoutController(await SharedPreferences.getInstance(), apps);
      layout.addWidget(const WidgetItem(id: 'w', launcherKind: 'clock', cols: 4, rows: 2));
      final shape = _shape(layout.items);
      final slots = layout.slots;
      final before = layout.tidyUp();
      expect(layout.slots, isEmpty);
      layout.restore(before);
      expect(_shape(layout.items), shape);
      expect(layout.slots, slots);
    });

    test('launcher widgets the launcher no longer has leave the home screen on start', () async {
      SharedPreferences.setMockInitialValues({
        'standard_home_layout': encodeLayout([
          const AppItem('a'),
          const WidgetItem(id: 'old', launcherKind: 'clock'),
          const WidgetItem(id: 'app', appWidgetId: 3, provider: 'p.kg/.W'),
        ]),
      });
      final layout = HomeLayoutController(await SharedPreferences.getInstance(), _FakeApps(['a']));
      expect(_shape(layout.items), 'a <app>');
    });

    test('widgets survive a save and load', () {
      const items = [
        WidgetItem(id: 'w', launcherKind: 'analogClock', cols: 2, rows: 2),
        WidgetItem(id: 'x', appWidgetId: 42, provider: 'p.kg/.Widget', cols: 4, rows: 1),
      ];
      expect(decodeLayout(encodeLayout(items)), items);
    });

    test('changing the number of columns re-flows the pages in reading order, with no holes', () async {
      SharedPreferences.setMockInitialValues({});
      final layout = HomeLayoutController(
        await SharedPreferences.getInstance(),
        _FakeApps(['a', 'b', 'c', 'd', 'e', 'f']),
      );
      // On 4 columns: a b c d / e _ _ f (a hole before f).
      for (final (i, id) in ['a', 'b', 'c', 'd'].indexed) {
        layout.place('app:$id', GridSlot(0, i, 0));
      }
      layout.place('app:e', const GridSlot(0, 0, 1));
      layout.place('app:f', const GridSlot(0, 3, 1));
      layout.commitSlots(arrange(layout.items, layout.slots, columns: 4, rows: 8).slots);
      await layout.setGrid(HomeGrid.medium); // 5 columns
      final packed = arrange(layout.items, layout.slots, columns: 5, rows: 8);
      String at(String id) => '${packed.slots['app:$id']!.col},${packed.slots['app:$id']!.row}';
      expect(
        [
          for (final id in ['a', 'b', 'c', 'd', 'e', 'f']) at(id),
        ],
        ['0,0', '1,0', '2,0', '3,0', '4,0', '0,1'],
      );
      // Same columns (another icon size, say): nothing moves.
      final before = layout.slots;
      await layout.setGrid(HomeGrid.medium);
      expect(layout.slots, before);
    });

    test('follows installs and uninstalls', () async {
      SharedPreferences.setMockInitialValues({});
      final apps = _FakeApps(['a', 'b']);
      final layout = HomeLayoutController(await SharedPreferences.getInstance(), apps);
      layout.createContainer('a');
      apps.setInstalled(['a', 'c']);
      expect(_shape(layout.items), '[a] c');
    });

    test('mode and layout are restored from prefs', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final layout = HomeLayoutController(prefs, _FakeApps(['a', 'b']));
      await layout.setMode(HomeMode.standard);
      layout.createContainer('b', name: 'Work');
      await Future<void>.delayed(Duration.zero);

      final again = HomeLayoutController(prefs, _FakeApps(['a', 'b']));
      expect(again.mode, HomeMode.standard);
      expect(_shape(again.items), 'a [b]');
      expect(again.containers.single.name, 'Work');
    });
  });

  testWidgets('pages and containers of every size render without overflow', (tester) async {
    // Phone-sized portrait screen.
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final ids = [for (var i = 0; i < 40; i++) 'app$i'];
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final apps = _FakeApps(ids);
    final layout = HomeLayoutController(prefs, apps);
    for (final (i, (w, h)) in [(1, 1), (2, 1), (1, 2), (4, 2), (4, 4), (2, 2)].indexed) {
      final c = layout.createContainer('app${i * 5}');
      for (var j = 1; j < 5; j++) {
        layout.addToContainer(c, 'app${i * 5 + j}');
      }
      layout.updateContainer(layout.container(c)!.copyWith(cols: w, rows: h, cornerRadius: 64));
    }

    final folder = layout.createFolder('app30', 'app31')!;
    for (var j = 32; j < 40; j++) {
      layout.addToContainer(folder, 'app$j');
    }
    expect(layout.containers.where((c) => c.isFolder), isNotEmpty);

    for (final editing in [false, true]) {
      layout.setEditing(editing);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: layout),
            ChangeNotifierProvider(create: (_) => DockController(prefs)),
            Provider.value(value: VisibleApps(apps.apps, const {})),
          ],
          child: const MaterialApp(home: Scaffold(body: StandardHome())),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('the editor renders for a container and a folder', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final apps = _FakeApps([for (var i = 0; i < 10; i++) 'app$i']);
    final layout = HomeLayoutController(prefs, apps);
    final id = layout.createContainer('app0');
    for (var i = 1; i < 10; i++) {
      layout.addToContainer(id, 'app$i');
    }
    layout.updateContainer(layout.container(id)!.copyWith(cols: 2, rows: 2)); // resized into a container

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: layout),
          Provider.value(value: VisibleApps(apps.apps, const {})),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) =>
                TextButton(onPressed: () => showContainerMenu(context, id), child: const Text('open')),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Container name'), findsOneWidget);
    expect(find.text('10 apps'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Shrunk to 1 x 1 (by its handles), it's a folder.
    layout.updateContainer(layout.container(id)!.copyWith(cols: 1, rows: 1));
    await tester.pumpAndSettle();
    expect(find.text('Folder name'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dragging an app in edit mode fixes it at the cell it is dropped on', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final apps = _FakeApps(['a', 'b', 'c']);
    final layout = HomeLayoutController(prefs, apps)..setEditing(true);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: layout),
          ChangeNotifierProvider(create: (_) => DockController(prefs)),
          Provider.value(value: VisibleApps(apps.apps, const {})),
        ],
        child: const MaterialApp(home: Scaffold(body: StandardHome())),
      ),
    );
    await tester.pumpAndSettle();
    expect(layout.slots['app:a'], const GridSlot(0, 0, 0));

    // Same geometry as StandardHome: 4 columns, cells as tall as wide (or a tile).
    final size = tester.getSize(find.byType(StandardHome));
    final cellW = (size.width - _side(HomeGrid.large, size.width) * 2) / 4;
    final cellH = HomeGrid.large.cellHeightFor(cellW);

    final gesture = await tester.startGesture(Offset(cellW / 2, cellH / 2) + _top);
    await tester.pump(const Duration(milliseconds: 400));
    await gesture.moveTo(Offset(cellW * 2.5, cellH * 3.5) + _top);
    await tester.pump();
    await gesture.moveTo(Offset(cellW * 2.5, cellH * 4.5) + _top);
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(layout.slots['app:a'], const GridSlot(0, 2, 4));
    expect(layout.slots['app:b'], const GridSlot(0, 1, 0)); // others stay put
  });

  testWidgets('hiding app names leaves icons only, in the same spots, and is remembered', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final apps = _FakeApps(['alpha', 'beta']);
    final layout = HomeLayoutController(prefs, apps);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: layout),
          ChangeNotifierProvider(create: (_) => DockController(prefs)),
          Provider.value(value: VisibleApps(apps.apps, const {})),
        ],
        child: const MaterialApp(home: Scaffold(body: StandardHome())),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('alpha'), findsOneWidget);
    final iconAt = tester.getRect(find.byType(AppIcon).first);

    final semantics = tester.ensureSemantics();
    await layout.setShowLabels(false);
    await tester.pumpAndSettle();
    expect(find.text('alpha'), findsNothing);
    expect(find.bySemanticsLabel(RegExp('^alpha')), findsOneWidget); // still named for screen readers
    semantics.dispose();
    expect(tester.getRect(find.byType(AppIcon).first), iconAt);
    expect(HomeLayoutController(prefs, apps).showLabels, isFalse);
  });

  testWidgets('rotating to landscape and back leaves every app where it was', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final apps = _FakeApps([for (var i = 0; i < 30; i++) 'app${i.toString().padLeft(2, '0')}']);
    final layout = HomeLayoutController(prefs, apps);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: layout),
          ChangeNotifierProvider(create: (_) => DockController(prefs)),
          Provider.value(value: VisibleApps(apps.apps, const {})),
        ],
        child: const MaterialApp(home: Scaffold(body: StandardHome())),
      ),
    );
    await tester.pumpAndSettle();
    final portrait = layout.slots;

    // Landscape has far fewer rows, so apps get pushed to later pages...
    tester.view.physicalSize = const Size(2400, 1080);
    await tester.pumpAndSettle();
    expect(layout.slots, portrait);

    // ...but only for show: back in portrait, the layout is as it was.
    tester.view.physicalSize = const Size(1080, 2400);
    await tester.pumpAndSettle();
    expect(layout.slots, portrait);
    expect(decodeSlots(prefs.getString('standard_home_slots')), portrait);
  });

  Future<(HomeLayoutController, Size)> pumpEditingHome(
    WidgetTester tester,
    List<String> ids, {
    bool editing = true,
    bool homeSwipes = false,
  }) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final apps = _FakeApps(ids);
    final layout = HomeLayoutController(prefs, apps)..setEditing(editing);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: layout),
          ChangeNotifierProvider(create: (_) => DockController(prefs)),
          Provider.value(value: VisibleApps(apps.apps, const {})),
        ],
        child: MaterialApp(
          home: Scaffold(
            // Like the home screen's swipe-down / swipe-up gestures.
            body: GestureDetector(onVerticalDragEnd: homeSwipes ? (_) {} : null, child: const StandardHome()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final home = tester.getSize(find.byType(StandardHome));
    final cellW = (home.width - _side(HomeGrid.large, home.width) * 2) / 4;
    final gridH = home.height - StandardHome.dotsHeight - StandardHome.topPadding;
    return (layout, Size(cellW, HomeGrid.large.cellHeightIn(gridH, cellW)));
  }

  group('widget handles', () {
    /// A 2 x 1 clock, selected; returns where its right grip is.
    Future<(HomeLayoutController, Offset, Size)> selectedClock(WidgetTester tester, int apps) async {
      final (layout, cell) = await pumpEditingHome(tester, [for (var i = 0; i < apps; i++) 'app$i']);
      layout.addWidget(
        const WidgetItem(id: 'w', launcherKind: 'clock', cols: 2, rows: 1, minCols: 2, maxCols: 6, maxRows: 3),
        at: const GridSlot(0, 0, 0),
      );
      layout.place('widget:w', const GridSlot(0, 0, 0)); // on the first page, even when it's full
      await tester.pumpAndSettle();
      layout.select('widget:w');
      await tester.pumpAndSettle();
      // Where it went: the first free 2 x 1 from the top.
      final slot = layout.arrangement!.find('widget:w')!.slot;
      final panel = HomeWidgetView.frameIn(
        HomeGrid.large,
        Size(cell.width * 2, cell.height),
        2,
        1,
      ).shift(Offset(slot.col * cell.width, slot.row * cell.height));
      return (layout, _top + Offset(panel.right + 4, panel.center.dy), cell);
    }

    testWidgets('a long press on a widget goes straight to its handles', (tester) async {
      final (layout, _) = await pumpEditingHome(tester, ['a'], editing: false);
      layout.addWidget(
        const WidgetItem(id: 'w', launcherKind: 'date'),
        at: const GridSlot(0, 0, 1),
      );
      await tester.pumpAndSettle();
      await tester.longPress(find.byType(HomeWidgetView));
      await tester.pumpAndSettle();
      expect((layout.editing, layout.selected), (true, 'widget:w'));
      expect(find.byType(WidgetHandles), findsOneWidget);
    });

    testWidgets('growing a widget moves apps aside when the page has room', (tester) async {
      final (layout, grip, cell) = await selectedClock(tester, 3);
      await tester.dragFrom(grip, Offset(cell.width, 0));
      await tester.pumpAndSettle();
      expect(layout.findWidget('w')!.cols, 3);
      expect(layout.arrangement!.pages.length, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('growing a widget is refused when it would push apps onto another page', (tester) async {
      final (layout, grip, cell) = await selectedClock(tester, 60); // page 1 full, more after
      final before = layout.slots;
      final gesture = await tester.startGesture(grip);
      for (var i = 1; i <= 10; i++) {
        await gesture.moveBy(Offset(cell.width / 10, 0));
        await tester.pump();
      }
      expect(find.text('No room on this page'), findsOneWidget);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(layout.findWidget('w')!.cols, 2);
      expect(layout.slots, before);
      expect(find.text('No room on this page'), findsNothing);
    });

    testWidgets('the remove button takes the widget off', (tester) async {
      final (layout, _, _) = await selectedClock(tester, 3);
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();
      expect(layout.widgets, isEmpty);
    });
  });

  testWidgets('an app dragged out of an open folder lands on the home screen', (tester) async {
    final (layout, cell) = await pumpEditingHome(tester, ['a', 'b', 'c', 'd'], editing: false);
    final id = layout.createFolder('a', 'b')!;
    layout.addToContainer(id, 'c');
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FolderTile));
    await tester.pumpAndSettle();

    final inPanel = find.descendant(of: find.byType(GridView), matching: find.text('b'));
    final gesture = await tester.startGesture(tester.getCenter(inPanel));
    await tester.pump(const Duration(milliseconds: 500));
    final target = Offset(cell.width * 0.5, cell.height * 1.5) + _top; // an empty cell, above the panel
    for (var i = 1; i <= 20; i++) {
      await gesture.moveTo(Offset.lerp(tester.getCenter(find.byType(StandardHome)), target, i / 20)!);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pumpAndSettle(); // the panel has closed; still holding
    await gesture.moveBy(const Offset(1, 1));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(layout.container(id)!.appIds, ['a', 'c']);
    expect(layout.slots['app:b'], const GridSlot(0, 0, 1));
    expect(layout.dragging, isFalse);
    expect(find.byType(GridView), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an app dragged inside an open folder stays in it until it leaves the panel', (tester) async {
    final (layout, _) = await pumpEditingHome(tester, ['a', 'b', 'c', 'd'], editing: false);
    final id = layout.createFolder('a', 'b')!;
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FolderTile));
    await tester.pumpAndSettle();

    final gesture = await tester.startGesture(
      tester.getCenter(find.descendant(of: find.byType(GridView), matching: find.text('b'))),
    );
    await tester.pump(const Duration(milliseconds: 500));
    await gesture.moveBy(const Offset(30, 0)); // still over the panel
    await tester.pumpAndSettle();
    expect(find.byType(GridView), findsOneWidget);
    expect(layout.dragging, isFalse);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(layout.container(id)!.appIds, ['a', 'b']);
    expect(find.byType(GridView), findsOneWidget); // still open
  });

  testWidgets('apps reorder by dragging them around inside an open folder', (tester) async {
    final (layout, _) = await pumpEditingHome(tester, ['a', 'b', 'c', 'd'], editing: false);
    final id = layout.createFolder('a', 'b')!;
    layout.addToContainer(id, 'c');
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FolderTile));
    await tester.pumpAndSettle();

    Offset at(String app) => tester.getCenter(find.descendant(of: find.byType(GridView), matching: find.text(app)));
    final gesture = await tester.startGesture(at('a'));
    await tester.pump(const Duration(milliseconds: 500));
    final to = at('c') + const Offset(10, 0);
    for (var i = 1; i <= 10; i++) {
      await gesture.moveTo(Offset.lerp(at('a'), to, i / 10)!);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();

    expect(layout.container(id)!.appIds, ['b', 'c', 'a']);
    expect(find.byType(GridView), findsOneWidget); // still open
    expect(layout.dragging, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('hiding app names hides folder and container names too, opened or not', (tester) async {
    final (layout, _) = await pumpEditingHome(tester, ['a', 'b', 'c', 'd', 'e'], editing: false);
    final folder = layout.createFolder('a', 'b')!;
    layout.updateContainer(layout.container(folder)!.copyWith(name: 'Games'));
    final group = layout.createFolder('c', 'd')!;
    layout.addToContainer(group, 'e');
    // Two rows up: a container shows its name (inside its panel's top).
    layout.updateContainer(layout.container(group)!.copyWith(name: 'Work', cols: 2, rows: 2));
    await tester.pumpAndSettle();
    expect(find.text('Games'), findsOneWidget);
    expect(find.text('Work'), findsOneWidget);
    final before = tester.getRect(find.byType(FolderTile));

    await layout.setShowLabels(false);
    await tester.pumpAndSettle();
    expect(find.text('Games'), findsNothing);
    expect(find.text('Work'), findsNothing);
    // The icon doesn't move: same middle, same height (the line stays, empty).
    final after = tester.getRect(find.byType(FolderTile));
    expect((after.center, after.height), (before.center, before.height));

    // Opened: no title, no app names.
    await tester.tap(find.byType(FolderTile));
    await tester.pumpAndSettle();
    expect(find.byType(GridView), findsOneWidget);
    expect(find.text('Games'), findsNothing);
    expect(find.descendant(of: find.byType(GridView), matching: find.text('a')), findsNothing);
    await tester.tapAt(const Offset(5, 5)); // close
    await tester.pumpAndSettle();

    await layout.setShowLabels(true);
    await tester.pumpAndSettle();
    expect(find.text('Games'), findsOneWidget);
  });

  testWidgets('dropping an app from an open folder on another app makes a new folder', (tester) async {
    final (layout, cell) = await pumpEditingHome(tester, ['a', 'b', 'c', 'd'], editing: false);
    final id = layout.createFolder('a', 'b')!;
    layout.addToContainer(id, 'c');
    await tester.pumpAndSettle();
    final d = tester.getCenter(find.text('d'));
    await tester.tap(find.byType(FolderTile));
    await tester.pumpAndSettle();

    final gesture = await tester.startGesture(
      tester.getCenter(find.descendant(of: find.byType(GridView), matching: find.text('c'))),
    );
    await tester.pump(const Duration(milliseconds: 500));
    await gesture.moveBy(const Offset(0, 20));
    await tester.pumpAndSettle();
    await gesture.moveTo(d - Offset(0, cell.height * 0.15)); // the middle of d's icon
    await tester.pump();
    await gesture.moveBy(const Offset(1, 0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(layout.container(id)!.appIds, ['a', 'b']);
    expect(layout.containerOf('d')!.appIds, ['d', 'c']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping empty space finishes editing, even with a container selected', (tester) async {
    final (layout, cell) = await pumpEditingHome(tester, ['a', 'b', 'c']);
    final id = layout.createFolder('a', 'b')!;
    layout.select('container:$id');
    await tester.pumpAndSettle();
    await tester.tapAt(Offset(cell.width * 2.5, cell.height * 3.5) + _top);
    await tester.pumpAndSettle();
    expect(layout.editing, isFalse);
    expect(layout.selected, isNull);
  });

  testWidgets('a group selected for resizing shows only its handles\' outline, at true size', (tester) async {
    final (layout, _) = await pumpEditingHome(tester, ['a', 'b', 'c']);
    final id = layout.createFolder('a', 'b')!;
    layout.select('container:$id');
    await tester.pumpAndSettle();

    final scale = tester.widget<AnimatedScale>(
      find.ancestor(of: find.byType(FolderTile), matching: find.byType(AnimatedScale)).first,
    );
    expect(scale.scale, 1);
    // Its drop ring (shown only when an app is dropped on it) stays hidden.
    final ring = tester.widgetList<AnimatedOpacity>(
      find.descendant(
        of: find.ancestor(of: find.byType(FolderTile), matching: find.byType(AnimatedScale)).first,
        matching: find.byWidgetPredicate((w) => w is AnimatedOpacity && w.child is DecoratedBox),
      ),
    );
    expect(ring.single.opacity, 0);
    // Other items still shrink a little in edit mode.
    final app = tester.widget<AnimatedScale>(
      find.ancestor(of: find.text('c'), matching: find.byType(AnimatedScale)).first,
    );
    expect(app.scale, 0.94);
  });

  testWidgets('the corner knob rides the outline: grab it without a jump, drag in to round, out to square', (
    tester,
  ) async {
    final (layout, _) = await pumpEditingHome(tester, ['a', 'b', 'c', 'd']);
    final id = layout.createFolder('a', 'b')!;
    layout
      ..addToContainer(id, 'c')
      ..updateContainer(layout.container(id)!.copyWith(cols: 2, rows: 1, cornerRadius: 16));
    layout.select('container:$id');
    await tester.pumpAndSettle();
    double radius() => layout.container(id)!.cornerRadius;

    final knob = find.byWidgetPredicate(
      (w) =>
          w is AnimatedContainer &&
          w.decoration is BoxDecoration &&
          (w.decoration! as BoxDecoration).shape == BoxShape.circle &&
          (w.decoration! as BoxDecoration).color == Colors.white,
    );
    expect(knob, findsOneWidget);
    final gesture = await tester.startGesture(tester.getCenter(knob));
    await gesture.moveBy(const Offset(1, 1));
    await tester.pump();
    await gesture.moveBy(const Offset(-1, -1));
    await tester.pump();
    expect(radius(), 16); // no jump on grabbing it

    await gesture.moveBy(const Offset(4, 4)); // further in along the diagonal
    await tester.pump();
    expect(radius(), greaterThan(16));
    await gesture.moveBy(const Offset(-40, -40)); // out past the corner
    await tester.pump();
    expect(radius(), 0);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('the outline\'s grips still resize: right edge, bottom edge, corner', (tester) async {
    final (layout, cell) = await pumpEditingHome(tester, [for (var i = 0; i < 9; i++) 'app$i']);
    final id = layout.createFolder('app0', 'app1')!;
    for (var i = 2; i < 9; i++) {
      layout.addToContainer(id, 'app$i');
    }
    layout.updateContainer(layout.container(id)!.copyWith(cols: 1, rows: 1));
    layout.place('container:$id', const GridSlot(0, 0, 0));
    layout.select('container:$id');
    await tester.pumpAndSettle();
    (int, int) size() => (layout.container(id)!.cols, layout.container(id)!.rows);

    Future<void> drag(Offset from, Offset by) async {
      final g = await tester.startGesture(from);
      for (var i = 0; i < 20; i++) {
        await g.moveBy(by / 20);
        await tester.pump();
      }
      await g.up();
      await tester.pumpAndSettle();
    }

    // The folder's icon, and its outline 4dp outside it.
    final icon = AppContainerTile.iconRect(HomeGrid.large, cell, 0, 0).shift(_top).inflate(4);
    await drag(Offset(icon.right, icon.center.dy), Offset(cell.width, 0));
    expect(size(), (2, 1));
    final panel = AppContainerTile.panelRect(
      HomeGrid.large,
      Size(cell.width * 2, cell.height),
      2,
      1,
    ).shift(_top).inflate(4);
    await drag(Offset(panel.center.dx, panel.bottom), Offset(0, cell.height));
    expect(size(), (2, 2));
    final big = AppContainerTile.panelRect(
      HomeGrid.large,
      Size(cell.width * 2, cell.height * 2),
      2,
      2,
    ).shift(_top).inflate(4);
    await drag(big.bottomRight, Offset(cell.width, 0));
    expect(size(), (3, 2));
  });

  testWidgets('while dragging, the landing ghost is the app icon\'s own shape, where its icon will sit', (
    tester,
  ) async {
    final (layout, cell) = await pumpEditingHome(tester, ['a', 'b', 'c']);
    final gesture = await tester.startGesture(tester.getCenter(find.text('a')));
    await tester.pump(const Duration(milliseconds: 400));
    final to = Offset(cell.width * 2.5, cell.height * 2.5) + _top; // the middle of empty cell (2, 2)
    for (var i = 1; i <= 10; i++) {
      await gesture.moveTo(Offset.lerp(tester.getCenter(find.text('a')), to, i / 10)!);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pumpAndSettle();

    final ghost = find.byWidgetPredicate(
      (w) =>
          w is DecoratedBox &&
          w.decoration is ShapeDecoration &&
          (w.decoration as ShapeDecoration).color != null &&
          (w.decoration as ShapeDecoration).color!.a > 0.05 &&
          (w.decoration as ShapeDecoration).color!.a < 0.12,
    );
    expect(ghost, findsOneWidget);
    final expected = AppContainerTile.iconRect(HomeGrid.large, cell, 2, 2).shift(_top);
    final actual = tester.getRect(ghost);
    expect(actual.center.dx, closeTo(expected.center.dx, 0.5));
    expect(actual.center.dy, closeTo(expected.center.dy, 0.5));
    // Icon-sized, not the whole cell.
    expect(actual.width, closeTo(expected.width, 0.01));
    expect(actual.height, closeTo(expected.height, 0.01));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(layout.slots['app:a'], const GridSlot(0, 2, 2));
  });

  testWidgets('a long press on an app without dragging opens its menu', (tester) async {
    final (layout, _) = await pumpEditingHome(tester, ['a', 'b'], editing: false);
    await layout.setMode(HomeMode.standard);
    await tester.pumpAndSettle();
    final gesture = await tester.startGesture(tester.getCenter(find.text('a')));
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(layout.editing, isFalse);
    expect(find.byType(BottomSheet), findsOneWidget);
  });

  testWidgets('a long press on a folder goes straight to its resize handles', (tester) async {
    final (layout, _) = await pumpEditingHome(tester, ['a', 'b', 'c'], editing: false);
    final id = layout.createFolder('a', 'b')!;
    await tester.pumpAndSettle();
    final gesture = await tester.startGesture(tester.getCenter(find.byType(FolderTile)));
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.up();
    await tester.pumpAndSettle();
    expect((layout.editing, layout.selected), (true, 'container:$id'));
    expect(find.byType(FrameHandles), findsOneWidget);
    expect(find.text('Folder name'), findsNothing); // no settings card
  });

  testWidgets('a group saved wider than the grid is outlined where it is drawn', (tester) async {
    final ids = [for (var i = 0; i < 6; i++) 'app$i'];
    final (layout, _) = await pumpEditingHome(tester, ids);
    final id = layout.createFolder('app0', 'app1')!;
    for (final app in ids.skip(2)) {
      layout.addToContainer(id, app);
    }
    // Six columns, as on the 6-column grid; the 4-column grid fits four.
    layout.reshape(const GridSlot(0, 0, 0), layout.container(id)!.copyWith(cols: 6, rows: 1));
    layout.select('container:$id');
    await tester.pumpAndSettle();
    final handles = tester.getRect(find.byType(FrameHandles));
    final panel = tester.getRect(find.byType(AppContainerTile));
    final outline = tester.getRect(
      find.descendant(of: find.byType(FrameHandles), matching: find.byType(CustomPaint)).first,
    );
    expect(panel.right, lessThanOrEqualTo(handles.right));
    expect(outline.left, closeTo(panel.left + HomeWidgetView.inset(HomeGrid.large) - 4, 0.5));
    expect(outline.right, closeTo(panel.right - HomeWidgetView.inset(HomeGrid.large) + 4, 0.5));
  });

  for (final names in [true, false]) {
    testWidgets('an opened folder is spaced evenly all round (names ${names ? 'shown' : 'hidden'})', (tester) async {
      final ids = [for (var i = 0; i < 8; i++) 'app$i'];
      final (layout, _) = await pumpEditingHome(tester, ids, editing: false);
      await layout.setShowLabels(names);
      final id = layout.createFolder('app0', 'app1')!;
      for (final app in ['app2', 'app3', 'app4', 'app5']) {
        layout.addToContainer(id, app); // six apps: a full row of four, then two
      }
      layout.updateContainer(layout.container(id)!.copyWith(name: ''));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(FolderTile));
      await tester.pumpAndSettle();

      final panel = tester.getRect(find.ancestor(of: find.byType(GridView), matching: find.byType(Container)).first);
      Rect icon(int i) => tester.getRect(
        find.descendant(
          of: find.byType(GridView),
          matching: find.byWidgetPredicate((w) => w is AppIcon && w.app.id == 'app$i'),
        ),
      );
      Rect bottomOf(int i) => names
          ? tester
                .getRect(find.descendant(of: find.byType(GridView), matching: find.text('app$i')))
                .let((label) => Rect.fromLTRB(icon(i).left, icon(i).top, icon(i).right, label.bottom))
          : icon(i);
      final gap = icon(1).left - icon(0).right;
      expect(gap, greaterThan(16));
      expect(icon(0).left - panel.left, closeTo(gap, 0.01)); // left edge
      expect(panel.right - icon(3).right, closeTo(gap, 0.01)); // right edge
      expect(icon(0).top - panel.top, closeTo(gap, 0.01)); // top edge
      expect(icon(4).top - bottomOf(0).bottom, closeTo(gap, 0.01)); // between rows
      expect(panel.bottom - bottomOf(4).bottom, closeTo(gap, 0.01)); // bottom edge
    });
  }

  testWidgets('an opened folder shows only its name and apps', (tester) async {
    final (layout, _) = await pumpEditingHome(tester, ['a', 'b', 'c'], editing: false);
    final id = layout.createFolder('a', 'b')!;
    layout.updateContainer(layout.container(id)!.copyWith(name: 'Games'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FolderTile));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.tune), findsNothing);
    expect(find.text('Games'), findsNWidgets(2)); // under the folder, and the open panel's title
  });

  testWidgets('dropping an item on one that fits its old spot swaps the two', (tester) async {
    final (layout, cell) = await pumpEditingHome(tester, ['a', 'b', 'c']);
    // Drop a near b's edge (not its middle, which would make a folder).
    final gesture = await tester.startGesture(Offset(cell.width / 2, cell.height / 2) + _top);
    await tester.pump(const Duration(milliseconds: 400));
    await gesture.moveTo(Offset(cell.width * 1.2, cell.height * 0.9) + _top);
    await tester.pump();
    await gesture.moveTo(Offset(cell.width * 1.15, cell.height * 0.88) + _top);
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(layout.slots['app:a'], const GridSlot(0, 1, 0));
    expect(layout.slots['app:b'], const GridSlot(0, 0, 0));
    expect(layout.containers, isEmpty);
  });

  testWidgets('dragging a selected container\'s edge resizes it, live', (tester) async {
    final (layout, cell) = await pumpEditingHome(tester, ['a', 'b', 'c', 'd', 'e']);
    final id = layout.createContainer('a');
    layout.addToContainer(id, 'e'); // two apps: room for two cells
    layout.updateContainer(layout.container(id)!.copyWith(cols: 1, rows: 1));
    layout.select('container:$id');
    await tester.pumpAndSettle();

    // Right-edge grip: middle of the panel's right side.
    // 1 x 1: a folder, whose panel is its icon.
    final panel = AppContainerTile.iconRect(HomeGrid.large, cell, 0, 0);
    final gesture = await tester.startGesture(Offset(panel.right + 4, panel.center.dy) + _top);
    await gesture.moveBy(Offset(cell.width * 0.6, 0));
    await tester.pump();
    await gesture.moveBy(Offset(cell.width * 0.5, 0));
    await tester.pump();
    expect(layout.container(id)!.cols, 2);
    expect(layout.interacting, isTrue);
    await gesture.up();
    await tester.pumpAndSettle();

    expect(layout.interacting, isFalse);
    expect(layout.container(id)!.cols, 2);
    expect(layout.slots['container:$id'], const GridSlot(0, 0, 0));
    // What it now covers moved aside.
    expect(layout.slots['app:b'], isNot(const GridSlot(0, 1, 0)));
  });

  testWidgets('holding a dragged app at the right edge flips to the next page, and it drops there', (tester) async {
    // Two pages (8 rows x 4 columns each here), the second with free cells.
    final (layout, cell) = await pumpEditingHome(tester, [
      for (var i = 0; i < 40; i++) 'app${i.toString().padLeft(2, '0')}',
    ]);
    expect(layout.slots['app:app39']?.page, 1);
    final width = tester.getSize(find.byType(StandardHome)).width;

    final gesture = await tester.startGesture(Offset(cell.width / 2, cell.height / 2) + _top);
    await tester.pump(const Duration(milliseconds: 400));
    await gesture.moveTo(Offset(width / 2, cell.height * 2) + _top);
    await tester.pump();
    // Hold at the right edge until the page flips.
    await gesture.moveTo(Offset(width - 6, cell.height * 3 + StandardHome.topPadding));
    await tester.pump();
    await gesture.moveTo(Offset(width - 5, cell.height * 3 + StandardHome.topPadding));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();
    // Drop on a cell of page 2.
    await gesture.moveTo(Offset(cell.width * 2.5, cell.height * 3.5) + _top);
    await tester.pump();
    await gesture.moveTo(Offset(cell.width * 2.5, cell.height * 3.6) + _top);
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(layout.slots['app:app00'], const GridSlot(1, 2, 3));
  });

  testWidgets('from the normal home screen, long-press and drag moves an app to another page', (tester) async {
    final (layout, cell) = await pumpEditingHome(tester, [
      for (var i = 0; i < 40; i++) 'app${i.toString().padLeft(2, '0')}',
    ], editing: false);
    expect(layout.editing, isFalse);
    final width = tester.getSize(find.byType(StandardHome)).width;

    // A normal long press, then drag without letting go.
    final gesture = await tester.startGesture(Offset(cell.width / 2, cell.height / 2) + _top);
    await tester.pump(const Duration(milliseconds: 600));
    expect(layout.editing, isTrue);
    expect(layout.dragging, isTrue);
    await gesture.moveTo(Offset(width / 2, cell.height * 2) + _top);
    await tester.pump();
    // To the right screen edge, and hold there.
    await gesture.moveTo(Offset(width - 4, cell.height * 3 + StandardHome.topPadding));
    await tester.pump();
    await gesture.moveTo(Offset(width - 3, cell.height * 3 + StandardHome.topPadding));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();
    // Grabbed at its middle; drop it with its middle over cell (1, 3).
    await gesture.moveTo(Offset(cell.width * 1.5, cell.height * 3.5) + _top);
    await tester.pump();
    await gesture.moveTo(Offset(cell.width * 1.5, cell.height * 3.55) + _top);
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(layout.slots['app:app00'], const GridSlot(1, 1, 3));
    expect(layout.dragging, isFalse);
    expect(layout.editing, isFalse); // nothing left to confirm
  });

  testWidgets('a long press without dragging leaves the layout and edit mode alone', (tester) async {
    final (layout, cell) = await pumpEditingHome(tester, ['a', 'b'], editing: false);
    final before = layout.slots;
    final gesture = await tester.startGesture(Offset(cell.width * 1.5, cell.height / 2) + _top);
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.moveBy(const Offset(3, 2));
    await tester.pump();
    await gesture.up();
    // The app menu would open here; this test has no providers for it.
    await tester.pump();
    tester.takeException();
    expect(layout.editing, isFalse);
    expect(layout.slots, before);
  });

  testWidgets('a folder\'s bottom grip makes it taller, even under a vertical-swipe listener', (tester) async {
    final (layout, cell) = await pumpEditingHome(tester, ['a', 'b', 'c', 'd', 'e', 'f'], homeSwipes: true);
    final id = layout.createFolder('a', 'b')!;
    layout
      ..addToContainer(id, 'e')
      ..addToContainer(id, 'f'); // four apps: up to four rows in one column
    layout.select('container:$id');
    await tester.pumpAndSettle();

    final panel = AppContainerTile.iconRect(HomeGrid.large, cell, 0, 0);
    final gesture = await tester.startGesture(Offset(panel.center.dx, panel.bottom + 4) + _top);
    // Small steps, like a real finger: a vertical-swipe listener would claim
    // the drag after a few of them unless the grip already has it.
    Future<void> drag(double dy) async {
      for (var moved = 0.0; moved < dy; moved += 4) {
        await gesture.moveBy(const Offset(0, 4));
        await tester.pump();
      }
    }

    await drag(cell.height * 0.8);
    expect(layout.container(id)!.rows, 2);
    await drag(cell.height);
    expect(layout.container(id)!.rows, 3);
    await gesture.up();
    await tester.pumpAndSettle();
    expect((layout.container(id)!.cols, layout.container(id)!.rows), (1, 3));
    expect(tester.takeException(), isNull);
  });

  testWidgets('five apps in 2 x 2 grow to 2 x 3, but not to 2 x 4 or 3 x 3', (tester) async {
    final (layout, cell) = await pumpEditingHome(tester, ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h']);
    final id = layout.createFolder('a', 'b')!;
    for (final app in ['c', 'd', 'e']) {
      layout.addToContainer(id, app);
    }
    layout.updateContainer(layout.container(id)!.copyWith(cols: 2, rows: 2));
    layout.select('container:$id');
    await tester.pumpAndSettle();
    final slot = layout.slots['container:$id']!;
    final origin = Offset(slot.col * cell.width, slot.row * cell.height) + _top;

    Future<void> drag(Offset grip, Offset step, int steps) async {
      final gesture = await tester.startGesture(grip);
      for (var i = 0; i < steps; i++) {
        await gesture.moveBy(step);
        await tester.pump();
      }
      await gesture.up();
      await tester.pumpAndSettle();
    }

    Rect panel() {
      final c = layout.container(id)!;
      return AppContainerTile.panelRect(
        HomeGrid.large,
        Size(c.cols * cell.width, c.rows * cell.height),
        c.cols.toDouble(),
        c.rows.toDouble(),
      ).shift(origin);
    }

    // Down two cells' worth: the third row gets one app, a fourth none.
    await drag(Offset(panel().center.dx, panel().bottom + 4), const Offset(0, 4), (cell.height * 2 / 4).ceil());
    expect((layout.container(id)!.cols, layout.container(id)!.rows), (2, 3));
    // Wider at three rows would leave the last row empty.
    await drag(Offset(panel().right + 4, panel().center.dy), const Offset(4, 0), (cell.width / 4).ceil());
    expect((layout.container(id)!.cols, layout.container(id)!.rows), (2, 3));
    expect(tester.takeException(), isNull);
  });

  testWidgets('container icons are home-sized and its panel sits evenly in its row', (tester) async {
    final (layout, cell) = await pumpEditingHome(tester, ['a', 'b', 'c', 'z'], editing: false);
    final id = layout.createContainer('a');
    layout.addToContainer(id, 'b');
    layout.updateContainer(layout.container(id)!.copyWith(cols: 2, rows: 1)); // 2 x 1 at (0, 0)
    layout.place('app:z', const GridSlot(0, 2, 0));
    await tester.pumpAndSettle();

    Finder icon(String id) => find.byWidgetPredicate((w) => w is AppIcon && w.app.id == id);
    final inContainer = tester.getRect(icon('a'));
    final alone = tester.getRect(icon('z'));
    expect(inContainer.width, closeTo(alone.width, 0.01)); // same, full-size icons
    final panel = tester.getRect(
      find.descendant(of: find.byType(AppContainerTile), matching: find.byType(DecoratedBox)).first,
    );
    // The cells less the widget inset, so as far from the row above as below.
    final cells = Rect.fromLTWH(_top.dx, _top.dy, cell.width * 2, cell.height);
    expect(panel.left - cells.left, closeTo(HomeWidgetView.inset(HomeGrid.large), 0.5));
    expect(panel.top - cells.top, closeTo(cells.bottom - panel.bottom, 0.5));
  });

  test('grid presets: equal spacing, and as many rows as the height holds', () {
    // This phone's home grid area: about 371 x 722dp.
    expect([for (final g in HomeGrid.values) g.sizeIn(371, 722)], ['4 × 8', '5 × 8', '6 × 8']);
    expect([for (final g in HomeGrid.values) g.iconSize], [52, 52, 44]);
    // The 4-column grid's 8 rows share the whole height: nothing left over.
    expect(HomeGrid.large.cellHeightIn(722, 371 / 4), 722 / 8);
    // Too short for 8 tiles: as many square rows as fit.
    expect(HomeGrid.large.rowsFor(500, 92), 5);
    expect(HomeGrid.large.cellHeightIn(500, 92), HomeGrid.large.cellHeightFor(92));
    // Square cells (equal spacing down and across) when a tile fits...
    expect(HomeGrid.large.cellHeightFor(99), 99);
    // ...otherwise just tall enough for the tile.
    expect(HomeGrid.compact.cellHeightFor(66), HomeGrid.compact.tileHeight + HomeGrid.minRowGap);
    expect(HomeGrid.large.rowsFor(50, 99), 1);
  });

  for (final preset in HomeGrid.values) {
    testWidgets('${preset.label} grid: icons are evenly spaced across, edges included', (tester) async {
      final ids = [for (var i = 0; i < 30; i++) 'app${i.toString().padLeft(2, '0')}'];
      await pumpEditingHome(tester, ids, editing: false);
      final layout = tester.element(find.byType(StandardHome)).read<HomeLayoutController>();
      await layout.setGrid(preset);
      layout.tidyUp(); // packed afresh, rows as wide as this grid
      await tester.pumpAndSettle();
      Rect icon(int i) => tester.getRect(
        find.byWidgetPredicate((w) => w is AppIcon && w.app.id == 'app${i.toString().padLeft(2, '0')}'),
      );
      final row = [for (var i = 0; i < preset.columns; i++) icon(i)];
      final home = tester.getRect(find.byType(StandardHome));
      final gaps = [
        row.first.left - home.left,
        for (var i = 1; i < row.length; i++) row[i].left - row[i - 1].right,
        home.right - row.last.right,
      ];
      for (final g in gaps) {
        expect(g, closeTo(gaps.first, 0.5));
      }
      expect(row.first.width, closeTo(preset.iconSize, 0.01));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('the app grid picker fits a phone and switches the grid', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final layout = await _controller(['a']);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: layout,
        child: const MaterialApp(
          home: Scaffold(body: SingleChildScrollView(child: HomeGridPicker())),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Compact'));
    await tester.pumpAndSettle();
    expect(layout.grid, HomeGrid.compact);
    expect(find.textContaining('6 × 8'), findsWidgets); // rows from this phone's grid area
  });

  test('a container keeps at least one app in every row and column', () {
    AppContainer group(int apps, int cols, int rows) =>
        AppContainer(id: 'c', name: '', appIds: [for (var i = 0; i < apps; i++) '$i'], cols: cols, rows: rows).fitted();
    (int, int) size(AppContainer c) => (c.cols, c.rows);
    expect(size(group(2, 4, 1)), (2, 1)); // two apps: not four cells wide
    expect(size(group(2, 2, 2)), (2, 1)); // a second row would be empty
    expect(size(group(3, 2, 2)), (2, 2)); // the last row partly filled is fine
    expect(size(group(5, 2, 3)), (2, 3));
    expect(size(group(5, 3, 2)), (3, 2));
    expect(size(group(5, 3, 3)), (3, 2)); // a third row would be empty
    expect(size(group(5, 2, 4)), (2, 3));
    expect(size(group(6, 3, 3)), (3, 2));
    expect(size(group(9, 3, 3)), (3, 3));
    expect(size(group(20, 2, 2)), (2, 2)); // more apps than cells is fine
    expect(size(group(1, 4, 4)), (1, 1)); // one app: a folder
  });

  test('a container that loses apps shrinks to fit', () async {
    final layout = await _controller(['a', 'b', 'c', 'd']);
    final id = layout.createContainer('a');
    for (final app in ['b', 'c', 'd']) {
      layout.addToContainer(id, app);
    }
    layout.updateContainer(layout.container(id)!.copyWith(cols: 4, rows: 1));
    expect(layout.container(id)!.cols, 4);
    layout.removeFromContainer('d');
    expect((layout.container(id)!.cols, layout.container(id)!.rows), (3, 1));
  });

  testWidgets('a container\'s grip stops where its apps run out', (tester) async {
    final (layout, cell) = await pumpEditingHome(tester, ['a', 'b', 'c', 'd', 'e', 'f']);
    final id = layout.createFolder('a', 'b')!; // two apps
    layout.select('container:$id');
    await tester.pumpAndSettle();

    final panel = AppContainerTile.iconRect(HomeGrid.large, cell, 0, 0);
    final gesture = await tester.startGesture(Offset(panel.right + 4, panel.center.dy) + _top);
    for (var i = 0; i < 80; i++) {
      await gesture.moveBy(const Offset(4, 0)); // three cells' worth
      await tester.pump();
    }
    await gesture.up();
    await tester.pumpAndSettle();
    expect((layout.container(id)!.cols, layout.container(id)!.rows), (2, 1));
  });

  group('dock', () {
    /// The home pages with the dock under them, as on the home screen.
    Future<(HomeLayoutController, DockController, Size)> pumpHomeWithDock(
      WidgetTester tester,
      List<String> ids, {
      List<String> docked = const [],
    }) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues({'dock_app_ids': docked});
      final prefs = await SharedPreferences.getInstance();
      final apps = _FakeApps(ids);
      final layout = HomeLayoutController(prefs, apps);
      await layout.setMode(HomeMode.standard);
      final dock = DockController(prefs);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: layout),
            ChangeNotifierProvider.value(value: dock),
            Provider.value(value: VisibleApps(apps.apps, const {})),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  const Expanded(child: StandardHome()),
                  Padding(padding: EdgeInsets.fromLTRB(_side(), 0, _side(), 24), child: const Dock()),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final cellW = (tester.getSize(find.byType(StandardHome)).width - _side() * 2) / 4;
      return (layout, dock, Size(cellW, HomeGrid.large.cellHeightFor(cellW)));
    }

    Finder inDock(String id) =>
        find.descendant(of: find.byType(Dock), matching: find.byWidgetPredicate((w) => w is AppIcon && w.app.id == id));

    Future<void> dragTo(WidgetTester tester, Offset from, Offset to) async {
      final gesture = await tester.startGesture(from);
      await tester.pump(const Duration(milliseconds: 600));
      for (var i = 1; i <= 12; i++) {
        await gesture.moveTo(Offset.lerp(from, to, i / 12)!);
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.moveBy(const Offset(1, 0));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
    }

    testWidgets('four dock apps line up under the four home columns', (tester) async {
      final (_, _, cell) = await pumpHomeWithDock(tester, ['a', 'b', 'c', 'd', 'e'], docked: ['b', 'c', 'd', 'e']);
      final left = tester.getTopLeft(find.byType(StandardHome)).dx + _side();
      for (final (i, id) in ['b', 'c', 'd', 'e'].indexed) {
        expect(tester.getCenter(inDock(id)).dx, closeTo(left + cell.width * (i + 0.5), 0.5));
      }
      // Wider apart than the panel's padding above and below them.
      final gap = tester.getTopLeft(inDock('c')).dx - tester.getTopRight(inDock('b')).dx;
      expect(gap, greaterThan(Dock.verticalPadding * 2));
    });

    testWidgets('five dock apps share the width evenly, still well apart', (tester) async {
      await pumpHomeWithDock(tester, ['a', 'b', 'c', 'd', 'e', 'f'], docked: ['b', 'c', 'd', 'e', 'f']);
      final gaps = [
        for (final (l, r) in [('b', 'c'), ('c', 'd'), ('d', 'e'), ('e', 'f')])
          tester.getTopLeft(inDock(r)).dx - tester.getTopRight(inDock(l)).dx,
      ];
      expect({for (final g in gaps) g.toStringAsFixed(2)}.length, 1); // equal
      expect(gaps.first, greaterThanOrEqualTo(12));
      // The ends get the same gap: from the grid's edges to the outer icons.
      final home = tester.getRect(find.byType(StandardHome));
      final (left, right) = (home.left + _side(), home.right - _side());
      expect(tester.getTopLeft(inDock('b')).dx - left, closeTo(gaps.first, 0.5));
      expect(right - tester.getTopRight(inDock('f')).dx, closeTo(gaps.first, 0.5));
    });

    testWidgets('a home app dragged into the dock joins it where dropped', (tester) async {
      final (layout, dock, _) = await pumpHomeWithDock(tester, ['a', 'b', 'c'], docked: ['b', 'c']);
      final target = tester.getCenter(inDock('b')) - const Offset(30, 0); // left half of b's slot
      await dragTo(tester, tester.getCenter(find.text('a')), target);
      expect(dock.ids, ['a', 'b', 'c']);
      expect(find.text('a'), findsNothing); // off the home pages
      expect(layout.dragging, isFalse);
      expect(layout.editing, isFalse);
    });

    testWidgets('an app dragged into an empty dock starts it', (tester) async {
      final (_, dock, _) = await pumpHomeWithDock(tester, ['a', 'b']);
      final gesture = await tester.startGesture(tester.getCenter(find.text('a')));
      await tester.pump(const Duration(milliseconds: 600));
      await gesture.moveBy(const Offset(0, 30));
      await tester.pump();
      expect(find.byType(Dock), findsOneWidget);
      await gesture.moveTo(tester.getCenter(find.byType(Dock)));
      await tester.pump();
      await gesture.moveBy(const Offset(1, 0));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(dock.ids, ['a']);
    });

    testWidgets('a dock app dragged onto the home screen leaves the dock', (tester) async {
      final (layout, dock, cell) = await pumpHomeWithDock(tester, ['a', 'b', 'c'], docked: ['c']);
      final target = Offset(cell.width * 2.5, cell.height * 2.5) + _top; // an empty cell
      await dragTo(tester, tester.getCenter(inDock('c')), target);
      expect(dock.ids, isEmpty);
      expect(layout.slots['app:c'], const GridSlot(0, 2, 2));
      expect(find.text('c'), findsOneWidget);
      expect(layout.dragging, isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets('dock apps reorder by dragging along the dock', (tester) async {
      final (_, dock, _) = await pumpHomeWithDock(tester, ['a', 'b', 'c', 'd'], docked: ['b', 'c', 'd']);
      await dragTo(tester, tester.getCenter(inDock('b')), tester.getCenter(inDock('d')) + const Offset(20, 0));
      expect(dock.ids, ['c', 'd', 'b']);
    });

    testWidgets('into a full dock, a home app trades places with the one it lands on', (tester) async {
      final ids = ['a', 'b', 'c', 'd', 'e', 'f'];
      final (layout, dock, _) = await pumpHomeWithDock(tester, ids, docked: ['b', 'c', 'd', 'e', 'f']);
      final from = layout.slots['app:a'];
      await dragTo(tester, tester.getCenter(find.text('a')), tester.getCenter(inDock('d')));
      expect(dock.ids, ['b', 'c', 'a', 'e', 'f']);
      expect(layout.slots['app:d'], from);
      expect(find.text('d'), findsOneWidget); // back on the home screen
    });

    testWidgets('a long press on a dock app without dragging opens nothing else', (tester) async {
      final (layout, dock, _) = await pumpHomeWithDock(tester, ['a', 'b'], docked: ['b']);
      final gesture = await tester.startGesture(tester.getCenter(inDock('b')));
      await tester.pump(const Duration(milliseconds: 600));
      await gesture.up();
      await tester.pump();
      tester.takeException(); // the app menu needs providers this test lacks
      await tester.pumpAndSettle();
      expect(dock.ids, ['b']);
      expect(layout.dragging, isFalse);
      expect(layout.editing, isFalse);
    });
  });

  group('dock size follows the grid', () {
    Future<(HomeLayoutController, DockController)> setUpDock(List<String> docked) async {
      SharedPreferences.setMockInitialValues({'dock_app_ids': docked});
      final prefs = await SharedPreferences.getInstance();
      final layout = HomeLayoutController(prefs, _FakeApps(['1', '2', '3', '4', '5', '6', '7']));
      return (layout, DockController(prefs, layout));
    }

    test('holds 5 apps with the 4- and 5-column grids and 6 with the 6-column grid', () async {
      final (layout, dock) = await setUpDock([]);
      for (final (grid, max) in [(HomeGrid.large, 5), (HomeGrid.medium, 5), (HomeGrid.compact, 6)]) {
        await layout.setGrid(grid);
        expect(dock.maxApps, max, reason: grid.name);
      }
      for (final id in ['1', '2', '3', '4', '5', '6', '7']) {
        await dock.pin(id);
      }
      expect(dock.ids, ['1', '2', '3', '4', '5', '6']);
      expect(dock.isFull, isTrue);
    });

    test('going back to a 5-app grid unpins the sixth app', () async {
      final (layout, dock) = await setUpDock([]);
      await layout.setGrid(HomeGrid.compact);
      for (final id in ['1', '2', '3', '4', '5', '6']) {
        await dock.pin(id);
      }
      await layout.setGrid(HomeGrid.medium);
      expect(dock.ids, ['1', '2', '3', '4', '5']);
      // Back to 6 columns: room for one more, but nothing comes back by itself.
      await layout.setGrid(HomeGrid.compact);
      expect(dock.ids, ['1', '2', '3', '4', '5']);
      expect(dock.isFull, isFalse);
    });
  });
}

extension _Let<T> on T {
  R let<R>(R Function(T) f) => f(this);
}
