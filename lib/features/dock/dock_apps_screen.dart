import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/apps/app_search.dart';
import '../../core/models/app_info.dart';
import '../../core/widgets/app_icon.dart';
import '../hidden_apps/visible_apps.dart';
import '../standard_home/home_layout.dart';
import '../widgets/launcher_widgets.dart';
import 'dock_controller.dart';

/// Settings > Dock apps: reorder, remove and add the apps in the dock.
class DockAppsScreen extends StatelessWidget {
  const DockAppsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final visible = context.watch<VisibleApps>();
    final dock = context.watch<DockController>();
    final apps = dock.ids.map(visible.byId).whereType<AppInfo>().toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Dock apps')),
      floatingActionButton: dock.isFull
          ? null
          : FloatingActionButton.extended(
              onPressed: () =>
                  Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const _AddDockAppScreen())),
              icon: const Icon(Icons.add),
              label: const Text('Add app'),
            ),
      body: apps.isEmpty
          ? const Center(child: Text('The dock is empty'))
          : ReorderableListView(
              padding: const EdgeInsets.only(top: 8, bottom: 96),
              header: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Also on the home screen: long-press the dock's empty space.
                    Text('Background', style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 8),
                    PanelStylePicker(value: dock.style, onChanged: (v) => dock.setStyle(v ?? GroupStyle.light)),
                    const SizedBox(height: 16),
                    Text(
                      '${apps.length} of ${dock.maxApps} · drag to reorder',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              buildDefaultDragHandles: false,
              onReorderItem: (from, to) {
                final order = apps.map((a) => a.id).toList();
                order.insert(to, order.removeAt(from));
                dock.reorder(order);
              },
              children: [
                for (final (i, app) in apps.indexed)
                  ListTile(
                    key: ValueKey(app.id),
                    leading: AppIcon(app: app, size: 40),
                    title: Text(app.label),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Remove from dock',
                          icon: const Icon(Icons.remove_circle_outline),
                          onPressed: () => dock.unpin(app.id),
                        ),
                        ReorderableDragStartListener(index: i, child: const Icon(Icons.drag_handle)),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}

/// Searchable list of apps not yet in the dock; tapping one adds it.
class _AddDockAppScreen extends StatefulWidget {
  const _AddDockAppScreen();

  @override
  State<_AddDockAppScreen> createState() => _AddDockAppScreenState();
}

class _AddDockAppScreenState extends State<_AddDockAppScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final dock = context.read<DockController>();
    final apps = filterApps(context.watch<VisibleApps>().apps.where((a) => !dock.isPinned(a.id)).toList(), _query);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Add to dock'),
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
          return ListTile(
            leading: AppIcon(app: app, size: 40),
            title: Text(app.label),
            onTap: () {
              dock.pin(app.id);
              Navigator.pop(context);
            },
          );
        },
      ),
    );
  }
}
