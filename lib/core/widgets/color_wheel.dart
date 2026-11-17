import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A colour picker: a hue / saturation wheel, a brightness slider under it,
/// and the colour's hex value, which can be typed in.
///
/// [onChangeStart] / [onChangeEnd] bracket a drag (of the wheel or the
/// slider), so a caller can save once at the end rather than on every step.
class ColorWheel extends StatefulWidget {
  const ColorWheel({
    super.key,
    required this.color,
    required this.onChanged,
    this.onChangeStart,
    this.onChangeEnd,
    this.size = 220,
  });

  final Color color;
  final ValueChanged<Color> onChanged;
  final VoidCallback? onChangeStart;
  final VoidCallback? onChangeEnd;

  /// The wheel's diameter.
  final double size;

  /// "RRGGBB" for [c] (no alpha, upper case).
  static String hexOf(Color c) => (c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase();

  /// The opaque colour for "RRGGBB", "#RRGGBB", "RGB" or "#RGB"; null if
  /// it isn't one.
  static Color? parseHex(String text) {
    var hex = text.trim().replaceFirst('#', '');
    if (hex.length == 3) hex = hex.split('').map((c) => '$c$c').join();
    if (hex.length != 6) return null;
    final v = int.tryParse(hex, radix: 16);
    return v == null ? null : Color(0xFF000000 | v);
  }

  @override
  State<ColorWheel> createState() => _ColorWheelState();
}

class _ColorWheelState extends State<ColorWheel> {
  /// Kept as HSV, not re-derived from the colour each time: a grey (no
  /// saturation) or black (no brightness) would otherwise lose its hue and
  /// the thumb would jump.
  late HSVColor _hsv = HSVColor.fromColor(widget.color);

  @override
  void didUpdateWidget(ColorWheel old) {
    super.didUpdateWidget(old);
    if (widget.color.toARGB32() != _hsv.toColor().toARGB32()) _hsv = HSVColor.fromColor(widget.color);
  }

  void _set(HSVColor hsv) {
    setState(() => _hsv = hsv);
    widget.onChanged(hsv.toColor());
  }

  void _pick(Offset local) {
    final r = widget.size / 2;
    final d = local - Offset(r, r);
    final hue = (math.atan2(d.dy, d.dx) * 180 / math.pi + 360) % 360;
    _set(_hsv.withHue(hue).withSaturation((d.distance / r).clamp(0.0, 1.0)));
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.size / 2;
    final angle = _hsv.hue * math.pi / 180;
    final thumb = Offset(r + math.cos(angle) * _hsv.saturation * r, r + math.sin(angle) * _hsv.saturation * r);
    final full = _hsv.withValue(1).withSaturation(math.max(_hsv.saturation, 0.0001)).toColor();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Takes the touch at once: in a scrolling sheet, a drag on the wheel
        // picks a colour rather than scrolling or closing the sheet.
        RawGestureDetector(
          gestures: {
            _EagerPan: GestureRecognizerFactoryWithHandlers<_EagerPan>(
              _EagerPan.new,
              (r) => r
                ..dragStartBehavior = DragStartBehavior.down
                ..onStart = (d) {
                  widget.onChangeStart?.call();
                  _pick(d.localPosition);
                }
                ..onUpdate = (d) {
                  _pick(d.localPosition);
                }
                ..onEnd = (_) {
                  widget.onChangeEnd?.call();
                }
                ..onCancel = () {
                  widget.onChangeEnd?.call();
                },
            ),
          },
          child: SizedBox.square(
            dimension: widget.size,
            child: CustomPaint(
              painter: _WheelPainter(value: _hsv.value),
              child: Stack(
                children: [
                  Positioned(
                    left: thumb.dx - 14,
                    top: thumb.dy - 14,
                    child: IgnorePointer(
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: _hsv.toColor(),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 3),
                          boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 6)],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            const Icon(Icons.brightness_6_rounded, size: 20, color: Colors.white70),
            const SizedBox(width: 8),
            Expanded(
              child: _GradientSlider(
                value: _hsv.value,
                colors: [Colors.black, full],
                onChangeStart: widget.onChangeStart,
                onChangeEnd: widget.onChangeEnd,
                onChanged: (v) => _set(_hsv.withValue(v)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _HexField(color: _hsv.toColor(), onChanged: (c) => _set(HSVColor.fromColor(c))),
      ],
    );
  }
}

/// A pan that wins the touch as soon as it lands.
class _EagerPan extends PanGestureRecognizer {
  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    resolve(GestureDisposition.accepted);
  }
}

/// Every hue around the edge, white at the centre, darkened to [value].
class _WheelPainter extends CustomPainter {
  _WheelPainter({required this.value});

  final double value;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final rect = Rect.fromCircle(center: center, radius: size.shortestSide / 2);
    canvas.drawCircle(
      center,
      rect.width / 2,
      Paint()
        ..shader = SweepGradient(
          colors: [for (var h = 0; h <= 360; h += 60) HSVColor.fromAHSV(1, h % 360, 1, 1).toColor()],
        ).createShader(rect),
    );
    canvas.drawCircle(
      center,
      rect.width / 2,
      Paint()..shader = const RadialGradient(colors: [Colors.white, Color(0x00FFFFFF)]).createShader(rect),
    );
    if (value < 1) {
      canvas.drawCircle(center, rect.width / 2, Paint()..color = Colors.black.withValues(alpha: 1 - value));
    }
    canvas.drawCircle(
      center,
      rect.width / 2,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = Colors.white24,
    );
  }

  @override
  bool shouldRepaint(_WheelPainter old) => old.value != value;
}

/// A slider on a track painted with [colors].
class _GradientSlider extends StatelessWidget {
  const _GradientSlider({
    required this.value,
    required this.colors,
    required this.onChanged,
    this.onChangeStart,
    this.onChangeEnd,
  });

  final double value;
  final List<Color> colors;
  final ValueChanged<double> onChanged;
  final VoidCallback? onChangeStart;
  final VoidCallback? onChangeEnd;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          height: 14,
          margin: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: colors),
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: Colors.white24),
          ),
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: Colors.transparent,
            inactiveTrackColor: Colors.transparent,
            thumbColor: Colors.white,
            overlayColor: Colors.white24,
            trackHeight: 14,
          ),
          child: Slider(
            value: value,
            onChanged: onChanged,
            onChangeStart: onChangeStart == null ? null : (_) => onChangeStart!(),
            onChangeEnd: onChangeEnd == null ? null : (_) => onChangeEnd!(),
          ),
        ),
      ],
    );
  }
}

