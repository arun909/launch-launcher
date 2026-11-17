import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/platform/system_apps_platform.dart';

/// Lists system apps and disables / re-enables them through Shizuku.
///
/// Unlike hiding, disabling is system-wide: the app disappears from every
/// launcher and can't run until re-enabled. Nothing is deleted.
class SystemAppsController extends ChangeNotifier {
  SystemAppsController(this._platform, this._prefs) : _disabledByUs = (_prefs.getStringList(_key) ?? const []).toSet();

  static const _key = 'disabled_by_launcher';

  final SystemAppsPlatform _platform;
  final SharedPreferences _prefs;
  final Set<String> _disabledByUs;

  ShizukuStatus? _status;
  List<SystemApp> _apps = const [];
  bool _loading = false;
  String? _loadError;
  final Set<String> _busy = {};

  /// Null until first checked.
  ShizukuStatus? get status => _status;
  bool get isReady => _status == ShizukuStatus.ready;
  List<SystemApp> get apps => _apps;
  bool get isLoading => _loading;
  String? get loadError => _loadError;

  /// Packages this app disabled, so they can all be restored in one go.
  Set<String> get disabledByUs => Set.unmodifiable(_disabledByUs);

  bool isBusy(String packageName) => _busy.contains(packageName);

  Future<void> refresh() async {
    _loading = true;
    _loadError = null;
    notifyListeners();
    await refreshStatus(notify: false);
    try {
      _apps = (await _platform.listSystemApps())
        ..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
    } catch (e) {
      _loadError = _message(e);
    }
    _loading = false;
    notifyListeners();
  }

  Future<void> refreshStatus({bool notify = true}) async {
    try {
      _status = await _platform.getShizukuStatus();
    } catch (e) {
      debugPrint('SystemAppsController: status failed: $e');
      _status = ShizukuStatus.notInstalled;
    }
    if (notify) notifyListeners();
  }

  Future<void> requestPermission() async {
    await _platform.requestShizukuPermission();
    await refreshStatus();
  }

  Future<void> openShizuku() => _platform.openShizuku();

  /// Returns null on success, or an error message to show.
  Future<String?> setEnabled(SystemApp app, {required bool enabled}) async {
    _busy.add(app.packageName);
    notifyListeners();
    String? error;
    try {
      await _platform.setAppEnabled(app.packageName, enabled: enabled);
      _apps = [for (final a in _apps) a.packageName == app.packageName ? a.copyWith(enabled: enabled) : a];
      enabled ? _disabledByUs.remove(app.packageName) : _disabledByUs.add(app.packageName);
      await _prefs.setStringList(_key, _disabledByUs.toList()..sort());
    } catch (e) {
      error = _message(e);
    }
    _busy.remove(app.packageName);
    notifyListeners();
    return error;
  }

  /// Re-enables everything this app disabled. Returns the labels that failed.
  Future<List<String>> enableAllDisabledByUs() async {
    final failed = <String>[];
    for (final app in _apps.where((a) => !a.enabled && _disabledByUs.contains(a.packageName)).toList()) {
      if (await setEnabled(app, enabled: true) != null) failed.add(app.label);
    }
    return failed;
  }

  static String _message(Object e) => e is PlatformException ? (e.message ?? e.code) : e.toString();
}
