import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/app_info.dart';
import '../models/icon_shape.dart';
import '../models/icon_style.dart';
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
  AppsController(
    this._platform,
    this._cache, {
    this._iconShape = IconShape.system,
    this._iconStyle = IconStyle.defaults,
    Map<String, String> iconOverrides = const {},
  }) : _iconOverrides = Map.unmodifiable(iconOverrides);

  final LauncherPlatform _platform;
  final AppCache _cache;

  static const _iconBatchSize = 16;

  /// Batches rendered at once (the native side has a thread for each, plus
  /// one spare so settings previews don't wait behind a full re-render).
  static const _parallelBatches = 2;

  /// App ids in the order their icons should be drawn when many are
  /// re-rendered: what's on screen first (dock, first home page). Others
  /// follow A–Z.
  List<String> Function()? iconPriority;

  List<AppInfo> _apps = const [];
  bool _loaded = false;
  StreamSubscription<PackageEvent>? _packageSub;
  Future<void>? _refreshing;

  /// The one follow-up run that requests made during a refresh share.
  Future<void>? _queued;
  IconShape _iconShape;
  IconStyle _iconStyle;
  Map<String, String> _iconOverrides;

  /// Set when the cached icons don't match [_iconShape] or [_iconStyle]: the
  /// next refresh re-renders every icon, even if no app changed.
  bool _restyleIcons = false;

  /// Apps whose icon the next refresh re-renders (their override changed).
  final _redrawIds = <String>{};

  /// All launchable apps, sorted by label.
  List<AppInfo> get apps => _apps;

  /// True once either the cache or a live query has produced a list.
  bool get isLoaded => _loaded;

  IconShape get iconShape => _iconShape;

  IconStyle get iconStyle => _iconStyle;

  /// Per-app icon choices: app id -> `original` or `<pack>:<icon name>`.
  Map<String, String> get iconOverrides => _iconOverrides;

  Future<void> init() async {
    final cached = await _cache.load();
    if (cached.isNotEmpty) _setApps(cached);
    if (await _cache.loadIconShape() != _iconShape || await _cache.loadIconStyle() != _iconStyle) {
      _restyleIcons = true;
    }
    _packageSub = _platform.packageEvents.listen((_) => refresh());
    await refresh();
  }

  /// Re-queries Android. Calls made while a refresh runs share one follow-up
  /// run, and complete when that run (which sees their changes) is done.
  Future<void> refresh() {
    final running = _refreshing;
    if (running == null) return _startRefresh();
    return _queued ??= running.catchError((_) {}).then((_) {
      _queued = null;
      return _startRefresh();
    });
  }

  Future<void> _startRefresh() => _refreshing = _doRefresh().whenComplete(() => _refreshing = null);

  /// Re-renders all icons in [shape]. Current icons stay on screen until
  /// their replacements arrive.
  Future<void> setIconShape(IconShape shape) {
    if (shape == _iconShape) return Future.value();
    _iconShape = shape;
    _restyleIcons = true;
    return refresh();
  }

  /// Re-renders all icons in [style], like [setIconShape].
  Future<void> setIconStyle(IconStyle style) {
    if (style == _iconStyle) return Future.value();
    _iconStyle = style;
    _restyleIcons = true;
    return refresh();
  }

  /// Sets (or with null, clears) app [id]'s own icon choice and re-renders it.
  Future<void> setIconOverride(String id, String? override) {
    if (_iconOverrides[id] == override) return Future.value();
    final next = {..._iconOverrides};
    override == null ? next.remove(id) : next[id] = override;
    _iconOverrides = Map.unmodifiable(next);
    _redrawIds.add(id);
    return refresh();
  }

  /// Clears every per-app icon choice and re-renders those icons.
  Future<void> clearIconOverrides() {
    if (_iconOverrides.isEmpty) return Future.value();
    _redrawIds.addAll(_iconOverrides.keys);
    _iconOverrides = const {};
    return refresh();
  }

  /// Icons for [ids] in a style that isn't applied (settings previews).
  /// Nothing is cached; failures give an empty map.
  Future<Map<String, Uint8List>> previewIcons(
    List<String> ids, {
    required IconShape shape,
    required IconStyle style,
    int sizePx = 144,
  }) async {
    try {
      return await _platform.getAppIcons(ids, sizePx: sizePx, shape: shape, style: style, overrides: _iconOverrides);
    } catch (e) {
      debugPrint('AppsController: preview failed: $e');
      return const {};
    }
  }

  /// Drops the on-disk cache and rebuilds everything, including icons.
  Future<void> rebuildCache() async {
    await _refreshing; // let a running refresh finish writing before wiping
    await _cache.clear();
    _apps = const [];
    notifyListeners();
    await refresh();
  }

  Future<bool> launch(AppInfo app) => _platform.launchApp(app.id);

  Future<void> openAppInfo(AppInfo app) => _platform.openAppInfo(app.packageName);

  /// The app list updates by itself once it's gone (package events).
  Future<bool> uninstall(AppInfo app) => _platform.uninstallApp(app.packageName);

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
    final shape = _iconShape;
    final style = _iconStyle;
    final overrides = _iconOverrides;
    final restyle = _restyleIcons;
    _restyleIcons = false;
    final redraw = {..._redrawIds};
    _redrawIds.clear();

    // Nothing installed, removed or updated (the usual case when returning to
    // home): skip the rebuild and disk writes, which would otherwise land in
    // the middle of the back-to-home animation.
    if (!restyle && redraw.isEmpty && _isUnchanged(previous, fresh)) return;

    var needIcons = <String>[];
    final merged = fresh.map((app) {
      final old = previous[app.id];
      final current = old?.icon != null && old!.lastUpdateTime == app.lastUpdateTime;
      if (!current || restyle || redraw.contains(app.id)) needIcons.add(app.id);
      // When restyling, keep showing the old icon until the new one arrives.
      return current ? app.copyWith(icon: old.icon) : app;
    }).toList();

    // Publish the list right away (new apps show with placeholder icons)...
    _setApps(merged);

    // ...then fill icons in batches so the UI fills in progressively, the
    // icons on screen first.
    needIcons = _onScreenFirst(needIcons);
    var allIconsFetched = true;
    var superseded = false;
    for (var i = 0; i < needIcons.length; i += _iconBatchSize * _parallelBatches) {
      // The look changed again: stop drawing outdated icons. The setter
      // queued a refresh that re-renders everything in the new look.
      if (shape != _iconShape || style != _iconStyle) {
        superseded = true;
        break;
      }
      final batches = [
        for (var j = i; j < (i + _iconBatchSize * _parallelBatches).clamp(0, needIcons.length); j += _iconBatchSize)
          needIcons.sublist(j, (j + _iconBatchSize).clamp(0, needIcons.length)),
      ];
      final results = await Future.wait(
        batches.map((batch) async {
          try {
            return await _platform.getAppIcons(batch, shape: shape, style: style, overrides: overrides);
          } catch (e) {
            debugPrint('AppsController: icon batch failed: $e');
            allIconsFetched = false;
            return const <String, Uint8List>{};
          }
        }),
      );
      final icons = {for (final r in results) ...r};
      if (icons.isEmpty) continue;
      _setApps([for (final a in _apps) icons.containsKey(a.id) ? a.copyWith(icon: icons[a.id]) : a]);
      for (final entry in icons.entries) {
        await _cache.saveIcon(entry.key, entry.value);
      }
    }

    await _cache.saveList(_apps);
    // Only claim the new look once every icon has it; otherwise the next
    // start restyles again.
    if (superseded) {
      _restyleIcons = true;
    } else if (allIconsFetched) {
      await _cache.saveIconShape(shape);
      await _cache.saveIconStyle(style);
    } else {
      if (restyle) _restyleIcons = true;
      _redrawIds.addAll(redraw);
    }
    await _cache.pruneIcons(_apps.where((a) => a.icon != null).map((a) => a.id));
  }

  /// [ids] with those in [iconPriority] first, in that order.
  List<String> _onScreenFirst(List<String> ids) {
    final priority = iconPriority?.call() ?? const [];
    if (priority.isEmpty) return ids;
    final rank = <String, int>{};
    for (final id in priority) {
      rank.putIfAbsent(id, () => rank.length);
    }
    final first = ids.where(rank.containsKey).toList()..sort((a, b) => rank[a]!.compareTo(rank[b]!));
    return [...first, ...ids.where((id) => !rank.containsKey(id))];
  }

  static bool _isUnchanged(Map<String, AppInfo> previous, List<AppInfo> fresh) {
    if (previous.isEmpty || previous.length != fresh.length) return false;
    for (final app in fresh) {
      final old = previous[app.id];
      if (old == null || old.icon == null || old.label != app.label || old.lastUpdateTime != app.lastUpdateTime) {
        return false;
      }
    }
    return true;
  }

  void _setApps(List<AppInfo> apps) {
    _apps = List.unmodifiable([...apps]..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase())));
    _loaded = true;
    notifyListeners();
  }

  @override
  void dispose() {
    _packageSub?.cancel();
    super.dispose();
  }
}
