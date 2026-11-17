import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/apps/apps_controller.dart';
import '../../../core/models/app_info.dart';
import '../../../core/platform/instant_platform.dart';
import '../../../core/widgets/app_icon.dart';
import '../../app_actions/app_actions_sheet.dart';
import '../../appearance/wallpaper_glass.dart';
import '../../standard_home/corner_shapes.dart';
import '../../hidden_apps/visible_apps.dart';

/// The last text-search apps found, shown at once while they're looked up
/// again (an app may have been installed since).
List<InstantTarget>? _lastTextTargets;

/// The text-search apps last found (null before the first look-up).
List<InstantTarget>? get cachedTextTargets => _lastTextTargets;

/// Looks up the text-search apps again (and caches them).
Future<List<InstantTarget>> loadTextTargets(InstantPlatform platform) async =>
    _lastTextTargets = await platform.targets(InstantKind.text);

/// The image apps last found, so the image sheet opens at once.
List<InstantTarget>? _lastImageTargets;

/// Link apps last found per kind of link (scheme + host), so a scanned
/// code's sheet opens at once.
final _lastLinkTargets = <String, List<InstantTarget>>{};

String _linkKey(String code) {
  final uri = Uri.tryParse(code);
  return '${uri?.scheme.toLowerCase()}:${uri?.host.toLowerCase()}';
}

/// Looks up the text and image apps ahead of time, so every sheet opens
/// without waiting.
void prefetchTargets(InstantPlatform platform) {
  loadTextTargets(platform).ignore();
  platform.targets(InstantKind.image).then((t) => _lastImageTargets = t).ignore();
}

/// Sheets open and close quickly: the widget is about getting somewhere.
const _fast = AnimationStyle(duration: Duration(milliseconds: 200), reverseDuration: Duration(milliseconds: 140));

Future<void> _sheet(BuildContext context, WidgetBuilder builder) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  sheetAnimationStyle: _fast,
  builder: builder,
);

/// "Ask Claude" for assistants, "Search YouTube" for the rest.
String askLabel(InstantTarget t) => (_assistants.contains(t.packageName) ? 'Ask ' : 'Search ') + t.label;

const _assistants = {
  'com.anthropic.claude',
  'com.openai.chatgpt',
  'com.google.android.apps.bard',
  'ai.perplexity.app.android',
};

/// A search box over the home screen, in glass, floating above the
/// keyboard; as you type, the installed apps whose names match slide in just
/// above it, and above them the apps that can search for it (Google, Claude,
/// ChatGPT, YouTube…) in one row that scrolls sideways. Search on the
/// keyboard uses the first app, or [preferred] (listed first) if given.
Future<void> showInstantSearch(BuildContext context, {String initial = '', InstantTarget? preferred}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      elevation: 0,
      barrierColor: Colors.black54,
      sheetAnimationStyle: _fast,
      builder: (_) => _SearchSheet(initial: initial, preferred: preferred),
    );

/// A scanned code: a link or payment offers the apps that open it (for UPI
/// the payment apps, with who's being paid); anything else is searched for.
Future<void> showScanned(BuildContext context, String code) async {
  if (!_hasScheme(code)) return showInstantSearch(context, initial: code);
  final platform = context.read<InstantPlatform>();
  final key = _linkKey(code);
  final fresh = platform.targets(InstantKind.link, data: code).then((t) => _lastLinkTargets[key] = t);
  // Seen this kind of link before: open now, the list refreshes in place.
  final cached = _lastLinkTargets[key];
  final first = cached ?? await fresh;
  if (!context.mounted) return;
  if (first.isEmpty) return showInstantSearch(context, initial: code);
  await _sheet(context, (_) => _LinkSheet(code: code, initial: first, fresh: cached == null ? null : fresh));
}

/// A picked image: send it to Lens, an assistant, or a payment app (which
/// reads a QR code in it).
Future<void> showImageTargets(BuildContext context, String path) async {
  final fresh = context.read<InstantPlatform>().targets(InstantKind.image).then((t) => _lastImageTargets = t);
  final cached = _lastImageTargets;
  final first = cached ?? await fresh;
  if (!context.mounted) return;
  await _sheet(context, (_) => _ImageSheet(path: path, initial: first, fresh: cached == null ? null : fresh));
}

bool _hasScheme(String s) => RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*:\S').hasMatch(s);

