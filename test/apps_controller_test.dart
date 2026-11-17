import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:minimal_launcher/core/apps/app_cache.dart';
import 'package:minimal_launcher/core/apps/apps_controller.dart';
import 'package:minimal_launcher/core/models/app_info.dart';
import 'package:minimal_launcher/core/models/icon_shape.dart';
import 'package:minimal_launcher/core/models/icon_style.dart';
import 'package:minimal_launcher/core/platform/launcher_platform.dart';

AppInfo _app(String id, {int updated = 1}) =>
    AppInfo(id: id, label: id, packageName: id.split('/').first, activityName: 'Main', lastUpdateTime: updated);

class _FakePlatform implements LauncherPlatform {
  List<AppInfo> installed = [];
  int iconCalls = 0;
  final shapesRequested = <IconShape>[];
  final stylesRequested = <IconStyle>[];
  final idsRequested = <List<String>>[];
  final overridesRequested = <Map<String, String>>[];

  @override
  Future<List<AppInfo>> getInstalledApps() async => installed;

  /// When set, icon calls wait for it (to change settings mid-render).
  Completer<void>? gate;

  @override
  Future<Map<String, Uint8List>> getAppIcons(
    List<String> ids, {
    int sizePx = 192,
    IconShape shape = IconShape.system,
    IconStyle style = IconStyle.defaults,
    Map<String, String> overrides = const {},
  }) async {
    iconCalls++;
    shapesRequested.add(shape);
    stylesRequested.add(style);
    idsRequested.add(ids);
    overridesRequested.add(overrides);
    await gate?.future;
    return {
      for (final id in ids) id: Uint8List.fromList([1]),
    };
  }

