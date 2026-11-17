import '../../core/apps/pinned_apps_controller.dart';

/// Apps pinned to the home-screen grid.
class HomeAppsController extends PinnedAppsController {
  HomeAppsController(super.prefs) : super(key: 'home_app_ids', maxApps: 8);
}
