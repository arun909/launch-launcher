import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/apps/apps_controller.dart';
import '../../core/platform/launcher_platform.dart';
import '../../core/models/icon_shape.dart';
import '../../core/models/icon_style.dart';
import '../../core/routing/app_routes.dart';
import '../appearance/appearance_controller.dart';
import '../appearance/home_grid_picker.dart';
import '../appearance/wallpaper_blur_tile.dart';
import '../dock/dock_controller.dart';
import '../hidden_apps/hidden_apps_controller.dart';
import '../search_widget/search_widget_controller.dart';
import '../standard_home/home_layout_controller.dart';
import '../standard_home/tidy_up.dart';
import '../web_viewer/full_screen_web_controller.dart';
import '../web_viewer/hold_search_controller.dart';

/// Launcher settings hub.
///
/// Each new feature adds one tile under a section, pointing at a screen inside
/// its own feature module.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final hiddenCount = context.select<HiddenAppsController, int>((h) => h.hiddenIds.length);
    final (iconShape, iconStyle) = context.select<AppearanceController, (IconShape, IconStyle)>(
      (a) => (a.iconShape, a.iconStyle),
    );
    final (dockCount, dockMax) = context.select<DockController, (int, int)>((d) => (d.ids.length, d.maxApps));
    final search = context.watch<SearchWidgetController>();
    final homeMode = context.select<HomeLayoutController, HomeMode>((l) => l.mode);
    final showLabels = context.select<HomeLayoutController, bool>((l) => l.showLabels);
    final fullScreenWeb = context.select<FullScreenWebController, bool>((w) => w.isOn);
    final holdSearch = context.select<HoldSearchController, bool>((h) => h.isOn);

    return Scaffold(
      appBar: AppBar(title: const Text('Launcher settings')),
      body: ListView(
        children: [
          const _SectionHeader('Appearance'),
          ListTile(
            leading: const Icon(Icons.interests_outlined),
            title: const Text('Icons'),
            subtitle: Text(
              [
                iconStyle.source.label,
                if (!iconStyle.isOriginal) iconStyle.background.label,
                iconShape.label,
              ].join(' · '),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.pushNamed(context, AppRoutes.icons),
          ),
          ListTile(
            leading: const Icon(Icons.wallpaper_outlined),
            title: const Text('Wallpapers'),
            subtitle: const Text('The phone\'s own wallpaper gallery'),
            trailing: const Icon(Icons.open_in_new),
            onTap: () async {
              final messenger = ScaffoldMessenger.of(context);
              if (!await context.read<LauncherPlatform>().openSystemWallpapers()) {
                messenger.showSnackBar(const SnackBar(content: Text('No wallpaper app found on this phone')));
              }
            },
          ),
          const WallpaperBlurTile(),
          ListTile(
            leading: const Icon(Icons.nightlight_outlined),
            title: const Text('Standby clock'),
            subtitle: const Text('A sideways clock on the lock screen'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.pushNamed(context, AppRoutes.standbySettings),
          ),

          const _SectionHeader('Home screen'),
          ListTile(
            leading: const Icon(Icons.dashboard_outlined),
            title: const Text('Layout'),
            subtitle: Text(
              homeMode == HomeMode.standard
                  ? 'All apps on home pages; group them into containers'
                  : 'Chosen apps on home; the rest in the swipe-up drawer',
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(72, 0, 16, 8),
            child: SegmentedButton<HomeMode>(
              segments: [for (final m in HomeMode.values) ButtonSegment(value: m, label: Text(m.label))],
              selected: {homeMode},
              onSelectionChanged: (s) => context.read<HomeLayoutController>().setMode(s.single),
            ),
          ),
          const HomeGridPicker(),
          SwitchListTile(
            secondary: const Icon(Icons.label_outline),
            title: const Text('App names'),
            subtitle: Text(
              showLabels
                  ? 'Shown under home-screen icons, folders and containers'
                  : 'Hidden: icons only on the home screen, folder names too',
            ),
            value: showLabels,
            onChanged: context.read<HomeLayoutController>().setShowLabels,
          ),
          if (homeMode == HomeMode.standard)
            ListTile(
              leading: const Icon(Icons.auto_awesome_mosaic_outlined),
              title: const Text('Tidy up home screen'),
              subtitle: const Text('Remove folders and line up every app A–Z, in as few pages as possible'),
              onTap: () => confirmTidyUp(context),
            ),
          ListTile(
            leading: const Icon(Icons.call_to_action_outlined),
            title: const Text('Dock apps'),
            subtitle: Text(dockCount == 0 ? 'Empty' : '$dockCount of $dockMax apps'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.pushNamed(context, AppRoutes.dockApps),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.search),
            title: const Text('Search bar'),
            subtitle: const Text('App search widget on the home screen'),
            value: search.isVisible,
            onChanged: search.setVisible,
          ),
          ListTile(
            enabled: search.isVisible,
            leading: const Icon(Icons.open_in_full),
            title: const Text('Search bar size'),
            subtitle: Text('${search.sizeLabel} · tap to resize on the home screen'),
            trailing: IconButton(
              tooltip: 'Reset size',
              icon: const Icon(Icons.restart_alt),
              onPressed: search.isVisible ? search.resetSize : null,
            ),
            onTap: () {
              // Back to the home screen with the resize handles showing.
              Navigator.popUntil(context, (route) => route.isFirst);
              search.startResizing();
            },
          ),

          const _SectionHeader('Apps'),
          ListTile(
            leading: const Icon(Icons.visibility_off_outlined),
            title: const Text('Hidden apps'),
            subtitle: Text(hiddenCount == 0 ? 'None' : '$hiddenCount hidden'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.pushNamed(context, AppRoutes.hiddenApps),
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

          const _SectionHeader('Browsing'),
          SwitchListTile(
            secondary: const Icon(Icons.fullscreen),
            title: const Text('Full-screen button'),
            subtitle: Text(
              fullScreenWeb
                  ? 'A button floats over Chrome and other browsers: tap it for the page full screen, '
                        'tap it again to go back to the browser'
                  : 'Shows a button over browsers to view any page full screen',
            ),
            value: fullScreenWeb,
            onChanged: (on) async {
              await context.read<FullScreenWebController>().setOn(on);
              if (context.mounted) context.read<HoldSearchController>().refresh();
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.manage_search),
            title: const Text('Hold to search'),
            subtitle: Text(
              holdSearch
                  ? 'In any app, touch and hold the bottom centre of the screen to search. '
                        'Results open in a floating window, with a full-screen button'
                  : 'Search from any app by holding the bottom centre of the screen',
            ),
            value: holdSearch,
            onChanged: (on) async {
              await context.read<HoldSearchController>().setOn(on);
              if (context.mounted) context.read<FullScreenWebController>().refresh();
            },
          ),
          if (holdSearch)
            ListTile(
              leading: const Icon(Icons.apps),
              title: const Text('Apps in the search bar'),
              subtitle: const Text('Choose and order where hold-to-search can search'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.pushNamed(context, AppRoutes.holdSearchApps),
            ),

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
