import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'controls_platform.dart' show ControlResult;

/// The phone's ringer mode.
enum RingerMode { normal, vibrate, silent }

/// The sound settings the control center's volume container shows.
@immutable
class SoundState {
  const SoundState({this.volume = 0.5, this.volumeSteps = 15, this.ringer = RingerMode.normal, this.dnd = false});

  factory SoundState.fromMap(Map<dynamic, dynamic> m) => SoundState(
    volume: (m['volume'] as num?)?.toDouble() ?? 0.5,
    volumeSteps: (m['volumeSteps'] as num?)?.toInt() ?? 15,
    ringer: RingerMode.values.asNameMap()[m['ringer']] ?? RingerMode.normal,
    dnd: m['dnd'] == true,
  );

  /// Media volume, 0–1.
  final double volume;

  /// How many steps media volume has (its maximum index).
  final int volumeSteps;
  final RingerMode ringer;

  /// Do Not Disturb.
  final bool dnd;

  SoundState copyWith({double? volume, RingerMode? ringer, bool? dnd}) => SoundState(
    volume: volume ?? this.volume,
    volumeSteps: volumeSteps,
    ringer: ringer ?? this.ringer,
    dnd: dnd ?? this.dnd,
  );
}

/// Dart side of `platform/SoundChannel.kt`; keep both in sync.
class SoundPlatform {
  static const _method = MethodChannel('com.arun.minimal_launcher/sound');
  static const _events = EventChannel('com.arun.minimal_launcher/sound/events');

  Future<SoundState> getSound() async =>
      SoundState.fromMap(await _method.invokeMapMethod<dynamic, dynamic>('getSound') ?? const {});

  /// Something may have changed; call [getSound]. Listen only while shown.
  Stream<void> get changes => _events.receiveBroadcastStream();

  /// [value]: 0–1 of media volume.
  Future<ControlResult> setVolume(double value) => _invoke('setVolume', {'value': value});

  /// Silent needs Do Not Disturb access: its page opens if not allowed.
  Future<ControlResult> setRinger(RingerMode mode) => _invoke('setRinger', {'mode': mode.name});

  Future<ControlResult> setDnd(bool on) => _invoke('setDnd', {'on': on});

  Future<ControlResult> _invoke(String method, Map<String, Object> args) async =>
      await _method.invokeMethod<String>(method, args) == 'opened' ? ControlResult.opened : ControlResult.done;
}
