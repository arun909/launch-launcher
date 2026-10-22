import 'package:flutter/material.dart';

import '../../features/app_drawer/app_drawer_screen.dart';
import '../../features/hidden_apps/hidden_apps_screen.dart';
import '../../features/hidden_apps/manage_apps_screen.dart';
import '../../features/settings/settings_screen.dart';
import '../../features/system_apps/system_apps_screen.dart';

/// Named routes. A new feature screen = one constant + one case here.
/// The home screen is the Navigator's root (`MaterialApp.home`), not a route.
abstract final class AppRoutes {
  static const drawer = '/drawer';
  static const settings = '/settings';
  static const hiddenApps = '/settings/hidden-apps';
  static const manageApps = '/settings/hidden-apps/manage';
  static const systemApps = '/settings/system-apps';

  static Route<dynamic>? onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case drawer:
        final focusSearch = settings.arguments == true;
        return _DrawerRoute(
          settings: settings,
          child: AppDrawerScreen(autofocusSearch: focusSearch),
        );
      case AppRoutes.settings:
        return MaterialPageRoute(settings: settings, builder: (_) => const SettingsScreen());
      case hiddenApps:
        return MaterialPageRoute(settings: settings, builder: (_) => const HiddenAppsScreen());
      case manageApps:
        return MaterialPageRoute(settings: settings, builder: (_) => const ManageAppsScreen());
      case systemApps:
        return MaterialPageRoute(settings: settings, builder: (_) => const SystemAppsScreen());
    }
    return null;
  }
}

/// Non-opaque slide-up route so the wallpaper stays visible behind the drawer.
class _DrawerRoute extends PageRouteBuilder<void> {
  _DrawerRoute({required Widget child, super.settings})
    : super(
        opaque: false,
        transitionDuration: const Duration(milliseconds: 220),
        reverseTransitionDuration: const Duration(milliseconds: 180),
        pageBuilder: (_, _, _) => child,
        transitionsBuilder: (_, animation, _, child) {
          final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
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
