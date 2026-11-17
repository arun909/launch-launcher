import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/platform/launcher_platform.dart';
import '../../core/routing/app_routes.dart';
import '../../core/theme/home_grid.dart';
import '../dock/dock.dart';
import '../standard_home/home_layout_controller.dart';
import '../standard_home/standard_home.dart';

/// Long-press menu for empty home-screen space: the dock turns into a dock of
/// action buttons (see [hiddenWhenOpen]). Home stays as it is, so changes
/// made from here (tidy up) show as they happen, but takes no touches while
/// it's open: tapping it, or Back, closes the menu.
///
/// Wallpapers only opens the phone's own wallpaper settings; the launcher
/// never changes the wallpaper itself.
class HomeOverview extends StatefulWidget {
  const HomeOverview({super.key, required this.child});

  /// The home screen's content.
  final Widget child;

  static HomeOverviewState of(BuildContext context) => context.findAncestorStateOfType<HomeOverviewState>()!;

  /// Fades [child] (home's own dock) out while the overview is open: the
  /// overview's dock of actions takes its place.
  static Widget hiddenWhenOpen(Widget child) => _HiddenWhenOpen(child: child);

  @override
  State<HomeOverview> createState() => HomeOverviewState();
}

class HomeOverviewState extends State<HomeOverview> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  /// Home's dock is this far above the bottom of the safe area (see
  /// HomeScreen).
  static const _dockBottom = 12.0;

  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
    reverseDuration: const Duration(milliseconds: 280),
  );

  late final _progress = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutQuart,
    reverseCurve: Curves.easeInCubic,
  );

  /// The layout before the last tidy up, while it can still be undone.
  HomeLayoutSnapshot? _beforeTidyUp;

  bool get isOpen => _controller.status == AnimationStatus.forward || _controller.status == AnimationStatus.completed;

  void open() {
    if (isOpen) return;
    HapticFeedback.mediumImpact();
    setState(() => _beforeTidyUp = null);
    _controller.forward();
  }

  void close() {
    if (!isOpen) return;
    _controller.reverse();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _progress.dispose();
    _controller.dispose();
    super.dispose();
  }

  /// Leaving the launcher (the Home key, an app opened) closes it at once,
  /// so home is back to normal on return.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.hidden || state == AppLifecycleState.paused) _controller.value = 0;
  }

  /// Closes the overview and runs [action] alongside.
  void _closeThen(VoidCallback action) {
    close();
    action();
  }

  void _toggleTidyUp() {
    HapticFeedback.selectionClick();
    final layout = context.read<HomeLayoutController>();
    final before = _beforeTidyUp;
    setState(() => _beforeTidyUp = before == null ? layout.tidyUp() : null);
    if (before != null) layout.restore(before);
  }

  List<_OverviewAction> _actions() {
    final layout = context.read<HomeLayoutController>();
    final platform = context.read<LauncherPlatform>();
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final standard = layout.mode == HomeMode.standard;
    return [
      if (standard)
        _OverviewAction(Icons.edit_outlined, 'Edit home screen', () => _closeThen(() => layout.setEditing(true))),
      if (standard)
        _beforeTidyUp == null
            ? _OverviewAction(Icons.auto_awesome_mosaic_outlined, 'Tidy up', _toggleTidyUp)
            : _OverviewAction(Icons.undo_rounded, 'Undo tidy up', _toggleTidyUp, highlighted: true),
      _OverviewAction(
        Icons.widgets_outlined,
        'Widgets',
        () => _closeThen(() => navigator.pushNamed(AppRoutes.widgets)),
      ),
      _OverviewAction(
        Icons.wallpaper_outlined,
        'Wallpapers',
        () => _closeThen(() async {
          if (!await platform.openSystemWallpapers()) {
            messenger?.showSnackBar(const SnackBar(content: Text('No wallpaper settings found on this phone')));
          }
        }),
      ),
      _OverviewAction(
        Icons.settings_outlined,
        'Launcher settings',
        () => _closeThen(() => navigator.pushNamed(AppRoutes.settings)),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final grid = context.select<HomeLayoutController, HomeGrid>((l) => l.grid);
    final padding = MediaQuery.paddingOf(context);
    final screen = MediaQuery.sizeOf(context);
    final actions = _actions();

    // The dock of actions: just where home's dock is, and as big.
    final dockHeight = grid.iconSize + 2 * Dock.verticalPadding;
    final dockSide = StandardHome.sidePaddingFor(grid, screen.width);

    return PopScope(
      canPop: !isOpen,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) close();
      },
      child: AnimatedBuilder(
        animation: _controller,
        child: widget.child,
        builder: (context, home) {
          final t = _progress.value;
          final shown = _controller.status != AnimationStatus.dismissed;

          // Every layer is always there (empty while closed), so the home
          // screen keeps its place in the tree, and its state.
          return _OverviewScope(
            open: shown,
            child: Stack(
              fit: StackFit.expand,
              children: [
                IgnorePointer(ignoring: shown, child: home),
                // Tap anywhere else to close.
                shown ? GestureDetector(behavior: HitTestBehavior.opaque, onTap: close) : const SizedBox.shrink(),
                Positioned(
                  left: dockSide,
                  right: dockSide,
                  bottom: padding.bottom + _dockBottom,
                  height: dockHeight,
                  child: shown
                      ? Opacity(
                          opacity: Curves.easeOut.transform(_controller.value),
                          child: Transform.translate(
                            offset: Offset(0, 32 * (1 - t)),
                            child: _ActionsDock(
                              actions: actions,
                              progress: _controller.value,
                              iconSize: grid.iconSize,
                              enabled: isOpen,
                            ),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _OverviewScope extends InheritedWidget {
  const _OverviewScope({required this.open, required super.child});

  final bool open;

  @override
  bool updateShouldNotify(_OverviewScope oldWidget) => open != oldWidget.open;
}

class _HiddenWhenOpen extends StatelessWidget {
  const _HiddenWhenOpen({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final open = context.dependOnInheritedWidgetOfExactType<_OverviewScope>()?.open ?? false;
    return AnimatedOpacity(opacity: open ? 0 : 1, duration: const Duration(milliseconds: 200), child: child);
  }
}

/// The actions in a frosted bar like home's dock (see Dock), each in place of
/// an app icon, popping in one after another.
class _ActionsDock extends StatelessWidget {
  const _ActionsDock({required this.actions, required this.progress, required this.iconSize, required this.enabled});

  final List<_OverviewAction> actions;
  final double progress;
  final double iconSize;
  final bool enabled;

  static const _radius = BorderRadius.all(Radius.circular(28));

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: _radius,
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.16), borderRadius: _radius),
          foregroundDecoration: BoxDecoration(
            borderRadius: _radius,
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              for (final (i, action) in actions.indexed)
                _PopIn(
                  // Staggered left to right.
                  progress: progress,
                  start: 0.1 + 0.08 * i,
                  child: _DockButton(action: action, size: iconSize, enabled: enabled),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OverviewAction {
  const _OverviewAction(this.icon, this.label, this.onTap, {this.highlighted = false});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  /// Shown brighter: an action just taken can be undone.
  final bool highlighted;
}

/// Pops [child] up into place, scaling past full size a little before
/// settling, as [progress] goes from [start] to [start] + 0.5.
class _PopIn extends StatelessWidget {
  const _PopIn({required this.progress, required this.start, required this.child});

  final double progress;
  final double start;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = Interval(start, math.min(start + 0.5, 1)).transform(progress);
    final pop = Curves.easeOutBack.transform(t);
    return Opacity(
      opacity: Curves.easeOut.transform(t),
      child: Transform.translate(
        offset: Offset(0, 24 * (1 - pop)),
        child: Transform.scale(scale: 0.6 + 0.4 * pop, child: child),
      ),
    );
  }
}

/// An action in the dock: a round button the size of an app icon, showing
/// only its icon; its label is the tooltip (long-press) and what screen
/// readers say.
class _DockButton extends StatelessWidget {
  const _DockButton({required this.action, required this.size, required this.enabled});

  final _OverviewAction action;
  final double size;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final highlighted = action.highlighted;
    return Tooltip(
      message: action.label,
      preferBelow: false,
      child: SizedBox.square(
        dimension: size,
        child: Material(
          type: MaterialType.transparency,
          child: Ink(
            decoration: ShapeDecoration(
              shape: CircleBorder(
                side: BorderSide(color: Colors.white.withValues(alpha: highlighted ? 0.6 : 0.18)),
              ),
              color: Colors.white.withValues(alpha: highlighted ? 0.3 : 0.12),
            ),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: enabled ? action.onTap : null,
              child: Center(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  transitionBuilder: (child, animation) => RotationTransition(
                    turns: Tween(begin: -0.25, end: 0.0).animate(animation),
                    child: FadeTransition(opacity: animation, child: child),
                  ),
                  child: Icon(action.icon, key: ValueKey(action.icon), color: Colors.white, size: size * 0.46),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
