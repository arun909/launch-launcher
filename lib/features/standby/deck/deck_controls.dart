import 'package:flutter/material.dart';

import '../../../core/platform/standby_platform.dart';

/// Colours and type the deck's parts share.
abstract final class DeckInk {
  static const plate = Color(0xFF111113);
  static const engraved = Color(0xFF8E877A);
  static const cream = Color(0xFFEDE6D6);
  static const dim = Color(0xFF9A9386);

  /// The deck's one theme colour: warm amber, as on a vintage display.
  static const amber = [Color(0xFFFFC56B), Color(0xFFFF9E2C)];

  static TextStyle label(double size, {Color color = engraved, double spacing = 2.2}) => TextStyle(
    fontFamily: 'ClockOswald',
    fontSize: size,
    letterSpacing: spacing,
    color: color,
    fontVariations: const [FontVariation('wght', 500)],
    height: 1,
  );
}

/// A recessed window in the faceplate: dark glass in a thin bevel.
class DeckWindow extends StatelessWidget {
  const DeckWindow({super.key, required this.child, this.padding = const EdgeInsets.all(10), this.radius = 10});

  final Widget child;
  final EdgeInsets padding;
  final double radius;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(radius),
      gradient: const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF020203), Color(0xFF09090B)],
      ),
      border: Border.all(color: const Color(0xFF2A2A2E), width: 1),
      boxShadow: const [BoxShadow(color: Color(0x14FFFFFF), offset: Offset(0, 1))],
    ),
    child: Padding(padding: padding, child: child),
  );
}

/// The transport: previous, play/pause, next, as glass buttons tinted with
/// the song's colours ([accent]).
class DeckTransport extends StatelessWidget {
  const DeckTransport({super.key, required this.media, required this.onCommand, required this.accent});

  final NowPlaying? media;
  final void Function(String command, {Duration? position}) onCommand;
  final List<Color> accent;

  @override
  Widget build(BuildContext context) {
    final m = media;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GlassButton(
          size: 46,
          icon: Icons.skip_previous_rounded,
          label: 'Previous',
          tint: accent,
          onTap: m != null && m.canPrevious ? () => onCommand('previous') : null,
        ),
        const SizedBox(width: 20),
        GlassButton(
          size: 62,
          icon: m?.playing ?? false ? Icons.pause_rounded : Icons.play_arrow_rounded,
          label: m?.playing ?? false ? 'Pause' : 'Play',
          tint: accent,
          strong: true,
          onTap: m == null ? null : () => onCommand(m.playing ? 'pause' : 'play'),
        ),
        const SizedBox(width: 20),
        GlassButton(
          size: 46,
          icon: Icons.skip_next_rounded,
          label: 'Next',
          tint: accent,
          onTap: m != null && m.canNext ? () => onCommand('next') : null,
        ),
      ],
    );
  }
}

/// A round glass button tinted with [tint]: a soft coloured glow behind it,
/// a translucent body, a bright rim and a curved highlight across its top.
/// It sinks a little when pressed. [strong]: more colour (play/pause).
class GlassButton extends StatefulWidget {
  const GlassButton({
    super.key,
    required this.size,
    required this.icon,
    required this.label,
    required this.tint,
    required this.onTap,
    this.strong = false,
  });

  final double size;
  final IconData icon;
  final String label;
  final List<Color> tint;
  final VoidCallback? onTap;
  final bool strong;

  @override
  State<GlassButton> createState() => _GlassButtonState();
}

class _GlassButtonState extends State<GlassButton> {
  bool _down = false;

  void _set(bool down) {
    if (down != _down) setState(() => _down = down);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    final s = widget.size;
    final a = widget.tint.first;
    final b = widget.tint.length > 1 ? widget.tint.last : a;
    final k = (widget.strong ? 1.0 : 0.6) * (enabled ? 1 : 0.35);
    return Semantics(
      button: true,
      label: widget.label,
      enabled: enabled,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => _set(true) : null,
        onTapUp: enabled ? (_) => _set(false) : null,
        onTapCancel: enabled ? () => _set(false) : null,
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _down ? 0.93 : 1,
          duration: const Duration(milliseconds: 90),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: s,
            height: s,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              // The song's colour lighting the glass from behind.
              boxShadow: [
                BoxShadow(
                  color: a.withValues(alpha: 0.35 * k),
                  blurRadius: s * 0.45,
                  spreadRadius: -s * 0.08,
                ),
              ],
              // Frosted glass, lit from below by the song's colour.
              gradient: RadialGradient(
                center: const Alignment(0, 0.85),
                radius: 1.05,
                colors: [
                  Color.lerp(a, Colors.white, 0.15)!.withValues(alpha: (_down ? 0.85 : 0.7) * k),
                  b.withValues(alpha: (_down ? 0.4 : 0.3) * k),
                  Colors.white.withValues(alpha: 0.07),
                ],
                stops: const [0, 0.55, 1],
              ),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                // The rim: bright where the light catches the top, the
                // song's colour at the foot.
                Positioned.fill(child: CustomPaint(painter: _RimPainter(a, enabled))),
                // The highlight across the top of the glass.
                Positioned(
                  top: s * 0.06,
                  left: s * 0.16,
                  right: s * 0.16,
                  height: s * 0.42,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.vertical(top: Radius.circular(s), bottom: Radius.circular(s * 0.4)),
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.white.withValues(alpha: _down ? 0.14 : 0.24),
                          Colors.white.withValues(alpha: 0),
                        ],
                      ),
                    ),
                  ),
                ),
                Icon(
                  widget.icon,
                  size: s * 0.48,
                  color: Colors.white.withValues(alpha: enabled ? 0.95 : 0.35),
                  shadows: [
                    Shadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 4, offset: const Offset(0, 1)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RimPainter extends CustomPainter {
  _RimPainter(this.color, this.enabled);

  final Color color;
  final bool enabled;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(0.6);
    canvas.drawOval(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withValues(alpha: enabled ? 0.65 : 0.25),
            Colors.white.withValues(alpha: 0.08),
            Color.lerp(color, Colors.white, 0.3)!.withValues(alpha: enabled ? 0.7 : 0.25),
          ],
          stops: const [0, 0.5, 1],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_RimPainter old) => old.color != color || old.enabled != enabled;
}
