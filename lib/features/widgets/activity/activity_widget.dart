import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/apps/apps_controller.dart';
import '../../../core/models/app_info.dart';
import '../../../core/platform/device_stats_platform.dart';
import '../../../core/platform/window_blur_platform.dart';
import '../../../core/widgets/app_icon.dart';
import '../../standard_home/home_layout.dart';
import '../../standard_home/home_layout_controller.dart';
import '../launcher_widgets.dart';
import '../stats/device_stats_controller.dart';

/// The activity widget: today's screen time, today's unlocks
/// and today's most used apps (all restart at midnight).
///
/// Material 3 rather than the launcher's black and white: its own tonal
/// surface (dark or light), or the launcher's wallpaper glass with
/// translucent tiles, coloured from a seed the user picks:
/// - 2 × 2: screen time and unlocks as two full-width rows, the top apps' icons
///   below;
/// - 4 × 1 / 6 × 1: a strip of screen time, unlocks and the top apps;
/// - 4 × 2 / 6 × 2: the two stats stacked on the left, the top apps as a
///   list with bars on the right.
const activityKind = LauncherWidgetKind(
  name: 'activity',
  label: 'Activity',
  description: 'Screen time, unlocks today and your most used apps, in Material colours',
  icon: Icons.data_usage_rounded,
  size: (4, 2),
  min: (2, 1),
  max: (6, 2),
  sizes: [(2, 2), (4, 1), (6, 1), (4, 2), (6, 2)],
  build: _build,
  customise: showActivitySettings,
  panelOf: _isGlass,
  styleOf: _panelStyleOf,
  interactive: true,
);

/// Its own Material surface, or the launcher's panel ([_panelStyleOf]:
/// glass blur unless picked otherwise). Stored as 'glass', its name when
/// the panel was always glass.
enum ActivitySurface { dark, light, glass }

/// Stored as 'surface'; older instances kept a 'light' flag.
ActivitySurface _surfaceOf(Map<String, dynamic> settings) =>
    ActivitySurface.values.asNameMap()[settings['surface']] ??
    (settings['light'] == true ? ActivitySurface.light : ActivitySurface.dark);

bool _isGlass(Map<String, dynamic> settings) => _surfaceOf(settings) == ActivitySurface.glass;

/// The panel it sits on with [ActivitySurface.glass] (WidgetItem.settings['style']):
/// any of [panelStyles], glass blur by default.
GroupStyle _panelStyleOf(Map<String, dynamic> settings) => panelStyleFrom(settings['style']);

Widget _build(BuildContext context, Map<String, dynamic> settings) =>
    ActivityWidget(seed: _seedOf(settings), surface: _surfaceOf(settings));

/// The colours it comes in.
const _seeds = <String, Color>{
  'teal': Color(0xFF00897B),
  'blue': Color(0xFF3F6FD8),
  'violet': Color(0xFF7E57C2),
  'rose': Color(0xFFD8436A),
  'amber': Color(0xFFE0A100),
  'green': Color(0xFF4C9A2A),
};

Color _seedOf(Map<String, dynamic> settings) => _seeds[settings['seed']] ?? _seeds['teal']!;

class ActivityWidget extends StatefulWidget {
  const ActivityWidget({super.key, required this.seed, this.surface = ActivitySurface.dark, this.stats});

  final Color seed;

  /// Dark or light Material, or on the launcher's panel (which draws the
  /// panel; this draws only translucent tiles on it, dark-inked on a light
  /// one, see PanelInk).
  final ActivitySurface surface;

  /// Fixed stats instead of the phone's (previews, tests).
  final DeviceStats? stats;

  @override
  State<ActivityWidget> createState() => _ActivityWidgetState();
}

