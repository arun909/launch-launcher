import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/platform/instant_platform.dart';
import '../../standard_home/corner_shapes.dart';
import '../../standard_home/home_layout.dart';
import '../../standard_home/home_layout_controller.dart';
import '../launcher_widgets.dart';
import 'chrome_sites.dart';

/// The Chrome widget: straight into a new Incognito tab or one of the
/// sites you've pinned to it (shared by every Chrome widget; see
/// [ChromeSitesController]), each with the site's own icon.
///
/// The instant widget's look: key-like squircle tiles with a faint fill and
/// hairline edge, one 8dp gap. Incognito first, then as many sites as fit,
/// in rows of roughly square tiles: 2 × 2 holds Incognito and three sites;
/// wider and 2-row sizes hold more. The first empty spot is a faint "+".
const chromeKind = LauncherWidgetKind(
  name: 'chrome',
  label: 'Chrome',
  description: 'Incognito tab and your sites, one tap away',
  icon: Icons.public_rounded,
  size: (4, 2),
  min: (2, 1),
  max: (6, 2),
  sizes: [(2, 2), (4, 1), (6, 1), (4, 2), (6, 2)],
  build: _build,
  customise: showChromeSettings,
  styleOf: _style,
  interactive: true,
);

GroupStyle _style(Map<String, dynamic> settings) => panelStyleFrom(settings['style']);

Widget _build(BuildContext context, Map<String, dynamic> settings) => const ChromeWidget();

const _gap = 8.0;
const _press = Duration(milliseconds: 70);
final _fill = Colors.black.withValues(alpha: 0.12);

/// Pressed and the edge are in the panel's ink (PanelInk): white, or dark
/// on a light panel.
Color _pressedFill(Color ink) => ink.withValues(alpha: 0.06);
BorderSide _edge(Color ink, [double alpha = 0.14]) => BorderSide(color: ink.withValues(alpha: alpha), width: 0.5);

class ChromeWidget extends StatelessWidget {
  const ChromeWidget({super.key});

