import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// One connected Bluetooth device.
@immutable
class BluetoothBattery {
  const BluetoothBattery({required this.name, required this.address, required this.battery, required this.kind});

  factory BluetoothBattery.fromMap(Map<dynamic, dynamic> m) => BluetoothBattery(
    name: m['name'] as String? ?? 'Device',
    address: m['address'] as String? ?? '',
    battery: (m['battery'] as num?)?.toInt() ?? -1,
    kind: m['kind'] as String? ?? 'other',
  );

  final String name;
  final String address;

  /// 0–100; null when the device doesn't report it.
  int? get level => battery >= 0 && battery <= 100 ? battery : null;
  final int battery;

  /// headphones, speaker, watch, input, phone, computer, car or other.
  final String kind;

  @override
  bool operator ==(Object other) =>
      other is BluetoothBattery &&
      other.name == name &&
      other.address == address &&
      other.battery == battery &&
      other.kind == kind;

  @override
  int get hashCode => Object.hash(name, address, battery, kind);
}

/// Time spent in one app today.
@immutable
class AppUsage {
  const AppUsage(this.package, this.time);

  final String package;
  final Duration time;

  @override
  bool operator ==(Object other) => other is AppUsage && other.package == package && other.time == time;

  @override
  int get hashCode => Object.hash(package, time);
}

/// Today's phone stats, as the phone-stats and activity widgets show them.
@immutable
class DeviceStats {
  const DeviceStats({
    required this.battery,
    required this.charging,
    required this.usageAccess,
    this.screenOn,
    this.unlocks,
    this.uptime,
    this.topApps,
    required this.bluetoothAllowed,
    this.bluetooth = const [],
  });

  factory DeviceStats.fromMap(Map<dynamic, dynamic> m) => DeviceStats(
    battery: (m['battery'] as num?)?.toInt() ?? 0,
    charging: m['charging'] as bool? ?? false,
    usageAccess: m['usageAccess'] as bool? ?? false,
    screenOn: switch (m['screenOnMs']) {
      final num ms => Duration(milliseconds: ms.toInt()),
      _ => null,
    },
    unlocks: (m['unlocks'] as num?)?.toInt(),
    uptime: switch (m['uptimeMs']) {
      final num ms => Duration(milliseconds: ms.toInt()),
      _ => null,
    },
    topApps: switch (m['topApps']) {
      final List<dynamic> l => [
        for (final a in l.cast<Map<dynamic, dynamic>>())
          AppUsage(a['package'] as String, Duration(milliseconds: (a['ms'] as num).toInt())),
      ],
      _ => null,
    },
    bluetoothAllowed: m['bluetoothAllowed'] as bool? ?? false,
    bluetooth: [
      for (final d in (m['bluetooth'] as List<dynamic>? ?? const []))
        BluetoothBattery.fromMap(d as Map<dynamic, dynamic>),
    ],
  );

  /// The phone's battery, 0–100.
  final int battery;
  final bool charging;

  /// Whether "Usage access" is on: without it there's no [screenOn] or [unlocks].
  final bool usageAccess;

  /// Screen-on time since midnight.
  final Duration? screenOn;

  /// Times unlocked since midnight.
  final int? unlocks;

  /// Since the phone last started.
  final Duration? uptime;

  /// Today's most used apps, most first (at most 5); null without Usage access.
  final List<AppUsage>? topApps;

  /// Whether "Nearby devices" is allowed: without it [bluetooth] is empty.
  final bool bluetoothAllowed;

  /// Connected Bluetooth devices.
  final List<BluetoothBattery> bluetooth;

  @override
  bool operator ==(Object other) =>
      other is DeviceStats &&
      other.battery == battery &&
      other.charging == charging &&
      other.usageAccess == usageAccess &&
      other.screenOn == screenOn &&
      other.unlocks == unlocks &&
      other.uptime?.inMinutes == uptime?.inMinutes &&
      listEquals(other.topApps, topApps) &&
      other.bluetoothAllowed == bluetoothAllowed &&
      listEquals(other.bluetooth, bluetooth);

  @override
  int get hashCode => Object.hash(
    battery,
    charging,
    usageAccess,
    screenOn,
    unlocks,
    uptime?.inMinutes,
    Object.hashAll(topApps ?? const []),
    bluetoothAllowed,
    Object.hashAll(bluetooth),
  );
}

/// Where the phone is, roughly (for the clock's weather).
@immutable
class GeoPoint {
  const GeoPoint(this.lat, this.lon, {this.place});

  final double lat;
  final double lon;

  /// The town's name, when known.
  final String? place;
}

/// Dart side of `DeviceStatsChannel.kt`; keep both in sync.
class DeviceStatsPlatform {
  static const _method = MethodChannel('com.arun.minimal_launcher/device_stats');
  static const _events = EventChannel('com.arun.minimal_launcher/device_stats_events');

  Future<DeviceStats?> stats() async {
    final m = await _method.invokeMapMethod<dynamic, dynamic>('stats');
    return m == null ? null : DeviceStats.fromMap(m);
  }

  /// Fires when something shown may have changed (battery, a device, an unlock).
  Stream<void> changes() => _events.receiveBroadcastStream();

  Future<void> openUsageAccess() => _method.invokeMethod('openUsageAccess');

  Future<void> requestBluetooth() => _method.invokeMethod('requestBluetooth');

  Future<bool> hasLocation() async => await _method.invokeMethod<bool>('hasLocation') ?? false;

  Future<void> requestLocation() => _method.invokeMethod('requestLocation');

  /// The phone's approximate location; null without permission or a fix.
  Future<GeoPoint?> location() async {
    final m = await _method.invokeMapMethod<String, dynamic>('location');
    if (m == null) return null;
    return GeoPoint((m['lat'] as num).toDouble(), (m['lon'] as num).toDouble(), place: m['place'] as String?);
  }
}