class _ActivityWidgetState extends State<ActivityWidget> {
  DeviceStatsController? _controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final c = widget.stats != null ? null : Provider.of<DeviceStatsController?>(context, listen: false);
    if (c == _controller) return;
    _controller?.detach();
    _controller = c?..attach();
  }

  @override
  void dispose() {
    _controller?.detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.stats != null ? null : context.watch<DeviceStatsController?>();
    final stats = widget.stats ?? controller?.stats;
    final apps = context.watch<AppsController?>();
    final glass = widget.surface == ActivitySurface.glass;
    final scheme = glass
        ? (PanelInk.lightOf(context) ? _lightPanelScheme(widget.seed, PanelInk.of(context)) : _glassScheme(widget.seed))
        : ColorScheme.fromSeed(
            seedColor: widget.seed,
            brightness: widget.surface == ActivitySurface.light ? Brightness.light : Brightness.dark,
          );
    final theme = Theme.of(context).copyWith(colorScheme: scheme);

    final byPackage = <String, AppInfo>{};
    for (final a in apps?.apps ?? const <AppInfo>[]) {
      byPackage.putIfAbsent(a.packageName, () => a);
    }
    final top = <(AppInfo, Duration)>[
      for (final u in stats?.topApps ?? const <AppUsage>[])
        if (byPackage[u.package] case final app?) (app, u.time),
    ].take(3).toList();

    final data = _Data(
      screenTime: stats?.screenOn,
      unlocks: stats?.unlocks,
      usageAccess: stats == null || stats.usageAccess,
      top: top,
      onAllow: controller?.openUsageAccess,
      onOpen: apps == null
          ? null
          : (app) {
              HapticFeedback.selectionClick();
              apps.launch(app);
            },
    );

    return Theme(
      data: theme,
      child: LayoutBuilder(
        builder: (context, box) {
          final w = box.maxWidth, h = box.maxHeight;
          final strip = h < 84;
          final radius = strip ? h / 2 : (h * 0.16).clamp(18.0, 28.0);
          final pad = strip ? 6.0 : (h * 0.06).clamp(8.0, 12.0);
          final Widget body;
          if (strip) {
            body = _Strip(data: data);
          } else if (w < 250) {
            body = _Square(data: data);
          } else {
            body = _Wide(data: data);
          }
          // The launcher draws the panel; the tiles sit straight on it.
          if (glass) return body;
          return DecoratedBox(
            decoration: ShapeDecoration(
              color: scheme.surfaceContainer,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
              shadows: const [BoxShadow(color: Color(0x33000000), blurRadius: 12, offset: Offset(0, 4))],
            ),
            child: Padding(padding: EdgeInsets.all(pad), child: body),
          );
        },
      ),
    );
  }
}

/// Material colours for tiles on wallpaper glass: the seed's dark tones,
/// see-through, with white type, so the wallpaper shows through as on the
/// launcher's other glass widgets.
ColorScheme _glassScheme(Color seed) {
  final s = ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark);
  return s.copyWith(
    primaryContainer: s.primaryContainer.withValues(alpha: 0.55),
    onPrimaryContainer: Colors.white,
    tertiaryContainer: s.tertiaryContainer.withValues(alpha: 0.5),
    onTertiaryContainer: Colors.white,
    surfaceContainerHighest: Colors.black.withValues(alpha: 0.16),
    onSurface: Colors.white,
    onSurfaceVariant: Colors.white.withValues(alpha: 0.72),
    primary: s.primary,
  );
}

/// [_glassScheme] for a light panel (GroupStyle.materialLight): the seed's
/// light tones, with [ink] type and faint dark tracks.
ColorScheme _lightPanelScheme(Color seed, Color ink) {
  final s = ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.light);
  return s.copyWith(
    surfaceContainerHighest: Colors.black.withValues(alpha: 0.06),
    onSurface: ink,
    onSurfaceVariant: ink.withValues(alpha: 0.68),
  );
}

/// What every layout draws from.
class _Data {
  const _Data({
    required this.screenTime,
    required this.unlocks,
    required this.usageAccess,
    required this.top,
    required this.onAllow,
    required this.onOpen,
  });

  final Duration? screenTime;
  final int? unlocks;
  final bool usageAccess;
  final List<(AppInfo, Duration)> top;
  final Future<void> Function()? onAllow;
  final void Function(AppInfo app)? onOpen;

  String get screenTimeText => usageAccess ? formatDuration(screenTime) : '—';
  String get unlocksText => usageAccess ? (unlocks?.toString() ?? '—') : '—';
}

/// "3d 4h", "5h 12m", "42m"; "—" when unknown.
String formatDuration(Duration? d) {
  if (d == null) return '—';
  if (d.inDays > 0) return '${d.inDays}d ${d.inHours % 24}h';
  final h = d.inHours, m = d.inMinutes % 60;
  return h == 0 ? '${m}m' : '${h}h ${m}m';
}

/// "1h 12m", "45m".
String _usageText(Duration d) {
  final h = d.inHours, m = d.inMinutes % 60;
  return h == 0 ? '${m}m' : '${h}h ${m}m';
}

const _gap = 8.0;

// ---- Layouts ---------------------------------------------------------------

/// 4 × 2 / 6 × 2: the stats stacked on the left, the apps on the right.
class _Wide extends StatelessWidget {
  const _Wide({required this.data});

