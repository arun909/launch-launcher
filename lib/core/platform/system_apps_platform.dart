import 'package:flutter/services.dart';

/// State of the Shizuku helper app, which grants the adb-level access needed
/// to disable system apps.
enum ShizukuStatus {
  notInstalled,
  notRunning,

  /// Very old Shizuku (pre v11) that this API can't talk to.
  unsupported,
  permissionNeeded,
  ready,
}

/// A system app as reported by Android. Includes already-disabled apps.
class SystemApp {
  const SystemApp({
    required this.packageName,
    required this.label,
    required this.icon,
    required this.enabled,
    this.defaultRole,
  });

  final String packageName;
  final String label;
  final Uint8List icon;
  final bool enabled;

  /// e.g. "default SMS app" if Android currently depends on it, else null.
  final String? defaultRole;

  factory SystemApp.fromMap(Map<dynamic, dynamic> map) => SystemApp(
    packageName: map['packageName'] as String,
    label: map['label'] as String,
    icon: map['icon'] as Uint8List,
    enabled: map['enabled'] as bool,
    defaultRole: map['defaultRole'] as String?,
  );

  SystemApp copyWith({required bool enabled}) => SystemApp(
    packageName: packageName,
    label: label,
    icon: icon,
    enabled: enabled,
    defaultRole: defaultRole,
  );
}

/// Dart side of `platform/SystemAppsChannel.kt`; keep both in sync.
class SystemAppsPlatform {
  static const _method = MethodChannel('com.arun.minimal_launcher/system_apps');

  Future<ShizukuStatus> getShizukuStatus() async {
    final raw = await _method.invokeMethod<String>('getShizukuStatus');
    return ShizukuStatus.values.byName(raw ?? 'notInstalled');
  }

  /// Shows Shizuku's permission dialog. Returns true if granted.
  Future<bool> requestShizukuPermission() async =>
      await _method.invokeMethod<bool>('requestShizukuPermission') ?? false;

  /// Opens Shizuku, or its Play Store page if it isn't installed.
  Future<bool> openShizuku() async => await _method.invokeMethod<bool>('openShizuku') ?? false;

  Future<List<SystemApp>> listSystemApps() async {
    final list = await _method.invokeListMethod<Map<dynamic, dynamic>>('listSystemApps');
    return (list ?? const []).map(SystemApp.fromMap).toList();
  }

  /// Throws [PlatformException] with a readable message on failure.
  Future<void> setAppEnabled(String packageName, {required bool enabled}) =>
      _method.invokeMethod('setAppEnabled', {'packageName': packageName, 'enabled': enabled});
}
