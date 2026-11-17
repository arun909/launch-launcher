import 'package:flutter/foundation.dart';

import '../../core/platform/instant_platform.dart';

/// "Full-screen button": a small floating button over web browsers; a tap
/// shows the page full screen (no address bar) right over the browser,
/// another tap goes back to it. It's an Android accessibility service, so whether it's on
/// is read back from Android ([refresh]), not kept here.
class FullScreenWebController extends ChangeNotifier {
  FullScreenWebController(this._platform) {
    refresh();
  }

  final InstantPlatform _platform;
  bool _on = false;

  bool get isOn => _on;

  /// Re-reads it (it can also be switched in Android's settings).
  Future<void> refresh() async {
    final on = await _platform.browserButton();
    if (on == _on) return;
    _on = on;
    notifyListeners();
  }

  /// Turns it on or off. False if Android's accessibility settings had to be
  /// opened instead, for the user to switch it there.
  Future<bool> setOn(bool value) async {
    if (await _platform.setBrowserButton(value)) {
      _on = value;
      notifyListeners();
      return true;
    }
    await _platform.openBrowserButtonSettings();
    return false;
  }
}
