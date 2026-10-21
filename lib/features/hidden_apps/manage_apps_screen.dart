import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/apps/app_search.dart';
import '../../core/apps/apps_controller.dart';
import '../../core/widgets/app_icon.dart';
import 'hidden_apps_controller.dart';

/// Every installed app with a hide toggle. Reached only from Settings, so
/// its search box doesn't expose hidden apps in the main drawer.
class ManageAppsScreen extends StatefulWidget {
  const ManageAppsScreen({super.key});

  @override
  State<ManageAppsScreen> createState() => _ManageAppsScreenState();
}

class _ManageAppsScreenState extends State<ManageAppsScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final all = context.watch<AppsController>().apps;
    final hidden = context.watch<HiddenAppsController>();
    final apps = filterApps(all, _query);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Choose apps to hide'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(64),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: SearchBar(
              hintText: 'Filter',
              leading: const Icon(Icons.search),
              onChanged: (q) => setState(() => _query = q),
            ),
          ),
        ),
      ),
      body: ListView.builder(
        itemCount: apps.length,
        itemBuilder: (context, i) {
          final app = apps[i];
          return CheckboxListTile(
            secondary: AppIcon(app: app, size: 40),
            title: Text(app.label),
            subtitle: Text(app.packageName, maxLines: 1, overflow: TextOverflow.ellipsis),
            value: hidden.isHidden(app.id),
            onChanged: (v) => hidden.setHidden(app.id, v ?? false),
          );
        },
      ),
    );
  }
}
