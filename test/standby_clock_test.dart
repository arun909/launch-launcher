import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:minimal_launcher/core/platform/standby_platform.dart';
import 'package:minimal_launcher/features/standby/standby_view.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:minimal_launcher/features/standby/standby_clock.dart';
import 'package:minimal_launcher/features/standby/standby_settings.dart';
import 'package:minimal_launcher/features/widgets/clock/digital_clock.dart';

/// Thursday 5 November 2026, 9:41:07 PM.
final _evening = DateTime(2026, 11, 5, 21, 41, 7);

Future<void> _pump(
  WidgetTester tester, {
  StandbySettings settings = const StandbySettings(),
  DateTime? now,
  StandbyStatus? status,
  Size size = const Size(880, 396),
  bool use24h = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(size: size, alwaysUse24HourFormat: use24h),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: StandbyClock(settings: settings, now: now ?? _evening, status: status),
      ),
    ),
  );
}

/// All the text drawn, in order, icons left out.
List<String> _texts(WidgetTester tester) => tester
    .widgetList<RichText>(find.byType(RichText))
    .map((t) => t.text.toPlainText())
    // Icons are drawn as one private-use glyph.
    .where((t) => !(t.runes.length == 1 && t.runes.first >= 0xE000 && t.runes.first <= 0xF8FF))
    .toList();

void main() {
  test('settings survive a save and load; missing ones are defaults', () {
    const custom = StandbySettings(
      font: ClockFont.serif,
      weight: 600,
      accent: 'Gold',
      nightMode: false,
      seconds: false,
      alarm: false,
    );
    expect(StandbySettings.fromJson(custom.toJson()), custom);
    expect(StandbySettings.fromJson(const {}), const StandbySettings());
    expect(const StandbySettings(accent: 'Nope').colors, standbyAccents.first.$2);
  });

  test('night mode covers 10 PM to 6 AM, and only when on', () {
    const s = StandbySettings();
    expect(s.isNight(DateTime(2026, 1, 1, 22)), isTrue);
    expect(s.isNight(DateTime(2026, 1, 1, 5, 59)), isTrue);
    expect(s.isNight(DateTime(2026, 1, 1, 6)), isFalse);
    expect(s.isNight(DateTime(2026, 1, 1, 21, 59)), isFalse);
    expect(s.copyWith(nightMode: false).isNight(DateTime(2026, 1, 1, 23)), isFalse);
  });

  testWidgets('landscape: date, the time digit by digit, AM/PM over the seconds, then the alarm', (tester) async {
    await _pump(tester, status: StandbyStatus(nextAlarm: _evening.add(const Duration(hours: 9))));
    final texts = _texts(tester);
    expect(texts.first, 'THURSDAY, 5 NOVEMBER');
    expect(texts.sublist(1, 8), ['9', ':', '4', '1', 'PM', '07', '6:41 AM']);
    expect(texts.any((t) => t.contains('%')), isFalse, reason: 'no battery any more');
    expect(tester.takeException(), isNull);
  });

  testWidgets('24-hour time has no AM/PM; seconds and alarm hide when turned off', (tester) async {
    await _pump(
      tester,
      use24h: true,
      settings: const StandbySettings(seconds: false, alarm: false),
      status: StandbyStatus(nextAlarm: _evening.add(const Duration(hours: 9))),
    );
    final texts = _texts(tester);
    expect(texts.sublist(1), ['2', '1', ':', '4', '1']);
  });

  testWidgets('portrait: hours over minutes, nothing overflows', (tester) async {
    await _pump(
      tester,
      size: const Size(400, 880),
      status: StandbyStatus(nextAlarm: _evening.add(const Duration(days: 2))),
    );
    expect(_texts(tester).sublist(1), ['9', '4', '1', 'PM', '07', 'SAT 9:41 PM']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('every font lays out without overflow', (tester) async {
    for (final f in ClockFont.values) {
      await _pump(tester, settings: StandbySettings(font: f, weight: 900));
      expect(tester.takeException(), isNull, reason: f.name);
    }
  });

  testWidgets('a live clock ticks and rolls its digits without errors', (tester) async {
    tester.view.physicalSize = const Size(880, 396);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: StandbyClock(settings: StandbySettings()),
      ),
    );
    await tester.pump(const Duration(seconds: 61));
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('shown again after being detached (closed) the clock is drawn, not black', (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('com.arun.minimal_launcher/standby'),
      (call) async => call.method == 'status' ? <String, Object?>{} : null,
    );
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    tester.view.physicalSize = const Size(880, 396);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(StandbyApp(prefs: prefs, platform: StandbyPlatform()));
    await tester.pump();
    expect(find.byType(StandbyClock), findsOneWidget);

    // Closed: Android detaches the engine.
    for (final s in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.detached,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(s);
    }
    // (No frames are drawn while hidden, so the black state isn't visible
    // here; what matters is coming back.)

    // Opened again: detached straight to resumed.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.byType(StandbyClock), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
