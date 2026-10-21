import 'dart:typed_data';

/// One launchable app entry (a launcher activity).
///
/// [id] is `"<packageName>/<activityName>"` and is the stable key used by
/// every feature (hidden list, home favorites, icon cache).
class AppInfo {
  const AppInfo({
    required this.id,
    required this.label,
    required this.packageName,
    required this.activityName,
    required this.lastUpdateTime,
    this.icon,
  });

  final String id;
  final String label;
  final String packageName;
  final String activityName;

  /// Package last-update time (ms since epoch). Used to invalidate cached icons.
  final int lastUpdateTime;

  /// PNG bytes, or null while not yet loaded.
  final Uint8List? icon;

  AppInfo copyWith({Uint8List? icon}) => AppInfo(
    id: id,
    label: label,
    packageName: packageName,
    activityName: activityName,
    lastUpdateTime: lastUpdateTime,
    icon: icon ?? this.icon,
  );

  /// Parses the map sent by the platform channel, or read from the cache.
  factory AppInfo.fromMap(Map<dynamic, dynamic> map) => AppInfo(
    id: map['id'] as String,
    label: map['label'] as String,
    packageName: map['packageName'] as String,
    activityName: map['activityName'] as String,
    lastUpdateTime: (map['lastUpdateTime'] as num?)?.toInt() ?? 0,
  );

  /// Metadata only; icons are cached as separate files.
  Map<String, dynamic> toMap() => {
    'id': id,
    'label': label,
    'packageName': packageName,
    'activityName': activityName,
    'lastUpdateTime': lastUpdateTime,
  };
}
