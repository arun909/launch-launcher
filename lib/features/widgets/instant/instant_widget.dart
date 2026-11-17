import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/platform/instant_platform.dart';
import '../../standard_home/corner_shapes.dart';
import '../../standard_home/home_layout.dart';
import '../../standard_home/home_layout_controller.dart';
import '../launcher_widgets.dart';
import 'instant_sheets.dart';

/// The instant-search widget: one place to search with any app (Google,
/// Claude, ChatGPT, YouTube…), scan a QR code (a UPI code offers the
/// payment apps that can pay it), speak a search, take a photo, record, or
/// send an image to Lens / an assistant / a payment app. Everything hands
/// off to the phone's own apps, except the camera: a live viewfinder of
/// our own (CaptureActivity.kt), so one tap goes straight to search. Sheets
/// open without waiting (the apps are looked up ahead of time) and quickly.
///
/// Black and white, all five (Search, Scan, Camera, Recorder, Image) in
/// every size; only sizes they all fit in (cols × rows; on grids narrower
/// than 6 columns the 6 means their full width, e.g. 5 on Medium):
/// - 2 × 2: the four two by two, the search pill under them;
/// - 4 × 1 / 6 × 1: a strip: a short search pill, then the four;
/// - 4 × 2 / 6 × 2: the four, the search pill (with its mic) under them.
/// The four sit in key-like tiles, by a few proportion rules:
/// - one material: tiles and pill share the same faint fill (the panel has
///   the glass), no borders, gradients or glows;
/// - one module: in the strip, tiles are as tall as the pill; in 2 rows and
///   the square, the tile row spans exactly the pill's width;
/// - one gap ([_gap], on the 8dp grid) between everything;
/// - continuous (squircle) corners at ~30% of a tile's height, the icon at
///   ~45% of it (Material's 24-in-48).
/// The pill's hint cycles through what you can do ("Ask Claude…").
const instantKind = LauncherWidgetKind(
  name: 'instant',
  label: 'Instant search',
  description: 'Search with any app, scan to pay, voice, camera, recorder and images',
  icon: Icons.manage_search_rounded,
  size: (6, 2),
  min: (2, 1),
  max: (6, 2),
  sizes: [(2, 2), (4, 1), (6, 1), (4, 2), (6, 2)],
  build: _build,
  customise: showInstantSettings,
  styleOf: _style,
  interactive: true,
);

/// Its panel: light, dark, glass blur (as a group's) or a solid Material
/// surface, dark or light (WidgetItem.settings['style']).
GroupStyle _style(Map<String, dynamic> settings) => panelStyleFrom(settings['style'], styles: _styles);

const _styles = panelStyles;

Widget _build(BuildContext context, Map<String, dynamic> settings) => InstantWidget(style: _style(settings));

class InstantWidget extends StatefulWidget {
  const InstantWidget({super.key, this.style = GroupStyle.glass});

  /// Its panel. On a solid Material surface: tiles and pill in the next
  /// tone up (down, on the light one), no hairlines (Material separates by
  /// tone, not by edges).
  final GroupStyle style;

  @override
  State<InstantWidget> createState() => _InstantWidgetState();
}

class _InstantWidgetState extends State<InstantWidget> {
  List<InstantTarget> _targets = cachedTextTargets ?? const [];

  @override
  void initState() {
    super.initState();
    final platform = Provider.of<InstantPlatform?>(context, listen: false);
    if (platform != null) {
      prefetchTargets(platform);
      loadTextTargets(platform).then((t) {
        if (mounted) setState(() => _targets = t);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = _Actions(context);
    final look = switch (widget.style) {
      GroupStyle.material => _Look.material,
      GroupStyle.materialLight => _Look.materialLight,
      _ => _Look.glass,
    };
    final hints = ['Search or ask', for (final t in _targets.take(5)) askLabel(t), 'Scan to pay'];

    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth, h = box.maxHeight;

        // 1 row: a short pill, then the four as square tiles its height.
        if (h < 84) {
          final unit = (h * 0.75).clamp(36.0, 40.0);
          return Row(
            children: [
              Expanded(
                child: _SearchPill(look: look, height: unit, hints: const ['Search'], onTap: a.search),
              ),
              for (final x in a.four) ...[
                const SizedBox(width: _gap),
                _Tile(look: look, action: x, width: unit, height: unit),
              ],
            ],
          );
        }

        // Square or 2 rows: the tiles (two by two in the square) spanning
        // the pill's width, the pill under them, the block centred.
        final square = w < 220;
        final perRow = square ? 2 : 4;
        final rows = square ? [a.four.take(2), a.four.skip(2)] : [a.four];
        final pill = square ? 40.0 : 52.0;
        final tileW = (w - _gap * (perRow - 1)) / perRow;
        final room = (h - pill - _gap * rows.length) / rows.length;
        final tileH = [room, tileW, square ? 52.0 : 72.0].reduce((x, y) => x < y ? x : y);
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final row in rows) ...[
                Row(
                  children: [
                    for (final (i, x) in row.indexed) ...[
                      if (i > 0) const SizedBox(width: _gap),
                      _Tile(look: look, action: x, width: tileW, height: tileH),
                    ],
                  ],
                ),
                const SizedBox(height: _gap),
              ],
              _SearchPill(
                look: look,
                height: pill,
                hints: square ? const ['Search'] : hints,
                onTap: a.search,
                onMic: a.voice,
              ),
            ],
          ),
        );
      },
    );
  }
}