/// Hands [text] / [file] to [target] and closes the sheet; a snack bar if
/// the app wouldn't open.
Future<void> _launch(BuildContext context, InstantTarget target, {String? text, String? file}) async {
  HapticFeedback.selectionClick();
  final navigator = Navigator.of(context);
  final messenger = ScaffoldMessenger.maybeOf(context);
  final ok = await context.read<InstantPlatform>().open(target, text: text, file: file);
  if (ok) {
    navigator.maybePop();
  } else {
    messenger?.showSnackBar(SnackBar(content: Text("Couldn't open ${target.label}")));
  }
}

class _SearchSheet extends StatefulWidget {
  const _SearchSheet({required this.initial, this.preferred});

  final String initial;
  final InstantTarget? preferred;

  @override
  State<_SearchSheet> createState() => _SearchSheetState();
}

class _SearchSheetState extends State<_SearchSheet> {
  late final _text = TextEditingController(text: widget.initial);
  late List<InstantTarget> _targets = _ordered(_lastTextTargets ?? const []);

  /// [_SearchSheet.preferred] first.
  List<InstantTarget> _ordered(List<InstantTarget> all) {
    final first = widget.preferred?.packageName;
    if (first == null) return all;
    return [...all.where((t) => t.packageName == first), ...all.where((t) => t.packageName != first)];
  }

