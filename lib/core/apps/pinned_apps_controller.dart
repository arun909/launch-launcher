import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A small, user-chosen, ordered list of app ids stored in prefs (the home
/// grid, the dock). Subclass per surface so each gets its own provider type.
///
/// Stores ids only. Surfaces resolve them through VisibleApps, so a pinned
/// app that is hidden or uninstalled simply isn't shown.
abstract class PinnedAppsController extends ChangeNotifier {
  PinnedAppsController(this._prefs, {required String key, required this._maxApps})
    : _key = key,
      _ids = _prefs.getStringList(key) ?? [];

  final SharedPreferences _prefs;
  final String _key;
  final int _maxApps;
  final List<String> _ids;

  /// Most apps the list holds. Subclasses may make it change over time (see
  /// [trimTo]).
  int get maxApps => _maxApps;

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

  /// Puts [order] first, in that order. Pinned ids missing from it (e.g.
  /// hidden apps a screen didn't show) keep their relative order after it.
  Future<void> reorder(List<String> order) async {
    final front = order.where(_ids.contains).toList();
    final rest = _ids.where((id) => !front.contains(id)).toList();
    _ids
      ..clear()
      ..addAll([...front, ...rest]);
    await _save();
  }

  /// Drag and drop: puts [appId] at [index] of [shown] (the pinned apps a
  /// surface shows, in order), moving it if it's already pinned. Into a full
  /// list it takes the place of the app at [index], which is unpinned and
  /// returned.
  Future<String?> placeAt(String appId, int index, List<String> shown) async {
    final order = shown.where((id) => id != appId).toList();
    String? replaced;
    if (!isPinned(appId) && isFull) {
      if (order.isEmpty) return null;
      replaced = order.removeAt(index.clamp(0, order.length - 1));
      _ids.remove(replaced);
    }
    order.insert(math.min(index, order.length).clamp(0, order.length), appId);
    if (!_ids.contains(appId)) _ids.add(appId);
    final rest = _ids.where((id) => !order.contains(id)).toList();
    _ids
      ..clear()
      ..addAll([...order, ...rest]);
    await _save();
    return replaced;
  }

  /// Unpins apps from the end until at most [max] are left. Where they go is
  /// up to the surface: the home screen keeps their old spots.
  @protected
  Future<void> trimTo(int max) async {
    if (_ids.length <= max) return;
    _ids.removeRange(max, _ids.length);
    await _save();
  }

  Future<void> _save() async {
    notifyListeners();
    await _prefs.setStringList(_key, _ids);
  }
}
