import 'package:flutter/foundation.dart';

import '../platform/launcher_platform.dart';

/// Whether Android currently uses this app as the home screen.
///
/// As the home screen, Back must never exit. Opened as a normal app (for
/// example just to manage hidden or system apps), Back exits as usual.
class HomeRoleController extends ChangeNotifier {
  HomeRoleController(this._platform) {
    refresh();
  }

  final LauncherPlatform _platform;

  // Assume home until we know: blocking Back briefly is harmless, while
  // exiting the home screen is not.
  bool _isDefaultHome = true;

  bool get isDefaultHome => _isDefaultHome;

  Future<void> refresh() async {
    try {
      final value = await _platform.isDefaultHome();
      if (value != _isDefaultHome) {
        _isDefaultHome = value;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('HomeRoleController: isDefaultHome failed: $e');
    }
  }
}