  @override
  void initState() {
    super.initState();
    loadTextTargets(context.read<InstantPlatform>()).then((t) {
      if (mounted) setState(() => _targets = _ordered(t));
    });
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  /// Apps whose names match [q]: names starting with it first, then a word
  /// in the name starting with it, then anywhere in the name.
  static List<AppInfo> _matching(List<AppInfo> all, String q) {
    if (q.isEmpty) return const [];
    final starts = <AppInfo>[], words = <AppInfo>[], inside = <AppInfo>[];
    for (final a in all) {
      final name = a.label.toLowerCase();
      if (name.startsWith(q)) {
        starts.add(a);
      } else if (name.contains(' $q')) {
        words.add(a);
      } else if (name.contains(q)) {
        inside.add(a);
      }
    }
    return [...starts, ...words, ...inside].take(24).toList();
  }

  @override
  Widget build(BuildContext context) {
    final query = _text.text.trim();
    final apps = _matching(context.watch<VisibleApps>().apps, query.toLowerCase());

    return Padding(
      padding: EdgeInsets.fromLTRB(12, 0, 12, MediaQuery.viewInsetsOf(context).bottom + 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_targets.isNotEmpty)
            _GlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _GlassHeading(query.isEmpty ? 'Search with' : 'Search “$query” with'),
                  _IconRow(
                    children: [
                      for (final t in _targets)
                        _RowTile(
                          key: ValueKey('t:${t.packageName}'),
                          app: _appFor(context, t),
                          label: t.label,
                          onTap: () => _launch(context, t, text: query),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          const SizedBox(height: 10),
          _GlassSearchField(
            controller: _text,
            // Spoken / scanned text arrives filled in: show the apps, not the keyboard.
            autofocus: widget.initial.isEmpty,
            hint: widget.preferred == null ? 'Search or ask' : '${askLabel(widget.preferred!)}…',
            onChanged: () => setState(() {}),
            onSubmitted: () {
              if (query.isEmpty) return;
              if (_targets.isNotEmpty) {
                _launch(context, _targets.first, text: query);
              } else if (apps.isNotEmpty) {
                openApp(context, apps.first).then((ok) {
                  if (ok && context.mounted) Navigator.maybePop(context);
                });
              }
            },
          ),
          // Matching apps, right under the bar: they grow in as you type.
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: apps.isEmpty
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: _GlassCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const _GlassHeading('Apps'),
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 160),
                            switchInCurve: Curves.easeOut,
                            switchOutCurve: Curves.easeIn,
                            layoutBuilder: (current, previous) =>
                                Stack(alignment: Alignment.centerLeft, children: [...previous, ?current]),
                            child: _IconRow(
                              key: ValueKey(apps.map((a) => a.id).join('|')),
                              children: [
                                for (final a in apps)
                                  _RowTile(
                                    key: ValueKey('a:${a.id}'),
                                    app: a,
                                    label: a.label,
                                    onTap: () async {
                                      final navigator = Navigator.of(context);
                                      if (await openApp(context, a)) navigator.maybePop();
                                    },
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// The launcher's own icon for [t] (shape, style, icon packs) where it has one.
AppInfo _appFor(BuildContext context, InstantTarget t) =>
    context.read<AppsController>().apps.where((a) => a.packageName == t.packageName).firstOrNull ??
    AppInfo(id: t.packageName, label: t.label, packageName: t.packageName, activityName: '', lastUpdateTime: 0);

/// The search sheet's glass: the wallpaper behind it blurred, a faint
/// darkening (white fills read "whitish") and a hairline rim.
final _glassFill = Colors.black.withValues(alpha: 0.22);
final _glassEdge = BorderSide(color: Colors.white.withValues(alpha: 0.16), width: 0.5);

class _GlassCard extends StatelessWidget {
  const _GlassCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final shape = CornerShapes.shape(26, side: _glassEdge);
    return WallpaperGlass(
      shape: shape,
      sigma: 24,
      child: DecoratedBox(
        decoration: ShapeDecoration(shape: shape, color: _glassFill),
        child: Padding(padding: const EdgeInsets.only(bottom: 8), child: child),
      ),
    );
  }
}

class _GlassHeading extends StatelessWidget {
  const _GlassHeading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(18, 14, 18, 4),
    child: Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: Colors.white.withValues(alpha: 0.62),
        fontSize: 12.5,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.3,
      ),
    ),
  );
}

/// One row of icons that scrolls sideways.
class _IconRow extends StatelessWidget {
  const _IconRow({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 86,
    child: ListView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      children: children,
    ),
  );
}

class _RowTile extends StatefulWidget {
  const _RowTile({super.key, required this.app, required this.label, required this.onTap});

  final AppInfo app;
  final String label;
  final VoidCallback onTap;

  @override
  State<_RowTile> createState() => _RowTileState();
}

class _RowTileState extends State<_RowTile> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _down ? 0.9 : 1,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: SizedBox(
          width: 72,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AppIcon(app: widget.app, size: 46),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.88), fontSize: 11.5),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The search bar: a glass pill, white text, search glyph, and a clear
/// button once there's text.
class _GlassSearchField extends StatelessWidget {
  const _GlassSearchField({
    required this.controller,
    required this.autofocus,
    required this.hint,
    required this.onChanged,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final bool autofocus;
  final String hint;
  final VoidCallback onChanged;
  final VoidCallback onSubmitted;

  @override
  Widget build(BuildContext context) {
    final shape = StadiumBorder(side: BorderSide(color: Colors.white.withValues(alpha: 0.24), width: 0.6));
    final hasText = controller.text.isNotEmpty;
    return WallpaperGlass(
      shape: shape,
      sigma: 24,
      child: DecoratedBox(
        decoration: ShapeDecoration(shape: shape, color: _glassFill),
        child: SizedBox(
          height: 58,
          child: Row(
            children: [
              const SizedBox(width: 20),
              Icon(Icons.search_rounded, size: 24, color: Colors.white.withValues(alpha: 0.9)),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: controller,
                  autofocus: autofocus,
                  textInputAction: TextInputAction.search,
                  onChanged: (_) => onChanged(),
                  onSubmitted: (_) => onSubmitted(),
                  cursorColor: Colors.white,
                  cursorWidth: 1.6,
                  style: const TextStyle(color: Colors.white, fontSize: 17, letterSpacing: 0.15),
                  decoration: InputDecoration(
                    isCollapsed: true,
                    border: InputBorder.none,
                    hintText: hint,
                    hintStyle: TextStyle(
                      color: Colors.white.withValues(alpha: 0.55),
                      fontSize: 17,
                      letterSpacing: 0.15,
                    ),
                  ),
                ),
              ),
              AnimatedOpacity(
                opacity: hasText ? 1 : 0,
                duration: const Duration(milliseconds: 150),
                child: IgnorePointer(
                  ignoring: !hasText,
                  child: IconButton(
                    icon: Icon(Icons.close_rounded, color: Colors.white.withValues(alpha: 0.85)),
                    onPressed: () {
                      controller.clear();
                      onChanged();
                    },
                  ),
                ),
              ),
              const SizedBox(width: 6),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shows [initial] at once and swaps in [fresh] (if any) when it arrives.
class _Refreshing extends StatelessWidget {
  const _Refreshing({required this.initial, required this.fresh, required this.builder});

  final List<InstantTarget> initial;
  final Future<List<InstantTarget>>? fresh;
  final Widget Function(List<InstantTarget>) builder;

  @override
  Widget build(BuildContext context) => fresh == null
      ? builder(initial)
      : FutureBuilder(future: fresh, initialData: initial, builder: (_, s) => builder(s.data ?? initial));
}

class _LinkSheet extends StatelessWidget {
  const _LinkSheet({required this.code, required this.initial, this.fresh});

  final String code;
  final List<InstantTarget> initial;
  final Future<List<InstantTarget>>? fresh;

  @override
  Widget build(BuildContext context) {
    final uri = Uri.tryParse(code);
    final upi = uri?.scheme.toLowerCase() == 'upi';
    final params = upi ? uri!.queryParameters : const <String, String>{};
    final payee = params['pn']?.trim();
    final id = params['pa']?.trim();
    final amount = params['am']?.trim();
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            upi ? 'Pay ${payee?.isNotEmpty == true ? payee : (id ?? '')}' : 'Open link',
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: 4),
          Text(
            upi ? [?id, if (amount != null && amount.isNotEmpty) '₹$amount'].join('  ·  ') : code,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          _Heading(upi ? 'Pay with' : 'Open with'),
          _Refreshing(
            initial: initial,
            fresh: fresh,
            builder: (targets) => _TargetGrid(
              targets: targets,
              onTap: (t) => _launch(context, t, text: code),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              ActionChip(
                avatar: const Icon(Icons.copy_rounded, size: 18),
                label: Text(upi ? 'Copy UPI ID' : 'Copy'),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: upi && id != null ? id : code));
                  Navigator.maybePop(context);
                },
              ),
              if (!upi)
                ActionChip(
                  avatar: const Icon(Icons.search_rounded, size: 18),
                  label: const Text('Search for it'),
                  onPressed: () {
                    final home = Navigator.of(context);
                    home.pop();
                    showInstantSearch(home.context, initial: code);
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ImageSheet extends StatelessWidget {
  const _ImageSheet({required this.path, required this.initial, this.fresh});

  final String path;
  final List<InstantTarget> initial;
  final Future<List<InstantTarget>>? fresh;

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.file(
                File(path),
                height: 140,
                cacheHeight: (140 * dpr).round(),
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => const SizedBox(height: 140, child: Icon(Icons.broken_image_outlined)),
              ),
            ),
          ),
          const _Heading('Search with'),
          _Refreshing(
            initial: initial,
            fresh: fresh,
            builder: (targets) => _TargetGrid(
              targets: targets,
              onTap: (t) => _launch(context, t, file: path),
              more: () async {
                final navigator = Navigator.of(context);
                if (await context.read<InstantPlatform>().more(InstantKind.image, file: path)) navigator.maybePop();
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 10),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      ),
    );
  }
}

/// Apps that can take it, as icons with names; [more] adds a "More" tile
/// for Android's share sheet.
class _TargetGrid extends StatelessWidget {
  const _TargetGrid({required this.targets, required this.onTap, this.more});

  final List<InstantTarget> targets;
  final ValueChanged<InstantTarget> onTap;
  final VoidCallback? more;

  @override
  Widget build(BuildContext context) {
    // The launcher's own icons (shape, style, icon packs) where it has them.
    final apps = context.watch<AppsController>().apps;
    AppInfo appFor(InstantTarget t) =>
        apps.where((a) => a.packageName == t.packageName).firstOrNull ??
        AppInfo(id: t.packageName, label: t.label, packageName: t.packageName, activityName: '', lastUpdateTime: 0);

    return _Grid(
      children: [
        for (final t in targets) _Tile(app: appFor(t), label: t.label, onTap: () => onTap(t)),
        if (more != null)
          _Tile(
            label: 'More',
            onTap: more!,
            icon: const CircleAvatar(radius: 24, child: Icon(Icons.more_horiz_rounded)),
          ),
      ],
    );
  }
}

/// Five to a row, as wide as fits.
class _Grid extends StatelessWidget {
  const _Grid({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final width = box.maxWidth / 5;
        return Wrap(
          children: [for (final c in children) SizedBox(width: width, child: c)],
        );
      },
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({this.app, this.icon, required this.label, required this.onTap});

  final AppInfo? app;
  final Widget? icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: [
            SizedBox.square(dimension: 48, child: icon ?? AppIcon(app: app!, size: 48)),
            const SizedBox(height: 6),
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}
