import 'package:flutter/material.dart';

import '../models/app_info.dart';

/// An app's icon, with a neutral placeholder while the icon is loading.
class AppIcon extends StatelessWidget {
  const AppIcon({super.key, required this.app, this.size = 48});

  final AppInfo app;
  final double size;

  @override
  Widget build(BuildContext context) {
    final icon = app.icon;
    if (icon == null) {
      return Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(size / 4)),
        child: Text(
          app.label.isEmpty ? '?' : app.label.characters.first.toUpperCase(),
          style: TextStyle(color: Colors.white, fontSize: size * 0.4),
        ),
      );
    }
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return Image.memory(
      icon,
      width: size,
      height: size,
      cacheWidth: (size * dpr).round(),
      gaplessPlayback: true,
      filterQuality: FilterQuality.medium,
    );
  }
}

/// Icon + label, the standard tappable cell used on home and in the drawer.
class AppTile extends StatelessWidget {
  const AppTile({super.key, required this.app, required this.onTap, this.onLongPress, this.iconSize = 52});

  final AppInfo app;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppIcon(app: app, size: iconSize),
            const SizedBox(height: 6),
            Text(
              app.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                shadows: [Shadow(blurRadius: 4, color: Colors.black54)],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