  final _Data data;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 2,
          child: Column(
            children: [
              Expanded(
                child: _StatTile(
                  icon: Icons.phone_android_rounded,
                  value: data.screenTimeText,
                  label: 'Screen time',
                  fill: scheme.primaryContainer,
                  ink: scheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(height: _gap),
              Expanded(
                child: _StatTile(
                  icon: Icons.lock_open_rounded,
                  value: data.unlocksText,
                  label: 'Unlocks today',
                  fill: scheme.tertiaryContainer,
                  ink: scheme.onTertiaryContainer,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: _gap),
        Expanded(flex: 3, child: _AppList(data: data)),
      ],
    );
  }
}

/// 2 × 2: screen time and unlocks as full-width rows (a two-across split
/// leaves ~55dp each, too narrow for "13h 17m"), the top apps' icons and
/// times below.
class _Square extends StatelessWidget {
  const _Square({required this.data});

  final _Data data;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 3,
          child: _Row(
            icon: Icons.phone_android_rounded,
            value: data.screenTimeText,
            label: 'Screen',
            fill: scheme.primaryContainer,
            ink: scheme.onPrimaryContainer,
          ),
        ),
        const SizedBox(height: 6),
        Expanded(
          flex: 3,
          child: _Row(
            icon: Icons.lock_open_rounded,
            value: data.unlocksText,
            label: 'Unlocks',
            fill: scheme.tertiaryContainer,
            ink: scheme.onTertiaryContainer,
          ),
        ),
        const SizedBox(height: 6),
        Expanded(
          flex: 4,
          child: !data.usageAccess
              ? _AllowButton(onAllow: data.onAllow)
              : data.top.isEmpty
              ? const _Empty()
              : Row(
                  children: [
                    for (final (i, (app, time)) in data.top.indexed) ...[
                      if (i > 0) const SizedBox(width: 6),
                      Expanded(
                        child: _AppChip(app: app, time: time, onOpen: data.onOpen),
                      ),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}

/// A stat as one full-width tonal row: icon, value, and its label at the end.
class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.value, required this.label, required this.fill, required this.ink});

  final IconData icon;
  final String value;
  final String label;
  final Color fill;
  final Color ink;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Semantics(
      label: '$label: $value',
      child: LayoutBuilder(
        builder: (context, box) {
          final h = box.maxHeight;
          final iconSize = (h * 0.5).clamp(14.0, 20.0);
          return DecoratedBox(
            decoration: ShapeDecoration(
              color: fill,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular((h * 0.36).clamp(8.0, 16.0))),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                children: [
                  Icon(icon, size: iconSize, color: ink),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        value,
                        maxLines: 1,
                        style: text.titleMedium?.copyWith(
                          color: ink,
                          fontWeight: FontWeight.w600,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(label, maxLines: 1, style: text.labelSmall?.copyWith(color: ink.withValues(alpha: 0.75))),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// 4 × 1 / 6 × 1: screen time, unlocks and as many apps as fit, in one line.
class _Strip extends StatelessWidget {
  const _Strip({required this.data});

  final _Data data;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, box) {
        // Two stat pills take ~45%; apps share the rest at ≥ 64dp each.
        final appRoom = ((box.maxWidth * 0.52) / 72).floor().clamp(0, 3);
        final apps = data.usageAccess ? data.top.take(appRoom).toList() : const <(AppInfo, Duration)>[];
        return Row(
          children: [
            Expanded(
              flex: 5,
              child: _Pill(
                icon: Icons.phone_android_rounded,
                value: data.screenTimeText,
                fill: scheme.primaryContainer,
                ink: scheme.onPrimaryContainer,
                label: 'Screen time',
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              flex: 4,
              child: _Pill(
                icon: Icons.lock_open_rounded,
                value: data.unlocksText,
                fill: scheme.tertiaryContainer,
                ink: scheme.onTertiaryContainer,
                label: 'Unlocks today',
              ),
            ),
            for (final (app, time) in apps) ...[
              const SizedBox(width: 6),
              Expanded(
                flex: 4,
                child: _Tappable(
                  onTap: data.onOpen == null ? null : () => data.onOpen!(app),
                  label: '${app.label}: ${_usageText(time)}',
                  radius: 100,
                  child: Ink(
                    decoration: ShapeDecoration(color: scheme.surfaceContainerHighest, shape: const StadiumBorder()),
                    child: Center(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              AppIcon(app: app, size: 22),
                              const SizedBox(width: 5),
                              Text(
                                _usageText(time),
                                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                  color: scheme.onSurface,
                                  fontFeatures: const [FontFeature.tabularFigures()],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

// ---- Parts -----------------------------------------------------------------

/// A tonal tile: an icon in a circle, the value large, its label small.
class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.value,
    required this.label,
    required this.fill,
    required this.ink,
  });

  final IconData icon;
  final String value;
  final String label;
  final Color fill;
  final Color ink;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Semantics(
      label: '$label: $value',
      child: LayoutBuilder(
        builder: (context, box) {
          final h = box.maxHeight;
          final pad = (h * 0.14).clamp(6.0, 12.0);
          final disc = (h * 0.38).clamp(20.0, 30.0);
          final valueStyle = text.titleLarge?.copyWith(
            color: ink,
            fontWeight: FontWeight.w600,
            height: 1.1,
            fontFeatures: const [FontFeature.tabularFigures()],
          );
          final labelStyle = text.labelSmall?.copyWith(color: ink.withValues(alpha: 0.78), height: 1.2);
          final words = Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(value, maxLines: 1, style: valueStyle),
              ),
              Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: labelStyle),
            ],
          );
          final iconDisc = Container(
            width: disc,
            height: disc,
            decoration: BoxDecoration(color: ink.withValues(alpha: 0.12), shape: BoxShape.circle),
            child: Icon(icon, size: disc * 0.58, color: ink),
          );
          return DecoratedBox(
            decoration: ShapeDecoration(
              color: fill,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular((h * 0.3).clamp(12.0, 20.0))),
            ),
            child: Padding(
              padding: EdgeInsets.all(pad),
              child: Row(
                children: [
                  iconDisc,
                  SizedBox(width: pad),
                  Expanded(child: words),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// A stat as a stadium: icon and value.
class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.value, required this.fill, required this.ink, required this.label});

  final IconData icon;
  final String value;
  final Color fill;
  final Color ink;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$label: $value',
      child: DecoratedBox(
        decoration: ShapeDecoration(color: fill, shape: const StadiumBorder()),
        child: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 18, color: ink),
                  const SizedBox(width: 6),
                  Text(
                    value,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: ink,
                      fontWeight: FontWeight.w600,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "Most used today": up to three rows of icon, name, time and a bar
/// relative to the most used.
class _AppList extends StatelessWidget {
  const _AppList({required this.data});

  final _Data data;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final Widget body;
    if (!data.usageAccess) {
      body = _AllowButton(onAllow: data.onAllow);
    } else if (data.top.isEmpty) {
      body = const _Empty();
    } else {
      final most = data.top.first.$2.inSeconds.clamp(1, 1 << 30);
      body = Column(
        children: [
          for (final (i, (app, time)) in data.top.indexed) ...[
            if (i > 0) const SizedBox(height: 2),
            Expanded(
              child: _AppRow(app: app, time: time, share: time.inSeconds / most, onOpen: data.onOpen),
            ),
          ],
          for (var i = data.top.length; i < 3; i++) const Spacer(),
        ],
      );
    }
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: scheme.surfaceContainerHighest,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'MOST USED TODAY',
              style: text.labelSmall?.copyWith(color: scheme.primary, letterSpacing: 1.1, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }
}

class _AppRow extends StatelessWidget {
  const _AppRow({required this.app, required this.time, required this.share, required this.onOpen});

  final AppInfo app;
  final Duration time;

  /// Its time over the most used app's, 0–1.
  final double share;
  final void Function(AppInfo app)? onOpen;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return _Tappable(
      onTap: onOpen == null ? null : () => onOpen!(app),
      label: '${app.label}: ${_usageText(time)}',
      radius: 10,
      child: LayoutBuilder(
        builder: (context, box) {
          final icon = (box.maxHeight * 0.72).clamp(16.0, 26.0);
          return Row(
            children: [
              AppIcon(app: app, size: icon),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            app.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: text.labelMedium?.copyWith(color: scheme.onSurface, height: 1.1),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _usageText(time),
                          style: text.labelMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                            height: 1.1,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                    if (box.maxHeight >= 26) ...[
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: share.clamp(0.04, 1.0),
                          minHeight: 4,
                          color: scheme.primary,
                          backgroundColor: scheme.primary.withValues(alpha: 0.16),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// 2 × 2's apps: an icon over its time, on a tonal chip.
class _AppChip extends StatelessWidget {
  const _AppChip({required this.app, required this.time, required this.onOpen});

  final AppInfo app;
  final Duration time;
  final void Function(AppInfo app)? onOpen;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _Tappable(
      onTap: onOpen == null ? null : () => onOpen!(app),
      label: '${app.label}: ${_usageText(time)}',
      radius: 14,
      child: Ink(
        decoration: ShapeDecoration(
          color: scheme.surfaceContainerHighest,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        child: LayoutBuilder(
          builder: (context, box) => Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AppIcon(app: app, size: (box.maxHeight * 0.5).clamp(14.0, 26.0).clamp(14.0, box.maxWidth * 0.6)),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  _usageText(time),
                  style: Theme.of(context).textTheme.labelSmall
                      ?.copyWith(color: scheme.onSurfaceVariant, fontFeatures: const [FontFeature.tabularFigures()]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AllowButton extends StatelessWidget {
  const _AllowButton({required this.onAllow});

  final Future<void> Function()? onAllow;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: FilledButton.tonalIcon(
          onPressed: onAllow == null
              ? null
              : () {
                  HapticFeedback.selectionClick();
                  onAllow!();
                },
          icon: const Icon(Icons.query_stats_rounded, size: 18),
          label: const Text('Allow usage access'),
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Text(
        'No apps used yet today',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
      ),
    );
  }
}

/// A Material ink ripple, when it does anything.
class _Tappable extends StatelessWidget {
  const _Tappable({required this.onTap, required this.label, required this.radius, required this.child});

  final VoidCallback? onTap;
  final String label;
  final double radius;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      button: onTap != null,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(radius), child: child),
      ),
    );
  }
}

// ---- Options ---------------------------------------------------------------

/// The widget's options: its colour, its surface (dark, light, or the
/// launcher's panel, and then which panel) and Usage access.
Future<void> showActivitySettings(BuildContext context, WidgetItem item) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  barrierColor: Colors.black26,
  builder: (_) => _ActivitySettingsSheet(id: item.id),
);

class _ActivitySettingsSheet extends StatelessWidget {
  const _ActivitySettingsSheet({required this.id});

  final String id;

  @override
  Widget build(BuildContext context) {
    final layout = context.watch<HomeLayoutController>();
    final item = layout.findWidget(id);
    if (item == null) return const SizedBox.shrink();
    final controller = context.watch<DeviceStatsController?>();
    final stats = controller?.stats;
    final theme = Theme.of(context);
    final seed = item.settings['seed'] as String? ?? 'teal';
    final surface = _surfaceOf(item.settings);
    final panel = _panelStyleOf(item.settings);
    void set(String key, Object value) => layout.updateWidgetSettings(id, {...item.settings, key: value});
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Activity', style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              'Screen time, unlocks and most used apps start again at midnight.',
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70),
            ),
            const SizedBox(height: 20),
            Text('Colour', style: theme.textTheme.titleSmall),
            const SizedBox(height: 10),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final MapEntry(key: name, value: color) in _seeds.entries)
                  _Swatch(
                    color: ColorScheme.fromSeed(seedColor: color, brightness: Brightness.dark).primary,
                    selected: name == seed,
                    onTap: () => set('seed', name),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text('Surface', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            SegmentedButton<ActivitySurface>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: ActivitySurface.dark, icon: Icon(Icons.dark_mode_outlined), label: Text('Dark')),
                ButtonSegment(
                  value: ActivitySurface.light,
                  icon: Icon(Icons.light_mode_outlined),
                  label: Text('Light'),
                ),
                ButtonSegment(value: ActivitySurface.glass, icon: Icon(Icons.blur_on), label: Text('Panel')),
              ],
              selected: {surface},
              onSelectionChanged: (v) {
                // Glass needs the wallpaper image.
                if (v.first == ActivitySurface.glass && panel == GroupStyle.glass) {
                  context.read<WindowBlurPlatform?>()?.requestWallpaperAccess();
                }
                set('surface', v.first.name);
              },
            ),
            // On the launcher's panel: which one.
            if (surface == ActivitySurface.glass) ...[
              const SizedBox(height: 16),
              Text('Panel background', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              PanelStylePicker(value: panel, onChanged: (s) => set('style', (s ?? GroupStyle.glass).name)),
            ],
            const SizedBox(height: 16),
            Text('Access', style: theme.textTheme.titleSmall),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Usage access'),
              subtitle: const Text('For unlocks and most used apps'),
              trailing: stats?.usageAccess ?? false
                  ? const Icon(Icons.check_rounded)
                  : TextButton(onPressed: controller?.openUsageAccess, child: const Text('Allow')),
            ),
          ],
        ),
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.color, required this.selected, required this.onTap});

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: selected ? Colors.white : Colors.transparent, width: 2.5),
        ),
        child: selected ? const Icon(Icons.check_rounded, size: 20, color: Colors.black87) : null,
      ),
    );
  }
}
