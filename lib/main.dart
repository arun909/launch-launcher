import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/apps/app_cache.dart';
import 'core/apps/apps_controller.dart';
import 'core/platform/launcher_platform.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  // Loaded before the first frame so hidden apps are never briefly visible.
  final prefs = await SharedPreferences.getInstance();
  final platform = LauncherPlatform();
  final apps = AppsController(platform, AppCache());
  apps.init(); // cache first, then live refresh; UI updates as it goes

  runApp(LauncherApp(prefs: prefs, platform: platform, apps: apps));
}
