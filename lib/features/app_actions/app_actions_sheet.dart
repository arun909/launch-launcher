import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/apps/apps_controller.dart';
import '../../core/apps/pinned_apps_controller.dart';
import '../../core/models/app_info.dart';
import '../../core/platform/app_widgets_platform.dart';
import '../../core/platform/launcher_platform.dart';
import '../../core/routing/app_routes.dart';
import '../../core/widgets/app_icon.dart';
import '../dock/dock_controller.dart';
import '../hidden_apps/hidden_apps_controller.dart';
import '../home/home_apps_controller.dart';
import '../standard_home/container_sheets.dart';
import '../standard_home/home_layout_controller.dart';

/// Long-press menu for an app, shared by the home screen and the drawer.
/// New per-app actions go here.
Future<void> showAppActions(BuildContext context, AppInfo app) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => _AppActionsSheet(app: app),
  );
}

class _AppActionsSheet extends StatelessWidget {
  const _AppActionsSheet({required this.app});

  final AppInfo app;

  @override
  Widget build(BuildContext context) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final layout = context.watch<HomeLayoutController>();
    final standard = layout.mode == HomeMode.standard;
    final container = standard ? layout.containerOf(app.id) : null;

    return SafeArea(
      // Scrolls when the screen is too short for every action (landscape).
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: AppIcon(app: app, size: 40),
              title: Text(app.label, style: Theme.of(context).textTheme.titleMedium),
              subtitle: Text(app.packageName),
            ),
            const Divider(),
            // Standard mode has every app on home already; containers instead.
            if (!standard)
              _PinTile(
                app: app,
                list: context.watch<HomeAppsController>(),
                place: 'home',
                addIcon: Icons.add_to_home_screen,
              )
            else if (container != null)
              ListTile(
                leading: const Icon(Icons.drive_file_move_rtl_outlined),
                title: Text('Remove from "${container.name}"'),
                subtitle: const Text('Put it back on the home screen'),
                onTap: () {
                  layout.removeFromContainer(app.id);
                  Navigator.pop(context);
                },
              )
            else
              ListTile(
                leading: const Icon(Icons.create_new_folder_outlined),
                title: const Text('Add to folder or container'),
                onTap: () {
                  // The navigator's context outlives this sheet.
                  final navigator = Navigator.of(context)..pop();
                  showAddToGroup(navigator.context, app);
                },
              ),
            _PinTile(
              app: app,
              list: context.watch<DockController>(),
              place: 'dock',
              addIcon: Icons.call_to_action_outlined,
            ),
            // Widgets go on the standard home's pages only.
            if (standard) _WidgetsTile(app: app),
            ListTile(
              leading: const Icon(Icons.palette_outlined),
              title: const Text('Change icon'),
              onTap: () {
                final navigator = Navigator.of(context)..pop();
                navigator.pushNamed(AppRoutes.iconPicker, arguments: app.id);
              },
            ),
            ListTile(
              leading: const Icon(Icons.visibility_off_outlined),
              title: const Text('Hide app'),
              subtitle: const Text('Only hides it in this launcher'),
              onTap: () {
                final hidden = context.read<HiddenAppsController>();
                hidden.hide(app.id);
                Navigator.pop(context);
                messenger?.showSnackBar(
                  SnackBar(
                    persist: false, // with an action, Flutter otherwise keeps it until tapped
                    content: Text('${app.label} hidden'),
                    action: SnackBarAction(label: 'Undo', onPressed: () => hidden.unhide(app.id)),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('App info'),
              onTap: () {
                context.read<AppsController>().openAppInfo(app);
                Navigator.pop(context);
              },
            ),
            // Not for this launcher's own entry ("Launcher Settings").
            if (app.packageName != LauncherPlatform.selfPackage)
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Uninstall'),
                onTap: () async {
                  final apps = context.read<AppsController>();
                  Navigator.pop(context);
                  final ok = await apps.uninstall(app);
                  if (!ok) messenger?.showSnackBar(SnackBar(content: Text("Couldn't uninstall ${app.label}")));
                },
              ),
          ],
        ),
      ),
    );
  }
}

/// "Widgets": the app's own widgets, shown only if it offers any.
class _WidgetsTile extends StatefulWidget {
  const _WidgetsTile({required this.app});

  final AppInfo app;

  @override
  State<_WidgetsTile> createState() => _WidgetsTileState();
}

class _WidgetsTileState extends State<_WidgetsTile> {
  late final Future<int> _count = context
      .read<AppWidgetsPlatform>()
      .getProviders()
      .then((all) => all.where((p) => p.packageName == widget.app.packageName).length)
      .catchError((_) => 0);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<int>(
      future: _count,
      builder: (context, snapshot) {
        final n = snapshot.data ?? 0;
        if (n == 0) return const SizedBox.shrink();
        return ListTile(
          leading: const Icon(Icons.widgets_outlined),
          title: const Text('Widgets'),
          subtitle: Text(n == 1 ? '1 widget' : '$n widgets'),
          onTap: () {
            final navigator = Navigator.of(context)..pop();
            navigator.pushNamed(AppRoutes.widgets, arguments: widget.app);
          },
        );
      },
    );
  }
}

/// "Add to …" / "Remove from …" for one pinned-apps list (home or dock).
class _PinTile extends StatelessWidget {
  const _PinTile({required this.app, required this.list, required this.place, required this.addIcon});

  final AppInfo app;
  final PinnedAppsController list;
  final String place;
  final IconData addIcon;

  @override
  Widget build(BuildContext context) {
    if (list.isPinned(app.id)) {
      return ListTile(
        leading: const Icon(Icons.remove_circle_outline),
        title: Text('Remove from $place'),
        onTap: () {
          list.unpin(app.id);
          Navigator.pop(context);
        },
      );
    }
    return ListTile(
      leading: Icon(addIcon),
      title: Text('Add to $place'),
      enabled: !list.isFull,
      subtitle: list.isFull ? Text('The $place is full (${list.maxApps} apps)') : null,
      onTap: () {
        list.pin(app.id);
        Navigator.pop(context);
      },
    );
  }
}

/// Launches [app], showing a message if Android couldn't start it.
/// Returns whether another app was launched (callers then close the drawer).
///
/// The launcher's own entry ("Launcher Settings") opens the settings screen
/// on top instead, and returns false so the drawer stays underneath for Back.
Future<bool> openApp(BuildContext context, AppInfo app) async {
  if (app.packageName == LauncherPlatform.selfPackage) {
    Navigator.pushNamed(context, AppRoutes.settings);
    return false;
  }
  final messenger = ScaffoldMessenger.maybeOf(context);
  final ok = await context.read<AppsController>().launch(app);
  if (!ok) {
    messenger?.showSnackBar(SnackBar(content: Text("Couldn't open ${app.label}")));
  }
  return ok;
}
