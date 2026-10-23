import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/apps/home_role_controller.dart';
import '../../core/models/app_info.dart';
import '../../core/routing/app_routes.dart';
import '../../core/widgets/app_icon.dart';
import '../app_actions/app_actions_sheet.dart';
import '../hidden_apps/visible_apps.dart';
import 'home_actions_sheet.dart';
import 'home_apps_controller.dart';
import 'widgets/clock.dart';

/// The home screen: clock, pinned apps and a search pill, over the wallpaper.
///
/// Swipe up or tap the search pill to open the drawer; long-press empty space
/// for wallpaper and settings.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  void _openDrawer(BuildContext context, {bool focusSearch = false}) =>
      Navigator.pushNamed(context, AppRoutes.drawer, arguments: focusSearch);

  @override
  Widget build(BuildContext context) {
    final visible = context.watch<VisibleApps>();
    final pinned = context
        .watch<HomeAppsController>()
        .ids
        .map(visible.byId) // hidden or uninstalled -> null -> dropped
        .whereType<AppInfo>()
        .toList();

    // As the home screen, Back does nothing. Opened as a normal app, it exits.
    final isDefaultHome = context.watch<HomeRoleController>().isDefaultHome;
    return PopScope(
      canPop: !isDefaultHome,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        // Fade home content out while anything (drawer, settings) is on top:
        // the drawer is see-through, and the wallpaper alone looks cleaner.
        // (isCurrent, not secondaryAnimation: Flutter only drives that between
        // matching route types, and the drawer uses a custom route.)
        body: AnimatedOpacity(
          opacity: (ModalRoute.of(context)?.isCurrent ?? true) ? 1 : 0,
          duration: const Duration(milliseconds: 160),
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onVerticalDragEnd: (details) {
              if ((details.primaryVelocity ?? 0) < -300) _openDrawer(context);
            },
            // App tiles handle their own long-press, so this only fires on empty space.
            onLongPress: () {
              HapticFeedback.mediumImpact();
              showHomeActions(context);
            },
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Expanded(
                          child: Padding(padding: EdgeInsets.only(top: 32), child: Clock()),
                        ),
                        IconButton(
                          tooltip: 'Launcher settings',
                          color: Colors.white70,
                          icon: const Icon(Icons.settings_outlined),
                          onPressed: () => Navigator.pushNamed(context, AppRoutes.settings),
                        ),
                      ],
                    ),
                    const Spacer(),
                    if (pinned.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 24),
                        child: Text(
                          'Swipe up for all apps.\nLong-press an app there to add it here.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white60),
                        ),
                      )
                    else
                      _PinnedGrid(apps: pinned),
                    _SearchPill(onTap: () => _openDrawer(context, focusSearch: true)),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PinnedGrid extends StatelessWidget {
  const _PinnedGrid({required this.apps});

  final List<AppInfo> apps;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 4,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 0.85,
      children: [
        for (final app in apps)
          AppTile(
            app: app,
            onTap: () => openApp(context, app),
            onLongPress: () => showAppActions(context, app),
          ),
      ],
    );
  }
}

class _SearchPill extends StatelessWidget {
  const _SearchPill({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.18),
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Row(
            children: [
              Icon(Icons.search, color: Colors.white70),
              SizedBox(width: 12),
              Text('Search apps', style: TextStyle(color: Colors.white70, fontSize: 16)),
            ],
          ),
        ),
      ),
    );
  }
}
