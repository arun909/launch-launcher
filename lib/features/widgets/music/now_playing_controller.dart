import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../../core/platform/standby_platform.dart';
import '../../standby/art_colors.dart';

/// What's playing, for the home screen's music widgets: any app on the
/// phone, or a computer's player relayed by a link app (Phone Link, KDE
/// Connect…). Which session wins is decided on the Android side
/// (NowPlaying.kt): playing on the phone first, then on a computer, then
/// paused ones.
///
/// Listens only while a music widget is on screen ([attach] / [detach]) and
/// the launcher is in front: Android pushes changes, nothing polls.
class NowPlayingController extends ChangeNotifier with WidgetsBindingObserver {
  NowPlayingController(this._platform) {
    WidgetsBinding.instance.addObserver(this);
  }

  final StandbyPlatform _platform;

  StreamSubscription<NowPlaying?>? _sub;
  int _users = 0;
  bool _foreground = true;
  bool _disposed = false;

  /// What's playing; null when nothing is.
  NowPlaying? get media => _media;
  NowPlaying? _media;

  /// The cover's two main colours (bright, for lines and glows); null
  /// without a cover or for a colourless one.
  List<Color>? get artPalette => _artPalette;
  List<Color>? _artPalette;
  String? _artKey;

  /// Whether notification access is on (reading other apps' players needs
  /// it). Assumed on until checked.
  bool get hasAccess => _hasAccess;
  bool _hasAccess = true;

  /// A music widget appeared.
  void attach() {
    _users++;
    _update();
  }

  /// A music widget went away.
  void detach() {
    _users--;
    _update();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final front = state == AppLifecycleState.resumed || state == AppLifecycleState.inactive;
    if (front == _foreground) return;
    _foreground = front;
    _update();
  }

  Future<void> _update() async {
    final want = _users > 0 && _foreground;
    if (!want) {
      await _sub?.cancel();
      _sub = null;
      return;
    }
    if (_sub != null) return;
    // Back from settings: access may have just been turned on.
    final access = await _platform.hasMediaAccess().catchError((Object _) => false);
    if (_disposed) return;
    if (access != _hasAccess) {
      _hasAccess = access;
      notifyListeners();
    }
    if (!access || _sub != null || !(_users > 0 && _foreground)) return;
    _sub = _platform.watchMedia().listen(_set, onError: (Object _) => _set(null));
  }

  void _set(NowPlaying? m) {
    if (_disposed) return;
    _media = m;
    notifyListeners();
    _updatePalette(m);
  }

  Future<void> _updatePalette(NowPlaying? m) async {
    final art = m?.art;
    final key = art == null ? null : m!.artKey ?? m.title;
    if (key == _artKey) return;
    _artKey = key;
    final colors = art == null ? null : await artColors(art);
    // A newer cover came meanwhile: that one wins.
    if (_disposed || _artKey != key) return;
    _artPalette = colors;
    notifyListeners();
  }

  /// play, pause, toggle, next, previous, or seek (with [position]), to the
  /// player shown. Play / pause shows at once, before the player answers.
  /// With nothing shown, play resumes the last player (by media key).
  void command(String command, {Duration? position}) {
    final m = _media;
    final now = DateTime.now();
    if (m != null && command == 'toggle') command = m.playing ? 'pause' : 'play';
    if (m != null && (command == 'play' || command == 'pause')) {
      _set(m.copyWith(playing: command == 'play', position: m.positionAt(now), at: now));
    } else if (m != null && command == 'seek' && position != null) {
      _set(m.copyWith(position: position, at: now));
    }
    HapticFeedback.selectionClick();
    _platform.mediaCommand(command, position: position);
  }

  /// The volume as (current, max), read when a volume drag starts.
  Future<(int, int)> volume() => _platform.volume().catchError((Object _) => (0, 0));

  /// Sets the volume level (0 to max).
  void setVolume(int level) => _platform.setVolume(level);

  /// Where notification access is turned on.
  Future<void> openAccess() => _platform.openMediaAccess();

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _sub?.cancel();
    super.dispose();
  }
}
