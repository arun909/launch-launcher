import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Height steps of the search widget, smallest first.
enum SearchWidgetHeight {
  compact('Compact', 48), // Material's minimum touch target
  standard('Standard', 56), // Material 3 search bar height
  large('Large', 64);

  const SearchWidgetHeight(this.label, this.dp);

  final String label;
  final double dp;
}

/// The home-screen search widget: whether it's shown, and its size.
///
/// Sized like an Android home-screen widget: it spans whole columns of the
/// same 4-column grid as the pinned apps ([startColumn] + [columns]), and its
/// height snaps between [SearchWidgetHeight] steps. [isResizing] is the
/// transient "resize handles showing" state and is not saved.
class SearchWidgetController extends ChangeNotifier {
  SearchWidgetController(this._prefs)
    : _visible = _prefs.getBool(_visibleKey) ?? true,
      _start = (_prefs.getInt(_startKey) ?? 0).clamp(0, gridColumns - 1),
      _height = SearchWidgetHeight.values.asNameMap()[_prefs.getString(_heightKey)] ?? SearchWidgetHeight.standard {
    _columns = (_prefs.getInt(_columnsKey) ?? gridColumns).clamp(1, gridColumns - _start);
  }

  static const gridColumns = 4;
  static const _visibleKey = 'search_widget_visible';
  static const _startKey = 'search_widget_start';
  static const _columnsKey = 'search_widget_columns';
  static const _heightKey = 'search_widget_height';

  final SharedPreferences _prefs;
  bool _visible;
  int _start;
  late int _columns;
  SearchWidgetHeight _height;
  bool _resizing = false;

  bool get isVisible => _visible;

  /// First grid column the widget covers (0 = leftmost).
  int get startColumn => _start;

  /// Number of grid columns the widget covers (1 to [gridColumns]).
  int get columns => _columns;

  SearchWidgetHeight get height => _height;

  bool get isResizing => _resizing;

  /// Short size description, e.g. "4 × 1 · Standard".
  String get sizeLabel => '$_columns × 1 · ${_height.label}';

  Future<void> setVisible(bool visible) async {
    if (visible == _visible) return;
    _visible = visible;
    if (!visible) _resizing = false;
    notifyListeners();
    await _prefs.setBool(_visibleKey, visible);
  }

  void startResizing() {
    if (!_visible || _resizing) return;
    _resizing = true;
    notifyListeners();
  }

  void stopResizing() {
    if (!_resizing) return;
    _resizing = false;
    notifyListeners();
  }

  /// Moves the left edge to grid line [column], keeping the right edge fixed.
  /// The widget always keeps at least one column.
  Future<void> moveLeftEdge(int column) {
    final end = _start + _columns;
    final start = column.clamp(0, end - 1);
    return _setSpan(start, end - start);
  }

  /// Moves the right edge to grid line [column], keeping the left edge fixed.
  Future<void> moveRightEdge(int column) {
    final end = column.clamp(_start + 1, gridColumns);
    return _setSpan(_start, end - _start);
  }

  Future<void> setHeight(SearchWidgetHeight height) async {
    if (height == _height) return;
    _height = height;
    notifyListeners();
    await _prefs.setString(_heightKey, height.name);
  }

  /// Back to the default full-width, standard-height bar.
  Future<void> resetSize() async {
    await _setSpan(0, gridColumns);
    await setHeight(SearchWidgetHeight.standard);
  }

  Future<void> _setSpan(int start, int columns) async {
    if (start == _start && columns == _columns) return;
    _start = start;
    _columns = columns;
    notifyListeners();
    await _prefs.setInt(_startKey, start);
    await _prefs.setInt(_columnsKey, columns);
  }
}
