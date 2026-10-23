import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/platform/launcher_platform.dart';
import '../../core/routing/app_routes.dart';

/// Long-press menu for empty home-screen space.
///
/// Wallpaper entries only open Android's own pickers; the launcher never
/// changes the wallpaper itself.
Future<void> showHomeActions(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => const _HomeActionsSheet(),
  );
}

class _HomeActionsSheet extends StatelessWidget {
  const _HomeActionsSheet();

  @override
  Widget build(BuildContext context) {
    final platform = context.read<LauncherPlatform>();
    final messenger = ScaffoldMessenger.maybeOf(context);
    final navigator = Navigator.of(context);

    Future<void> open(Future<bool> Function() action, String failure) async {
      navigator.pop();
      if (!await action()) messenger?.showSnackBar(SnackBar(content: Text(failure)));
    }

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.wallpaper_outlined),
            title: const Text('Wallpapers'),
            subtitle: const Text('Pick from the phone\'s wallpaper apps'),
            onTap: () => open(platform.openWallpaperPicker, 'No wallpaper app found on this phone'),
          ),
          ListTile(
            leading: const Icon(Icons.animation_outlined),
            title: const Text('Live wallpapers'),
            onTap: () => open(platform.openLiveWallpaperPicker, 'This phone has no live-wallpaper picker'),
          ),
          ListTile(
            leading: const Icon(Icons.settings_outlined),
            title: const Text('Launcher settings'),
            onTap: () => navigator
              ..pop()
              ..pushNamed(AppRoutes.settings),
          ),
        ],
      ),
    );
  }
}
