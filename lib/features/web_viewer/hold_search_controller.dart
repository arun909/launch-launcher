import 'package:flutter/foundation.dart';

import '../../core/platform/instant_platform.dart';

/// "Hold to search": touch and hold the bottom centre of the screen in any
/// app for a small search panel; the results show in a floating card over
/// that app, with a full-screen button. It lives in the same accessibility
/// service as the full-screen button, so whether it's on is read back from
/// Android ([refresh]), not kept here.
class HoldSearchController extends ChangeNotifier {
  HoldSearchController(this._platform) {
    refresh();
  }

  final InstantPlatform _platform;
  bool _on = false;

  bool get isOn => _on;

  Future<void> refresh() async {
    final on = await _platform.holdSearch();
    if (on == _on) return;
    _on = on;
    notifyListeners();
  }

  /// False if Android's accessibility settings had to be opened instead.
  Future<bool> setOn(bool value) async {
    if (await _platform.setHoldSearch(value)) {
      _on = value;
      notifyListeners();
      return true;
    }
    await _platform.openBrowserButtonSettings();
    return false;
  }
}
