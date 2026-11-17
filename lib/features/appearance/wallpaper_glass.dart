import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../core/platform/window_blur_platform.dart';

/// Frosted glass in [shape] behind [child]: the wallpaper right behind it,
/// heavily blurred, plus whatever Flutter draws behind it.
///
/// Android draws the wallpaper behind the launcher's window, out of a
/// BackdropFilter's reach, so this paints its own blurred copy of that bit
/// of wallpaper (WindowBlurPlatform.wallpaper: the picture, a live
/// wallpaper's preview, or a gradient of its colours). Until that's loaded
/// it's a BackdropFilter only.
class WallpaperGlass extends StatelessWidget {
  const WallpaperGlass({super.key, required this.shape, this.sigma = 15, required this.child});

  final ShapeBorder shape;
  final double sigma;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // Nullable: absent in tests, which have no platform.
    final wallpaper = context.select<WindowBlurPlatform?, ui.Image?>((p) => p?.wallpaper);
    return ClipPath(
      clipper: ShapeBorderClipper(shape: shape),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
        child: wallpaper == null
            // Not loaded yet: frost it more instead.
            ? DecoratedBox(
                decoration: const BoxDecoration(color: Color(0x1FFFFFFF)),
                child: child,
              )
            : _WallpaperPatch(image: wallpaper, screen: MediaQuery.sizeOf(context), sigma: sigma, child: child),
      ),
    );
  }
}

class _WallpaperPatch extends SingleChildRenderObjectWidget {
  const _WallpaperPatch({required this.image, required this.screen, required this.sigma, super.child});

  final ui.Image image;
  final Size screen;
  final double sigma;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderWallpaperPatch(image, screen, sigma);

  @override
  void updateRenderObject(BuildContext context, _RenderWallpaperPatch renderObject) => renderObject
    ..image = image
    ..screen = screen
    ..sigma = sigma;
}

/// Paints the screen-sized [image] lined up with the screen, blurred, under
/// its child. Where it sits on screen can change without it repainting
/// (a page scrolled, a route animating), so after every frame it checks,
/// and repaints if it has moved. Idle, there are no frames and no checks.
class _RenderWallpaperPatch extends RenderProxyBox {
  _RenderWallpaperPatch(this._image, this._screen, this._sigma);

  ui.Image _image;
  set image(ui.Image v) {
    if (v == _image) return;
    _image = v;
    markNeedsPaint();
  }

  Size _screen;
  set screen(Size v) {
    if (v == _screen) return;
    _screen = v;
    markNeedsPaint();
  }

  double _sigma;
  set sigma(double v) {
    if (v == _sigma) return;
    _sigma = v;
    markNeedsPaint();
  }

  /// Local-to-screen transform as last painted.
  Matrix4? _painted;
  bool _watching = false;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _watch();
  }

  void _watch() {
    if (_watching) return;
    _watching = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _watching = false;
      if (!attached) return;
      if (_painted != null && hasSize && getTransformTo(null) != _painted) markNeedsPaint();
      _watch();
    });
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final toScreen = getTransformTo(null);
    _painted = toScreen;
    final fromScreen = Matrix4.tryInvert(toScreen);
    if (fromScreen != null) {
      final canvas = context.canvas;
      final bounds = offset & size;
      canvas
        ..save()
        ..clipRect(bounds)
        ..translate(offset.dx, offset.dy)
        ..transform(fromScreen.storage);
      // Now in screen coordinates: the wallpaper fills the screen.
      final screenRect = Offset.zero & _screen;
      final src = Offset.zero & Size(_image.width.toDouble(), _image.height.toDouble());
      final spot = MatrixUtils.transformRect(toScreen, Offset.zero & size);
      canvas
        ..saveLayer(
          // Just its own spot (and what blurs into it), not the whole screen.
          spot.inflate(_sigma * 3),
          Paint()..imageFilter = ui.ImageFilter.blur(sigmaX: _sigma, sigmaY: _sigma, tileMode: TileMode.clamp),
        )
        ..drawImageRect(_image, src, screenRect, Paint()..filterQuality = FilterQuality.low)
        ..restore();
      canvas.restore();
    }
    super.paint(context, offset);
  }
}
