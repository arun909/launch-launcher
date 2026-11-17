import 'package:shared_preferences/shared_preferences.dart';

import '../../core/apps/pinned_apps_controller.dart';
import '../standard_home/home_layout.dart';
import '../standard_home/home_layout_controller.dart';

/// Apps in the dock at the bottom of the home screen.
///
/// Holds as many apps as the home grid allows (see HomeGrid.dockApps): 6 with
/// the 6-column grid, otherwise 5. Switching to a smaller grid unpins the
/// apps past the new limit, which go back to their spots on the home screen.
class DockController extends PinnedAppsController {
  DockController(super.prefs, [this._layout])
    : _prefs = prefs,
      _style = GroupStyle.values.asNameMap()[prefs.getString(_styleKey)] ?? GroupStyle.light,
      _fitToApps = prefs.getBool(_fitKey) ?? false,
      super(key: 'dock_app_ids', maxApps: _defaultMax) {
    _layout?.addListener(_onLayout);
    _onLayout();
  }

  static const _defaultMax = 5;
  static const _styleKey = 'dock_style';
  static const _fitKey = 'dock_fit';

  final SharedPreferences _prefs;
  GroupStyle _style;

  /// The bar's background: light, dark or glass blur, as a group's.
  GroupStyle get style => _style;

  Future<void> setStyle(GroupStyle style) async {
    if (style == _style) return;
    _style = style;
    notifyListeners();
    await _prefs.setString(_styleKey, style.name);
  }

  bool _fitToApps;

  /// The bar only as wide as its apps need, centred; else the grid's width.
  bool get fitToApps => _fitToApps;

  Future<void> setFitToApps(bool fit) async {
    if (fit == _fitToApps) return;
    _fitToApps = fit;
    notifyListeners();
    await _prefs.setBool(_fitKey, fit);
  }

  final HomeLayoutController? _layout;

  /// The limit last applied.
  int _max = 0;

  @override
  int get maxApps => _layout?.grid.dockApps ?? _defaultMax;

  void _onLayout() {
    final max = maxApps;
    if (max == _max) return;
    _max = max;
    if (ids.length > max) {
      trimTo(max);
    } else {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _layout?.removeListener(_onLayout);
    super.dispose();
  }
}
