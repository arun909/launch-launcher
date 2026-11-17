import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/platform/standby_platform.dart';
import 'art_colors.dart';
import 'beat_driver.dart';
import 'deck/deck_view.dart';
import 'deck/spectrum_driver.dart';
import 'standby_clock.dart';
import 'standby_media_tile.dart';
import 'standby_settings.dart';

/// The whole app inside the standby clock's own engine (StandbyEngine.kt,
/// shown by StandbyActivity.kt over the lock screen).
///
/// The engine is kept between showings, so the settings are re-read each
/// time it's shown. While hidden the clock isn't built at all: no timers, no
/// frames.
class StandbyApp extends StatefulWidget {
  const StandbyApp({super.key, required this.prefs, required this.platform});

  final SharedPreferences prefs;
  final StandbyPlatform platform;

  @override
  State<StandbyApp> createState() => _StandbyAppState();
}

class _StandbyAppState extends State<StandbyApp> with WidgetsBindingObserver, TickerProviderStateMixin {
  late StandbySettings _settings = StandbyController.load(widget.prefs);
  StreamSubscription<StandbyStatus>? _sub;
  StandbyStatus? _status;
  bool _shown = true;

  StreamSubscription<NowPlaying?>? _mediaSub;
  NowPlaying? _media;

  /// The shown song's cover colours (null: colourless or none), and whose
  /// they are. Kept as one list per cover, so the clock fades only on a change.
  List<Color>? _artColors;
  String? _artColorsKey;

  /// The beat pulse: listened to only while a song plays on the phone with
  /// its tile up (not at night, not a laptop's track).
  late final BeatDriver _beats = BeatDriver(this);
  StreamSubscription<BeatFrame>? _beatSub;

  /// The deck style's meters and EQ: read only while it's up and a song
  /// plays on the phone.
  late final SpectrumDriver _spectrum = SpectrumDriver(this);
  StreamSubscription<SpectrumFrame>? _spectrumSub;

  bool get _deck => _settings.style == StandbyStyle.deck;

  bool get _wantSpectrum {
    final m = _media;
    return _shown && _deck && _settings.media && m != null && m.playing && !m.connected;
  }

  void _updateSpectrum() {
    if (_wantSpectrum) {
      _spectrumSub ??= widget.platform.watchSpectrum().listen(_spectrum.feed, onError: (Object _) {});
    } else if (_spectrumSub != null) {
      _spectrumSub?.cancel();
      _spectrumSub = null;
      _spectrum.rest();
    }
  }

  bool get _wantBeats {
    final m = _media;
    return _shown &&
        !_deck &&
        _settings.media &&
        _settings.beatPulse &&
        _settings.glow &&
        m != null &&
        m.playing &&
        !m.connected &&
        !_settings.isNight(DateTime.now());
  }

  void _updateBeats() {
    if (_wantBeats) {
      _beatSub ??= widget.platform.watchBeats().listen(_beats.feed, onError: (Object _) {});
    } else {
      _beatSub?.cancel();
      _beatSub = null;
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _show();
  }

  /// From the state itself, not show/hide events: the engine is detached
  /// when the clock closes, and coming back from detached reports only
  /// "start" and "resume", never "show" (which left it black).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed || AppLifecycleState.inactive:
        if (!_shown || _sub == null) _show();
      case AppLifecycleState.hidden || AppLifecycleState.paused || AppLifecycleState.detached:
        if (_shown) _hide();
    }
  }

  Future<void> _show() async {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _sub ??= widget.platform.watch().listen(
      (s) {
        if (s != _status) setState(() => _status = s);
      },
      onError: (Object _) {}, // No alarm line rather than no clock.
    );
    if (mounted) setState(() => _shown = true);
    // Changed in the launcher's settings since the last showing.
    await widget.prefs.reload();
    final next = StandbyController.load(widget.prefs);
    if (mounted && next != _settings) setState(() => _settings = next);
    _watchMedia();
    _updateBeats();
    _updateSpectrum();
  }

  void _watchMedia() {
    if (!_settings.media || !_shown) return _stopMedia();
    _mediaSub ??= widget.platform.watchMedia().listen(
      _onMedia,
      onError: (Object _) {}, // No notification access: no tile.
    );
  }

  void _stopMedia() {
    _mediaSub?.cancel();
    _mediaSub = null;
    if (mounted && _media != null) setState(() => _media = null);
    _media = null;
  }

  void _onMedia(NowPlaying? m) {
    if (!mounted) return;
    // Which tracks are shown (a paused one only if it played since the
    // lock, until unlock) is decided on the Android side, NowPlaying.kt.
    setState(() => _media = m);
    _updateArtColors(m);
    _updateBeats();
    _updateSpectrum();
  }

  Future<void> _updateArtColors(NowPlaying? m) async {
    if (!_settings.matchArt || m == null) return;
    final key = m.art == null ? null : m.artKey ?? m.title;
    if (key == _artColorsKey) return;
    _artColorsKey = key;
    final art = m.art;
    final colors = art == null ? null : await artColors(art);
    // A newer cover came meanwhile: that one wins.
    if (!mounted || _artColorsKey != key) return;
    setState(() => _artColors = colors);
  }

  /// Sent to the player; play/pause shows at once, before it answers.
  void _command(String command, {Duration? position}) {
    final m = _media;
    if (m != null && (command == 'play' || command == 'pause')) {
      final now = DateTime.now();
      _onMedia(m.copyWith(playing: command == 'play', position: m.positionAt(now), at: now));
    } else if (m != null && command == 'seek' && position != null) {
      // Stays where it was dropped, not back to the old spot until the player answers.
      _onMedia(m.copyWith(position: position, at: DateTime.now()));
    }
    HapticFeedback.selectionClick();
    widget.platform.mediaCommand(command, position: position);
  }

  void _hide() {
    _sub?.cancel();
    _sub = null;
    _stopMedia();
    if (mounted) setState(() => _shown = false);
    _updateBeats();
    _updateSpectrum();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sub?.cancel();
    _mediaSub?.cancel();
    _beatSub?.cancel();
    _beats.dispose();
    _spectrumSub?.cancel();
    _spectrum.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(brightness: Brightness.dark, scaffoldBackgroundColor: Colors.black),
    home: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.platform.dismiss,
      child: _shown && _deck
          ? DeckView(
              settings: _settings,
              status: _status,
              media: _settings.media ? _media : null,
              spectrum: _spectrum,
              colors: _settings.media && _settings.matchArt && _media != null ? _artColors : null,
              onCommand: _command,
            )
          : _shown
          ? StandbyClock(
              settings: _settings,
              status: _status,
              // The song's colours while its tile is up.
              colors: _settings.media && _settings.matchArt && _media != null ? _artColors : null,
              beats: _settings.media && _settings.beatPulse && _settings.glow ? _beats : null,
              art: _settings.media && _settings.artGlow ? _media?.art : null,
              artKey: _media?.artKey ?? _media?.title,
              footer: switch (_media) {
                final m? when _settings.media => (context, width, accent, night) => StandbyMediaTile(
                  media: m,
                  width: width,
                  accent: accent,
                  night: night,
                  onCommand: _command,
                ),
                _ => null,
              },
            )
          : const ColoredBox(color: Colors.black),
    ),
  );
}
