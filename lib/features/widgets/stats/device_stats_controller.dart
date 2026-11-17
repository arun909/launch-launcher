import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../../core/platform/device_stats_platform.dart';

/// Today's phone stats for the phone-stats widgets.
///
/// Reads them only while such a widget is on screen ([attach] / [detach])
/// and the launcher is in front: again when Android says something changed
/// (battery, a Bluetooth device, an unlock) and once a minute for the
/// screen time.
class DeviceStatsController extends ChangeNotifier with WidgetsBindingObserver {
  DeviceStatsController(this._platform) {
    WidgetsBinding.instance.addObserver(this);
  }

  final DeviceStatsPlatform _platform;

  int _users = 0;
  bool _foreground = true;
  bool _disposed = false;
  StreamSubscription<void>? _sub;
  Timer? _tick;
  Timer? _soon;

  /// The latest stats; null until first read.
  DeviceStats? get stats => _stats;
  DeviceStats? _stats;

  void attach() {
    _users++;
    _update();
  }

  void detach() {
    _users--;
    _update();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final front = state == AppLifecycleState.resumed;
    if (front == _foreground) return;
    _foreground = front;
    _update();
  }

  void _update() {
    final want = _users > 0 && _foreground;
    if (!want) {
      _sub?.cancel();
      _sub = null;
      _tick?.cancel();
      _tick = null;
      return;
    }
    // Back in front: Usage access or Bluetooth may have just been allowed.
    refresh();
    _sub ??= _platform.changes().listen((_) => _refreshSoon(), onError: (Object _) {});
    _tick ??= Timer.periodic(const Duration(minutes: 1), (_) => refresh());
  }

  /// Several changes at once (a device connecting sends a few): read once.
  void _refreshSoon() {
    _soon?.cancel();
    _soon = Timer(const Duration(milliseconds: 400), refresh);
  }

  Future<void> refresh() async {
    final s = await _platform.stats().catchError((Object _) => null);
    if (_disposed || s == null || s == _stats) return;
    _stats = s;
    notifyListeners();
  }

  Future<void> openUsageAccess() => _platform.openUsageAccess();

  Future<void> requestBluetooth() => _platform.requestBluetooth();

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _sub?.cancel();
    _tick?.cancel();
    _soon?.cancel();
    super.dispose();
  }
}
