import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/apps/apps_controller.dart';
import 'core/apps/home_role_controller.dart';
import 'core/platform/launcher_platform.dart';
import 'core/platform/system_apps_platform.dart';
import 'core/routing/app_routes.dart';
import 'core/theme/app_theme.dart';
import 'features/hidden_apps/hidden_apps_controller.dart';
import 'features/hidden_apps/visible_apps.dart';
import 'features/home/home_apps_controller.dart';
import 'features/home/home_screen.dart';
import 'features/system_apps/system_apps_controller.dart';

/// Root widget: dependency wiring (providers) and launcher-level behaviour.
///
/// To add a feature with state: create its controller in its own module and
/// register it in [_providers]. Nothing else here should need to change.
class LauncherApp extends StatefulWidget {
  const LauncherApp({super.key, required this.prefs, required this.platform, required this.apps});

  final SharedPreferences prefs;
  final LauncherPlatform platform;
  final AppsController apps;

  @override
  State<LauncherApp> createState() => _LauncherAppState();
}

class _LauncherAppState extends State<LauncherApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  late final StreamSubscription<void> _homeSub;
  late final AppLifecycleListener _lifecycle;
  late final HomeRoleController _homeRole = HomeRoleController(widget.platform);

  @override
  void initState() {
    super.initState();
    // Home pressed while we're already in front: back to the home screen.
    _homeSub = widget.platform.homePressed.listen((_) {
      FocusManager.instance.primaryFocus?.unfocus();
      _navigatorKey.currentState?.popUntil((route) => route.isFirst);
    });
    // Catch changes that happened while the process was in the background.
    // The default home app may also have been changed in Android settings.
    _lifecycle = AppLifecycleListener(
      onResume: () {
        widget.apps.refresh();
        _homeRole.refresh();
      },
    );
  }

  @override
  void dispose() {
    _homeSub.cancel();
    _lifecycle.dispose();
    _homeRole.dispose();
    super.dispose();
  }

  List<SingleChildWidget> get _providers => [
    Provider<LauncherPlatform>.value(value: widget.platform),
    ChangeNotifierProvider<AppsController>.value(value: widget.apps),
    ChangeNotifierProvider<HomeRoleController>.value(value: _homeRole),
    ChangeNotifierProvider(create: (_) => HiddenAppsController(widget.prefs)),
    ChangeNotifierProvider(create: (_) => HomeAppsController(widget.prefs)),
    ChangeNotifierProvider(create: (_) => SystemAppsController(SystemAppsPlatform(), widget.prefs)),
    // The hidden-app filter, applied once for every app-listing surface.
    ProxyProvider2<AppsController, HiddenAppsController, VisibleApps>(
      update: (_, apps, hidden, _) => VisibleApps(apps.apps, hidden.hiddenIds),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: _providers,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          systemNavigationBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
        ),
        child: MaterialApp(
          title: 'Minimal Launcher',
          debugShowCheckedModeBanner: false,
          navigatorKey: _navigatorKey,
          theme: AppTheme.dark(),
          home: const HomeScreen(),
          onGenerateRoute: AppRoutes.onGenerateRoute,
        ),
      ),
    );
  }
}
