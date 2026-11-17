import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/home_grid.dart';
import '../standard_home/home_layout_controller.dart';

/// Settings row: pick the app grid (apps per row, with matching icon and
/// label sizes). Each option is drawn as a miniature home screen.
class HomeGridPicker extends StatelessWidget {
  const HomeGridPicker({super.key});

  @override
  Widget build(BuildContext context) {
    final layout = context.watch<HomeLayoutController>();
    final area = layout.gridArea;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          leading: const Icon(Icons.grid_view_rounded),
          title: const Text('App grid'),
          subtitle: Text(
            '${layout.grid.sizeIn(area.width, area.height)} · ${layout.grid.iconSize.round()}dp icons · '
            'home screen, folders and app drawer',
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Row(
            children: [
              for (final grid in HomeGrid.values)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: _Option(
                      grid: grid,
                      area: area,
                      selected: grid == layout.grid,
                      onTap: () => layout.setGrid(grid),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(72, 0, 16, 8),
          child: Text(
            'Apps keep their places; any past the last column move to the nearest free spot.',
            style: theme.textTheme.bodySmall,
          ),
        ),
        // App icon size, within the grid's cells.
        ListTile(
          leading: const Icon(Icons.photo_size_select_large_rounded),
          title: const Text('App icon size'),
          subtitle: Text('${layout.grid.iconSize.round()}dp · ${(layout.iconScale * 100).round()}% of the grid\'s'),
          trailing: layout.iconScale == 1
              ? null
              : TextButton(onPressed: () => layout.setIconScale(1), child: const Text('Reset')),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(56, 0, 8, 8),
          child: Row(
            children: [
              const Icon(Icons.apps_rounded, size: 18),
              Expanded(
                child: Slider(
                  min: HomeGrid.minIconScale,
                  max: HomeGrid.maxIconScale,
                  divisions: 6,
                  value: layout.iconScale,
                  label: '${(layout.iconScale * 100).round()}%',
                  onChanged: layout.setIconScale,
                ),
              ),
              const Icon(Icons.apps_rounded, size: 28),
            ],
          ),
        ),
      ],
    );
  }
}

class _Option extends StatelessWidget {
  const _Option({required this.grid, required this.area, required this.selected, required this.onTap});

  final HomeGrid grid;

  /// The home grid area on this phone: the preview has its proportions and
  /// shows the rows it really gets.
  final Size area;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: selected ? scheme.primaryContainer : scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: selected ? scheme.primary : Colors.transparent, width: 2),
        ),
        child: Column(
          children: [
            AspectRatio(
              aspectRatio: area.width / area.height,
              child: _MiniScreen(grid: grid, area: area),
            ),
            const SizedBox(height: 8),
            Text(grid.label, style: Theme.of(context).textTheme.labelLarge),
            Text(
              '${grid.sizeIn(area.width, area.height)} · ${grid.iconSize.round()}dp',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

/// A phone outline with the grid's icons as rounded squares, to scale.
class _MiniScreen extends StatelessWidget {
  const _MiniScreen({required this.grid, required this.area});

  final HomeGrid grid;
  final Size area;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, box) {
        // The real grid, scaled down: same cell shape, same icon proportion.
        final scale = box.maxWidth / area.width;
        final realCell = area.width / grid.columns;
        final cell = realCell * scale;
        final cellHeight = grid.cellHeightIn(area.height, realCell) * scale;
        final rows = grid.rowsFor(area.height, realCell);
        final icon = grid.iconSize * scale;
        return DecoratedBox(
          decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(10)),
          child: Column(
            children: [
              for (var r = 0; r < rows; r++)
                Row(
                  children: [
                    for (var c = 0; c < grid.columns; c++)
                      SizedBox(
                        width: cell,
                        height: cellHeight,
                        child: Center(
                          child: Container(
                            width: icon,
                            height: icon,
                            decoration: BoxDecoration(
                              color: scheme.primary.withValues(alpha: 0.55),
                              borderRadius: BorderRadius.circular(icon * 0.25),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }
}
