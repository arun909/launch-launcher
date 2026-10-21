import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/apps/apps_controller.dart';
import '../../core/routing/app_routes.dart';
import '../../core/widgets/app_icon.dart';
import 'hidden_apps_controller.dart';

/// Settings > Hidden apps: the only place hidden apps are listed.
class HiddenAppsScreen extends StatelessWidget {
  const HiddenAppsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final all = context.watch<AppsController>().apps;
    final hidden = context.watch<HiddenAppsController>();
    final hiddenApps = all.where((a) => hidden.isHidden(a.id)).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Hidden apps')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.pushNamed(context, AppRoutes.manageApps),
        icon: const Icon(Icons.visibility_off_outlined),
        label: const Text('Choose apps to hide'),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          const _HidingNote(),
          if (hiddenApps.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: Text('No hidden apps')),
            ),
          for (final app in hiddenApps)
            ListTile(
              leading: AppIcon(app: app, size: 40),
              title: Text(app.label),
              subtitle: Text(app.packageName, maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: TextButton(onPressed: () => hidden.unhide(app.id), child: const Text('Unhide')),
            ),
        ],
      ),
    );
  }
}

class _HidingNote extends StatelessWidget {
  const _HidingNote();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.all(16),
      color: scheme.secondaryContainer,
      child: const Padding(
        padding: EdgeInsets.all(16),
        child: Text(
          'Hidden apps are removed from the home screen, app drawer and search '
          'in this launcher only. They are still installed, can still run in '
          'the background, and still appear in Android Settings.',
        ),
      ),
    );
  }
}
