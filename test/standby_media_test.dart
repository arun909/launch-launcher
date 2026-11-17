import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minimal_launcher/core/platform/standby_platform.dart';
import 'package:minimal_launcher/features/standby/standby_clock.dart';
import 'package:minimal_launcher/features/standby/standby_media_tile.dart';
import 'package:minimal_launcher/features/standby/standby_settings.dart';

final _t0 = DateTime(2026, 11, 5, 21, 41, 7);

NowPlaying _song({bool playing = true, Duration? duration = const Duration(minutes: 3, seconds: 33)}) => NowPlaying(
  title: 'Midnight City',
  artist: 'M83',
  app: 'Spotify',
  duration: duration,
  position: const Duration(minutes: 1, seconds: 5),
  playing: playing,
  canSeek: true,
  at: _t0,
);

void main() {
  test('position moves on while playing, stops when paused, stays within the track', () {
    final later = _t0.add(const Duration(seconds: 10));
    expect(_song().positionAt(later), const Duration(minutes: 1, seconds: 15));
    expect(_song(playing: false).positionAt(later), const Duration(minutes: 1, seconds: 5));
    expect(_song().positionAt(_t0.add(const Duration(hours: 1))), const Duration(minutes: 3, seconds: 33));
  });

  test('the cover is kept across updates that leave it out, and dropped on a new track', () {
    final art = Uint8List.fromList([1, 2, 3]);
    final first = NowPlaying.fromMap({'title': 'A', 'artKey': 'a', 'hasArt': true, 'art': art});
    final update = NowPlaying.fromMap({'title': 'A', 'artKey': 'a', 'hasArt': false, 'playing': true}, previous: first);
    expect(update.art, art);
    expect(update.playing, isTrue);
    final next = NowPlaying.fromMap({'title': 'B', 'artKey': 'b', 'hasArt': false}, previous: update);
    expect(next.art, isNull);
  });

  test('says when it plays on a connected computer', () {
    expect(NowPlaying.fromMap({'title': 'A', 'connected': true}).connected, isTrue);
    expect(NowPlaying.fromMap({'title': 'A'}).connected, isFalse);
  });

  Future<void> pumpClock(
    WidgetTester tester,
    NowPlaying? media, {
    List<String>? commands,
    List<Duration>? seeks,
  }) async {
    const size = Size(880, 396);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: StandbyClock(
          settings: const StandbySettings(),
          now: _t0,
          footer: media == null
              ? null
              : (context, width, accent, night) => StandbyMediaTile(
                  media: media,
                  width: width,
                  accent: accent,
                  night: night,
                  now: _t0,
                  onCommand: (c, {position}) {
                    commands?.add(c);
                    if (position != null) seeks?.add(position);
                  },
                ),
        ),
      ),
    );
  }

  testWidgets('the tile shows the track, where it is, its length, and sends the controls', (tester) async {
    final commands = <String>[];
    await pumpClock(tester, _song(), commands: commands);
    expect(find.text('Midnight City'), findsOneWidget);
    expect(find.text('M83  ·  Spotify'), findsOneWidget);
    expect(find.text('1:05'), findsOneWidget);
    expect(find.text('3:33'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.bySemanticsLabel('Pause'));
    await tester.tap(find.bySemanticsLabel('Next'));
    await tester.tap(find.bySemanticsLabel('Previous'));
    expect(commands, ['pause', 'next', 'previous']);
  });

  testWidgets('paused shows play; a stream with no length shows LIVE/PAUSED', (tester) async {
    await pumpClock(tester, _song(playing: false, duration: null));
    expect(find.bySemanticsLabel('Play'), findsOneWidget);
    expect(find.text('PAUSED'), findsOneWidget);
  });

  testWidgets('the clock still fits with the tile, in portrait too', (tester) async {
    await pumpClock(tester, _song());
    expect(tester.takeException(), isNull);
    tester.view.physicalSize = const Size(396, 880);
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('Midnight City'), findsOneWidget);
  });

  testWidgets('dragging across the song moves through it, with a readout while dragging', (tester) async {
    final seeks = <Duration>[];
    await pumpClock(tester, _song(), seeks: seeks);

    // From the title: moves on from where it was (1:05 of 3:33), by the drag.
    final gesture = await tester.startGesture(tester.getCenter(find.text('Midnight City')));
    await gesture.moveBy(const Offset(20, 0));
    await gesture.moveBy(const Offset(60, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Midnight City'), findsNothing);
    expect(find.textContaining('+'), findsOneWidget);
    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(seeks, hasLength(1));
    expect(seeks.single, greaterThan(const Duration(minutes: 1, seconds: 5)));
    expect(find.text('Midnight City'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a tap on the line jumps there', (tester) async {
    final seeks = <Duration>[];
    await pumpClock(tester, _song(), seeks: seeks);
    final line = tester.getRect(
      find.byWidgetPredicate((w) => w is CustomPaint && w.painter.runtimeType.toString() == '_LinePainter'),
    );
    await tester.tapAt(Offset(line.left + line.width * 0.75, line.center.dy));
    expect(seeks, hasLength(1));
    expect(seeks.single.inSeconds, closeTo(213 * 0.75, 3));
  });

  testWidgets('no dragging when the player can\'t seek', (tester) async {
    final seeks = <Duration>[];
    await pumpClock(
      tester,
      NowPlaying(title: 'Radio', duration: const Duration(minutes: 3), playing: true, at: _t0),
      seeks: seeks,
    );
    await tester.drag(find.text('Radio'), const Offset(100, 0));
    await tester.pump(const Duration(milliseconds: 300));
    expect(seeks, isEmpty);
  });
}
