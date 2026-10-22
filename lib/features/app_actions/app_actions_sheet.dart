import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/apps/apps_controller.dart';
import '../../core/models/app_info.dart';
import '../../core/widgets/app_icon.dart';
import '../hidden_apps/hidden_apps_controller.dart';
import '../home/home_apps_controller.dart';

/// Long-press menu for an app, shared by the home screen and the drawer.
/// New per-app actions (e.g. "Uninstall" later) go here.
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
    final home = context.watch<HomeAppsController>();
    final pinned = home.isPinned(app.id);
    final messenger = ScaffoldMessenger.maybeOf(context);

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: AppIcon(app: app, size: 40),
            title: Text(app.label, style: Theme.of(context).textTheme.titleMedium),
            subtitle: Text(app.packageName),
          ),
          const Divider(),
          if (pinned)
            ListTile(
              leading: const Icon(Icons.remove_circle_outline),
              title: const Text('Remove from home'),
              onTap: () {
                home.unpin(app.id);
                Navigator.pop(context);
              },
            )
          else
            ListTile(
              leading: const Icon(Icons.add_to_home_screen),
              title: const Text('Add to home'),
              enabled: !home.isFull,
              subtitle: home.isFull ? const Text('Home is full (${HomeAppsController.maxApps} apps)') : null,
              onTap: () {
                home.pin(app.id);
                Navigator.pop(context);
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
        ],
      ),
    );
  }
}

/// Launches [app], showing a message if Android couldn't start it.
/// Returns whether it launched.
Future<bool> openApp(BuildContext context, AppInfo app) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final ok = await context.read<AppsController>().launch(app);
  if (!ok) {
    messenger?.showSnackBar(SnackBar(content: Text("Couldn't open ${app.label}")));
  }
  return ok;
}
