import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/platform/window_blur_platform.dart';
import 'appearance_controller.dart';

/// Settings row: how much to blur the wallpaper behind the drawer and search.
class WallpaperBlurTile extends StatelessWidget {
  const WallpaperBlurTile({super.key});

  @override
  Widget build(BuildContext context) {
    final appearance = context.watch<AppearanceController>();
    final level = appearance.blurLevel;
    final supported = context.watch<WindowBlurPlatform>().isSupported;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          enabled: supported,
          leading: const Icon(Icons.blur_on),
          title: const Text('Background blur'),
          subtitle: Text(
            supported
                ? 'Wallpaper behind the app drawer and search · ${level == 0 ? 'Off' : '$level%'}'
                : 'Not supported on this phone right now (needs Android 12+ with blur enabled by the maker; '
                      'off in battery saver)',
          ),
          trailing: level == AppearanceController.defaultBlurLevel
              ? null
              : IconButton(
                  tooltip: 'Reset blur',
                  icon: const Icon(Icons.restart_alt),
                  onPressed: supported ? () => appearance.setBlurLevel(AppearanceController.defaultBlurLevel) : null,
                ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 56, right: 8),
          child: Slider(
            value: level.toDouble(),
            max: 100,
            divisions: 20,
            label: level == 0 ? 'Off' : '$level%',
            onChanged: supported ? (v) => appearance.setBlurLevel(v.round()) : null,
          ),
        ),
      ],
    );
  }
}
