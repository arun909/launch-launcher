import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/apps/apps_controller.dart';
import '../../core/platform/app_widgets_platform.dart';
import '../../core/widgets/app_icon.dart';
import '../standard_home/home_layout.dart';
import '../standard_home/home_layout_controller.dart';
import 'launcher_widgets.dart';

/// Long-press menu for a drawer-mode widget: resize it, or remove it. (In
/// standard mode a long press goes to its handles on the grid instead.)
Future<void> showWidgetActions(BuildContext context, WidgetItem item) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (_) => _WidgetActionsSheet(id: item.id),
  );
}

/// Takes widget [item] off the home screen, and releases an app widget's id.
void removeHomeWidget(BuildContext context, WidgetItem item) {
  context.read<HomeLayoutController>().removeWidget(item.id);
  if (item.appWidgetId case final id?) context.read<AppWidgetsPlatform>().deleteWidget(id);
}

/// Reopens an app widget's own settings screen.
Future<void> reconfigureHomeWidget(BuildContext context, WidgetItem item) async {
  final id = item.appWidgetId;
  if (id == null) return;
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (!await context.read<AppWidgetsPlatform>().reconfigure(id)) {
    messenger?.showSnackBar(const SnackBar(content: Text('This widget\'s settings couldn\'t be opened')));
  }
}

class _WidgetActionsSheet extends StatelessWidget {
  const _WidgetActionsSheet({required this.id});

  final String id;

  @override
  Widget build(BuildContext context) {
    final layout = context.watch<HomeLayoutController>();
    final item = layout.findWidget(id);
    if (item == null) return const SizedBox.shrink();
    final kind = LauncherWidgetKind.fromName(item.launcherKind);
    final app = item.isAppWidget
        ? context.watch<AppsController>().apps.where((a) => a.packageName == item.providerPackage).firstOrNull
        : null;

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: app != null ? AppIcon(app: app, size: 40) : Icon(kind?.icon ?? Icons.widgets_outlined, size: 32),
            title: Text(
              kind?.label ?? (app != null ? '${app.label} widget' : 'App widget'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            subtitle: Text(kind != null ? 'Launcher widget' : 'From ${app?.label ?? item.providerPackage}'),
          ),
          const Divider(),
          if (kind?.sizes case final sizes?)
            ListTile(
              leading: const Icon(Icons.aspect_ratio_rounded),
              title: const Text('Size'),
              trailing: Wrap(
                spacing: 8,
                children: [
                  for (final (c, r) in sizes)
                    ChoiceChip(
                      // As drawn: wider than the grid, it's clamped to it.
                      label: Text('${math.min(c, layout.grid.columns)} × $r'),
                      selected: item.cols == c && item.rows == r,
                      onSelected: (_) => layout.resizeWidget(id, cols: c, rows: r),
                    ),
                ],
              ),
            )
          else ...[
            _SpanStepper(
              label: 'Width',
              value: item.cols,
              min: item.minCols,
              max: math.min(item.maxCols, layout.grid.columns),
              onChanged: (v) => layout.resizeWidget(id, cols: v, rows: item.rows),
            ),
            _SpanStepper(
              label: 'Height',
              value: item.rows,
              min: item.minRows,
              max: item.maxRows,
              onChanged: (v) => layout.resizeWidget(id, cols: item.cols, rows: v),
            ),
          ],
          if (kind?.customise case final customise?)
            ListTile(
              leading: const Icon(Icons.tune_rounded),
              title: const Text('Customise'),
              onTap: () {
                Navigator.pop(context);
                customise(context, item);
              },
            ),
          if (item.reconfigurable)
            ListTile(
              leading: const Icon(Icons.settings_outlined),
              title: const Text('Widget settings'),
              onTap: () {
                Navigator.pop(context);
                reconfigureHomeWidget(context, item);
              },
            ),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: const Text('Remove widget'),
            onTap: () {
              Navigator.pop(context);
              removeHomeWidget(context, item);
            },
          ),
        ],
      ),
    );
  }
}

/// "Width  [−] 2 cells [+]".
class _SpanStepper extends StatelessWidget {
  const _SpanStepper({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final int value;

  /// The widget's least and most size this way.
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(label == 'Width' ? Icons.swap_horiz_rounded : Icons.swap_vert_rounded),
      title: Text(label),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: value > min ? () => onChanged(value - 1) : null,
            icon: const Icon(Icons.remove_rounded),
          ),
          SizedBox(width: 64, child: Text('$value ${value == 1 ? 'cell' : 'cells'}', textAlign: TextAlign.center)),
          IconButton(onPressed: value < max ? () => onChanged(value + 1) : null, icon: const Icon(Icons.add_rounded)),
        ],
      ),
    );
  }
}