/// "# [RRGGBB]": shows [color]'s hex value; a valid one typed in is applied
/// as it's typed.
class _HexField extends StatefulWidget {
  const _HexField({required this.color, required this.onChanged});

  final Color color;
  final ValueChanged<Color> onChanged;

  @override
  State<_HexField> createState() => _HexFieldState();
}

class _HexFieldState extends State<_HexField> {
  late final _controller = TextEditingController(text: ColorWheel.hexOf(widget.color));
  final _focus = FocusNode();
  bool _invalid = false;

  @override
  void initState() {
    super.initState();
    // Left half-typed: back to the colour's own value.
    _focus.addListener(() {
      if (!_focus.hasFocus) _show(widget.color);
    });
  }

  @override
  void didUpdateWidget(_HexField old) {
    super.didUpdateWidget(old);
    // Picked on the wheel: shown here, unless it's being typed.
    if (!_focus.hasFocus && old.color != widget.color) _show(widget.color);
  }

  void _show(Color c) {
    _controller.text = ColorWheel.hexOf(c);
    if (_invalid) setState(() => _invalid = false);
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: widget.color,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white24),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: TextField(
            controller: _controller,
            focusNode: _focus,
            maxLength: 7,
            textCapitalization: TextCapitalization.characters,
            autocorrect: false,
            enableSuggestions: false,
            style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()], letterSpacing: 1.5),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp('[#0-9a-fA-F]'))],
            decoration: InputDecoration(
              prefixText: '# ',
              labelText: 'Hex',
              counterText: '',
              isDense: true,
              border: const OutlineInputBorder(),
              errorText: _invalid ? 'Six hex digits, like FF9F0A' : null,
            ),
            onChanged: (text) {
              final c = ColorWheel.parseHex(text);
              setState(() => _invalid = c == null && text.replaceFirst('#', '').length >= 6);
              if (c != null && text.replaceFirst('#', '').length == 6) widget.onChanged(c);
            },
            onSubmitted: (text) {
              final c = ColorWheel.parseHex(text);
              if (c != null) {
                widget.onChanged(c);
                _show(c);
              } else {
                setState(() => _invalid = true);
              }
            },
          ),
        ),
      ],
    );
  }
}
