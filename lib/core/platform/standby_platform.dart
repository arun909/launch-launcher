import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// What the standby clock shows besides the time.
@immutable
class StandbyStatus {
  const StandbyStatus({this.nextAlarm});

  factory StandbyStatus.fromMap(Map<dynamic, dynamic> map) => StandbyStatus(
    nextAlarm: switch (map['nextAlarm']) {
      final num ms => DateTime.fromMillisecondsSinceEpoch(ms.toInt()),
      _ => null,
    },
  );

  final DateTime? nextAlarm;

  @override
  bool operator ==(Object other) => other is StandbyStatus && other.nextAlarm == nextAlarm;

  @override
  int get hashCode => nextAlarm.hashCode;
}

/// What's playing on the phone, for the standby clock's media tile.
@immutable
class NowPlaying {
  const NowPlaying({
    required this.title,
    this.artist,
    this.album,
    this.app,
    this.package,
    this.connected = false,
    this.duration,
    this.position = Duration.zero,
    this.speed = 1,
    this.playing = false,
    this.canPrevious = true,
    this.canNext = true,
    this.canSeek = false,
    this.art,
    this.artKey,
    required this.at,
  });

  /// From the platform map; [previous]'s cover is kept when the map leaves
  /// it out (it's sent only when the track changes).
  factory NowPlaying.fromMap(Map<dynamic, dynamic> map, {NowPlaying? previous, DateTime? at}) {
    final artKey = map['artKey'] as String?;
    final art = map['hasArt'] == true
        ? map['art'] as Uint8List?
        : (previous != null && previous.artKey == artKey ? previous.art : null);
    Duration? ms(Object? v) => v is num ? Duration(milliseconds: v.toInt()) : null;
    return NowPlaying(
      title: map['title'] as String? ?? '',
      artist: map['artist'] as String?,
      album: map['album'] as String?,
      app: map['app'] as String?,
      package: map['package'] as String?,
      connected: map['connected'] == true,
      duration: ms(map['durationMs']),
      position: ms(map['positionMs']) ?? Duration.zero,
      speed: (map['speed'] as num?)?.toDouble() ?? 1,
      playing: map['playing'] == true,
      canPrevious: map['canPrevious'] != false,
      canNext: map['canNext'] != false,
      canSeek: map['canSeek'] == true,
      art: art,
      artKey: artKey,
      at: at ?? DateTime.now(),
    );
  }

  final String title;
  final String? artist;
  final String? album;

  /// The player's name ("Spotify").
  final String? app;
  final String? package;

  /// Playing on a connected computer (relayed by a link app like Phone
  /// Link), not on the phone itself.
  final bool connected;

  /// Null for live streams and apps that don't say.
  final Duration? duration;

  /// Where it was at [at].
  final Duration position;
  final double speed;
  final bool playing;
  final bool canPrevious;
  final bool canNext;
  final bool canSeek;

  /// The cover (JPEG), if any.
  final Uint8List? art;
  final String? artKey;

  /// When [position] was read.
  final DateTime at;

  /// Where it is at [now], moving on from [position] while playing.
  Duration positionAt(DateTime now) {
    var p = position;
    if (playing) p += Duration(microseconds: (now.difference(at).inMicroseconds * speed).round());
    if (p < Duration.zero) return Duration.zero;
    if (duration case final d? when p > d) return d;
    return p;
  }

  NowPlaying copyWith({bool? playing, Duration? position, DateTime? at}) => NowPlaying(
    title: title,
    artist: artist,
    album: album,
    app: app,
    package: package,
    connected: connected,
    duration: duration,
    position: position ?? this.position,
    speed: speed,
    playing: playing ?? this.playing,
    canPrevious: canPrevious,
    canNext: canNext,
    canSeek: canSeek,
    art: art,
    artKey: artKey,
    at: at ?? this.at,
  );
}

/// A hit the visualizer heard in what the phone plays, in one band.
@immutable
class BeatFrame {
  const BeatFrame({this.beat = false, this.band = 0, this.strength = 0});

