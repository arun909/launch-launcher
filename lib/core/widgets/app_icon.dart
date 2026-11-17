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
        // Fully rounded corners: a circle for round icons, close enough for the rest.
        decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(size / 2)),
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
  const AppTile({
    super.key,
    required this.app,
    required this.onTap,
    this.onLongPress,
    this.iconSize = 52,
    this.labelSize = 12,
    this.showLabel = true,
  });

  final AppInfo app;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final double iconSize;

  /// Label font size; its line is always 16 high (Material 3 label styles).
  final double labelSize;

  /// False: icon only. The label's line stays (empty), so the icon doesn't
  /// move, and screen readers still get the name.
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    // No ink: a launcher icon shows no highlight box when tapped.
    final tile = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppIcon(app: app, size: iconSize),
            const SizedBox(height: 6),
            // A fixed line height keeps every tile exactly 90 high, so icons in
            // containers line up with these (see HomeGrid.tileHeight).
            SizedBox(
              height: 16,
              child: !showLabel
                  ? null
                  : Text(
                      app.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: labelSize,
                        shadows: [Shadow(blurRadius: 4, color: Colors.black54)],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
    return showLabel ? tile : Semantics(label: app.label, child: tile);
  }
}