  @override
  Widget build(BuildContext context) {
    // Nullable: absent in tests and previews without the app's providers.
    final controller = Provider.of<ChromeSitesController?>(context);
    final sites = controller?.sites ?? const <ChromeSite>[];

    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth, h = box.maxHeight;
        final rows = h < 84 ? 1 : 2;
        // Roughly square tiles, as tall as the rows allow.
        final tileH = ((h - _gap * (rows - 1)) / rows).clamp(0.0, 72.0);
        final perRow = ((w + _gap) / (tileH + _gap)).floor().clamp(2, 12);
        final tileW = (w - _gap * (perRow - 1)) / perRow;

        Widget slot(int i) {
          if (i == 0) {
            return _Key(
              width: tileW,
              height: tileH,
              label: 'New Incognito tab',
              run: _incognito,
              child: _incognitoGlyph,
            );
          }
          final s = i - 1;
          if (s < sites.length) {
            return _SiteKey(site: sites[s], icon: controller?.iconOf(sites[s]), width: tileW, height: tileH);
          }
          if (s == sites.length && sites.length < ChromeSitesController.max) {
            return _AddKey(width: tileW, height: tileH);
          }
          return SizedBox(width: tileW, height: tileH);
        }

        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var r = 0; r < rows; r++) ...[
                if (r > 0) const SizedBox(height: _gap),
                Row(
                  children: [
                    for (var c = 0; c < perRow; c++) ...[if (c > 0) const SizedBox(width: _gap), slot(r * perRow + c)],
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// Chrome into [action] (see InstantPlatform.chrome), a snack bar if it won't open.
Future<void> _chrome(BuildContext context, String action, {String? url}) async {
  HapticFeedback.selectionClick();
  final messenger = ScaffoldMessenger.maybeOf(context);
  final ok = await Provider.of<InstantPlatform?>(context, listen: false)?.chrome(action, url: url) ?? false;
  if (!ok) messenger?.showSnackBar(const SnackBar(content: Text("Couldn't open Chrome")));
}

void _incognito(BuildContext context) => _chrome(context, 'incognito');

Widget _incognitoGlyph(double size) => Builder(
  builder: (context) =>
      CustomPaint(size: Size.square(size), painter: _IncognitoPainter(PanelInk.of(context).withValues(alpha: 0.92))),
);

/// A key-like tile: [_fill] with an [_edge], continuous corners at ~30% of
/// its shorter side, its glyph at ~45%. Brightens and dips when pressed.
class _Key extends StatefulWidget {
  const _Key({
    required this.width,
    required this.height,
    required this.label,
    required this.run,
    required this.child,
    this.faint = false,
  });

  final double width;
  final double height;
  final String label;
  final void Function(BuildContext context) run;

  /// The glyph, at the size given.
  final Widget Function(double size) child;

  /// An empty slot: no fill, a fainter edge.
  final bool faint;

  @override
  State<_Key> createState() => _KeyState();
}

class _KeyState extends State<_Key> {
  bool _down = false;

  void _set(bool down) {
    if (down != _down) setState(() => _down = down);
  }

  @override
  Widget build(BuildContext context) {
    final h = widget.height;
    final side = h < widget.width ? h : widget.width;
    final ink = PanelInk.of(context);
    return Semantics(
      button: true,
      label: widget.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _set(true),
        onTapUp: (_) => _set(false),
        onTapCancel: () => _set(false),
        onTap: () => widget.run(context),
        child: AnimatedScale(
          scale: _down ? 0.94 : 1,
          duration: _press,
          curve: Curves.easeOut,
          child: AnimatedContainer(
            duration: _press,
            width: widget.width,
            height: h,
            decoration: ShapeDecoration(
              shape: CornerShapes.shape(side * 0.3, side: widget.faint ? _edge(ink, 0.1) : _edge(ink)),
              color: _down ? _pressedFill(ink) : (widget.faint ? Colors.transparent : _fill),
            ),
            alignment: Alignment.center,
            child: widget.child((side * 0.45).roundToDouble()),
          ),
        ),
      ),
    );
  }
}

/// A faint "+" that adds a site.
class _AddKey extends StatelessWidget {
  const _AddKey({required this.width, required this.height});

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) => _Key(
    width: width,
    height: height,
    label: 'Add a site',
    faint: true,
    run: (context) {
      HapticFeedback.selectionClick();
      showSiteEditor(context);
    },
    child: (size) => Icon(Icons.add_rounded, size: size, color: PanelInk.of(context).withValues(alpha: 0.5)),
  );
}

/// A site, opened in Chrome on tap: its own icon, else its initial.
class _SiteKey extends StatelessWidget {
  const _SiteKey({required this.site, required this.icon, required this.width, required this.height});

  final ChromeSite site;
  final File? icon;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return _Key(
      width: width,
      height: height,
      label: 'Open ${site.name}',
      run: (context) => _chrome(context, 'url', url: site.url),
      child: (size) => _SiteFace(site: site, icon: icon, size: size * 1.25),
    );
  }
}

/// [site]'s icon at [size] (rounded a little, as app icons are), or its
/// initial while it has none.
class _SiteFace extends StatelessWidget {
  const _SiteFace({required this.site, required this.icon, required this.size});

  final ChromeSite site;
  final File? icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    final letter = Text(
      site.name.isEmpty ? '?' : site.name.characters.first.toUpperCase(),
      style: TextStyle(
        color: PanelInk.of(context).withValues(alpha: 0.92),
        fontSize: size * 0.7,
        height: 1,
        fontWeight: FontWeight.w500,
      ),
    );
    final file = icon;
    if (file == null) return letter;
    final px = (size * MediaQuery.devicePixelRatioOf(context)).round();
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.24),
      child: Image.file(
        file,
        width: size,
        height: size,
        cacheWidth: px,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.medium,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => letter,
      ),
    );
  }
}

/// Incognito's hat and glasses, as a plain line glyph (24-unit grid, 2-unit
/// strokes, like Material's outlined icons).
class _IncognitoPainter extends CustomPainter {
  const _IncognitoPainter(this.color);

  /// The panel's ink (PanelInk).
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final u = size.width / 24;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8 * u
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    Offset p(double x, double y) => Offset(x * u, y * u);

    // Brim.
    canvas.drawLine(p(2.5, 10.5), p(21.5, 10.5), paint);
    // Crown.
    canvas.drawPath(
      Path()
        ..moveTo(6 * u, 10.5 * u)
        ..lineTo(7.6 * u, 4.6 * u)
        ..quadraticBezierTo(8 * u, 3.6 * u, 9 * u, 4 * u)
        ..lineTo(12 * u, 5 * u)
        ..lineTo(15 * u, 4 * u)
        ..quadraticBezierTo(16 * u, 3.6 * u, 16.4 * u, 4.6 * u)
        ..lineTo(18 * u, 10.5 * u),
      paint,
    );
    // Glasses and their bridge.
    canvas.drawCircle(p(7, 17), 3.2 * u, paint);
    canvas.drawCircle(p(17, 17), 3.2 * u, paint);
    canvas.drawPath(
      Path()
        ..moveTo(10.2 * u, 16.6 * u)
        ..quadraticBezierTo(12 * u, 15.2 * u, 13.8 * u, 16.6 * u),
      paint,
    );
  }

  @override
  bool shouldRepaint(_IncognitoPainter oldDelegate) => oldDelegate.color != color;
}

