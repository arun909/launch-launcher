import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/platform/window_blur_platform.dart';
import 'appearance_controller.dart';

/// Blurs the wallpaper while the route containing this widget is open, in step
/// with the route's open / close animation, at the user's blur level.
///
/// The blur is on the launcher's whole window (Android draws the wallpaper
/// behind it), so it's cleared again when the route closes.
class WallpaperBlur extends StatefulWidget {
  const WallpaperBlur({super.key, this.radius, required this.child});

  /// Blur radius in logical pixels; null: the user's blur level.
  final double? radius;

  final Widget child;

  /// Dark tint to put over the wallpaper. Lighter when it's actually blurred,
  /// since the blur already keeps the wallpaper from competing with the icons.
  static Color tint(BuildContext context, {required double unblurred, required double blurred}) {
    final level = context.select<AppearanceController, int>((a) => a.blurLevel);
    final supported = context.select<WindowBlurPlatform, bool>((p) => p.isSupported);
    return Colors.black.withValues(alpha: level > 0 && supported ? blurred : unblurred);
  }

  @override
  State<WallpaperBlur> createState() => _WallpaperBlurState();
}

class _WallpaperBlurState extends State<WallpaperBlur> {
  Animation<double>? _animation;
  // Nullable: absent in tests, which have no platform.
  late final WindowBlurPlatform? _platform = context.read<WindowBlurPlatform?>();
  int _sentRadius = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final animation = ModalRoute.of(context)?.animation;
    if (animation != _animation) {
      _animation?.removeListener(_update);
      _animation = animation?..addListener(_update);
    }
    _update();
  }

  @override
  void dispose() {
    _animation?.removeListener(_update);
    if (_sentRadius != 0) _platform?.setBlurRadius(0);
    super.dispose();
  }

  void _update() {
    if (!mounted) return;
    final progress = _animation?.value ?? 1;
    if (widget.radius == 0 && _sentRadius == 0) return; // Nothing to clear.
    final radius =
        (widget.radius ?? context.read<AppearanceController>().blurRadius) * MediaQuery.devicePixelRatioOf(context);
    final px = (radius * progress).round();
    if (px == _sentRadius) return;
    _sentRadius = px;
    _platform?.setBlurRadius(px);
  }

  @override
  Widget build(BuildContext context) {
    // Rebuild (and re-send) if the level changes while open.
    if (widget.radius == null) context.select<AppearanceController, int>((a) => a.blurLevel);
    WidgetsBinding.instance.addPostFrameCallback((_) => _update());
    return widget.child;
  }
}
