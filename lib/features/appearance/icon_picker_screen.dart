import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/apps/apps_controller.dart';
import '../../core/models/app_info.dart';
import '../../core/models/icon_shape.dart';
import '../../core/models/icon_style.dart';
import '../../core/platform/launcher_platform.dart';
import '../../core/widgets/app_icon.dart';
import 'appearance_controller.dart';

/// Picks one app's icon: the style's own choice, the app's original icon, or
/// any icon from the bundled packs (searchable, with suggestions first).
class IconPickerScreen extends StatefulWidget {
  const IconPickerScreen({super.key, required this.appId});

  final String appId;

  @override
  State<IconPickerScreen> createState() => _IconPickerScreenState();
}

class _IconPickerScreenState extends State<IconPickerScreen> {
  static const _packs = [IconSource.lawnicons, IconSource.arcticons];
  static const _maxSuggestions = 24;

  late final LauncherPlatform _platform = context.read<LauncherPlatform>();
  late final AppearanceController _appearance = context.read<AppearanceController>();
  late final _loader = _GlyphLoader(
    _platform,
    shape: _appearance.iconShape,
    // Original icons have no plate settings to show; preview in the default look.
    style: _appearance.iconStyle.isOriginal ? IconStyle.defaults : _appearance.iconStyle,
    appId: widget.appId,
  );
  final _query = TextEditingController();

  /// Every pack icon as a `<pack>:<name>` ref.
  List<String> _all = const [];
  List<String> _suggested = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
    _query.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _loader.dispose();
    _query.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final refs = await Future.wait(_packs.map(_platform.getPackIconRefs));
    final defaults = await _platform.getPackIconsForApp(widget.appId);
    if (!mounted) return;
    final all = [for (final r in refs) ...r];
    setState(() {
      _all = all;
      _suggested = _suggestionsFor(all, defaults);
      _loading = false;
    });
  }

  /// The packs' own picks for this app, then icons named like it.
  List<String> _suggestionsFor(List<String> all, List<String> picks) {
    final app = context.read<AppsController>().apps.where((a) => a.id == widget.appId).firstOrNull;
    final words = _words('${app?.label ?? ''} ${app?.packageName.split('.').last ?? ''}');
    final named = all.where((ref) {
      final name = _GlyphTile.nameOf(ref);
      return words.any((w) => name.contains(w));
    });
    return {...picks, ...named}.take(_maxSuggestions).toList();
  }

  static List<String> _words(String text) =>
      text.toLowerCase().split(RegExp(r'[^a-z0-9]+')).where((w) => w.length >= 3).toList();

  List<String> get _filtered {
    final words = _query.text.toLowerCase().split(RegExp(r'[\s_]+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return _all;
    return _all.where((ref) => words.every(ref.contains)).toList();
  }

  void _choose(String? override) {
    _appearance.setIconOverride(widget.appId, override);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.select<AppsController, AppInfo?>((a) => a.apps.where((x) => x.id == widget.appId).firstOrNull);
    final current = context.select<AppearanceController, String?>((a) => a.iconOverrides[widget.appId]);
    final theme = Theme.of(context);
    final searching = _query.text.trim().isNotEmpty;
    final results = _filtered;

    return Scaffold(
      appBar: AppBar(title: Text(app == null ? 'Change icon' : 'Icon for ${app.label}')),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Row(
                children: [
                  if (app != null) AppIcon(app: app, size: 56),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        ChoiceChip(
                          label: const Text('Default'),
                          tooltip: 'Whatever the icon settings give this app',
                          selected: current == null,
                          onSelected: (_) => _choose(null),
                        ),
                        ChoiceChip(
                          label: const Text('Original'),
                          tooltip: 'The app\'s own icon',
                          selected: current == 'original',
                          onSelected: (_) => _choose('original'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: SearchBar(
                controller: _query,
                hintText: 'Search ${_all.isEmpty ? '' : '${_all.length} '}icons',
                leading: const Icon(Icons.search),
                trailing: [
                  if (searching) IconButton(tooltip: 'Clear', icon: const Icon(Icons.close), onPressed: _query.clear),
                ],
                elevation: const WidgetStatePropertyAll(0),
              ),
            ),
          ),
          if (_loading)
            const SliverFillRemaining(hasScrollBody: false, child: Center(child: CircularProgressIndicator()))
          else ...[
            if (!searching && _suggested.isNotEmpty) ...[_sectionTitle(theme, 'Suggested'), _grid(_suggested, current)],
            _sectionTitle(theme, searching ? '${results.length} found' : 'All icons'),
            if (results.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text('No icons match "${_query.text.trim()}"', textAlign: TextAlign.center),
                ),
              )
            else
              _grid(results, current),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ],
      ),
    );
  }

  Widget _sectionTitle(ThemeData theme, String text) => SliverToBoxAdapter(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(text, style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary)),
    ),
  );

  Widget _grid(List<String> refs, String? current) => SliverPadding(
    padding: const EdgeInsets.symmetric(horizontal: 8),
    sliver: SliverGrid.builder(
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 84, childAspectRatio: 0.8),
      itemCount: refs.length,
      itemBuilder: (context, i) =>
          _GlyphTile(ref: refs[i], loader: _loader, selected: refs[i] == current, onTap: () => _choose(refs[i])),
    ),
  );
}

