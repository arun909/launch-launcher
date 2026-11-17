import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/platform/sound_platform.dart';
import '../launcher_widgets.dart';
import 'sound_controller.dart';
import 'pill_slider.dart';
import 'tile_look.dart';

/// The volume widget: 2 × 2, on glass, a dark or a Material panel, like
/// brightness.
const volumeKind = LauncherWidgetKind(
  name: 'volume',
  label: 'Volume',
  description: 'Media volume slider with silent, vibrate and Do Not Disturb',
  icon: Icons.volume_up_outlined,
  size: (2, 2),
  min: (2, 2),
  max: (2, 2),
  sizes: [(2, 2)],
  build: _build,
  customise: showControlsSettings,
  styleOf: controlsStyleOf,
  interactive: true,
);

Widget _build(BuildContext context, Map<String, dynamic> settings) => VolumeTile(dark: controlsDark(settings));

/// Volume, in the brightness widget's style: a tall pill slider for
/// media volume, whose speaker mutes and unmutes it, and beside it three
/// round buttons: silent, vibrate / ring (one button: vibrate when on, the
/// normal ring when off) and Do Not Disturb.
class VolumeTile extends StatelessWidget {
  const VolumeTile({super.key, this.dark = false});

  /// On a dark panel (else glass; a light one is PanelInk's).
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final sound = context.watch<SoundController>();
    final s = sound.state;
    final vibrate = s.ringer == RingerMode.vibrate;
    return LayoutBuilder(
      builder: (context, box) {
        // Same proportions as the brightness widget.
        final size = math.min(box.maxWidth, box.maxHeight);
        final space = size * 0.08;
        final column = (box.maxWidth - space) / 2;
        final button = math.min(column, (box.maxHeight - 2 * space) / 3);
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: column,
              child: PillSlider(
                position: sound.volumePosition,
                label: 'Volume',
                glyphLabel: 'Mute',
                glyphToggled: s.volume <= 0,
                glyph: (size, level, split) => CustomPaint(
                  size: Size.square(size),
                  painter: _SpeakerPainter(level: level, split: split, light: PanelInk.lightOf(context)),
                ),
                dark: dark,
                onStart: sound.startVolume,
                onChanged: sound.setVolume,
                onEnd: sound.endVolume,
                onGlyphTap: sound.toggleMute,
                // A tick on each of the phone's volume steps.
                steps: s.volumeSteps,
              ),
            ),
            SizedBox(width: space),
            SizedBox(
              width: column,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  RoundButton(
                    icon: Icons.notifications_off,
                    label: 'Silent',
                    active: s.ringer == RingerMode.silent,
                    activeColor: TileLook.alert,
                    dark: dark,
                    size: button,
                    onTap: sound.toggleSilent,
                  ),
                  RoundButton(
                    icon: vibrate ? Icons.vibration : Icons.notifications_active,
                    label: vibrate ? 'Vibrate' : 'Ring',
                    active: vibrate,
                    dark: dark,
                    size: button,
                    onTap: sound.toggleVibrate,
                  ),
                  RoundButton(
                    icon: Icons.bedtime,
                    label: 'Do Not Disturb',
                    active: s.dnd,
                    dark: dark,
                    size: button,
                    onTap: sound.toggleDnd,
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

/// A drawn speaker: a rounded body and cone, with up to three sound waves
/// that appear as the volume rises; at zero, a slash through it. Split
/// white / black where the fill's edge crosses it, like the sun.
class _SpeakerPainter extends CustomPainter {
  _SpeakerPainter({required this.level, required this.split, required this.light});

  final double level;
  final double split;
  final bool light;

  @override
  void paint(Canvas canvas, Size size) =>
      paintSplit(canvas, size, split, (color) => _speaker(canvas, size, color), light: light);

  void _speaker(Canvas canvas, Size size, Color color) {
    final s = size.width;
    // The speaker sits a little left of centre, leaving room for its waves.
    final left = s * 0.16;
    final cy = s / 2;
    final fill = Paint()
      ..color = color
      ..isAntiAlias = true;
    final body = Path()
      ..addRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(left, cy - s * 0.11, s * 0.14, s * 0.22), Radius.circular(s * 0.03)),
      )
      ..moveTo(left + s * 0.1, cy - s * 0.11)
      ..lineTo(left + s * 0.3, cy - s * 0.26)
      ..lineTo(left + s * 0.3, cy + s * 0.26)
      ..lineTo(left + s * 0.1, cy + s * 0.11)
      ..close();
    canvas.drawPath(body, fill);

    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.075
      ..strokeCap = StrokeCap.round;
    final centre = Offset(left + s * 0.26, cy);
    if (level <= 0) {
      // Muted: a short cross where the waves would be.
      final x = left + s * 0.5;
      final d = s * 0.09;
      canvas
        ..drawLine(Offset(x - d, cy - d), Offset(x + d, cy + d), stroke)
        ..drawLine(Offset(x - d, cy + d), Offset(x + d, cy - d), stroke);
      return;
    }
    // Waves: the first from just above zero, the others as it gets louder.
    for (var i = 0; i < 3; i++) {
      final show = i == 0 ? 1.0 : ((level - i / 3) * 3).clamp(0.0, 1.0);
      if (show <= 0) continue;
      final r = s * (0.14 + 0.12 * i);
      stroke.color = color.withValues(alpha: color.a * show);
      canvas.drawArc(Rect.fromCircle(center: centre, radius: r), -math.pi / 4, math.pi / 2, false, stroke);
    }
  }

  @override
  bool shouldRepaint(_SpeakerPainter old) => old.level != level || old.split != split || old.light != light;
}
