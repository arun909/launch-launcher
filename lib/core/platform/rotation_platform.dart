import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Dart side of the rotation bridge. The Kotlin counterpart is
/// `android/app/src/main/kotlin/.../platform/RotationChannel.kt`.
///
/// The launcher no longer rotates on its own; Android reports when the phone
/// is held in another orientation, and the screen turns only after [rotate].
class RotationPlatform extends ChangeNotifier {
  RotationPlatform() {
    _method.setMethodCallHandler((call) async {
      if (call.method != 'onSuggestion') return;
      final value = call.arguments == true;
      if (value == _suggested) return;
      _suggested = value;
      notifyListeners();
    });
  }

  static const _method = MethodChannel('com.arun.minimal_launcher/rotation');

  bool _suggested = false;

  /// True while the phone is held in an orientation the screen isn't in.
  bool get suggested => _suggested;

  /// Turns the screen to match how the phone is held.
  Future<void> rotate() => _method.invokeMethod('rotate');

  @override
  void dispose() {
    _method.setMethodCallHandler(null);
    super.dispose();
  }
}
