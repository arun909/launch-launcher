import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Dart side of the window-blur bridge. The Kotlin counterpart is
/// `android/app/src/main/kotlin/.../platform/WindowBlurChannel.kt`.
///
/// Blurs the system wallpaper behind the launcher's window, which Flutter
/// can't do itself (the wallpaper is drawn by Android, behind our surface).
class WindowBlurPlatform extends ChangeNotifier {
  static const _method = MethodChannel('com.arun.minimal_launcher/window_blur');

  bool _isSupported = false;

  /// False before Android 12, on phones whose maker hasn't enabled window blur,
  /// or while the phone has it turned off (e.g. battery saver). Call [refresh]
  /// to update it.
  bool get isSupported => _isSupported;

  Future<void> refresh() async {
    final supported = await _method.invokeMethod<bool>('isSupported') ?? false;
    if (supported == _isSupported) return;
    _isSupported = supported;
    notifyListeners();
  }

  ui.Image? _wallpaper;
  bool _wallpaperExact = false;

  /// A small copy of the wallpaper as it fills the screen, for glass folders
  /// to blur the bit behind them; null until loaded. For a live wallpaper,
  /// which apps can't see, it's the wallpaper's preview image; without photo
  /// access, a gradient of its colours. See [refreshWallpaper].
  ui.Image? get wallpaper => _wallpaper;

  /// Reloads [wallpaper]; it may have changed while the launcher was away.
  Future<void> refreshWallpaper() async {
    Map<Object?, Object?>? reply;
    try {
      reply = await _method.invokeMethod<Map<Object?, Object?>>('getWallpaper', {'width': _wallpaperWidth});
    } on PlatformException catch (e) {
      debugPrint('WindowBlurPlatform: getWallpaper failed: $e');
    }
    final bytes = reply?['png'] as Uint8List?;
    ui.Image? image;
    if (bytes != null) {
      final codec = await ui.instantiateImageCodec(bytes);
      image = (await codec.getNextFrame()).image;
      codec.dispose();
    }
    _wallpaper?.dispose();
    _wallpaper = image;
    _wallpaperExact = reply?['exact'] == true;
    notifyListeners();
  }

  /// For glass folders: asks Android for photo access, which reading a
  /// picture wallpaper needs, unless [wallpaper] is that picture already (or
  /// it's a live one, which needs none). Once allowed, it loads when the
  /// launcher is back in front (see App's onResume).
  Future<void> requestWallpaperAccess() async {
    if (_wallpaperExact) return;
    final granted = await _method.invokeMethod<bool>('requestWallpaperAccess') ?? false;
    if (granted) await refreshWallpaper(); // e.g. a live wallpaper since replaced
  }

  /// Plenty for something that's blurred anyway.
  static const _wallpaperWidth = 360;

  @override
  void dispose() {
    _wallpaper?.dispose();
    super.dispose();
  }

  /// Blur radius in physical pixels; 0 removes the blur. A no-op where
  /// unsupported.
  Future<void> setBlurRadius(int radius) => _method.invokeMethod('setBlurRadius', {'radius': radius});
}
