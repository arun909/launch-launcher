import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/apps/apps_controller.dart';
import '../../core/models/app_info.dart';
import '../../core/platform/app_widgets_platform.dart';
import '../../core/widgets/app_icon.dart';
import '../standard_home/home_layout.dart';
import '../standard_home/home_layout_controller.dart';
import '../standard_home/app_container_tile.dart';
import 'home_widget_view.dart';
import 'launcher_widgets.dart';
import 'widget_placement.dart';

/// Picks a widget to put on the home screen, from two lists:
/// - App widgets: the ones installed apps offer (Android app widgets);
/// - Launcher widgets: the launcher's own (see LauncherWidgetKind).
///
/// With [app], just that app's widgets (from its long-press menu).
class WidgetPickerScreen extends StatelessWidget {
  const WidgetPickerScreen({super.key, this.app});

  final AppInfo? app;

  @override
  Widget build(BuildContext context) {
    if (app case final app?) {
      return Scaffold(
        appBar: AppBar(title: Text('${app.label} widgets')),
        body: _AppWidgetsTab(package: app.packageName),
      );
    }
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Add widget'),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.apps_rounded), text: 'App widgets'),
              Tab(icon: Icon(Icons.auto_awesome_outlined), text: 'Launcher widgets'),
            ],
          ),
        ),
        body: const TabBarView(children: [_AppWidgetsTab(), _LauncherWidgetsTab()]),
      ),
    );
  }
}

class _AppWidgetsTab extends StatefulWidget {
  const _AppWidgetsTab({this.package});

  /// Only this app's widgets, with no search.
  final String? package;

  @override
  State<_AppWidgetsTab> createState() => _AppWidgetsTabState();
}

class _AppWidgetsTabState extends State<_AppWidgetsTab> with AutomaticKeepAliveClientMixin {
  late final Future<List<AppWidgetProvider>> _providers = context.read<AppWidgetsPlatform>().getProviders();
  String _query = '';
  bool _adding = false;

  @override
  bool get wantKeepAlive => true;

  Future<void> _add(AppWidgetProvider p) async {
    if (_adding) return;
    final platform = context.read<AppWidgetsPlatform>();
    final layout = context.read<HomeLayoutController>();
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    // Room first, so nothing is bound for a widget that won't be added.
    final cell = homeCell(context, layout.grid);
    final place = await findRoom(context, appWidgetItem(p, grid: layout.grid, cell: cell));
    if (place == null || !mounted) return;
    setState(() => _adding = true);
    try {
      // Told its exact size up front, so its first layout already fits.
      final i = place.item;
      final size = HomeWidgetView.layoutSizeOf(
        layout.grid,
        HomeWidgetView.sizeOf(layout.grid, cell, i.cols, i.rows),
        i.cols,
        i.rows,
      );
      final appWidgetId = await platform.addWidget(p.provider, size);
      if (appWidgetId == null) return; // Not allowed, or setup cancelled.
      layout.addWidget(place.item.copyWith(appWidgetId: appWidgetId), at: place.slot);
      // From an app's menu (maybe in the drawer): back to home to see it.
      widget.package == null ? navigator.pop() : navigator.popUntil((r) => r.isFirst);
    } on PlatformException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Couldn\'t add the widget: ${e.message}')));
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return FutureBuilder<List<AppWidgetProvider>>(
      future: _providers,
      builder: (context, snapshot) {
        if (snapshot.hasError) return const Center(child: Text('Couldn\'t load app widgets'));
        final all = snapshot.data;
        if (all == null) return const Center(child: CircularProgressIndicator());
        if (all.isEmpty) return const Center(child: Text('No installed app offers a widget'));

        final only = widget.package;
        final q = _query.trim().toLowerCase();
        final shown = only != null
            ? all.where((p) => p.packageName == only).toList()
            : q.isEmpty
            ? all
            : all.where((p) => p.label.toLowerCase().contains(q) || p.appLabel.toLowerCase().contains(q)).toList();
        // Grouped by app, in the (sorted) order they came.
        final groups = <String, List<AppWidgetProvider>>{};
        for (final p in shown) {
          groups.putIfAbsent(p.packageName, () => []).add(p);
        }
        final apps = context.watch<AppsController>().apps;

        return Stack(
          children: [
            CustomScrollView(
              slivers: [
                if (only == null)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    sliver: SliverToBoxAdapter(
                      child: SearchBar(
                        hintText: 'Search widgets',
                        leading: const Icon(Icons.search_rounded),
                        elevation: const WidgetStatePropertyAll(0),
                        onChanged: (v) => setState(() => _query = v),
                      ),
                    ),
                  ),
                if (groups.isEmpty)
                  const SliverFillRemaining(hasScrollBody: false, child: Center(child: Text('No widgets match'))),
                for (final MapEntry(key: package, value: providers) in groups.entries)
                  SliverToBoxAdapter(
                    child: _AppGroup(
                      app: apps.where((a) => a.packageName == package).firstOrNull,
                      appLabel: providers.first.appLabel,
                      providers: providers,
                      onAdd: _add,
                    ),
                  ),
                const SliverPadding(padding: EdgeInsets.only(bottom: 24)),
              ],
            ),
            if (_adding) const Positioned(left: 0, right: 0, top: 0, child: LinearProgressIndicator()),
          ],
        );
      },
    );
  }
}

