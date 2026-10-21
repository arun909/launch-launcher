import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/app_info.dart';
import '../platform/launcher_platform.dart';
import 'app_cache.dart';

/// Source of truth for the installed-app list.
///
/// Shows the cached list immediately on start, then reconciles with
/// PackageManager in the background, fetching icons only for apps that are
/// new or were updated since they were cached.
///
/// This list is UNFILTERED. UI should read `VisibleApps`
/// (features/hidden_apps/visible_apps.dart), which removes hidden apps.
class AppsController extends ChangeNotifier {
  AppsController(this._platform, this._cache);

  final LauncherPlatform _platform;
  final AppCache _cache;

  static const _iconBatchSize = 24;

  List<AppInfo> _apps = const [];
  bool _loaded = false;
  StreamSubscription<PackageEvent>? _packageSub;
  Future<void>? _refreshing;
  bool _refreshQueued = false;

  /// All launchable apps, sorted by label.
  List<AppInfo> get apps => _apps;

  /// True once either the cache or a live query has produced a list.
  bool get isLoaded => _loaded;

  Future<void> init() async {
    final cached = await _cache.load();
    if (cached.isNotEmpty) _setApps(cached);
    _packageSub = _platform.packageEvents.listen((_) => refresh());
    await refresh();
  }

  /// Re-queries Android. Concurrent calls are coalesced into one follow-up run.
  Future<void> refresh() {
    if (_refreshing != null) {
      _refreshQueued = true;
      return _refreshing!;
    }
    return _refreshing = _doRefresh().whenComplete(() {
      _refreshing = null;
      if (_refreshQueued) {
        _refreshQueued = false;
        refresh();
      }
    });
  }

  /// Drops the on-disk cache and rebuilds everything, including icons.
  Future<void> rebuildCache() async {
    await _cache.clear();
    _apps = const [];
    notifyListeners();
    await refresh();
  }

  Future<bool> launch(AppInfo app) => _platform.launchApp(app.id);

  Future<void> openAppInfo(AppInfo app) => _platform.openAppInfo(app.packageName);

  Future<void> _doRefresh() async {
    final List<AppInfo> fresh;
    try {
      fresh = await _platform.getInstalledApps();
    } catch (e) {
      debugPrint('AppsController: getInstalledApps failed: $e');
      if (!_loaded) {
        _loaded = true;
        notifyListeners();
      }
      return;
    }

    final previous = {for (final a in _apps) a.id: a};
    final needIcons = <String>[];
    var merged = fresh.map((app) {
      final old = previous[app.id];
      if (old?.icon != null && old!.lastUpdateTime == app.lastUpdateTime) {
        return app.copyWith(icon: old.icon);
      }
      needIcons.add(app.id);
      return app;
    }).toList();

    // Publish the list right away (new apps show with placeholder icons)...
    _setApps(merged);

    // ...then fill icons in batches so the UI fills in progressively.
    for (var i = 0; i < needIcons.length; i += _iconBatchSize) {
      final batch = needIcons.sublist(i, (i + _iconBatchSize).clamp(0, needIcons.length));
      try {
        final icons = await _platform.getAppIcons(batch);
        merged = [for (final a in _apps) icons.containsKey(a.id) ? a.copyWith(icon: icons[a.id]) : a];
        _setApps(merged);
        for (final entry in icons.entries) {
          await _cache.saveIcon(entry.key, entry.value);
        }
      } catch (e) {
        debugPrint('AppsController: icon batch failed: $e');
      }
    }

    await _cache.saveList(_apps);
    await _cache.pruneIcons(_apps.where((a) => a.icon != null).map((a) => a.id));
  }

  void _setApps(List<AppInfo> apps) {
    _apps = List.unmodifiable(
      [...apps]..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase())),
    );
    _loaded = true;
    notifyListeners();
  }

  @override
  void dispose() {
    _packageSub?.cancel();
    super.dispose();
  }
}
