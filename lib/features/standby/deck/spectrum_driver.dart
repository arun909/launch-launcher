import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../../../core/platform/standby_platform.dart';

/// Turns the 20-35 readings a second the phone sends (see [SpectrumFrame])
/// into meter motion at the display's pace, for the deck style:
///
/// - [bands]: the EQ columns. They jump up at once and fall at a steady
///   rate, like a hardware LED analyser.
/// - [peaks]: a cap above each column that holds for a moment, then drops
///   with gravity.
/// - [needles]: the two VU needles, a damped spring tuned to the VU
///   standard's ~300 ms rise with a touch of overshoot.
/// - [overload]: each meter's peak lamp, lit for a moment past +1 VU.
///
/// Painters listen to it (`repaint:`). It ticks only while something moves;
/// once the music stops and everything has settled, no frames.
class SpectrumDriver extends ChangeNotifier {
  SpectrumDriver(TickerProvider vsync) {
    _ticker = vsync.createTicker(_tick);
  }

  static const bandCount = 10;

  /// The bands' centre frequencies, as printed under the columns.
  static const labels = ['31', '63', '125', '250', '500', '1k', '2k', '4k', '8k', '16k'];

  /// Column fall, in full heights a second.
  static const fall = 1.6;

  /// How long a peak cap waits before dropping.
  static const peakHold = Duration(milliseconds: 650);

  late final Ticker _ticker;
  Duration? _last;
  Duration _lastFrame = Duration.zero;
  Duration _clock = Duration.zero;

  final List<double> bands = List.filled(bandCount, 0);
  final List<double> peaks = List.filled(bandCount, 0);
  final List<double> needles = [0, 0];
  final List<bool> overload = [false, false];

  final List<double> _target = List.filled(bandCount, 0);
  final List<double> _peakWait = List.filled(bandCount, 0);
  final List<double> _peakSpeed = List.filled(bandCount, 0);
  final List<double> _needleTarget = [0, 0];
  final List<double> _needleSpeed = [0, 0];
  final List<double> _overloadFor = [0, 0];

  /// A reading from the phone.
  void feed(SpectrumFrame frame) {
    for (var i = 0; i < bandCount && i < frame.bands.length; i++) {
      _target[i] = frame.bands[i].clamp(0.0, 1.0);
    }
    _needleTarget[0] = frame.left.clamp(0.0, 1.0);
    _needleTarget[1] = frame.right.clamp(0.0, 1.0);
    for (var m = 0; m < 2; m++) {
      if (_needleTarget[m] > overloadAt) _overloadFor[m] = 0.35;
    }
    _lastFrame = _clock;
    _wake();
  }

  /// The music stopped: everything falls back to rest.
  void rest() {
    _target.fillRange(0, bandCount, 0);
    _needleTarget.fillRange(0, 2, 0);
    _wake();
  }

  /// Where on the 0-1 needle scale +1 VU sits (the meter spans -20..+3).
  static const overloadAt = 21 / 23;

  void _wake() {
    if (!_ticker.isActive) {
      _last = null;
      _ticker.start();
    }
  }

  void _tick(Duration elapsed) {
    final last = _last;
    final dt = last == null ? 1 / 60 : math.min(0.05, (elapsed - last).inMicroseconds / 1e6);
    _last = elapsed;
    _clock += Duration(microseconds: (dt * 1e6).round());
    // Readings stopped coming (paused, or the phone refused): fall to rest.
    if (_clock - _lastFrame > const Duration(milliseconds: 300)) {
      _target.fillRange(0, bandCount, 0);
      _needleTarget.fillRange(0, 2, 0);
    }

    var moving = false;
    for (var i = 0; i < bandCount; i++) {
      final t = _target[i];
      bands[i] = t > bands[i] ? bands[i] + (t - bands[i]) * math.min(1.0, dt * 40) : math.max(t, bands[i] - fall * dt);
      if (bands[i] >= peaks[i]) {
        peaks[i] = bands[i];
        _peakWait[i] = peakHold.inMicroseconds / 1e6;
        _peakSpeed[i] = 0;
      } else if ((_peakWait[i] -= dt) <= 0) {
        _peakSpeed[i] += 2.4 * dt;
        peaks[i] = math.max(bands[i], peaks[i] - _peakSpeed[i] * dt);
      }
      moving |= bands[i] > 0.001 || peaks[i] > 0.001 || t > 0;
    }

    // Damped spring, in substeps so a dropped frame can't make it blow up.
    const omega = 2 * math.pi * 2.0;
    const zeta = 0.78;
    for (var m = 0; m < 2; m++) {
      final steps = (dt / 0.004).ceil();
      final h = dt / steps;
      for (var s = 0; s < steps; s++) {
        final a = omega * omega * (_needleTarget[m] - needles[m]) - 2 * zeta * omega * _needleSpeed[m];
        _needleSpeed[m] += a * h;
        needles[m] += _needleSpeed[m] * h;
      }
      // The pin stops it at both ends.
      if (needles[m] < 0) {
        needles[m] = 0;
        _needleSpeed[m] = 0;
      } else if (needles[m] > 1.04) {
        needles[m] = 1.04;
        _needleSpeed[m] = 0;
      }
      _overloadFor[m] -= dt;
      overload[m] = _overloadFor[m] > 0;
      moving |= needles[m] > 0.001 || _needleSpeed[m].abs() > 0.001 || _needleTarget[m] > 0 || overload[m];
    }

    notifyListeners();
    if (!moving) _ticker.stop();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }
}
