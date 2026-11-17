import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minimal_launcher/core/platform/controls_platform.dart';
import 'package:minimal_launcher/features/widgets/controls/brightness_widget.dart';
import 'package:minimal_launcher/features/widgets/controls/display_controller.dart';
import 'package:minimal_launcher/features/widgets/controls/volume_widget.dart';
import 'package:minimal_launcher/features/widgets/launcher_widgets.dart';
import 'package:provider/provider.dart';

/// The brightness widget against a fake phone: records what it asks
/// the phone to change.
void main() {
  const channel = MethodChannel('com.arun.minimal_launcher/controls');
  late List<MethodCall> calls;
  late Map<String, Object> phone;

  setUp(() {
    calls = [];
    phone = {'brightness': 0.25, 'autoBrightness': false, 'nightLight': false, 'extraDim': false, 'darkTheme': false};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      final args = call.arguments as Map?;
      switch (call.method) {
        case 'getDisplay':
          return phone;
        case 'setBrightness':
          phone['brightness'] = args!['value'] as double;
        case 'setAutoBrightness':
          phone['autoBrightness'] = args!['on'] as bool;
      }
      return 'done';
    });
    // The change events: nothing ever arrives.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('com.arun.minimal_launcher/controls/events'),
      (_) async => null,
    );
  });

  /// The widget as on the home screen: 2 × 2, inside its glass panel.
  Future<void> pump(WidgetTester tester) async {
    // The phone's screen: 1080 × 2400 at 2.75.
    tester.view
      ..physicalSize = const Size(1080, 2400)
      ..devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => DisplayController(ControlsPlatform()),
        child: const MaterialApp(
          home: Center(
            child: SizedBox.square(
              dimension: 180,
              child: LauncherWidgetView(kind: brightnessKind, radius: 28, padding: 12),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// The slider: the tile's left column.
  Rect slider(WidgetTester tester) {
    final tile = tester.getRect(find.byType(BrightnessTile));
    return Rect.fromLTRB(tile.left + 16, tile.top + 16, tile.center.dx - 8, tile.bottom - 16);
  }

  double sent() => (calls.lastWhere((c) => c.method == 'setBrightness').arguments as Map)['value'] as double;

  testWidgets('a quick drag up brightens the screen', (tester) async {
    await pump(tester);
    final s = slider(tester);
    await tester.dragFrom(s.center, const Offset(0, -60));
    await tester.pumpAndSettle();
    expect(calls.any((c) => c.method == 'setBrightness'), isTrue);
    expect(sent(), greaterThan(0.25));
  });

  testWidgets('a finger resting before it drags still adjusts brightness', (tester) async {
    await pump(tester);
    final s = slider(tester);
    final g = await tester.startGesture(s.center);
    await tester.pump(const Duration(milliseconds: 800)); // longer than a long-press
    for (var i = 0; i < 6; i++) {
      await g.moveBy(const Offset(0, -10));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await g.up();
    await tester.pumpAndSettle();
    expect(calls.any((c) => c.method == 'setBrightness'), isTrue);
    expect(sent(), greaterThan(0.25));
  });

  testWidgets('tapping the sun turns auto brightness on, and again off', (tester) async {
    await pump(tester);
    final s = slider(tester);
    final sun = Offset(s.center.dx, s.bottom - s.width / 2);
    await tester.tapAt(sun);
    await tester.pumpAndSettle();
    expect(phone['autoBrightness'], isTrue);
    await tester.tapAt(sun);
    await tester.pumpAndSettle();
    expect(phone['autoBrightness'], isFalse);
  });

  testWidgets('dragging in auto mode turns auto off, so the level stays', (tester) async {
    phone['autoBrightness'] = true;
    await pump(tester);
    final s = slider(tester);
    await tester.dragFrom(s.center, const Offset(0, -60));
    await tester.pumpAndSettle();
    expect(phone['autoBrightness'], isFalse);
    expect(sent(), greaterThan(0.25));
  });

  test('brightness and volume are 2 × 2 launcher widgets, on glass unless dark', () {
    for (final name in ['brightness', 'volume']) {
      final kind = LauncherWidgetKind.fromName(name)!;
      expect(kind.size, (2, 2));
      expect(kind.interactive, isTrue);
      expect(kind.styleOf(const {}).name, 'glass');
      expect(kind.styleOf(const {'style': 'dark'}).name, 'dark');
      expect(kind.styleOf(const {'style': 'light'}).name, 'glass');
    }
    expect(volumeKind.name, 'volume');
  });
}
