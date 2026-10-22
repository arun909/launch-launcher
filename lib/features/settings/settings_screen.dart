import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/apps/apps_controller.dart';
import '../../core/platform/launcher_platform.dart';
import '../../core/routing/app_routes.dart';
import '../hidden_apps/hidden_apps_controller.dart';

/// Launcher settings hub.
///
/// Each future customization feature adds one tile under its section, pointing
/// at a screen inside its own feature module. The "Coming soon" tiles mark
/// where planned features will plug in.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final hiddenCount = context.select<HiddenAppsController, int>((h) => h.hiddenIds.length);

    return Scaffold(
      appBar: AppBar(title: const Text('Launcher settings')),
      body: ListView(
        children: [
          const _SectionHeader('Apps'),
          ListTile(
            leading: const Icon(Icons.visibility_off_outlined),
            title: const Text('Hidden apps'),
            subtitle: Text(hiddenCount == 0 ? 'None' : '$hiddenCount hidden'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.pushNamed(context, AppRoutes.hiddenApps),
          ),
          ListTile(
            leading: const Icon(Icons.block),
            title: const Text('Disable system apps'),
            subtitle: const Text('Removes them from every launcher · needs Shizuku'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.pushNamed(context, AppRoutes.systemApps),
          ),
          ListTile(
            leading: const Icon(Icons.refresh),
            title: const Text('Reload app list & icons'),
            subtitle: const Text('Clears the cache and re-reads installed apps'),
            onTap: () {
              context.read<AppsController>().rebuildCache();
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Reloading apps…')));
            },
          ),

          const _SectionHeader('Appearance'),
          const _ComingSoonTile(icon: Icons.style_outlined, title: 'Icon pack'),
          const _ComingSoonTile(icon: Icons.grid_view, title: 'Grid size'),
          const _ComingSoonTile(icon: Icons.palette_outlined, title: 'Theme'),

          const _SectionHeader('Behaviour'),
          const _ComingSoonTile(icon: Icons.swipe_outlined, title: 'Gestures'),

          const _SectionHeader('System'),
          ListTile(
            leading: const Icon(Icons.home_outlined),
            title: const Text('Default home app'),
            subtitle: const Text('Choose which launcher Android uses'),
            onTap: () => context.read<LauncherPlatform>().openHomeSettings(),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(color: Theme.of(context).colorScheme.primary),
      ),
    );
  }
}

/// Placeholder for a planned setting. Replace with a real tile when built.
class _ComingSoonTile extends StatelessWidget {
  const _ComingSoonTile({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      enabled: false,
      leading: Icon(icon),
      title: Text(title),
      subtitle: const Text('Coming soon'),
    );
  }
}
