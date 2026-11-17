import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../../core/platform/controls_platform.dart';

/// Live brightness, auto brightness, night light, extra dim and theme, for
/// the brightness widget. Changes show at once; the phone's own value
/// comes back through [ControlsPlatform.changes].
class DisplayController extends ChangeNotifier {
  DisplayController(this._platform) {
    _changes = _platform.changes.listen((_) => refresh(), onError: (_) {});
    refresh();
  }

  final ControlsPlatform _platform;
  StreamSubscription<void>? _changes;
  bool _disposed = false;

  DisplayState _state = const DisplayState();
  DisplayState get state => _state;

  bool _dragging = false;

  /// A switch just flipped: shown as asked until the phone agrees, or this
  /// long (the theme takes a moment to switch).
  final _pending = <String, (bool, DateTime)>{};
  static const _settle = Duration(seconds: 3);

  Future<void> refresh() async {
    final DisplayState fresh;
    try {
      fresh = await _platform.getDisplay();
    } on PlatformException {
      return;
    }
    if (_disposed) return;
    final now = DateTime.now();
    bool keep(String name, bool real) {
      final p = _pending[name];
      if (p == null) return real;
      if (p.$1 == real || now.isAfter(p.$2)) {
        _pending.remove(name);
        return real;
      }
      return p.$1;
    }

    _state = fresh.copyWith(
      // Mid-drag, the slider stays under the finger.
      brightness: _dragging ? _state.brightness : fresh.brightness,
      autoBrightness: keep('auto', fresh.autoBrightness),
      nightLight: keep('night', fresh.nightLight),
      extraDim: keep('dim', fresh.extraDim),
      darkTheme: keep('theme', fresh.darkTheme),
    );
    notifyListeners();
  }

  // --- Brightness ---

  /// Slider position (0–1, bottom to top) for the brightness setting:
  /// square-root, so the dim end, where the eye notices small steps, gets
  /// more of the slider.
  double get brightnessPosition => math.sqrt(_state.brightness.clamp(0.0, 1.0));

  /// Moving the slider takes over from auto brightness, which would
  /// otherwise keep re-adjusting the screen to the room's light, so the
  /// level picked doesn't stay.
  void startBrightness() {
    _dragging = true;
    _brightnessBlocked = false;
    if (_state.autoBrightness) {
      _pending['auto'] = (false, DateTime.now().add(_settle));
      _state = _state.copyWith(autoBrightness: false);
      notifyListeners();
      _platform.setAutoBrightness(false).catchError((_) => ControlResult.done);
    }
  }

  /// Android needs the user to allow it first: its page opened, so stop
  /// sending for the rest of this drag (each send would open it again).
  bool _brightnessBlocked = false;

  /// One write at a time; the latest value waits for the one in flight.
  bool _brightnessBusy = false;
  double? _brightnessQueued;

  void setBrightness(double position) {
    final value = math.max(1 / 255, position * position);
    _state = _state.copyWith(brightness: value);
    notifyListeners();
    if (!_brightnessBlocked) _sendBrightness(value);
  }

  void _sendBrightness(double value) {
    if (_brightnessBusy) {
      _brightnessQueued = value;
      return;
    }
    _brightnessBusy = true;
    _platform
        .setBrightness(value)
        .then((r) {
          if (r == ControlResult.opened) _brightnessBlocked = true;
        })
        .catchError((_) {})
        .whenComplete(() {
          _brightnessBusy = false;
          final queued = _brightnessQueued;
          _brightnessQueued = null;
          if (queued != null && !_brightnessBlocked) _sendBrightness(queued);
        });
  }

  void endBrightness() {
    _dragging = false;
    unawaited(refresh());
  }

  // --- Switches ---

  Future<void> toggleAutoBrightness() =>
      _flip('auto', !_state.autoBrightness, (v) => _state.copyWith(autoBrightness: v), _platform.setAutoBrightness);

  Future<void> toggleNightLight() =>
      _flip('night', !_state.nightLight, (v) => _state.copyWith(nightLight: v), _platform.setNightLight);

  Future<void> toggleDarkTheme() =>
      _flip('theme', !_state.darkTheme, (v) => _state.copyWith(darkTheme: v), _platform.setDarkTheme);

  Future<void> toggleExtraDim() =>
      _flip('dim', !_state.extraDim, (v) => _state.copyWith(extraDim: v), _platform.setExtraDim);

  Future<void> _flip(
    String name,
    bool on,
    DisplayState Function(bool) apply,
    Future<ControlResult> Function(bool) send,
  ) async {
    HapticFeedback.lightImpact();
    _pending[name] = (on, DateTime.now().add(_settle));
    _state = apply(on);
    notifyListeners();
    try {
      // Its settings page opened instead: show the real value again.
      if (await send(on) == ControlResult.opened) _pending.remove(name);
    } on PlatformException {
      _pending.remove(name);
    }
    if (!_disposed) await refresh();
  }

  @override
  void dispose() {
    _disposed = true;
    _changes?.cancel();
    super.dispose();
  }
}
