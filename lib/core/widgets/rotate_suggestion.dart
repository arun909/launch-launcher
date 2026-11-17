import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../platform/rotation_platform.dart';

/// Shows a small rotate button over [child] while the phone is held in another
/// orientation, like Android's own rotation suggestion. Tapping it turns the
/// screen; ignoring it leaves the layout as it is. It hides itself after a few
/// seconds so it never lingers.
class RotateSuggestion extends StatefulWidget {
  const RotateSuggestion({super.key, required this.child});

  final Widget child;

  @override
  State<RotateSuggestion> createState() => _RotateSuggestionState();
}

class _RotateSuggestionState extends State<RotateSuggestion> {
  static const _visibleFor = Duration(seconds: 5);

  late final RotationPlatform _rotation = context.read<RotationPlatform>();
  Timer? _hideTimer;
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    _rotation.addListener(_onSuggestion);
  }

  void _onSuggestion() {
    _hideTimer?.cancel();
    setState(() => _visible = _rotation.suggested);
    if (_visible) _hideTimer = Timer(_visibleFor, () => setState(() => _visible = false));
  }

  void _rotate() {
    _hideTimer?.cancel();
    setState(() => _visible = false);
    _rotation.rotate();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _rotation.removeListener(_onSuggestion);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        Positioned(
          right: 16,
          bottom: 16,
          child: SafeArea(
            child: IgnorePointer(
              ignoring: !_visible,
              child: AnimatedScale(
                scale: _visible ? 1 : 0.6,
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                child: AnimatedOpacity(
                  opacity: _visible ? 1 : 0,
                  duration: const Duration(milliseconds: 180),
                  child: Material(
                    color: Colors.black.withValues(alpha: 0.6),
                    shape: const CircleBorder(),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: _rotate,
                      child: const Padding(
                        padding: EdgeInsets.all(14),
                        child: Icon(
                          Icons.screen_rotation,
                          color: Colors.white,
                          size: 26,
                          semanticLabel: 'Rotate screen',
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
