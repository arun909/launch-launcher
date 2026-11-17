import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minimal_launcher/core/widgets/color_wheel.dart';
import 'package:minimal_launcher/features/standard_home/home_layout.dart';
import 'package:minimal_launcher/features/widgets/clock/digital_clock.dart';
import 'package:minimal_launcher/features/widgets/launcher_widgets.dart';
import 'package:minimal_launcher/features/widgets/widget_placement.dart';

/// Tuesday 27 October 2026, 9:05:07 PM.
final _evening = DateTime(2026, 10, 27, 21, 5, 7);

Future<void> _pump(WidgetTester tester, ClockSettings s, {Size size = const Size(320, 140), bool use24h = false}) {
  return tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(alwaysUse24HourFormat: use24h),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox.fromSize(
            size: size,
            child: DigitalClock(settings: s, now: _evening),
          ),
        ),
      ),
    ),
  );
}

/// All the text drawn, spans joined.
String _shown(WidgetTester tester) =>
    tester.widgetList<RichText>(find.byType(RichText)).map((t) => t.text.toPlainText()).join(' | ');

void main() {
  test('the clock is a launcher widget, 2 × 1 up to a quarter of the screen high', () {
    expect(LauncherWidgetKind.fromName('digitalClock'), digitalClockKind);
    final w = launcherWidgetItem(digitalClockKind);
    expect((w.cols, w.rows, w.minCols, w.minRows, w.maxCols, w.maxRows), (4, 2, 2, 1, 6, 2));
  });

  test('each clock keeps its own settings through a save and load; missing ones are defaults', () {
    const custom = ClockSettings(
      font: ClockFont.dots,
      weight: 700,
      color: 0xFFFF453A,
      scale: 0.6,
      hourFormat: ClockHours.h24,
      seconds: true,
      date: false,
      align: ClockAlign.start,
      panel: false,
    );
    final a = launcherWidgetItem(digitalClockKind).copyWith(settings: custom.toJson());
    final b = launcherWidgetItem(digitalClockKind);
    final loaded = decodeLayout(encodeLayout([a, b])).cast<WidgetItem>();
    expect(loaded, [a, b]);
    expect(ClockSettings.fromJson(loaded[0].settings), custom);
    expect(ClockSettings.fromJson(loaded[1].settings), const ClockSettings());
    expect(ClockSettings.fromJson({'font': 'gone', 'scale': 9, 'weight': 5}).scale, 1);
  });

  test('a gradient clock keeps its colours and direction; one colour is no gradient', () {
    const g = ClockSettings(gradient: [0xFFBF953F, 0xFFFCF6BA, 0xFFB38728], gradientDirection: GradientDirection.down);
    final back = ClockSettings.fromJson(g.toJson());
    expect(back, g);
    expect(back.shader()!.colors.length, 3);
    expect(back.shader()!.begin, Alignment.topCenter);
    expect(
      ClockSettings.fromJson({
        'gradient': [0xFF000000],
      }).gradient,
      isNull,
    );
    expect(const ClockSettings().shader(), isNull);
    expect(g.copyWith(gradient: () => null).gradient, isNull);
    expect(g.copyWith(seconds: true).gradient, g.gradient);
  });

  test('wallpaper colours and tap-to-open are saved; wallpaper colours win only once known', () {
    const w = ClockSettings(wallpaperColors: true, tapOpensClock: false, color: 0xFF112233);
    final back = ClockSettings.fromJson(w.toJson());
    expect(back, w);
    expect(const ClockSettings().tapOpensClock, isTrue);
    expect(w.shader(), isNull); // Not known yet: its own solid colour.
    final shader = w.shader(wallpaper: const [Color(0xFFFF0000), Color(0xFF0000FF)])!;
    expect(shader.colors, const [Color(0xFFFF0000), Color(0xFF0000FF)]);
    expect(const ClockSettings().shader(wallpaper: const [Color(0xFFFF0000), Color(0xFF0000FF)]), isNull);
  });

  test('hex values are shown as RRGGBB and read with or without #, in 3 or 6 digits', () {
    expect(ColorWheel.hexOf(const Color(0xFFFF9F0A)), 'FF9F0A');
    expect(ColorWheel.hexOf(const Color(0xFF00000A)), '00000A');
    expect(ColorWheel.parseHex('#ff9f0a'), const Color(0xFFFF9F0A));
    expect(ColorWheel.parseHex('F0A'), const Color(0xFFFF00AA));
    expect(ColorWheel.parseHex('12345'), isNull);
    expect(ColorWheel.parseHex('GGGGGG'), isNull);
  });

  testWidgets('a gradient clock is painted through a gradient mask', (tester) async {
    await _pump(tester, const ClockSettings(gradient: [0xFFFF7E5F, 0xFFFEB47B]));
    expect(find.byType(ShaderMask), findsNWidgets(2)); // time and date
    await _pump(tester, const ClockSettings());
    expect(find.byType(ShaderMask), findsNothing);
  });

  test('a weight a font lacks is drawn at the nearest it has', () {
    expect(const ClockSettings(font: ClockFont.condensed, weight: 900).fontWeight, 700);
    expect(const ClockSettings(font: ClockFont.inter, weight: 900).fontWeight, 900);
  });

  test('times in 12- and 24-hour format', () {
    expect(DigitalClock.formatTime(_evening, use24h: false), ('9:05', '07', 'PM'));
    expect(DigitalClock.formatTime(_evening, use24h: true), ('21:05', '07', ''));
    expect(DigitalClock.formatTime(DateTime(2026, 1, 1, 0, 30), use24h: false).$1, '12:30');
    expect(DigitalClock.formatTime(DateTime(2026, 1, 1, 7, 3), use24h: true).$1, '07:03');
  });

  test('the date gets longer with the room the clock has', () {
    expect(DigitalClock.dateLengthFor(const Size(120, 50)), DateLength.none); // 2 × 1
    expect(DigitalClock.dateLengthFor(const Size(300, 50)), DateLength.medium); // 4 × 1, beside
    expect(DigitalClock.dateLengthFor(const Size(130, 140)), DateLength.short); // 2 × 2
    expect(DigitalClock.dateLengthFor(const Size(200, 140)), DateLength.medium); // 3 × 2
    expect(DigitalClock.dateLengthFor(const Size(320, 140)), DateLength.long); // 4 × 2
    expect(DigitalClock.formatDate(_evening, DateLength.short), 'Tue 27');
    expect(DigitalClock.formatDate(_evening, DateLength.medium), 'Tue, 27 Oct');
    expect(DigitalClock.formatDate(_evening, DateLength.long), 'Tuesday, 27 October');
  });

  testWidgets('follows the phone\'s 12 / 24-hour setting unless told otherwise', (tester) async {
    await _pump(tester, const ClockSettings(), use24h: true);
    expect(_shown(tester), contains('21:05'));
    await _pump(tester, const ClockSettings());
    expect(_shown(tester), contains('9:05 PM'));
    await _pump(tester, const ClockSettings(hourFormat: ClockHours.h24));
    expect(_shown(tester), contains('21:05'));
    await _pump(tester, const ClockSettings(hourFormat: ClockHours.h12, amPm: false), use24h: true);
    expect(_shown(tester), isNot(contains('PM')));
  });

  testWidgets('seconds and the date show only when asked for', (tester) async {
    await _pump(tester, const ClockSettings(seconds: true, hourFormat: ClockHours.h24));
    expect(_shown(tester), contains('21:05:07'));
    expect(_shown(tester), contains('Tuesday, 27 October'));
    await _pump(tester, const ClockSettings(date: false, hourFormat: ClockHours.h24));
    expect(_shown(tester), isNot(contains(':07')));
    expect(_shown(tester), isNot(contains('Oct')));
  });

  testWidgets('fits every size it can be, with nothing overflowing', (tester) async {
    for (final size in const [Size(110, 48), Size(300, 48), Size(130, 140), Size(380, 140)]) {
      for (final font in ClockFont.values) {
        await _pump(
          tester,
          ClockSettings(font: font, seconds: true, hourFormat: ClockHours.h12),
          size: size,
        );
        expect(tester.takeException(), isNull, reason: '$font at $size');
      }
    }
  });
}
