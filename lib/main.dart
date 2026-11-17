import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/apps/app_cache.dart';
import 'core/apps/apps_controller.dart';
import 'core/platform/launcher_platform.dart';
import 'core/platform/standby_platform.dart';
import 'features/appearance/appearance_controller.dart';
import 'features/standby/standby_view.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  // Loaded before the first frame so hidden apps are never briefly visible.
  final prefs = await SharedPreferences.getInstance();
  final platform = LauncherPlatform();
  final apps = AppsController(
    platform,
    AppCache(),
    iconShape: AppearanceController.savedIconShape(prefs),
    iconStyle: AppearanceController.savedIconStyle(prefs),
    iconOverrides: AppearanceController.savedIconOverrides(prefs),
  );
  apps.init(); // cache first, then live refresh; UI updates as it goes

  runApp(LauncherApp(prefs: prefs, platform: platform, apps: apps));
}

/// The standby clock's own engine (StandbyEngine.kt) starts here: just the
/// clock, none of the launcher.
@pragma('vm:entry-point')
Future<void> standbyMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  runApp(StandbyApp(prefs: prefs, platform: StandbyPlatform()));
}
