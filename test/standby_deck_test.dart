import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minimal_launcher/core/platform/standby_platform.dart';
import 'package:minimal_launcher/features/standby/deck/deck_view.dart';
import 'package:minimal_launcher/features/standby/deck/record_player.dart';
import 'package:minimal_launcher/features/standby/deck/spectrum_driver.dart';
import 'package:minimal_launcher/features/standby/standby_settings.dart';

class _Vsync implements TickerProvider {
  @override
  Ticker createTicker(TickerCallback onTick) => Ticker(onTick);
}

final _now = DateTime(2026, 11, 5, 21, 41, 8);

Future<void> _pump(WidgetTester tester, {NowPlaying? media, List<String>? commands}) async {
  tester.view.physicalSize = const Size(880, 396);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: DeckView(
        settings: const StandbySettings(style: StandbyStyle.deck),
        now: _now,
        media: media,
        onCommand: (c, {position}) => commands?.add(c),
      ),
    ),
  );
}

void main() {
  test('the style survives a save and load; glow by default', () {
    const deck = StandbySettings(style: StandbyStyle.deck, accent: 'Gold');
    expect(StandbySettings.fromJson(deck.toJson()), deck);
    expect(StandbySettings.fromJson(const {}).style, StandbyStyle.glow);
    expect(StandbySettings.fromJson(const {'style': 'nope'}).style, StandbyStyle.glow);
  });

  testWidgets('without music: a resting deck, transport off, no volume controls', (tester) async {
    final commands = <String>[];
    await _pump(tester, commands: commands);
    expect(find.text('Nothing playing'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Previous'));
    expect(commands, isEmpty);
    expect(find.bySemanticsLabel('Volume up'), findsNothing);
  });

  testWidgets('night mode turns the deck red at night, only when on', (tester) async {
    Future<void> at(DateTime t, {bool night = true}) async {
      await tester.pumpWidget(
        MaterialApp(
          home: DeckView(
            settings: StandbySettings(style: StandbyStyle.deck, nightMode: night),
            now: t,
          ),
        ),
      );
    }

    await at(DateTime(2026, 11, 5, 23, 10));
    expect(find.byType(ColorFiltered), findsOneWidget);
    await at(DateTime(2026, 11, 5, 23, 10), night: false);
    expect(find.byType(ColorFiltered), findsNothing);
    await at(DateTime(2026, 11, 5, 14, 10));
    expect(find.byType(ColorFiltered), findsNothing);
  });

  testWidgets('with music: track, times and controls', (tester) async {
    final commands = <String>[];
    await _pump(
      tester,
      commands: commands,
      media: NowPlaying(
        title: 'Midnight City',
        artist: 'M83',
        duration: const Duration(minutes: 4, seconds: 3),
        position: const Duration(minutes: 1, seconds: 22),
        at: _now,
      ),
    );
    expect(find.text('Midnight City'), findsOneWidget);
    expect(find.text('1:22'), findsOneWidget);
    expect(find.text('-2:41'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Play'));
    await tester.tap(find.bySemanticsLabel('Next'));
    expect(commands, ['play', 'next']);
  });

  testWidgets('meters jump up, then fall to rest once readings stop', (tester) async {
    final d = SpectrumDriver(_Vsync());
    addTearDown(d.dispose);
    d.feed(SpectrumFrame(bands: List.filled(10, 0.9), left: 0.95, right: 0.5));
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 100));
    expect(d.bands.first, greaterThan(0.8));
    expect(d.overload, [true, false]);
    for (var i = 0; i < 300; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(d.bands.every((b) => b == 0), isTrue);
    expect(d.needles.every((n) => n < 0.01), isTrue);
  });

  testWidgets('the record spins while playing and brakes to a stop on pause', (tester) async {
    Widget player(bool playing) => MaterialApp(
      home: SizedBox(
        width: 200,
        height: 200,
        child: RecordPlayer(playing: playing, accent: const [Colors.amber]),
      ),
    );
    double angle() {
      final t = tester.widget<Transform>(
        find.descendant(of: find.byType(RecordPlayer), matching: find.byType(Transform)).first,
      );
      return t.transform.storage[1]; // sin of the angle
    }

    await tester.pumpWidget(player(true));
    for (var i = 0; i < 120; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    final spinning = angle();
    await tester.pump(const Duration(milliseconds: 100));
    expect(angle(), isNot(spinning));

    await tester.pumpWidget(player(false));
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 300));
    final braking = angle();
    await tester.pump(const Duration(milliseconds: 100));
    expect(angle(), isNot(braking), reason: 'still slowing down');
    for (var i = 0; i < 100; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    final stopped = angle();
    await tester.pump(const Duration(seconds: 1));
    expect(angle(), stopped);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });
}
