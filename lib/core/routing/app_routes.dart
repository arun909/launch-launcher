import 'package:flutter/material.dart';

import '../models/app_info.dart';

import '../../features/app_drawer/app_drawer_screen.dart';
import '../../features/app_drawer/quick_search_screen.dart';
import '../../features/appearance/icon_picker_screen.dart';
import '../../features/appearance/icons_screen.dart';
import '../../features/dock/dock_apps_screen.dart';
import '../../features/hidden_apps/hidden_apps_screen.dart';
import '../../features/hidden_apps/manage_apps_screen.dart';
import '../../features/standby/standby_settings_screen.dart';
import '../../features/settings/settings_screen.dart';
import '../../features/system_apps/system_apps_screen.dart';
import '../../features/web_viewer/hold_search_apps_screen.dart';
import '../../features/widgets/widget_picker_screen.dart';

/// Named routes. A new feature screen = one constant + one case here.
/// The home screen is the Navigator's root (`MaterialApp.home`), not a route.
abstract final class AppRoutes {
  static const drawer = '/drawer';
  static const search = '/search';
  static const settings = '/settings';
  static const hiddenApps = '/settings/hidden-apps';
  static const manageApps = '/settings/hidden-apps/manage';
  static const systemApps = '/settings/system-apps';
  static const dockApps = '/settings/dock-apps';
  static const icons = '/settings/icons';
  static const standbySettings = '/settings/standby';
  static const holdSearchApps = '/settings/hold-search-apps';

  /// Arguments: the app id (String).
  static const iconPicker = '/icon-picker';
  static const widgets = '/widgets';

  static Route<dynamic>? onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case drawer:
        return _DrawerRoute(settings: settings, child: const AppDrawerScreen());
      case search:
        return _DrawerRoute(settings: settings, child: const QuickSearchScreen());
      case AppRoutes.settings:
        return MaterialPageRoute(settings: settings, builder: (_) => const SettingsScreen());
      case hiddenApps:
        return MaterialPageRoute(settings: settings, builder: (_) => const HiddenAppsScreen());
      case manageApps:
        return MaterialPageRoute(settings: settings, builder: (_) => const ManageAppsScreen());
      case icons:
        return MaterialPageRoute(settings: settings, builder: (_) => const IconsScreen());
      case iconPicker:
        final appId = settings.arguments as String;
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => IconPickerScreen(appId: appId),
        );
      case dockApps:
        return MaterialPageRoute(settings: settings, builder: (_) => const DockAppsScreen());
      case widgets:
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => WidgetPickerScreen(app: settings.arguments as AppInfo?),
        );
      case standbySettings:
        return MaterialPageRoute(settings: settings, builder: (_) => const StandbySettingsScreen());
      case holdSearchApps:
        return MaterialPageRoute(settings: settings, builder: (_) => const HoldSearchAppsScreen());
      case systemApps:
        return MaterialPageRoute(settings: settings, builder: (_) => const SystemAppsScreen());
    }
    return null;
  }
}

/// Non-opaque slide-up route so the wallpaper stays visible behind the drawer
/// (and behind quick search).
class _DrawerRoute extends PageRouteBuilder<void> {
  _DrawerRoute({required Widget child, super.settings})
    : super(
        opaque: false,
        transitionDuration: const Duration(milliseconds: 220),
        reverseTransitionDuration: const Duration(milliseconds: 180),
        pageBuilder: (_, _, _) => child,
        transitionsBuilder: (_, animation, _, child) {
          // Closing starts fast and settles gently, mirroring the opening
          // (the default would reverse easeOut: slow start, abrupt end).
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );
          return FadeTransition(
            opacity: curved,
            child: SlideTransition(
              position: Tween(begin: const Offset(0, 0.08), end: Offset.zero).animate(curved),
              child: child,
            ),
          );
        },
      );
}
