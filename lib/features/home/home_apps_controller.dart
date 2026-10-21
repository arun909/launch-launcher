import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The small, user-chosen set of apps pinned to the home screen (ordered).
///
/// Stores ids only. The home screen resolves them through VisibleApps, so a
/// pinned app that is hidden or uninstalled simply isn't shown.
class HomeAppsController extends ChangeNotifier {
  HomeAppsController(this._prefs) : _ids = _prefs.getStringList(_key) ?? [];

  static const _key = 'home_app_ids';
  static const maxApps = 8;

  final SharedPreferences _prefs;
  final List<String> _ids;

  List<String> get ids => List.unmodifiable(_ids);

  bool isPinned(String appId) => _ids.contains(appId);

  bool get isFull => _ids.length >= maxApps;

  Future<void> pin(String appId) async {
    if (isPinned(appId) || isFull) return;
    _ids.add(appId);
    await _save();
  }

  Future<void> unpin(String appId) async {
    if (_ids.remove(appId)) await _save();
  }

  Future<void> _save() async {
    notifyListeners();
    await _prefs.setStringList(_key, _ids);
  }
}
