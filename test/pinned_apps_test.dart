import 'package:flutter_test/flutter_test.dart';
import 'package:minimal_launcher/features/dock/dock_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('reorder moves the given ids first and keeps the rest after them', () async {
    SharedPreferences.setMockInitialValues({
      'dock_app_ids': ['a', 'hidden', 'b', 'c'],
    });
    final dock = DockController(await SharedPreferences.getInstance());

    await dock.reorder(['c', 'a', 'b']);

    expect(dock.ids, ['c', 'a', 'b', 'hidden']);
  });

  test('the dock holds at most five apps', () async {
    SharedPreferences.setMockInitialValues({});
    final dock = DockController(await SharedPreferences.getInstance());
    for (final id in ['1', '2', '3', '4', '5', '6']) {
      await dock.pin(id);
    }
    expect(dock.ids, ['1', '2', '3', '4', '5']);
    expect(dock.isFull, isTrue);
  });
}
