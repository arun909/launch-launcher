import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/apps/apps_controller.dart';
import 'core/apps/home_role_controller.dart';
import 'core/platform/instant_platform.dart';
import 'core/platform/app_widgets_platform.dart';
import 'core/platform/device_stats_platform.dart';
import 'core/platform/launcher_platform.dart';
import 'core/platform/rotation_platform.dart';
import 'core/platform/standby_platform.dart';
import 'core/platform/system_apps_platform.dart';
import 'core/platform/window_blur_platform.dart';
import 'core/routing/app_routes.dart';
import 'core/theme/app_theme.dart';
import 'core/widgets/rotate_suggestion.dart';
import 'core/platform/controls_platform.dart';
import 'core/platform/sound_platform.dart';
import 'features/widgets/chrome/chrome_sites.dart';
import 'features/widgets/controls/display_controller.dart';
import 'features/widgets/controls/sound_controller.dart';
import 'features/appearance/appearance_controller.dart';
import 'features/dock/dock_controller.dart';
import 'features/hidden_apps/hidden_apps_controller.dart';
import 'features/hidden_apps/visible_apps.dart';
import 'features/home/home_apps_controller.dart';
import 'features/home/home_screen.dart';
import 'features/search_widget/search_widget_controller.dart';
import 'features/standard_home/home_layout.dart';
import 'features/standard_home/home_layout_controller.dart';
import 'features/standby/standby_settings.dart';
import 'features/system_apps/system_apps_controller.dart';
import 'features/widgets/clock/weather.dart';
import 'features/widgets/music/now_playing_controller.dart';
import 'features/web_viewer/full_screen_web_controller.dart';
import 'features/web_viewer/hold_search_controller.dart';
import 'features/widgets/stats/device_stats_controller.dart';

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
  final _appWidgets = AppWidgetsPlatform();

  @override
  void initState() {
    super.initState();
    // Home pressed while we're already in front: back to the home screen.
    _homeSub = widget.platform.homePressed.listen((_) {
      FocusManager.instance.primaryFocus?.unfocus();
      _navigatorKey.currentContext?.read<SearchWidgetController>().stopResizing();
      _navigatorKey.currentContext?.read<HomeLayoutController>().setEditing(false);
      _navigatorKey.currentState?.popUntil((route) => route.isFirst);
    });
    // Catch changes that happened while the process was in the background.
    // The default home app may also have been changed in Android settings.
    // Release app-widget ids no longer on the home screen (removed while the
    // app wasn't running, or an add that never finished).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final layout = _navigatorKey.currentContext?.read<HomeLayoutController>();
      if (layout != null) _appWidgets.keepOnly(layout.widgets.map((w) => w.appWidgetId).whereType<int>());
    });
    // When every icon is redrawn (new icon style), draw the visible ones first.
    widget.apps.iconPriority = () {
      final context = _navigatorKey.currentContext;
      if (context == null) return const [];
      return [
        ...context.read<DockController>().ids,
        ...context.read<HomeAppsController>().ids,
        for (final item in context.read<HomeLayoutController>().items)
          ...switch (item) {
            AppItem(:final appId) => [appId],
            AppContainer(:final appIds) => appIds,
            _ => const <String>[],
          },
      ];
    };
    _lifecycle = AppLifecycleListener(
      onResume: () {
        widget.apps.refresh();
        _homeRole.refresh();
        // Blur can be switched off and on with battery saver.
        _navigatorKey.currentContext?.read<FullScreenWebController>().refresh();
        _navigatorKey.currentContext?.read<HoldSearchController>().refresh();
        _navigatorKey.currentContext?.read<WindowBlurPlatform>()
          ?..refresh()
          ..refreshWallpaper(); // May have been changed meanwhile.
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
    Provider<AppWidgetsPlatform>.value(value: _appWidgets),
    ChangeNotifierProvider(
      create: (_) => WindowBlurPlatform()
        ..refresh()
        ..refreshWallpaper(),
    ),
    ChangeNotifierProvider(create: (_) => RotationPlatform(), lazy: false),
    Provider(create: (_) => StandbyPlatform()),
    // The instant-search widget's scanner, voice input and app hand-offs.
    Provider(create: (_) => InstantPlatform()),
    // What's playing, for the home screen's music widgets.
    ChangeNotifierProvider(create: (c) => NowPlayingController(c.read<StandbyPlatform>())),
    // The phone-stats widget's numbers, and the clock's weather.
    Provider(create: (_) => DeviceStatsPlatform()),
    ChangeNotifierProvider(create: (c) => DeviceStatsController(c.read<DeviceStatsPlatform>())),
    ChangeNotifierProvider(create: (c) => WeatherController(widget.prefs, c.read<DeviceStatsPlatform>())),
    ChangeNotifierProvider(create: (_) => StandbyController(widget.prefs)),
    ChangeNotifierProvider<AppsController>.value(value: widget.apps),
    ChangeNotifierProvider<HomeRoleController>.value(value: _homeRole),
    ChangeNotifierProvider(create: (_) => AppearanceController(widget.prefs, widget.apps)),
    ChangeNotifierProvider(create: (_) => HiddenAppsController(widget.prefs)),
    ChangeNotifierProvider(create: (c) => FullScreenWebController(c.read<InstantPlatform>())),
    ChangeNotifierProvider(create: (c) => HoldSearchController(c.read<InstantPlatform>())),
    ChangeNotifierProvider(create: (_) => HomeAppsController(widget.prefs)),
    ChangeNotifierProvider(create: (_) => HomeLayoutController(widget.prefs, widget.apps)),
    // Its size follows the home grid.
    ChangeNotifierProvider(create: (c) => DockController(widget.prefs, c.read<HomeLayoutController>())),
    ChangeNotifierProvider(create: (_) => SearchWidgetController(widget.prefs)),
    ChangeNotifierProvider(create: (_) => ChromeSitesController(widget.prefs)),
    // The brightness and volume widgets' live state: made (and listening)
    // only once one is on the home screen.
    ChangeNotifierProvider(create: (_) => DisplayController(ControlsPlatform())),
    ChangeNotifierProvider(create: (_) => SoundController(SoundPlatform())),
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
          // Over every screen: the launcher turns only when this is tapped.
          builder: (context, child) => RotateSuggestion(child: child!),
        ),
      ),
    );
  }
}
