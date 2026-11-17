import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/apps/apps_controller.dart';
import '../../core/models/icon_shape.dart';
import '../../core/models/icon_style.dart';

/// User-chosen look of the launcher. Stored in the launcher's own prefs only;
/// nothing here touches phone-wide settings.
class AppearanceController extends ChangeNotifier {
  AppearanceController(this._prefs, this._apps)
    : _iconShape = savedIconShape(_prefs),
      _customRadius = _prefs.getInt(_customRadiusKey) ?? IconShape.maxRadius,
      _blurLevel = _prefs.getInt(_blurLevelKey) ?? defaultBlurLevel;

  static const _iconShapeKey = 'icon_shape';
  static const _iconStyleKey = 'icon_style';
  static const _iconOverridesKey = 'icon_overrides';
  static const _customRadiusKey = 'icon_custom_radius';
  static const _blurLevelKey = 'background_blur_level';

  /// Wallpaper blur behind the drawer and search, 0 (off) to 100.
  static const defaultBlurLevel = 50;

  /// Blur radius at level 100, in logical pixels.
  static const maxBlurRadius = 80.0;

  /// Read before the app list loads, so icons are rendered in the right shape
  /// from the first fetch.
  static IconShape savedIconShape(SharedPreferences prefs) => IconShape.decode(prefs.getString(_iconShapeKey));

  static IconStyle savedIconStyle(SharedPreferences prefs) => IconStyle.decode(prefs.getString(_iconStyleKey));

  /// Per-app icon choices: app id -> `original` or `<pack>:<icon name>`.
  static Map<String, String> savedIconOverrides(SharedPreferences prefs) {
    try {
      final raw = jsonDecode(prefs.getString(_iconOverridesKey) ?? '{}') as Map<String, dynamic>;
      return raw.map((k, v) => MapEntry(k, v as String));
    } catch (_) {
      return const {};
    }
  }

  final SharedPreferences _prefs;
  final AppsController _apps;
  IconShape _iconShape;
  int _customRadius;
  int _blurLevel;

  IconShape get iconShape => _iconShape;

  /// Last radius picked, kept while "System default" is selected so switching
  /// back restores it.
  int get customRadius => _customRadius;

  int get blurLevel => _blurLevel;

  /// Blur radius in logical pixels for the current [blurLevel].
  double get blurRadius => maxBlurRadius * _blurLevel / 100;

  Future<void> setBlurLevel(int level) async {
    level = level.clamp(0, 100);
    if (level == _blurLevel) return;
    _blurLevel = level;
    notifyListeners();
    await _prefs.setInt(_blurLevelKey, level);
  }

  /// Owned by [AppsController], which renders with it; persisted here.
  IconStyle get iconStyle => _apps.iconStyle;

  Map<String, String> get iconOverrides => _apps.iconOverrides;

  Future<void> setIconStyle(IconStyle style) async {
    if (style == iconStyle) return;
    final rendering = _apps.setIconStyle(style);
    notifyListeners();
    await _prefs.setString(_iconStyleKey, style.encode());
    await rendering;
  }

  /// [override] is `original`, `<pack>:<icon name>`, or null for the style's own icon.
  Future<void> setIconOverride(String appId, String? override) async {
    final rendering = _apps.setIconOverride(appId, override);
    notifyListeners();
    await _saveOverrides();
    await rendering;
  }

  Future<void> clearIconOverrides() async {
    final rendering = _apps.clearIconOverrides();
    notifyListeners();
    await _saveOverrides();
    await rendering;
  }

  /// Back to the app's own icons in the phone's shape, keeping custom icons.
  Future<void> resetIcons() async {
    await setIconShape(IconShape.system);
    await setIconStyle(IconStyle.defaults);
  }

  Future<void> _saveOverrides() => _prefs.setString(_iconOverridesKey, jsonEncode(_apps.iconOverrides));

  Future<void> setIconShape(IconShape shape) async {
    if (shape == _iconShape) return;
    _iconShape = shape;
    if (shape.radius case final r?) {
      _customRadius = r;
      await _prefs.setInt(_customRadiusKey, r);
    }
    notifyListeners();
    await _prefs.setString(_iconShapeKey, shape.encode());
    await _apps.setIconShape(shape);
  }
}
