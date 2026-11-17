import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/widgets/app_icon.dart';
import 'container_sheets.dart';
import 'corner_shapes.dart';
import 'home_layout.dart';
import 'home_layout_controller.dart';

/// A folder / container's settings, in a small card right next to it: its
/// name, its apps, resizing, ungrouping.
///
/// Not shown anywhere for now: a long press goes straight to the resize
/// handles. Kept to bring back.
///
/// The card sits below [anchor] (the folder's panel, in global coordinates)
/// if it fits, otherwise above it, and moves up out of the keyboard's way
/// while renaming. With no [anchor], it's centred.
Future<void> showContainerMenu(BuildContext context, String containerId, {Rect? anchor}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close',
    barrierColor: Colors.black26,
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (_, _, _) => _ContainerMenu(containerId: containerId, anchor: anchor),
    transitionBuilder: (_, animation, _, child) {
      final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(scale: Tween(begin: 0.94, end: 1.0).animate(curved), child: child),
      );
    },
  );
}

class _ContainerMenu extends StatelessWidget {
  const _ContainerMenu({required this.containerId, required this.anchor});

  final String containerId;
  final Rect? anchor;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    // Kept clear of the status / navigation bars and the keyboard.
    final insets = media.padding + EdgeInsets.only(bottom: media.viewInsets.bottom);
    return CustomSingleChildLayout(
      delegate: _NextTo(anchor, insets),
      child: _ContainerMenuCard(containerId: containerId),
    );
  }
}

/// Lays the card out next to the folder; see [showContainerMenu].
class _NextTo extends SingleChildLayoutDelegate {
  _NextTo(this.anchor, this.insets);

  final Rect? anchor;
  final EdgeInsets insets;

  static const _margin = 16.0;
  static const _gap = 8.0;
  static const _width = 300.0;

  Rect _area(Size size) => Rect.fromLTRB(
    _margin + insets.left,
    _margin + insets.top,
    size.width - _margin - insets.right,
    size.height - _margin - insets.bottom,
  );

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final area = _area(constraints.biggest);
    return BoxConstraints(
      minWidth: math.min(_width, area.width),
      maxWidth: math.min(_width, area.width),
      maxHeight: math.max(0, area.height),
    );
  }

  @override
  Offset getPositionForChild(Size size, Size child) {
    final area = _area(size);
    final a = anchor;
    if (a == null) return area.center - Offset(child.width / 2, child.height / 2);
    final x = (a.center.dx - child.width / 2)
        .clamp(area.left, math.max(area.left, area.right - child.width))
        .toDouble();
    final below = a.bottom + _gap, above = a.top - _gap - child.height;
    final y = below + child.height <= area.bottom
        ? below
        : above >= area.top
        ? above
        : math.max(area.top, area.bottom - child.height);
    return Offset(x, y);
  }

  @override
  bool shouldRelayout(_NextTo old) => old.anchor != anchor || old.insets != insets;
}

class _ContainerMenuCard extends StatelessWidget {
  const _ContainerMenuCard({required this.containerId});

  final String containerId;

  @override
  Widget build(BuildContext context) {
    final layout = context.watch<HomeLayoutController>();
    final c = layout.container(containerId);
    if (c == null) return const SizedBox.shrink(); // ungrouped meanwhile
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Material(
      color: scheme.surfaceContainerHigh,
      shape: CornerShapes.shape(28),
      clipBehavior: Clip.antiAlias,
      elevation: 3,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              initialValue: c.name,
              decoration: InputDecoration(
                labelText: c.isFolder ? 'Folder name' : 'Container name',
                prefixIcon: const Icon(Icons.edit_outlined),
                filled: true,
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              ),
              textCapitalization: TextCapitalization.sentences,
              onChanged: (name) => layout.updateContainer(c.copyWith(name: name)),
              onFieldSubmitted: (_) => Navigator.pop(context),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _AppStrip(container: c)),
                const SizedBox(width: 8),
                FilledButton.tonal(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(builder: (_) => ContainerAppPicker(containerId: containerId)),
                  ),
                  child: Text('${c.appIds.length} apps'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Divider(height: 1),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              leading: const Icon(Icons.open_in_full),
              title: const Text('Resize & round corners'),
              onTap: () {
                Navigator.pop(context);
                layout
                  ..setEditing(true)
                  ..select(c.key);
              },
            ),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              iconColor: scheme.error,
              textColor: scheme.error,
              leading: const Icon(Icons.call_split),
              title: const Text('Ungroup'),
              subtitle: const Text('Its apps go back on the home screen'),
              onTap: () {
                Navigator.pop(context);
                layout.ungroup(containerId);
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// The group's apps as a scrollable row of icons.
class _AppStrip extends StatelessWidget {
  const _AppStrip({required this.container});

  final AppContainer container;

  @override
  Widget build(BuildContext context) {
    final apps = visibleAppsOf(context, container);
    return SizedBox(
      height: 32,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: apps.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (_, i) => Tooltip(
          message: apps[i].label,
          child: AppIcon(app: apps[i], size: 32),
        ),
      ),
    );
  }
}
