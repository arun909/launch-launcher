import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minimal_launcher/core/platform/standby_platform.dart';
import 'package:minimal_launcher/core/widgets/media_glyph.dart';
import 'package:minimal_launcher/features/standard_home/home_layout.dart';
import 'package:minimal_launcher/features/widgets/home_widget_view.dart';
import 'package:minimal_launcher/core/theme/home_grid.dart';
import 'package:minimal_launcher/features/widgets/launcher_widgets.dart';
import 'package:minimal_launcher/features/widgets/music/music_widget.dart';
import 'package:minimal_launcher/features/widgets/music/now_playing_controller.dart';
import 'package:provider/provider.dart';

/// Stands in for the platform: what's playing is set by the test.
class _FakeController extends NowPlayingController {
  _FakeController(this._m, {this.access = true}) : super(StandbyPlatform());

  final NowPlaying? _m;
  final bool access;
  final commands = <String>[];

  @override
  NowPlaying? get media => _m;

  @override
  bool get hasAccess => access;

  @override
  void attach() {}

  @override
  void detach() {}

  @override
  void command(String command, {Duration? position}) => commands.add(command);
}

NowPlaying _song({bool connected = false, bool playing = true, Uint8List? art}) => NowPlaying(
  title: 'A very long song title that never seems to end',
  artist: 'Some Artist',
  album: 'The Album',
  app: connected ? 'Arun’s laptop' : 'Spotify',
  package: 'com.spotify.music',
  connected: connected,
  duration: const Duration(minutes: 3, seconds: 30),
  position: const Duration(minutes: 1),
  playing: playing,
  canSeek: true,
  art: art,
  at: DateTime(2026),
);

Finder _glyph(Glyph g) => find.byWidgetPredicate((w) => w is MediaGlyph && w.glyph == g);

const _grid = HomeGrid.large;
const _cell = Size(92.75, 92.75);

/// Each grid with its cells on a ~412dp-wide phone.
const _grids = [(HomeGrid.large, _cell), (HomeGrid.medium, Size(74.2, 90)), (HomeGrid.compact, Size(61.8, 61.8))];

Future<void> _pump(
  WidgetTester tester,
  NowPlayingController c,
  int cols,
  int rows, [
  Map<String, dynamic>? s,
  (HomeGrid, Size) on = (_grid, _cell),
]) async {
  final size = HomeWidgetView.sizeOf(on.$1, on.$2, cols, rows);
  await tester.pumpWidget(
    MaterialApp(
      home: ChangeNotifierProvider<NowPlayingController?>.value(
        value: c,
        child: Center(
          child: SizedBox.fromSize(
            size: size,
            child: LauncherWidgetView(kind: musicKind, radius: 17, padding: 11, settings: s ?? const {}),
          ),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  const sizes = [(6, 1), (6, 2)];

  testWidgets('lays out cleanly at every size, in every state', (tester) async {
    for (final state in [
      _song(),
      _song(connected: true, playing: false),
      null, // nothing playing
    ]) {
      for (final (c, r) in sizes) {
        for (final grid in _grids) {
          for (final style in panelStyles) {
            final s = MusicSettings(style: style, matchArt: true).toJson();
            await _pump(tester, _FakeController(state), c, r, s, grid);
            expect(tester.takeException(), isNull, reason: '$c×$r ${grid.$1.name} ${style.name} ${state?.title}');
          }
        }
      }
    }
    for (final (c, r) in sizes) {
      for (final grid in _grids) {
        await _pump(tester, _FakeController(null, access: false), c, r, null, grid);
        expect(tester.takeException(), isNull, reason: 'no access $c×$r ${grid.$1.name}');
      }
    }
  });

  testWidgets('4×2 shows the song, album and source, and its buttons work', (tester) async {
    final c = _FakeController(_song());
    await _pump(tester, c, 6, 2);
    expect(find.text('A very long song title that never seems to end'), findsOneWidget);
    expect(find.text('Some Artist  ·  The Album  ·  Spotify'), findsOneWidget);
    await tester.tap(_glyph(Glyph.pause));
    await tester.tap(_glyph(Glyph.next));
    await tester.tap(_glyph(Glyph.previous));
    expect(c.commands, ['pause', 'next', 'previous']);
  });

  testWidgets('a computer’s player shows its name', (tester) async {
    await _pump(tester, _FakeController(_song(connected: true)), 6, 2);
    expect(find.textContaining('Arun’s laptop'), findsOneWidget);
    expect(find.byIcon(Icons.laptop_rounded), findsOneWidget);
  });

  testWidgets('album name can be turned off', (tester) async {
    await _pump(tester, _FakeController(_song()), 6, 2, const MusicSettings(showAlbum: false).toJson());
    expect(find.text('Some Artist  ·  Spotify'), findsOneWidget);
  });

  test('settings round-trip', () {
    const s = MusicSettings(style: GroupStyle.dark, matchArt: true, showAlbum: false);
    final back = MusicSettings.fromJson(s.toJson());
    expect(back.style, GroupStyle.dark);
    expect(back.matchArt, isTrue);
    expect(back.showAlbum, isFalse);
    expect(MusicSettings.fromJson(const {}).style, GroupStyle.glass);
    expect(MusicSettings.fromJson(const {}).matchArt, isFalse);
  });

  test('is an interactive launcher widget starting at 6×2', () {
    expect(LauncherWidgetKind.fromName('music'), same(musicKind));
    expect(musicKind.size, (6, 2));
    expect(musicKind.interactive, isTrue);
  });

  testWidgets('6 × 1 is a strip with all three controls', (tester) async {
    for (final grid in _grids) {
      final c = _FakeController(_song());
      await _pump(tester, c, 6, 1, null, grid);
      expect(find.textContaining('A very long song title', findRichText: true), findsOneWidget);
      await tester.tap(_glyph(Glyph.pause));
      await tester.tap(_glyph(Glyph.next));
      expect(c.commands, ['pause', 'next'], reason: grid.$1.name);
    }
  });

  test('comes only in 6 × 1 and 6 × 2: resizing snaps to the nearer', () {
    expect(musicKind.snap(4, 1), (6, 1));
    expect(musicKind.snap(5, 1), (6, 1));
    expect(musicKind.snap(4, 2), (6, 2));
    expect(musicKind.snap(6, 2), (6, 2));
  });
}
