import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../launcher_widgets.dart';
import 'display_controller.dart';
import 'pill_slider.dart';
import 'tile_look.dart';

/// The brightness widget: 2 × 2, on glass, a dark or a Material panel.
const brightnessKind = LauncherWidgetKind(
  name: 'brightness',
  label: 'Brightness',
  description: 'Brightness slider with auto brightness, night mode, extra dim and the theme',
  icon: Icons.brightness_6_outlined,
  size: (2, 2),
  min: (2, 2),
  max: (2, 2),
  sizes: [(2, 2)],
  build: _build,
  customise: showControlsSettings,
  styleOf: controlsStyleOf,
  interactive: true,
);

Widget _build(BuildContext context, Map<String, dynamic> settings) => BrightnessTile(dark: controlsDark(settings));

/// Brightness, OriginOS style: a tall pill slider filling with white from
/// the bottom, whose sun turns auto brightness on and off, and beside it
/// three round buttons: night mode (night light), extra dim, and the dark /
/// light theme. Fills the widget's panel (the panel is drawn around it).
class BrightnessTile extends StatelessWidget {
  const BrightnessTile({super.key, this.dark = false});

  /// On a dark panel (else glass; a light one is PanelInk's).
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final display = context.watch<DisplayController>();
    final s = display.state;
    return LayoutBuilder(
      builder: (context, box) {
        // In proportion to its size: one spacing between the two columns,
        // the slider filling the left one, three buttons down the right as
        // big as they fit.
        final size = math.min(box.maxWidth, box.maxHeight);
        final space = size * 0.08;
        final column = (box.maxWidth - space) / 2;
        final button = math.min(column, (box.maxHeight - 2 * space) / 3);
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: column,
              // The sun at its bottom is also auto brightness: tap it to
              // turn auto on (an "A" appears in the sun) or off.
              child: PillSlider(
                position: display.brightnessPosition,
                label: 'Brightness',
                glyphLabel: 'Auto brightness',
                glyphToggled: s.autoBrightness,
                glyph: (size, level, split) => _Sun(
                  size: size,
                  level: level,
                  auto: s.autoBrightness,
                  split: split,
                  light: PanelInk.lightOf(context),
                ),
                dark: dark,
                onStart: display.startBrightness,
                onChanged: display.setBrightness,
                onEnd: display.endBrightness,
                onGlyphTap: display.toggleAutoBrightness,
                steps: 20,
              ),
            ),
            SizedBox(width: space),
            SizedBox(
              width: column,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  RoundButton(
                    icon: Icons.nightlight_round,
                    label: 'Night mode',
                    active: s.nightLight,
                    dark: dark,
                    size: button,
                    onTap: display.toggleNightLight,
                  ),
                  RoundButton(
                    icon: Icons.brightness_low,
                    label: 'Extra dim',
                    active: s.extraDim,
                    dark: dark,
                    size: button,
                    onTap: s.extraDimAvailable ? display.toggleExtraDim : null,
                  ),
                  RoundButton(
                    icon: Icons.contrast,
                    label: s.darkTheme ? 'Dark theme' : 'Light theme',
                    active: s.darkTheme,
                    dark: dark,
                    size: button,
                    onTap: display.toggleDarkTheme,
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// A drawn sun: a disc with eight rounded rays that grow with [level]. With
/// [auto] on, the disc grows and an "A" is cut out of it. White above
/// [split] (from its top), black below it, on the slider's white fill: the
/// colour changes exactly where the fill's edge crosses it.
class _Sun extends StatelessWidget {
  const _Sun({required this.size, required this.level, required this.auto, required this.split, this.light = false});

  final double size;
  final double level;
  final bool auto;
  final double split;

  /// On a light panel (see paintSplit).
  final bool light;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(end: auto ? 1 : 0),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      builder: (context, a, _) => CustomPaint(
        size: Size.square(size),
        painter: _SunPainter(level: level, auto: a, split: split, light: light),
      ),
    );
  }
}

class _SunPainter extends CustomPainter {
  _SunPainter({required this.level, required this.auto, required this.split, required this.light});

  final double level;

  /// 0 (off) to 1 (on), animated.
  final double auto;
  final double split;
  final bool light;

  @override
  void paint(Canvas canvas, Size size) =>
      paintSplit(canvas, size, split, (color) => _sun(canvas, size, color), light: light);

  void _sun(Canvas canvas, Size size, Color color) {
    final s = size.width;
    final c = size.center(Offset.zero);
    final disc = s * (0.2 + 0.1 * auto);

    canvas.saveLayer(Offset.zero & size, Paint());
    canvas.drawCircle(c, disc, Paint()..color = color);
    // Rays: from just off the disc, longer the brighter.
    final ray = Paint()
      ..color = color
      ..strokeWidth = s * 0.085
      ..strokeCap = StrokeCap.round;
    final from = disc + s * 0.09;
    final length = s * (0.03 + 0.09 * level) * (1 - 0.35 * auto);
    for (var i = 0; i < 8; i++) {
      final angle = i * math.pi / 4;
      final dir = Offset(math.cos(angle), math.sin(angle));
      canvas.drawLine(c + dir * from, c + dir * (from + length), ray);
    }
    // Auto: an "A" cut out of the disc.
    if (auto > 0) {
      final text = TextPainter(
        text: TextSpan(
          text: 'A',
          style: TextStyle(
            fontSize: disc * 1.25,
            height: 1,
            fontWeight: FontWeight.w700,
            color: Color.fromRGBO(0, 0, 0, auto),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      canvas.saveLayer(Offset.zero & size, Paint()..blendMode = BlendMode.dstOut);
      text.paint(canvas, c - Offset(text.width / 2, text.height / 2));
      canvas.restore();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SunPainter old) =>
      old.level != level || old.auto != auto || old.split != split || old.light != light;
}
