import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Called with whether hidden apps' notifications should be dismissed, and
/// the packages of the hidden apps.
typedef HiddenNotificationsSync = void Function(bool block, Set<String> packages);

/// Persisted set of hidden app ids, and whether their notifications show.
///
/// Hiding is purely cosmetic: it only affects what this launcher displays.
/// It does not stop, disable or uninstall the app. The one exception is
/// [showNotifications]: turned off, the launcher dismisses notifications from
/// hidden apps (with notification access; see [onSync]).
class HiddenAppsController extends ChangeNotifier {
  HiddenAppsController(this._prefs, {this.onSync})
    : _hidden = (_prefs.getStringList(_key) ?? const []).toSet(),
      _showNotifications = _prefs.getBool(_notificationsKey) ?? true {
    _sync();
  }

  static const _key = 'hidden_app_ids';
  static const _notificationsKey = 'hidden_apps_show_notifications';

  final SharedPreferences _prefs;
  final Set<String> _hidden;
  bool _showNotifications;

  /// Hands the current state to the notification filter (native side).
  final HiddenNotificationsSync? onSync;

  /// Includes ids of apps that have since been uninstalled; they're kept so
  /// the app stays hidden if it's reinstalled.
  Set<String> get hiddenIds => Set.unmodifiable(_hidden);

  /// Packages of the hidden apps (an id is `"<package>/<activity>"`).
  Set<String> get hiddenPackages => {for (final id in _hidden) id.split('/').first};

  bool isHidden(String appId) => _hidden.contains(appId);

  /// Whether hidden apps' notifications still show. On by default.
  bool get showNotifications => _showNotifications;

  Future<void> hide(String appId) => setHidden(appId, true);

  Future<void> unhide(String appId) => setHidden(appId, false);

  Future<void> setHidden(String appId, bool hidden) async {
    final changed = hidden ? _hidden.add(appId) : _hidden.remove(appId);
    if (!changed) return;
    notifyListeners();
    _sync();
    await _prefs.setStringList(_key, _hidden.toList()..sort());
  }

  Future<void> setShowNotifications(bool show) async {
    if (show == _showNotifications) return;
    _showNotifications = show;
    notifyListeners();
    _sync();
    await _prefs.setBool(_notificationsKey, show);
  }

  void _sync() => onSync?.call(!_showNotifications, hiddenPackages);
}
