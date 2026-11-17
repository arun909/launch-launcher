import 'dart:async';

import 'package:flutter/services.dart';

import '../models/app_info.dart';
import '../models/icon_shape.dart';
import '../models/icon_style.dart';

/// Kind of package change reported by Android.
enum PackageEventType { added, removed, changed }

class PackageEvent {
  const PackageEvent(this.type, this.packageName);
  final PackageEventType type;
  final String packageName;
}

/// Dart side of the native bridge. The Kotlin counterpart is
/// `android/app/src/main/kotlin/.../platform/LauncherChannel.kt`; channel names
/// and method signatures here must match it.
///
/// This is the only file that talks to the launcher channels. Features depend
/// on this class (not on MethodChannel directly), so it can be faked in tests.
/// Future native features should get their own class under core/platform/.
class LauncherPlatform {
  LauncherPlatform() {
    _method.setMethodCallHandler(_onNativeCall);
  }

  /// This launcher's application id. Its own entry in the app list opens the
  /// settings screen instead of launching (see `openApp`).
  static const selfPackage = 'com.arun.minimal_launcher';

  static const _method = MethodChannel('com.arun.minimal_launcher/launcher');
  static const _events = EventChannel('com.arun.minimal_launcher/package_events');

  final _homePressed = StreamController<void>.broadcast();

  /// Fires when Home is pressed while the launcher is already in front.
  Stream<void> get homePressed => _homePressed.stream;

  /// Install / uninstall / update events.
  late final Stream<PackageEvent> packageEvents = _events.receiveBroadcastStream().map((raw) {
    final map = raw as Map<dynamic, dynamic>;
    return PackageEvent(PackageEventType.values.byName(map['type'] as String), map['packageName'] as String);
  });

  /// Metadata (no icons) for every launchable app.
  Future<List<AppInfo>> getInstalledApps() async {
    final list = await _method.invokeListMethod<Map<dynamic, dynamic>>('getInstalledApps');
    return (list ?? const []).map(AppInfo.fromMap).toList();
  }

  /// PNG icon bytes keyed by app id, drawn in [shape] and [style].
  /// [overrides] maps app ids to `original` or `<pack>:<icon name>`.
  Future<Map<String, Uint8List>> getAppIcons(
    List<String> ids, {
    int sizePx = 192,
    IconShape shape = IconShape.system,
    IconStyle style = IconStyle.defaults,
    Map<String, String> overrides = const {},
  }) async {
    final map = await _method.invokeMapMethod<String, Uint8List>('getAppIcons', {
      'ids': ids,
      'sizePx': sizePx,
      'cornerRadius': shape.radius, // null = the phone's own mask
      'style': style.toMap(),
      'overrides': {for (final id in ids) id: ?overrides[id]},
    });
    return map ?? const {};
  }

  /// PNG bytes of bundled pack icons keyed by `<pack>:<name>` ref, in the
  /// colour [style] gives [appId].
  Future<Map<String, Uint8List>> getPackIcons(
    List<String> refs, {
    int sizePx = 144,
    IconShape shape = IconShape.system,
    IconStyle style = IconStyle.defaults,
    String? appId,
  }) async {
    final map = await _method.invokeMapMethod<String, Uint8List>('getPackIcons', {
      'refs': refs,
      'sizePx': sizePx,
      'cornerRadius': shape.radius,
      'style': style.toMap(),
      'appId': appId,
    });
    return map ?? const {};
  }

  /// Every icon in a bundled pack as a `<pack>:<name>` ref for [getPackIcons].
  Future<List<String>> getPackIconRefs(IconSource pack) async {
    final names = await _method.invokeListMethod<String>('getPackIconNames', {'pack': pack.name}) ?? const [];
    return [for (final n in names) '${pack.name}:$n'];
  }

  /// Refs of the icon each bundled pack would use for app [id].
  Future<List<String>> getPackIconsForApp(String id) async {
    final map = await _method.invokeMapMethod<String, String>('getPackIconsForApp', {'id': id}) ?? const {};
    return [for (final e in map.entries) '${e.key}:${e.value}'];
  }

  /// Returns false if the app could not be launched (e.g. just uninstalled).
  Future<bool> launchApp(String id) async => await _method.invokeMethod<bool>('launchApp', {'id': id}) ?? false;

  Future<void> openAppInfo(String packageName) => _method.invokeMethod('openAppInfo', {'packageName': packageName});

  /// Opens Android's uninstall confirmation for [packageName].
  /// Returns false if the phone has no uninstaller to show it.
  Future<bool> uninstallApp(String packageName) async =>
      await _method.invokeMethod<bool>('uninstallApp', {'packageName': packageName}) ?? false;

  /// Opens Android's "Default home app" picker.
  Future<void> openHomeSettings() => _method.invokeMethod('openHomeSettings');

  /// Opens the phone's own wallpaper settings (vivo's Themes, say), as its
  /// own launcher does, with albums, live wallpapers and the rest; else
  /// Android's chooser of wallpaper apps. Returns false if the phone has none.
  Future<bool> openSystemWallpapers() async => await _method.invokeMethod<bool>('openSystemWallpapers') ?? false;

  /// Opens the phone's clock app (its alarms). Returns false if it has none.
  Future<bool> openClock() async => await _method.invokeMethod<bool>('openClock') ?? false;

  /// Pulls down the notification shade. Returns false if the phone refused.
  Future<bool> expandNotifications() async => await _method.invokeMethod<bool>('expandNotifications') ?? false;

  /// Pulls down the quick-settings panel. Returns false if the phone refused.
  Future<bool> expandQuickSettings() async => await _method.invokeMethod<bool>('expandQuickSettings') ?? false;

  /// True if Android currently uses this app as the home screen.
  Future<bool> isDefaultHome() async => await _method.invokeMethod<bool>('isDefaultHome') ?? false;

  Future<dynamic> _onNativeCall(MethodCall call) async {
    switch (call.method) {
      case 'onHomePressed':
        _homePressed.add(null);
    }
  }
}