  @override
  Stream<PackageEvent> get packageEvents => const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MemoryCache implements AppCache {
  List<AppInfo> saved = [];
  int saves = 0;
  IconShape iconShape = IconShape.system;
  IconStyle? iconStyle = IconStyle.defaults;

  @override
  Future<List<AppInfo>> load() async => saved;
  @override
  Future<void> saveList(List<AppInfo> apps) async {
    saves++;
    saved = apps;
  }

  @override
  Future<void> saveIcon(String id, Uint8List png) async {}
  @override
  Future<IconShape> loadIconShape() async => iconShape;
  @override
  Future<void> saveIconShape(IconShape shape) async => iconShape = shape;
  @override
  Future<IconStyle?> loadIconStyle() async => iconStyle;
  @override
  Future<void> saveIconStyle(IconStyle style) async => iconStyle = style;
  @override
  Future<void> pruneIcons(Iterable<String> keepIds) async {}
  @override
  Future<void> clear() async => saved = [];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _FakePlatform platform;
  late _MemoryCache cache;
  late AppsController controller;

  setUp(() {
    platform = _FakePlatform()..installed = [_app('a/A'), _app('b/B')];
    cache = _MemoryCache();
    controller = AppsController(platform, cache);
  });

  test('first refresh loads apps with icons and saves the cache', () async {
    await controller.init();
    expect(controller.apps.map((a) => a.id), ['a/A', 'b/B']);
    expect(controller.apps.every((a) => a.icon != null), isTrue);
    expect(cache.saves, 1);
  });

  test('refresh with nothing changed does not rebuild or write', () async {
    await controller.init();
    var notified = 0;
    controller.addListener(() => notified++);

    await controller.refresh();

    expect(notified, 0);
    expect(cache.saves, 1);
    expect(platform.iconCalls, 1);
  });

  test('an updated app gets a fresh icon', () async {
    await controller.init();
    platform.installed = [_app('a/A', updated: 2), _app('b/B')];

    await controller.refresh();

    expect(platform.iconCalls, 2);
    expect(controller.apps.first.lastUpdateTime, 2);
  });

  test('an empty app list still finishes loading', () async {
    platform.installed = [];
    await controller.init();
    expect(controller.isLoaded, isTrue);
  });

  test('changing the icon shape re-renders every icon, keeping old ones meanwhile', () async {
    await controller.init();
    final oldIcon = controller.apps.first.icon;

    final restyle = controller.setIconShape(IconShape.circle);
    expect(controller.apps.first.icon, same(oldIcon));
    await restyle;

    expect(platform.iconCalls, 2);
    expect(platform.shapesRequested.last, IconShape.circle);
    expect(cache.iconShape, IconShape.circle);
  });

  test('icons cached in another shape are re-rendered on start', () async {
    await controller.init();
    controller = AppsController(platform, cache, iconShape: IconShape.circle);

    await controller.init();

    expect(platform.iconCalls, 2);
    expect(cache.iconShape, IconShape.circle);
  });

  test('icon shapes round-trip through their stored form', () {
    for (final shape in [IconShape.system, IconShape.circle, const IconShape.rounded(0), const IconShape.rounded(23)]) {
      expect(IconShape.decode(shape.encode()), shape);
    }
    expect(IconShape.decode('circle'), IconShape.circle);
    expect(IconShape.decode('99'), IconShape.circle);
    expect(IconShape.decode('garbage'), IconShape.system);
  });

  test('changing the icon style re-renders every icon and records the style', () async {
    await controller.init();
    const style = IconStyle(source: IconSource.lawnicons, background: IconBackground.black);

    await controller.setIconStyle(style);

    expect(platform.iconCalls, 2);
    expect(platform.idsRequested.last, ['a/A', 'b/B']);
    expect(platform.stylesRequested.last, style);
    expect(cache.iconStyle, style);
  });

  test('icons cached in another style are re-rendered on start', () async {
    await controller.init();
    controller = AppsController(platform, cache, iconStyle: const IconStyle(source: IconSource.themed));

    await controller.init();

    expect(platform.iconCalls, 2);
    expect(cache.iconStyle!.source, IconSource.themed);
  });

  test('icons drawn by an older renderer are redrawn on start', () async {
    await controller.init();
    cache.iconStyle = null; // what AppCache reports for another renderer version
    controller = AppsController(platform, cache);

    await controller.init();

    expect(platform.iconCalls, 2);
    expect(cache.iconStyle, IconStyle.defaults);
  });

  test('an icon override re-renders only that app, with the override', () async {
    await controller.init();

    await controller.setIconOverride('b/B', 'lawnicons:chrome');

    expect(platform.idsRequested.last, ['b/B']);
    expect(platform.overridesRequested.last, {'b/B': 'lawnicons:chrome'});
    expect(controller.iconOverrides, {'b/B': 'lawnicons:chrome'});

    await controller.setIconOverride('b/B', null);
    expect(platform.idsRequested.last, ['b/B']);
    expect(controller.iconOverrides, isEmpty);
  });

  test('clearing overrides re-renders the apps that had one', () async {
    controller = AppsController(platform, cache, iconOverrides: {'a/A': 'original'});
    await controller.init();

    await controller.clearIconOverrides();

    expect(platform.idsRequested.last, ['a/A']);
    expect(controller.iconOverrides, isEmpty);
  });

  test('icon styles round-trip through their stored form', () {
    const styles = [
      IconStyle.defaults,
      IconStyle(
        source: IconSource.arcticons,
        fillGaps: false,
        background: IconBackground.none,
        color: 0xFF8EC9FF,
        appColor: true,
        lineWeight: 1.75,
        glyphScale: 0.7,
        fallback: IconFallback.grayscale,
        legacyBackground: LegacyBackground.tinted,
      ),
    ];
    for (final style in styles) {
      expect(IconStyle.decode(style.encode()), style);
    }
    expect(IconStyle.decode(null), IconStyle.defaults);
    expect(IconStyle.decode('garbage'), IconStyle.defaults);
    expect(IconStyle.decode('{"pack":"nope","lineWeight":99}'), const IconStyle(lineWeight: IconStyle.maxLineWeight));
  });

  test('a newer style stops the outdated re-render and wins', () async {
    platform.installed = [for (var i = 0; i < 100; i++) _app('app$i/A')];
    await controller.init();
    platform.iconCalls = 0;
    platform.stylesRequested.clear();

    platform.gate = Completer();
    const first = IconStyle(source: IconSource.lawnicons);
    const second = IconStyle(source: IconSource.arcticons);
    final a = controller.setIconStyle(first);
    await Future<void>.delayed(Duration.zero);
    final b = controller.setIconStyle(second); // while the first is drawing
    platform.gate!.complete();
    platform.gate = null;
    await a;
    await b;

    // The first run stopped after its in-flight batches; the second drew all 100.
    expect(platform.stylesRequested.where((s) => s == first).length, lessThan(100 ~/ 16 + 1));
    expect(platform.idsRequested.where((ids) => ids.isNotEmpty).length, greaterThan(0));
    expect(cache.iconStyle, second);
    expect(platform.stylesRequested.last, second);
  });

  test('a refresh requested mid-run completes only after its own run', () async {
    await controller.init();
    platform.gate = Completer();
    final first = controller.setIconStyle(const IconStyle(source: IconSource.themed));
    await Future<void>.delayed(Duration.zero);
    final second = controller.setIconStyle(const IconStyle(source: IconSource.lawnicons));
    platform.gate!.complete();
    platform.gate = null;

    await second;
    expect(cache.iconStyle!.source, IconSource.lawnicons);
    await first;
  });

  test('a full re-render draws the prioritised (on-screen) apps first', () async {
    platform.installed = [
      for (final id in ['a', 'b', 'c', 'd']) _app('$id/A'),
    ];
    await controller.init();
    controller.iconPriority = () => ['d/A', 'b/A'];

    await controller.setIconStyle(const IconStyle(source: IconSource.lawnicons));

    expect(platform.idsRequested.last, ['d/A', 'b/A', 'a/A', 'c/A']);
  });
}