/// A press: quick enough to feel instant, long enough to be seen.
const _press = Duration(milliseconds: 70);

/// The one gap between tiles, rows and the pill.
const _gap = 8.0;

/// What tiles and pill share.
class _Look {
  const _Look(this.fill, this.pressedFill, this.edge);

  /// Not another white frost over the panel's glass (stacked, those go
  /// milky), but a faint neutral darkening that keeps the blurred
  /// wallpaper's own colour, and a precise hairline edge (one physical
  /// pixel at about the phone's density) that keeps them crisp. Pressed:
  /// the darkening lifts, the glass shows a little brighter.
  static const glass = _Look(Color(0x1F000000), Color(0x0FFFFFFF), BorderSide(color: Color(0x24FFFFFF), width: 0.5));

  /// On the Material surface: the next tones up (surfaceContainerHighest,
  /// and a lighter state layer when pressed), no edges.
  static const material = _Look(Color(0xFF33353A), Color(0xFF3E4046), BorderSide.none);

  /// On the light Material surface: a tone down, a little deeper when
  /// pressed, no edges.
  static const materialLight = _Look(Color(0xFFE2E3E8), Color(0xFFD6D7DD), BorderSide.none);

  final Color fill;
  final Color pressedFill;
  final BorderSide edge;
}

/// One action: its icon and (for screen readers) its name.
class _Action {
  const _Action(this.icon, this.label, this.run);
  final IconData icon;
  final String label;
  final VoidCallback run;
}

/// What the widget's buttons do. Everything opens another app or a sheet.
class _Actions {
  _Actions(this.context);

  final BuildContext context;

  InstantPlatform? get _platform => Provider.of<InstantPlatform?>(context, listen: false);

  _Action get scanAction => _Action(Icons.qr_code_scanner_rounded, 'Scan', scan);
  _Action get cameraAction => _Action(Icons.photo_camera_outlined, 'Camera', camera);
  _Action get recorderAction => _Action(Icons.graphic_eq_rounded, 'Recorder', recorder);
  _Action get imageAction => _Action(Icons.image_outlined, 'Image', image);

  List<_Action> get four => [scanAction, cameraAction, recorderAction, imageAction];

  void search() {
    HapticFeedback.selectionClick();
    showInstantSearch(context);
  }

  Future<void> voice() => _guard(() async {
    final said = await _platform?.listen();
    if (said != null && said.trim().isNotEmpty && context.mounted) showInstantSearch(context, initial: said);
  });

  Future<void> scan() => _guard(() async {
    final code = await _platform?.scan();
    if (code != null && code.trim().isNotEmpty && context.mounted) await showScanned(context, code.trim());
  });

  Future<void> image() => _guard(() async {
    final path = await _platform?.pickImage();
    if (path != null && context.mounted) await showImageTargets(context, path);
  });

  /// Take a photo in the camera's live viewfinder, then search with it
  /// (Lens, an assistant, a payment app, or any app through More).
  Future<void> camera() => _guard(() async {
    final path = await _platform?.capture();
    if (path != null && context.mounted) await showImageTargets(context, path);
  });

  Future<void> recorder() => _guard(() async {
    if (await _platform?.openRecorder() == false) throw const InstantError('No recorder app found');
  });

  /// Runs [work] with a light tap, reporting what went wrong as a snack bar.
  Future<void> _guard(Future<void> Function() work) async {
    HapticFeedback.selectionClick();
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await work();
    } on InstantError catch (e) {
      messenger?.showSnackBar(SnackBar(content: Text(e.message)));
    } on PlatformException catch (e) {
      messenger?.showSnackBar(SnackBar(content: Text(e.message ?? 'Something went wrong')));
    }
  }
}

/// Dips when pressed, as the music widget's buttons do.
class _Pressable extends StatefulWidget {
  const _Pressable({required this.onTap, required this.child});

  final VoidCallback onTap;
  final Widget child;

  @override
  State<_Pressable> createState() => _PressableState();
}

class _PressableState extends State<_Pressable> {
  bool _down = false;

  void _set(bool down) {
    if (down != _down) setState(() => _down = down);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _set(true),
      onTapUp: (_) => _set(false),
      onTapCancel: () => _set(false),
      onTap: widget.onTap,
      child: AnimatedScale(scale: _down ? 0.88 : 1, duration: _press, curve: Curves.easeOut, child: widget.child),
    );
  }
}

/// One action in a key-like tile in its [_Look], continuous corners at ~30% of
/// its height, the icon at ~45% of it. Brightens and dips when pressed.
class _Tile extends StatefulWidget {
  const _Tile({required this.look, required this.action, required this.width, required this.height});

