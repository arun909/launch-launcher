import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../launcher_widgets.dart';
import 'tile_look.dart';

/// Draws a slider's glyph at [size], for a slider at [level] (0–1), whose
/// fill's edge crosses it [split] from its top (white above, black below;
/// the other way round on a light panel, see [paintSplit]).
typedef PillGlyphBuilder = Widget Function(double size, double level, double split);

/// A vertical pill slider (brightness, volume), filling with white (ink on
/// a light panel, see TileLook) from the bottom with a flat top edge (like
/// vivo's own). Dragging moves it by how
/// far the finger moves (it doesn't jump to the finger); a tap sets it
/// there. It swells a little while held, and stretches like rubber when
/// pulled past either end.
///
/// The glyph in its bottom's round end is a button of its own ([onGlyphTap]).
class PillSlider extends StatefulWidget {
  const PillSlider({
    super.key,
    required this.position,
    required this.label,
    required this.glyphLabel,
    required this.glyphToggled,
    required this.glyph,
    required this.dark,
    required this.onStart,
    required this.onChanged,
    required this.onEnd,
    required this.onGlyphTap,
    this.steps = 20,
  });

  /// A light tick each time the slider crosses one of this many steps, and
  /// a firmer one at either end.
  final int steps;

  /// 0 (bottom) to 1 (top).
  final double position;
  final String label;
  final String glyphLabel;
  final bool glyphToggled;
  final PillGlyphBuilder glyph;
  final bool dark;
  final VoidCallback onStart;
  final ValueChanged<double> onChanged;
  final VoidCallback onEnd;
  final VoidCallback onGlyphTap;

  @override
  State<PillSlider> createState() => _PillSliderState();
}

class _PillSliderState extends State<PillSlider> {
  /// Where the drag has the slider, unclamped: past 0 or 1 is overscroll.
  double? _drag;

  /// Most the slider stretches when pulled past an end, as a fraction.
  static const _maxStretch = 0.06;

  /// How far the finger moves before it's a drag (Flutter's default is 18).
  static const _slop = 3.0;

  void _start() {
    _drag = widget.position;
    widget.onStart();
  }

  void _move(double raw) {
    final before = (_drag ?? widget.position).clamp(0.0, 1.0);
    final after = raw.clamp(0.0, 1.0);
    if (after != before) {
      if (after == 0 || after == 1) {
        HapticFeedback.mediumImpact();
      } else if ((after * widget.steps).round() != (before * widget.steps).round()) {
        HapticFeedback.lightImpact();
      }
    }
    setState(() => _drag = raw);
    if (after != before) widget.onChanged(after);
  }

  void _finish() {
    if (_drag == null) return;
    setState(() => _drag = null);
    widget.onEnd();
  }

  @override
  Widget build(BuildContext context) {
    final raw = _drag ?? widget.position;
    final value = raw.clamp(0.0, 1.0);
    // Pulled past an end: stretch towards the pull, easing off the further it goes.
    final over = raw - value;
    final stretch = _maxStretch * (1 - math.exp(-over.abs() * 4));
    final held = _drag != null;
    final light = PanelInk.lightOf(context);
    return Semantics(
      label: widget.label,
      slider: true,
      value: '${(value * 100).round()}%',
      child: LayoutBuilder(
        builder: (context, box) {
          final w = box.maxWidth;
          final h = box.maxHeight;
          final fill = h * value;
          // The glyph: in the bottom's round end.
          final glyph = w * 0.56;
          final glyphInset = (w - glyph) / 2;
          void tapUp(TapUpDetails d) {
            if (d.localPosition.dy > h - w) {
              HapticFeedback.lightImpact();
              widget.onGlyphTap();
              return;
            }
            _start();
            _move(1 - d.localPosition.dy / h);
            _finish();
          }

          return RawGestureDetector(
            behavior: HitTestBehavior.opaque,
            gestures: {
              // Takes the finger after a tiny movement, before the
              // home screen's long press (to move the widget) can, so a slow or careful drag still adjusts it.
              VerticalDragGestureRecognizer: GestureRecognizerFactoryWithHandlers<VerticalDragGestureRecognizer>(
                VerticalDragGestureRecognizer.new,
                (r) => r
                  ..gestureSettings = const DeviceGestureSettings(touchSlop: _slop)
                  ..onStart = ((_) => _start())
                  ..onUpdate = ((d) => _move((_drag ?? value) - d.delta.dy / h))
                  ..onEnd = ((_) => _finish())
                  ..onCancel = _finish,
              ),
              TapGestureRecognizer: GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
                TapGestureRecognizer.new,
                (r) => r.onTapUp = tapUp,
              ),
            },
            child: TweenAnimationBuilder<double>(
              // Follows the finger; springs back when let go.
              tween: Tween(end: stretch * (over >= 0 ? 1 : -1)),
              duration: held ? Duration.zero : const Duration(milliseconds: 420),
              curve: Curves.elasticOut,
              builder: (context, s, child) => Transform(
                alignment: s >= 0 ? Alignment.bottomCenter : Alignment.topCenter,
                transform: Matrix4.diagonal3Values(1, 1 + s.abs(), 1),
                child: child,
              ),
              child: AnimatedScale(
                scale: held ? 1.03 : 1,
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOut,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(w / 2),
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: ColoredBox(color: TileLook.part(false, widget.dark, light: light)),
                      ),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        height: fill,
                        child: ColoredBox(color: TileLook.part(true, widget.dark, light: light)),
                      ),
                      Positioned(
                        left: glyphInset,
                        bottom: glyphInset,
                        child: Semantics(
                          button: true,
                          toggled: widget.glyphToggled,
                          label: widget.glyphLabel,
                          // Where the fill's edge crosses it, from its top.
                          child: widget.glyph(glyph, value, glyph - (fill - glyphInset)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Paints [draw] white above [split] (from the top) and black below it, so
/// a glyph changes colour exactly where the slider's fill crosses it. On a
/// [light] panel: ink above, white below (TileLook.content).
void paintSplit(Canvas canvas, Size size, double split, void Function(Color color) draw, {bool light = false}) {
  final rect = Offset.zero & size;
  final at = split.clamp(0.0, size.height);
  for (final (part, color) in [
    (
      Rect.fromLTRB(rect.left - size.width, rect.top - size.height, rect.right + size.width, at),
      TileLook.content(false, light: light),
    ),
    (
      Rect.fromLTRB(rect.left - size.width, at, rect.right + size.width, rect.bottom + size.height),
      TileLook.content(true, light: light),
    ),
  ]) {
    if (part.height <= 0) continue;
    canvas
      ..save()
      ..clipRect(part);
    draw(color);
    canvas.restore();
  }
}
