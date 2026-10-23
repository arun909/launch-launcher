import 'dart:async';

import 'package:flutter/services.dart';

import '../models/app_info.dart';

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

  /// PNG icon bytes keyed by app id.
  Future<Map<String, Uint8List>> getAppIcons(List<String> ids, {int sizePx = 192}) async {
    final map = await _method.invokeMapMethod<String, Uint8List>('getAppIcons', {
      'ids': ids,
      'sizePx': sizePx,
    });
    return map ?? const {};
  }

  /// Returns false if the app could not be launched (e.g. just uninstalled).
  Future<bool> launchApp(String id) async =>
      await _method.invokeMethod<bool>('launchApp', {'id': id}) ?? false;

  Future<void> openAppInfo(String packageName) =>
      _method.invokeMethod('openAppInfo', {'packageName': packageName});

  /// Opens Android's "Default home app" picker.
  Future<void> openHomeSettings() => _method.invokeMethod('openHomeSettings');

  /// Opens Android's chooser of wallpaper apps (system picker, Photos, themes...).
  /// Returns false if the phone has none.
  Future<bool> openWallpaperPicker() async =>
      await _method.invokeMethod<bool>('openWallpaperPicker') ?? false;

  /// Opens Android's live-wallpaper list. Returns false if the phone has none.
  Future<bool> openLiveWallpaperPicker() async =>
      await _method.invokeMethod<bool>('openLiveWallpaperPicker') ?? false;

  /// True if Android currently uses this app as the home screen.
  Future<bool> isDefaultHome() async => await _method.invokeMethod<bool>('isDefaultHome') ?? false;

  Future<dynamic> _onNativeCall(MethodCall call) async {
    switch (call.method) {
      case 'onHomePressed':
        _homePressed.add(null);
    }
  }
}