  final _Look look;
  final _Action action;
  final double width;
  final double height;

  @override
  State<_Tile> createState() => _TileState();
}

class _TileState extends State<_Tile> {
  bool _down = false;

  void _set(bool down) {
    if (down != _down) setState(() => _down = down);
  }

  @override
  Widget build(BuildContext context) {
    final h = widget.height;
    // Corners and icon go by the shorter side, so tall tiles stay key-like.
    final side = h < widget.width ? h : widget.width;
    return Semantics(
      button: true,
      label: widget.action.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _set(true),
        onTapUp: (_) => _set(false),
        onTapCancel: () => _set(false),
        onTap: widget.action.run,
        child: AnimatedScale(
          scale: _down ? 0.94 : 1,
          duration: _press,
          curve: Curves.easeOut,
          child: AnimatedContainer(
            duration: _press,
            width: widget.width,
            height: h,
            decoration: ShapeDecoration(
              shape: CornerShapes.shape(side * 0.3, side: widget.look.edge),
              color: _down ? widget.look.pressedFill : widget.look.fill,
            ),
            alignment: Alignment.center,
            child: Icon(
              widget.action.icon,
              size: (side * 0.45).roundToDouble(),
              color: PanelInk.of(context).withValues(alpha: 0.92),
            ),
          ),
        ),
      ),
    );
  }
}

/// The search pill: plain and faint (the panel has the glass), tap to
/// type, mic (if any) to speak. Its hint cycles through [hints].
class _SearchPill extends StatefulWidget {
  const _SearchPill({required this.look, required this.height, required this.hints, required this.onTap, this.onMic});

  final _Look look;
  final double height;
  final List<String> hints;
  final VoidCallback onTap;

  /// Voice search; null for none.
  final VoidCallback? onMic;

  @override
  State<_SearchPill> createState() => _SearchPillState();
}

class _SearchPillState extends State<_SearchPill> {
  static const _every = Duration(milliseconds: 3200);
  Timer? _timer;
  int _hint = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(_every, (_) {
      if (mounted && widget.hints.length > 1) setState(() => _hint = (_hint + 1) % widget.hints.length);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final h = widget.height;
    final hint = widget.hints.isEmpty ? 'Search' : widget.hints[_hint % widget.hints.length];
    final mic = widget.onMic;
    final ink = PanelInk.of(context);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.selectionClick();
        widget.onTap();
      },
      child: Container(
        height: h,
        decoration: ShapeDecoration(
          shape: StadiumBorder(side: widget.look.edge),
          color: widget.look.fill,
        ),
        child: Row(
          children: [
            SizedBox(width: h * 0.3),
            Icon(Icons.search_rounded, size: h * 0.5, color: ink.withValues(alpha: 0.9)),
            SizedBox(width: h * 0.2),
            Expanded(
              child: ClipRect(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 280),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  layoutBuilder: (current, previous) =>
                      Stack(alignment: Alignment.centerLeft, children: [...previous, ?current]),
                  transitionBuilder: (child, anim) => FadeTransition(
                    opacity: anim,
                    child: SlideTransition(
                      position: Tween(begin: const Offset(0, 0.5), end: Offset.zero).animate(anim),
                      child: child,
                    ),
                  ),
                  child: Text(
                    '$hint…',
                    key: ValueKey(hint),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: ink.withValues(alpha: 0.72),
                      fontSize: h >= 44 ? 16 : 15,
                      letterSpacing: 0.15,
                    ),
                  ),
                ),
              ),
            ),
            if (mic != null)
              _Pressable(
                onTap: mic,
                child: SizedBox.square(
                  dimension: h,
                  child: Icon(Icons.mic_none_rounded, size: h * 0.5, color: ink.withValues(alpha: 0.92)),
                ),
              )
            else
              SizedBox(width: h * 0.3),
          ],
        ),
      ),
    );
  }
}

/// The widget's options: its background.
Future<void> showInstantSettings(BuildContext context, WidgetItem item) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  barrierColor: Colors.black26,
  sheetAnimationStyle: const AnimationStyle(
    duration: Duration(milliseconds: 200),
    reverseDuration: Duration(milliseconds: 140),
  ),
  builder: (_) => _InstantSettingsSheet(id: item.id),
);

class _InstantSettingsSheet extends StatelessWidget {
  const _InstantSettingsSheet({required this.id});

  final String id;

  @override
  Widget build(BuildContext context) {
    final layout = context.watch<HomeLayoutController>();
    final item = layout.findWidget(id);
    if (item == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Instant search', style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              'The buttons with the search bar under them (2 × 2, 4 wide or the full width of the grid) or a '
              'strip (1 row, 4 wide or full width). Drag its handles to switch.',
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70),
            ),
            const SizedBox(height: 20),
            Text('Background', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            PanelStylePicker(
              styles: _styles,
              value: _style(item.settings),
              onChanged: (v) => layout.updateWidgetSettings(id, {...item.settings, 'style': v?.name}),
            ),
          ],
        ),
      ),
    );
  }
}
