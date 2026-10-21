import 'package:flutter_test/flutter_test.dart';
import 'package:minimal_launcher/core/apps/app_search.dart';
import 'package:minimal_launcher/core/models/app_info.dart';
import 'package:minimal_launcher/features/hidden_apps/hidden_apps_controller.dart';
import 'package:minimal_launcher/features/hidden_apps/visible_apps.dart';
import 'package:shared_preferences/shared_preferences.dart';

AppInfo _app(String label) => AppInfo(
  id: 'pkg.${label.toLowerCase()}/Main',
  label: label,
  packageName: 'pkg.${label.toLowerCase()}',
  activityName: 'Main',
  lastUpdateTime: 0,
);

void main() {
  final camera = _app('Camera');
  final chrome = _app('Chrome');
  final googleCam = _app('Google Camera');
  final all = [camera, chrome, googleCam];

  group('VisibleApps', () {
    test('removes hidden apps from the list and from byId', () {
      final visible = VisibleApps(all, {chrome.id});
      expect(visible.apps, [camera, googleCam]);
      expect(visible.byId(chrome.id), isNull);
      expect(visible.byId(camera.id), camera);
    });

    test('hidden apps never come back through search', () {
      final visible = VisibleApps(all, {chrome.id});
      expect(filterApps(visible.apps, 'chr'), isEmpty);
    });
  });

  group('filterApps', () {
    test('empty query returns everything', () => expect(filterApps(all, '  '), all));

    test('ranks prefix, then word prefix, then substring', () {
      expect(filterApps(all, 'cam'), [camera, googleCam]);
      expect(filterApps(all, 'ROM'), [chrome]);
    });
  });

  group('HiddenAppsController', () {
    test('persists across instances (i.e. app restarts)', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      await HiddenAppsController(prefs).hide(chrome.id);
      final reloaded = HiddenAppsController(prefs);
      expect(reloaded.isHidden(chrome.id), isTrue);

      await reloaded.unhide(chrome.id);
      expect(HiddenAppsController(prefs).isHidden(chrome.id), isFalse);
    });
  });
}
