import '../../core/models/app_info.dart';

/// The installed apps minus hidden ones: the only app list that user-facing
/// surfaces (home, drawer, search) should read.
///
/// Keeping the hidden filter in exactly one place means a new feature that
/// lists apps can't accidentally leak hidden apps. Built in app.dart via a
/// ProxyProvider from AppsController + HiddenAppsController.
class VisibleApps {
  VisibleApps(List<AppInfo> all, Set<String> hiddenIds)
    : apps = List.unmodifiable(all.where((a) => !hiddenIds.contains(a.id))) {
    _byId = {for (final a in apps) a.id: a};
  }

  /// Visible apps, in the same (label-sorted) order as AppsController.
  final List<AppInfo> apps;
  late final Map<String, AppInfo> _byId;

  /// The app if installed and visible, else null.
  AppInfo? byId(String id) => _byId[id];
}
