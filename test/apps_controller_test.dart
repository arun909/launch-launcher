import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:minimal_launcher/core/apps/app_cache.dart';
import 'package:minimal_launcher/core/apps/apps_controller.dart';
import 'package:minimal_launcher/core/models/app_info.dart';
import 'package:minimal_launcher/core/platform/launcher_platform.dart';

AppInfo _app(String id, {int updated = 1}) => AppInfo(
  id: id,
  label: id,
  packageName: id.split('/').first,
  activityName: 'Main',
  lastUpdateTime: updated,
);

class _FakePlatform implements LauncherPlatform {
  List<AppInfo> installed = [];
  int iconCalls = 0;

  @override
  Future<List<AppInfo>> getInstalledApps() async => installed;

  @override
  Future<Map<String, Uint8List>> getAppIcons(List<String> ids, {int sizePx = 192}) async {
    iconCalls++;
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
}
