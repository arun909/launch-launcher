import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../../standby/art_colors.dart';

/// The wallpaper's two main colours, made bright enough to read as a
/// clock's gradient over it; null while unknown or when the wallpaper is
/// (nearly) colourless. Worked out once per wallpaper image and shared by
/// every clock.
Future<List<Color>?> wallpaperColors(ui.Image wallpaper) {
  if (identical(wallpaper, _for)) return _colors!;
  _for = wallpaper;
  return _colors = _pick(wallpaper);
}

ui.Image? _for;
Future<List<Color>?>? _colors;

/// Small is plenty for main colours, and quick.
const _w = 32, _h = 64;

Future<List<Color>?> _pick(ui.Image image) async {
  try {
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      const Rect.fromLTWH(0, 0, _w * 1.0, _h * 1.0),
      Paint()..filterQuality = FilterQuality.medium,
    );
    final picture = recorder.endRecording();
    final small = await picture.toImage(_w, _h);
    picture.dispose();
    final data = await small.toByteData(format: ui.ImageByteFormat.rawRgba);
    small.dispose();
    return data == null ? null : pickArtColors(data.buffer.asUint8List());
  } catch (_) {
    // E.g. the image was replaced (and disposed) meanwhile.
    return null;
  }
}
