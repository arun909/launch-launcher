import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../../core/platform/controls_platform.dart' show ControlResult;
import '../../../core/platform/sound_platform.dart';

/// Live media volume, ringer mode and Do Not Disturb while the control
/// center is open. Changes show at once; the phone's own value comes back
/// through [SoundPlatform.changes].
class SoundController extends ChangeNotifier {
  SoundController(this._platform) {
    _changes = _platform.changes.listen((_) => refresh(), onError: (_) {});
    refresh();
  }

  final SoundPlatform _platform;
  StreamSubscription<void>? _changes;
  bool _disposed = false;

  SoundState _state = const SoundState();
  SoundState get state => _state;

  bool _dragging = false;

  /// A ringer mode or DND just changed: shown as asked until the phone
  /// agrees, or this long.
  RingerMode? _pendingRinger;
  bool? _pendingDnd;
  DateTime _pendingUntil = DateTime(0);
  static const _settle = Duration(seconds: 2);

  Future<void> refresh() async {
    final SoundState fresh;
    try {
      fresh = await _platform.getSound();
    } on PlatformException {
      return;
    }
    if (_disposed) return;
    final late = DateTime.now().isAfter(_pendingUntil);
    if (late || _pendingRinger == fresh.ringer) _pendingRinger = null;
    if (late || _pendingDnd == fresh.dnd) _pendingDnd = null;
    _state = fresh.copyWith(
      // Mid-drag, the slider stays under the finger.
      volume: _dragging ? _state.volume : fresh.volume,
      ringer: _pendingRinger,
      dnd: _pendingDnd,
    );
    notifyListeners();
  }

  // --- Volume ---

  double get volumePosition => _state.volume.clamp(0.0, 1.0);

  /// Before muting with the speaker: what to go back to.
  double _unmuted = 0.5;

  void startVolume() => _dragging = true;

  /// One write at a time; the latest value waits for the one in flight.
  bool _busy = false;
  double? _queued;

  void setVolume(double position) {
    final steps = _state.volumeSteps;
    final before = (_state.volume * steps).round();
    // Snapped to the phone's own steps (the slider ticks on each).
    final after = (position * steps).round();
    _state = _state.copyWith(volume: position);
    notifyListeners();
    if (after != before) _send(after / steps);
  }

  void _send(double value) {
    if (_busy) {
      _queued = value;
      return;
    }
    _busy = true;
    _platform.setVolume(value).catchError((_) => ControlResult.done).whenComplete(() {
      _busy = false;
      final queued = _queued;
      _queued = null;
      if (queued != null) _send(queued);
    });
  }

  void endVolume() {
    _dragging = false;
    final steps = _state.volumeSteps;
    // Rest on the step it was sent as.
    _state = _state.copyWith(volume: (_state.volume * steps).round() / steps);
    notifyListeners();
    unawaited(refresh());
  }

  /// The speaker: mute, or back to the volume before.
  void toggleMute() {
    HapticFeedback.lightImpact();
    final muted = _state.volume <= 0;
    if (!muted) _unmuted = _state.volume;
    final value = muted ? (_unmuted > 0 ? _unmuted : 0.5) : 0.0;
    _state = _state.copyWith(volume: value);
    notifyListeners();
    _send(value);
  }

  // --- Ringer and DND ---

  /// Silent, or back to ringing.
  Future<void> toggleSilent() => _setRinger(_state.ringer == RingerMode.silent ? RingerMode.normal : RingerMode.silent);

  /// Vibrate, or back to ringing (from silent: vibrate).
  Future<void> toggleVibrate() =>
      _setRinger(_state.ringer == RingerMode.vibrate ? RingerMode.normal : RingerMode.vibrate);

  Future<void> _setRinger(RingerMode mode) async {
    HapticFeedback.lightImpact();
    _pendingRinger = mode;
    _pendingUntil = DateTime.now().add(_settle);
    _state = _state.copyWith(ringer: mode);
    notifyListeners();
    try {
      // Its settings page opened instead: show the real value again.
      if (await _platform.setRinger(mode) == ControlResult.opened) _pendingRinger = null;
    } on PlatformException {
      _pendingRinger = null;
    }
    if (!_disposed) await refresh();
  }

  Future<void> toggleDnd() async {
    HapticFeedback.lightImpact();
    final on = !_state.dnd;
    _pendingDnd = on;
    _pendingUntil = DateTime.now().add(_settle);
    _state = _state.copyWith(dnd: on);
    notifyListeners();
    try {
      if (await _platform.setDnd(on) == ControlResult.opened) _pendingDnd = null;
    } on PlatformException {
      _pendingDnd = null;
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
