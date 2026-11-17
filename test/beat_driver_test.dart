import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minimal_launcher/core/platform/standby_platform.dart';
import 'package:minimal_launcher/features/standby/beat_driver.dart';
import 'package:minimal_launcher/features/standby/standby_clock.dart';
import 'package:minimal_launcher/features/standby/standby_settings.dart';

void main() {
  testWidgets('a hit lights one of its band\'s points, which fades and stops ticking', (tester) async {
    final driver = BeatDriver(const TestVSync());
    addTearDown(driver.dispose);
    await tester.pumpWidget(const SizedBox());

    driver.feed(const BeatFrame(beat: true, band: 2, strength: 0.5));
    // Swells in over a few frames rather than snapping on.
    await tester.pump(const Duration(milliseconds: 16));
    final first = driver.pulses[4];
    expect(first, inExclusiveRange(0, 0.6));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(driver.pulses[4], greaterThan(first));
    expect(driver.heat[4], greaterThan(0));
    expect(driver.drift[4].distance, lessThanOrEqualTo(BeatDriver.wander * 1.5));
    expect(driver.energy, driver.pulses[4]);
    // Only that one point: not its partner, nor other bands'.
    for (final i in [0, 1, 2, 3, 5]) {
      expect(driver.pulses[i], 0);
    }

    for (var i = 0; i < 200; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(driver.pulses, everyElement(0));
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('a band\'s hits take turns between its points; a hard one lights both', (tester) async {
    final driver = BeatDriver(const TestVSync());
    addTearDown(driver.dispose);
    await tester.pumpWidget(const SizedBox());

    driver.feed(const BeatFrame(beat: true, strength: 0.5));
    driver.feed(const BeatFrame(beat: true, strength: 0.5));
    await tester.pump(const Duration(milliseconds: 16));
    expect(driver.pulses[0], greaterThan(0));
    expect(driver.pulses[1], greaterThan(0));

    await tester.pump(const Duration(seconds: 3));
    driver.feed(const BeatFrame(beat: true, band: 1, strength: 1));
    await tester.pump(const Duration(milliseconds: 16));
    expect(driver.pulses[2], greaterThan(0));
    expect(driver.pulses[3], greaterThan(0));
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('it is live while hits come, and not once they stop', (tester) async {
    final driver = BeatDriver(const TestVSync());
    addTearDown(driver.dispose);
    await tester.pumpWidget(const SizedBox());
    expect(driver.live.value, isFalse);
    driver.feed(const BeatFrame(beat: true, strength: 0.5));
    expect(driver.live.value, isTrue);
    await tester.pump(const Duration(seconds: 2));
    driver.feed(const BeatFrame(beat: true, band: 1, strength: 0.5));
    await tester.pump(const Duration(seconds: 2));
    expect(driver.live.value, isTrue);
    await tester.pump(BeatDriver.quietAfter);
    expect(driver.live.value, isFalse);
  });

  test('frames that are not hits, or of no known band, leave it still', () {
    final driver = BeatDriver(const TestVSync());
    addTearDown(driver.dispose);
    driver.feed(const BeatFrame(strength: 1));
    driver.feed(const BeatFrame(beat: true, band: 7, strength: 1));
    expect(driver.pulses, everyElement(0));
  });

  for (final size in [const Size(880, 396), const Size(396, 880)]) {
    testWidgets('the clock\'s digits come alive with the hits and settle after (${size.width}x${size.height})', (
      tester,
    ) async {
      final driver = BeatDriver(const TestVSync());
      addTearDown(driver.dispose);
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: StandbyClock(settings: const StandbySettings(), now: DateTime(2026, 11, 5, 21, 41), beats: driver),
        ),
      );
      driver.feed(const BeatFrame(beat: true, strength: 0.5));
      await tester.pump(const Duration(milliseconds: 1700));
      driver.feed(const BeatFrame(beat: true, strength: 1));
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(tester.takeException(), isNull);
      await tester.pump(BeatDriver.quietAfter);
      await tester.pump(const Duration(seconds: 2));
      expect(driver.live.value, isFalse);
      expect(tester.takeException(), isNull);
    });
  }
}
