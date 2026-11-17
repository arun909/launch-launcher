import 'package:flutter_test/flutter_test.dart';
import 'package:minimal_launcher/features/search_widget/search_widget_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late SearchWidgetController c;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    c = SearchWidgetController(await SharedPreferences.getInstance());
  });

  test('defaults to a visible, full-width, standard-height bar', () {
    expect(c.isVisible, isTrue);
    expect((c.startColumn, c.columns), (0, 4));
    expect(c.height, SearchWidgetHeight.standard);
  });

  test('left edge moves the start and keeps the right edge fixed', () async {
    await c.moveLeftEdge(1);
    expect((c.startColumn, c.columns), (1, 3));
    await c.moveLeftEdge(9); // can't pass the right edge: one column stays
    expect((c.startColumn, c.columns), (3, 1));
  });

  test('right edge changes width only and stays inside the grid', () async {
    await c.moveRightEdge(2);
    expect((c.startColumn, c.columns), (0, 2));
    await c.moveRightEdge(-5);
    expect((c.startColumn, c.columns), (0, 1));
    await c.moveRightEdge(99);
    expect((c.startColumn, c.columns), (0, 4));
  });

  test('size survives a restart; resizing mode does not', () async {
    await c.moveLeftEdge(1);
    await c.setHeight(SearchWidgetHeight.large);
    c.startResizing();

    final again = SearchWidgetController(await SharedPreferences.getInstance());
    expect((again.startColumn, again.columns), (1, 3));
    expect(again.height, SearchWidgetHeight.large);
    expect(again.isResizing, isFalse);
  });

  test('hiding the bar ends resizing', () async {
    c.startResizing();
    await c.setVisible(false);
    expect(c.isResizing, isFalse);
    c.startResizing();
    expect(c.isResizing, isFalse);
  });
}