class _GlyphTile extends StatelessWidget {
  const _GlyphTile({required this.ref, required this.loader, required this.selected, required this.onTap});

  final String ref;
  final _GlyphLoader loader;
  final bool selected;
  final VoidCallback onTap;

  /// The icon's own name: `lawnicons:google_chrome` -> `google_chrome`.
  static String nameOf(String ref) => ref.substring(ref.indexOf(':') + 1);

  /// `lawnicons:google_chrome` -> `Google chrome`.
  static String prettyName(String ref) {
    final name = nameOf(ref).replaceAll('_', ' ').trim();
    return name.isEmpty ? ref : name[0].toUpperCase() + name.substring(1);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pack = IconSource.values.byName(ref.substring(0, ref.indexOf(':')));
    return Tooltip(
      message: '${prettyName(ref)} · ${pack.label}',
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: selected ? scheme.primary : Colors.transparent, width: 2),
          ),
          padding: const EdgeInsets.all(6),
          child: Column(
            children: [
              Expanded(
                child: ListenableBuilder(
                  listenable: loader,
                  builder: (context, _) {
                    final png = loader.get(ref);
                    return png == null
                        ? Center(
                            child: Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(22)),
                            ),
                          )
                        : Image.memory(png, width: 52, height: 52, gaplessPlayback: true);
                  },
                ),
              ),
              const SizedBox(height: 4),
              Text(
                prettyName(ref),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Renders pack icons on demand, in batches, for the tiles on screen.
class _GlyphLoader extends ChangeNotifier {
  _GlyphLoader(this._platform, {required this.shape, required this.style, required this.appId});

  static const _batchSize = 48;

  final LauncherPlatform _platform;
  final IconShape shape;
  final IconStyle style;
  final String appId;

  final _icons = <String, Uint8List>{};
  final _pending = <String>{};
  final _requested = <String>{};
  bool _scheduled = false;
  bool _disposed = false;

  /// The icon if rendered; otherwise queues it and returns null.
  Uint8List? get(String ref) {
    final png = _icons[ref];
    if (png == null && _requested.add(ref)) {
      _pending.add(ref);
      if (!_scheduled) {
        _scheduled = true;
        // After this frame's builds, so one batch covers every visible tile.
        scheduleMicrotask(_flush);
      }
    }
    return png;
  }

  Future<void> _flush() async {
    while (_pending.isNotEmpty && !_disposed) {
      final batch = _pending.take(_batchSize).toList();
      _pending.removeAll(batch);
      try {
        final icons = await _platform.getPackIcons(batch, sizePx: 144, shape: shape, style: style, appId: appId);
        if (_disposed) return;
        _icons.addAll(icons);
        notifyListeners();
      } catch (e) {
        debugPrint('IconPicker: render failed: $e');
      }
    }
    _scheduled = false;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