// ---- Options -----------------------------------------------------------------

/// The widget's options: its sites (shared by every Chrome widget) and its background.
Future<void> showChromeSettings(BuildContext context, WidgetItem item) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  barrierColor: Colors.black26,
  sheetAnimationStyle: const AnimationStyle(
    duration: Duration(milliseconds: 200),
    reverseDuration: Duration(milliseconds: 140),
  ),
  builder: (_) => _ChromeSettingsSheet(id: item.id),
);

/// Adds a site, or edits site [index], in a small dialog.
Future<void> showSiteEditor(BuildContext context, {int? index}) {
  final sites = context.read<ChromeSitesController>();
  final current = index == null ? null : sites.sites[index];
  return showDialog<void>(
    context: context,
    builder: (_) =>
        _SiteDialog(initial: current, onSave: (site) => index == null ? sites.add(site) : sites.replace(index, site)),
  );
}

class _ChromeSettingsSheet extends StatelessWidget {
  const _ChromeSettingsSheet({required this.id});

  final String id;

  @override
  Widget build(BuildContext context) {
    final layout = context.watch<HomeLayoutController>();
    final item = layout.findWidget(id);
    if (item == null) return const SizedBox.shrink();
    final sites = context.watch<ChromeSitesController>();
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: Colors.white70);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Chrome', style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              'Incognito and your sites, in order: the widget shows as many as its size fits '
              '(2 × 2 holds three). Icons come from each site.',
              style: muted,
            ),
            const SizedBox(height: 20),
            Text('Sites', style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            if (sites.sites.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text('No sites yet: add up to ${ChromeSitesController.max}.', style: muted),
              )
            else
              ReorderableListView(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                buildDefaultDragHandles: false,
                onReorderItem: sites.move,
                children: [
                  for (final (i, s) in sites.sites.indexed)
                    ListTile(
                      key: ValueKey('${s.url}#$i'),
                      contentPadding: EdgeInsets.zero,
                      leading: SizedBox.square(
                        dimension: 40,
                        child: Center(
                          child: _SiteFace(site: s, icon: sites.iconOf(s), size: 32),
                        ),
                      ),
                      title: Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(s.shortUrl, maxLines: 1, overflow: TextOverflow.ellipsis),
                      onTap: () => showSiteEditor(context, index: i),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Remove',
                            icon: const Icon(Icons.remove_circle_outline_rounded),
                            onPressed: () => sites.remove(i),
                          ),
                          ReorderableDragStartListener(
                            index: i,
                            child: const Padding(padding: EdgeInsets.all(8), child: Icon(Icons.drag_handle_rounded)),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            if (!sites.isFull)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => showSiteEditor(context),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Add site'),
                ),
              ),
            const SizedBox(height: 16),
            Text('Background', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            PanelStylePicker(
              value: _style(item.settings),
              onChanged: (v) => layout.updateWidgetSettings(id, {...item.settings, 'style': v?.name}),
            ),
          ],
        ),
      ),
    );
  }
}

class _SiteDialog extends StatefulWidget {
  const _SiteDialog({required this.initial, required this.onSave});

  final ChromeSite? initial;
  final ValueChanged<ChromeSite> onSave;

  @override
  State<_SiteDialog> createState() => _SiteDialogState();
}

class _SiteDialogState extends State<_SiteDialog> {
  late final _address = TextEditingController(text: widget.initial?.url ?? '');
  late final _name = TextEditingController(text: widget.initial?.name ?? '');

  @override
  void dispose() {
    _address.dispose();
    _name.dispose();
    super.dispose();
  }

  bool get _valid {
    final a = _address.text.trim();
    return a.isNotEmpty && !a.contains(' ') && a.contains('.');
  }

  void _save() {
    if (!_valid) return;
    widget.onSave(ChromeSite.typed(_address.text, _name.text));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initial == null ? 'Add site' : 'Edit site'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _address,
            autofocus: true,
            keyboardType: TextInputType.url,
            autocorrect: false,
            textInputAction: TextInputAction.next,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: 'Address', hintText: 'youtube.com'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _save(),
            decoration: const InputDecoration(labelText: 'Name (optional)'),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _valid ? _save : null, child: const Text('Save')),
      ],
    );
  }
}