  factory BeatFrame.fromMap(Map<dynamic, dynamic> map) => BeatFrame(
    beat: map['beat'] == true,
    band: (map['band'] as num?)?.toInt() ?? 0,
    strength: (map['strength'] as num?)?.toDouble() ?? 0,
  );

  final bool beat;

  /// Where it hit: 0 bass, 1 mids, 2 treble.
  final int band;

  /// How hard the beat hit, 0 to 1.
  final double strength;
}

/// One reading of the phone's sound for the deck style: 10 octave bands
/// (31 Hz to 16 kHz) and the meters' left and right, all 0 to 1.
@immutable
class SpectrumFrame {
  const SpectrumFrame({required this.bands, this.left = 0, this.right = 0});

  factory SpectrumFrame.fromMap(Map<dynamic, dynamic> map) => SpectrumFrame(
    bands: [for (final v in (map['bands'] as List?) ?? const []) (v as num).toDouble()],
    left: (map['left'] as num?)?.toDouble() ?? 0,
    right: (map['right'] as num?)?.toDouble() ?? 0,
  );

  final List<double> bands;
  final double left;
  final double right;
}

/// Dart side of the standby bridge. The Kotlin counterpart is
/// `android/app/src/main/kotlin/.../platform/standby/StandbyChannel.kt`; it
/// runs both in the launcher and in the clock's own engine.
class StandbyPlatform {
  StandbyPlatform() {
    _method.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onStatus':
          _changes.add(StandbyStatus.fromMap(call.arguments as Map<dynamic, dynamic>));
        case 'onMedia':
          _onMedia?.call(call.arguments as Map<dynamic, dynamic>?);
        case 'onBeat':
          _beats?.add(BeatFrame.fromMap(call.arguments as Map<dynamic, dynamic>));
        case 'onSpectrum':
          _spectrum?.add(SpectrumFrame.fromMap(call.arguments as Map<dynamic, dynamic>));
      }
    });
  }

  void Function(Map<dynamic, dynamic>?)? _onMedia;
  StreamController<BeatFrame>? _beats;
  StreamController<SpectrumFrame>? _spectrum;

  static const _method = MethodChannel('com.arun.minimal_launcher/standby');

  late final _changes = StreamController<StandbyStatus>.broadcast(
    onListen: () => _method.invokeMethod('listen', true),
    onCancel: () => _method.invokeMethod('listen', false),
  );

  /// The status now, then on every change for as long as it's listened to.
  Stream<StandbyStatus> watch() async* {
    final now = await _method.invokeMapMethod<dynamic, dynamic>('status');
    if (now != null) yield StandbyStatus.fromMap(now);
    yield* _changes.stream;
  }

  /// Whether the clock opens on the lock screen when the phone is sideways.
  Future<bool> isEnabled() async => await _method.invokeMethod<bool>('isEnabled') ?? false;

  Future<void> setEnabled(bool on) => _method.invokeMethod('setEnabled', on);

  /// Whether locking the phone while it lies still (flat or propped, any way
  /// up) opens the clock too, not only when it's sideways.
  Future<bool> isOnRest() async => await _method.invokeMethod<bool>('isOnRest') ?? true;

  Future<void> setOnRest(bool on) => _method.invokeMethod('setOnRest', on);

  /// Whether the clock keeps the screen on while it's up (off: only while
  /// charging; on battery the usual timeout applies).
  Future<bool> isKeepOn() async => await _method.invokeMethod<bool>('isKeepOn') ?? true;

  Future<void> setKeepOn(bool on) => _method.invokeMethod('setKeepOn', on);

  /// Whether Android lets the clock open over the lock screen (notifications
  /// and full-screen notifications allowed).
  Future<bool> canOpenFromLock() async => await _method.invokeMethod<bool>('canOpenFromLock') ?? false;

  /// The settings page where that's allowed.
  Future<void> openPermission() => _method.invokeMethod('openPermission');

  /// Opens the clock now (it stays open upright too, until tapped).
  Future<void> showNow() => _method.invokeMethod('showNow');

  /// Closes the clock; on the lock screen, asks to unlock first.
  Future<void> dismiss() => _method.invokeMethod('dismiss');

  /// Whether notification access is on, which reading what's playing needs.
  Future<bool> hasMediaAccess() async => await _method.invokeMethod<bool>('hasMediaAccess') ?? false;

  /// The settings page where notification access is turned on.
  Future<void> openMediaAccess() => _method.invokeMethod('openMediaAccess');

  /// What's playing now (null: nothing), then on every change, for as long
  /// as it's listened to. One listener at a time.
  Stream<NowPlaying?> watchMedia() {
    NowPlaying? last;
    late final StreamController<NowPlaying?> out;
    void add(Map<dynamic, dynamic>? map) {
      last = map == null ? null : NowPlaying.fromMap(map, previous: last);
      if (!out.isClosed) out.add(last);
    }

    out = StreamController<NowPlaying?>(
      onListen: () async {
        _onMedia = add;
        try {
          await _method.invokeMethod('listenMedia', true);
          add(await _method.invokeMapMethod<dynamic, dynamic>('media'));
        } on PlatformException catch (e) {
          out.addError(e);
        }
      },
      onCancel: () {
        if (_onMedia == add) _onMedia = null;
        return _method.invokeMethod('listenMedia', false);
      },
    );
    return out.stream;
  }

  /// Whether the beat pulse may listen (Android's "microphone" permission;
  /// only the phone's own output is read, never the microphone).
  Future<bool> hasAudioPermission() async => await _method.invokeMethod<bool>('hasAudioPermission') ?? false;

  /// Android's permission dialog (from the launcher, not the clock).
  Future<void> requestAudioPermission() => _method.invokeMethod('requestAudioPermission');

  /// The beats of what the phone plays, for as long as it's listened to.
  /// Nothing comes if the phone doesn't allow it. One listener at a time.
  Stream<BeatFrame> watchBeats() {
    late final StreamController<BeatFrame> out;
    out = StreamController<BeatFrame>(
      onListen: () {
        _beats = out;
        _method.invokeMethod<bool>('listenBeats', true).catchError((Object _) => false);
      },
      onCancel: () {
        if (_beats == out) _beats = null;
        return _method.invokeMethod('listenBeats', false);
      },
    );
    return out.stream;
  }

  /// play, pause, toggle, next, previous, or seek (with [position]).
  Future<bool> mediaCommand(String command, {Duration? position}) async =>
      await _method.invokeMethod<bool>('mediaCommand', {
        'command': command,
        if (position != null) 'positionMs': position.inMilliseconds,
      }) ??
      false;

  /// The volume of what's playing (its session's own: a computer's through a
  /// link app, or the phone's music volume), as (current, max).
  Future<(int, int)> volume() async {
    final m = await _method.invokeMapMethod<String, dynamic>('volume');
    return ((m?['current'] as num?)?.toInt() ?? 0, (m?['max'] as num?)?.toInt() ?? 0);
  }

  /// Sets that volume, 0 to its max, without the system's volume panel.
  Future<bool> setVolume(int level) async => await _method.invokeMethod<bool>('setVolume', level) ?? false;

  /// The deck style's EQ and meter levels, for as long as it's listened to.
  /// Nothing comes if the phone doesn't allow it. One listener at a time.
  Stream<SpectrumFrame> watchSpectrum() {
    late final StreamController<SpectrumFrame> out;
    out = StreamController<SpectrumFrame>(
      onListen: () {
        _spectrum = out;
        _method.invokeMethod<bool>('listenSpectrum', true).catchError((Object _) => false);
      },
      onCancel: () {
        if (_spectrum == out) _spectrum = null;
        return _method.invokeMethod('listenSpectrum', false);
      },
    );
    return out.stream;
  }
}
