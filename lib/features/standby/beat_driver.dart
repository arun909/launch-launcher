import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../../core/platform/standby_platform.dart';

/// Turns the hits the phone hears (see [BeatFrame]) into smooth motion for
/// the standby clock's background glow, at the display's pace. There are
/// [spotCount] glow points, [spotsPerBand] for each band (bass, mids,
/// treble; see [bandOf]); a hit lights one of its band's points, taking
/// turns, so the glow hops here and there; a hard hit lights them all.
///
/// - [pulses]: each hit swells its point in over ~50 ms and lets it ebb
///   out over a few hundred, rather than snapping on and off.
/// - [heat]: how hard the point's last hit was, easing between hits; the
///   glow warms and brightens its colour with it.
/// - [energy]: the brightest point now, for the clock digits' glass.
/// - [drift]: each hit nudges its patch to a new spot nearby, and it glides
///   there, so the patches wander a little with the music.
///
/// - [live]: true while hits keep coming (till [quietAfter] without one);
///   the steady glow fades out meanwhile, so the hits light a dark screen,
///   and comes back when the music pauses or goes quiet.
///
/// Painters listen to it (`repaint:`). It ticks only while something
/// moves; between hits and once the music stops, no frames.
class BeatDriver extends ChangeNotifier {
  BeatDriver(TickerProvider vsync, {math.Random? random}) : _random = random ?? math.Random() {
    _ticker = vsync.createTicker(_tick);
  }

  static const bandCount = 3;
  static const spotsPerBand = 2;
  static const spotCount = bandCount * spotsPerBand;

  /// Which band glow point [spot] belongs to.
  static int bandOf(int spot) => spot ~/ spotsPerBand;

  /// A hit this hard (0 to 1) lights all its band's points at once.
  static const hardHit = 0.8;

  /// How far a patch wanders from its home, as a fraction of the screen.
  static const wander = 0.06;

  final math.Random _random;
  late final Ticker _ticker;
  Duration _last = Duration.zero;

  /// Each 0 to 1, per glow point: its brightness now.
  final List<double> pulses = List.filled(spotCount, 0);

  /// Each 0 to 1, per point: how hard its last hit was, smoothed.
  final List<double> heat = List.filled(spotCount, 0);

  /// Each point's offset from its home, in fractions of the screen.
  final List<Offset> drift = List.filled(spotCount, Offset.zero);

  final List<double> _target = List.filled(spotCount, 0);
  final List<double> _heatTarget = List.filled(spotCount, 0);
  final List<Offset> _driftTarget = List.filled(spotCount, Offset.zero);

  /// Per band, the point its next hit lights.
  final List<int> _turn = List.filled(bandCount, 0);

  /// The brightest point now, 0 to 1.
  double get energy => pulses.reduce(math.max);

  /// How long without a hit before the music counts as stopped.
  static const quietAfter = Duration(seconds: 3);

  /// Whether hits are coming in.
  final ValueNotifier<bool> live = ValueNotifier(false);
  Timer? _quiet;

  /// A hit from the visualizer.
  void feed(BeatFrame frame) {
    final b = frame.band;
    if (!frame.beat || b < 0 || b >= bandCount) return;
    final first = b * spotsPerBand;
    final spots = frame.strength >= hardHit
        ? [for (var i = 0; i < spotsPerBand; i++) first + i]
        : [first + (_turn[b]++ % spotsPerBand)];
    for (final i in spots) {
      // Harder hits swell more, so the glow follows the song's accents.
      _target[i] = math.max(_target[i], 0.35 + 0.65 * frame.strength);
      _heatTarget[i] = frame.strength;
      _driftTarget[i] = Offset((_random.nextDouble() * 2 - 1) * wander, (_random.nextDouble() * 2 - 1) * wander);
    }
    live.value = true;
    _quiet?.cancel();
    _quiet = Timer(quietAfter, () => live.value = false);
    if (!_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    }
  }

  void _tick(Duration elapsed) {
    final dt = _last == Duration.zero ? 1 / 60 : (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    var moving = false;
    for (var i = 0; i < spotCount; i++) {
      // The hit itself ebbs (treble quicker, as hi-hats are)...
      _target[i] *= math.exp(-dt * (bandOf(i) == 2 ? 7.5 : 5.5));
      if (_target[i] < 0.003) _target[i] = 0;
      // ...and the light follows it: in fast, out with the target's ebb.
      final rise = _target[i] > pulses[i];
      pulses[i] += (_target[i] - pulses[i]) * math.min(1.0, dt * (rise ? 22 : 14));
      if (pulses[i] < 0.003 && _target[i] == 0) pulses[i] = 0;

      heat[i] += (_heatTarget[i] - heat[i]) * math.min(1.0, dt * 6);
      drift[i] += (_driftTarget[i] - drift[i]) * math.min(1.0, dt * 2.5);

      moving |= pulses[i] > 0 || _target[i] > 0;
    }
    notifyListeners();
    // Once dark, the colour and spot can settle unseen: they're used only lit.
    if (!moving) _ticker.stop();
  }

  @override
  void dispose() {
    _quiet?.cancel();
    live.dispose();
    _ticker.dispose();
    super.dispose();
  }
}
