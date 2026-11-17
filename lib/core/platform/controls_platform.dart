import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The display settings the control center's brightness container shows.
@immutable
class DisplayState {
  const DisplayState({
    this.brightness = 0.5,
    this.autoBrightness = false,
    this.nightLight = false,
    this.extraDim = false,
    this.extraDimAvailable = true,
    this.darkTheme = false,
  });

  factory DisplayState.fromMap(Map<dynamic, dynamic> m) => DisplayState(
    brightness: (m['brightness'] as num?)?.toDouble() ?? 0.5,
    autoBrightness: m['autoBrightness'] == true,
    nightLight: m['nightLight'] == true,
    extraDim: m['extraDim'] == true,
    extraDimAvailable: m['extraDimAvailable'] != false,
    darkTheme: m['darkTheme'] == true,
  );

  /// 0–1 of the brightness setting's range (not of the slider).
  final double brightness;
  final bool autoBrightness;

  /// The warm night light (vivo's "eye protection"), shown as night mode.
  final bool nightLight;

  /// Android's "Extra dim": the screen darker than its lowest brightness.
  final bool extraDim;
  final bool extraDimAvailable;

  /// The phone's dark theme (off: light theme).
  final bool darkTheme;

  DisplayState copyWith({
    double? brightness,
    bool? autoBrightness,
    bool? nightLight,
    bool? extraDim,
    bool? darkTheme,
  }) => DisplayState(
    brightness: brightness ?? this.brightness,
    autoBrightness: autoBrightness ?? this.autoBrightness,
    nightLight: nightLight ?? this.nightLight,
    extraDim: extraDim ?? this.extraDim,
    extraDimAvailable: extraDimAvailable,
    darkTheme: darkTheme ?? this.darkTheme,
  );
}

/// How a change went.
enum ControlResult {
  /// Changed in place.
  done,

  /// The launcher isn't allowed to change it yet: its settings page opened
  /// instead.
  opened,
}

/// Dart side of `platform/ControlsChannel.kt`; keep both in sync.
class ControlsPlatform {
  static const _method = MethodChannel('com.arun.minimal_launcher/controls');
  static const _events = EventChannel('com.arun.minimal_launcher/controls/events');

  Future<DisplayState> getDisplay() async =>
      DisplayState.fromMap(await _method.invokeMapMethod<dynamic, dynamic>('getDisplay') ?? const {});

  /// Something may have changed; call [getDisplay]. Listen only while shown.
  Stream<void> get changes => _events.receiveBroadcastStream();

  /// [value]: 0–1 of the brightness setting's range.
  Future<ControlResult> setBrightness(double value) => _invoke('setBrightness', {'value': value});

  Future<ControlResult> setAutoBrightness(bool on) => _invoke('setAutoBrightness', {'on': on});

  Future<ControlResult> setNightLight(bool on) => _invoke('setNightLight', {'on': on});

  Future<ControlResult> setExtraDim(bool on) => _invoke('setExtraDim', {'on': on});

  /// Needs Shizuku; otherwise the display settings open.
  Future<ControlResult> setDarkTheme(bool on) => _invoke('setDarkTheme', {'on': on});

  Future<ControlResult> _invoke(String method, Map<String, Object> args) async =>
      await _method.invokeMethod<String>(method, args) == 'opened' ? ControlResult.opened : ControlResult.done;
}