/// One app's widgets: its name, then a row of preview cards.
class _AppGroup extends StatelessWidget {
  const _AppGroup({required this.app, required this.appLabel, required this.providers, required this.onAdd});

  final AppInfo? app;
  final String appLabel;
  final List<AppWidgetProvider> providers;
  final ValueChanged<AppWidgetProvider> onAdd;

  @override
  Widget build(BuildContext context) {
    final layout = context.read<HomeLayoutController>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          leading: app != null ? AppIcon(app: app!, size: 36) : const Icon(Icons.android_rounded, size: 32),
          title: Text(appLabel, style: Theme.of(context).textTheme.titleMedium),
          subtitle: Text(providers.length == 1 ? '1 widget' : '${providers.length} widgets'),
        ),
        SizedBox(
          height: 212,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: providers.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, i) {
              final p = providers[i];
              final cell = homeCell(context, layout.grid);
              final item = appWidgetItem(p, grid: layout.grid, cell: cell);
              return _PickerCard(
                title: p.label,
                subtitle: _sizeNote(item, layout),
                onTap: () => onAdd(p),
                preview: _ProviderPreview(
                  provider: p.provider,
                  size: HomeWidgetView.layoutSizeOf(
                    layout.grid,
                    HomeWidgetView.sizeOf(layout.grid, cell, item.cols, item.rows),
                    item.cols,
                    item.rows,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// "4 × 2", "4 × 2 · resizable", or a warning if it can't fit a page.
String _sizeNote(WidgetItem w, HomeLayoutController layout) {
  if (w.minCols > layout.grid.columns || w.minRows > layout.gridRows) return 'Too big for your grid';
  return '${w.cols} × ${w.rows}${w.resizable ? ' · resizable' : ''}';
}

class _ProviderPreview extends StatelessWidget {
  const _ProviderPreview({required this.provider, required this.size});

  final String provider;

  /// The size it will have on the home screen, in dp.
  final Size size;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: context.read<AppWidgetsPlatform>().preview(provider, size),
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (bytes == null) {
          return snapshot.connectionState == ConnectionState.done
              ? const Icon(Icons.widgets_outlined, size: 40, color: Colors.white54)
              : const SizedBox.shrink();
        }
        return Image.memory(bytes, fit: BoxFit.contain, gaplessPlayback: true);
      },
    );
  }
}

class _LauncherWidgetsTab extends StatelessWidget {
  const _LauncherWidgetsTab();

  /// The kinds by their picker section, in the order they're listed: a
  /// group where its first member is; the ungrouped (null) together, untitled.
  static Map<String?, List<LauncherWidgetKind>> _grouped() {
    final out = <String?, List<LauncherWidgetKind>>{};
    for (final k in LauncherWidgetKind.values) {
      out.putIfAbsent(k.group, () => []).add(k);
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final layout = context.read<HomeLayoutController>();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Text(
            'Made by this launcher: nothing running in the background.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white70),
          ),
        ),
        if (LauncherWidgetKind.values.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 48),
            child: Center(
              child: Text('No launcher widgets yet', style: TextStyle(color: Colors.white54)),
            ),
          ),
        for (final MapEntry(key: group, value: kinds) in _grouped().entries) ...[
          if (group != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 12),
              child: Text(group, style: Theme.of(context).textTheme.titleMedium),
            ),
          for (final kind in kinds)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _PickerCard(
                wide: true,
                title: kind.label,
                subtitle: '${kind.description} · ${_sizeNote(launcherWidgetItem(kind), layout)}',
                preview: _TrueSizePreview(kind: kind, layout: layout),
                onTap: () async {
                  final navigator = Navigator.of(context);
                  final place = await findRoom(context, launcherWidgetItem(kind));
                  if (place == null) return;
                  layout.addWidget(place.item, at: place.slot);
                  navigator.pop();
                },
              ),
            ),
          if (group != null) const SizedBox(height: 12),
        ],
      ],
    );
  }
}

/// A launcher widget exactly as it will look on the home screen (its frame
/// at its starting size), scaled down only if the card is too small.
class _TrueSizePreview extends StatelessWidget {
  const _TrueSizePreview({required this.kind, required this.layout});

  final LauncherWidgetKind kind;
  final HomeLayoutController layout;

  @override
  Widget build(BuildContext context) {
    final grid = layout.grid;
    final size = HomeWidgetView.sizeOf(grid, homeCell(context, grid), kind.size.$1, kind.size.$2);
    // A tap adds it: its own buttons don't take it.
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: IgnorePointer(
        child: SizedBox.fromSize(
          size: size,
          child: LauncherWidgetView(
            kind: kind,
            radius: HomeWidgetView.radiusFor(kind.size.$1, kind.size.$2, size),
            padding: AppContainerTile.pad(grid),
          ),
        ),
      ),
    );
  }
}

/// A preview over a title and subtitle; tap to add.
class _PickerCard extends StatelessWidget {
  const _PickerCard({
    required this.title,
    required this.subtitle,
    required this.preview,
    required this.onTap,
    this.wide = false,
  });

  final String title;
  final String subtitle;
  final Widget preview;
  final VoidCallback onTap;

  /// Full width (launcher widgets) instead of a card in a row.
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: wide ? null : 168,
      child: Material(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                height: wide ? 140 : 128,
                padding: const EdgeInsets.all(8),
                // Dark, like a wallpaper, so white widget content shows.
                color: Colors.black.withValues(alpha: 0.35),
                child: preview,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: wide ? 2 : 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
