import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persisted set of hidden app ids.
///
/// Hiding is purely cosmetic: it only affects what this launcher displays.
/// It does not stop, disable or uninstall the app.
class HiddenAppsController extends ChangeNotifier {
  HiddenAppsController(this._prefs) : _hidden = (_prefs.getStringList(_key) ?? const []).toSet();

  static const _key = 'hidden_app_ids';

  final SharedPreferences _prefs;
  final Set<String> _hidden;

  /// Includes ids of apps that have since been uninstalled; they're kept so
  /// the app stays hidden if it's reinstalled.
  Set<String> get hiddenIds => Set.unmodifiable(_hidden);

  bool isHidden(String appId) => _hidden.contains(appId);

  Future<void> hide(String appId) => setHidden(appId, true);

  Future<void> unhide(String appId) => setHidden(appId, false);

  Future<void> setHidden(String appId, bool hidden) async {
    final changed = hidden ? _hidden.add(appId) : _hidden.remove(appId);
    if (!changed) return;
    notifyListeners();
    await _prefs.setStringList(_key, _hidden.toList()..sort());
  }
}
