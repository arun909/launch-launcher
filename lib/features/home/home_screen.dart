import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/apps/home_role_controller.dart';
import '../../core/models/app_info.dart';
import '../../core/platform/launcher_platform.dart';
import '../../core/routing/app_routes.dart';
import '../../core/theme/spacing.dart';
import '../../core/widgets/app_icon.dart';
import '../../core/widgets/home_grid_delegate.dart';
import '../app_actions/app_actions_sheet.dart';
import '../dock/dock.dart';
import '../hidden_apps/visible_apps.dart';
import '../search_widget/search_widget.dart';
import '../search_widget/search_widget_controller.dart';
import '../standard_home/home_layout_controller.dart';
import '../standard_home/home_layout.dart';
import '../standard_home/standard_home.dart';
import '../widgets/home_widget_view.dart';
import '../widgets/widget_actions_sheet.dart';
import 'home_apps_controller.dart';
import 'home_overview.dart';

/// The home screen, over the wallpaper. In drawer mode: widgets, pinned apps,
/// the search widget and the dock. In standard mode: every app on swipeable pages (see
/// [StandardHome]) above the search widget and the dock.
///
/// Swipe up to open the drawer (drawer mode only: standard mode has no
/// drawer, and swiping up there does nothing); tap the search widget for
/// quick search. Swipe down on the right for the phone's control center
/// (quick settings); on the left for notifications -- in drawer mode only
/// from the upper half, as a swipe down on the lower left opens quick
/// search there. Long-press empty space for the overview (see [HomeOverview]):
/// settings, wallpaper, tidy up.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  void _openDrawer(BuildContext context, {bool focusSearch = false}) =>
      Navigator.pushNamed(context, focusSearch ? AppRoutes.search : AppRoutes.drawer);

  @override
  Widget build(BuildContext context) {
    final visible = context.watch<VisibleApps>();
    final pinned = context
        .watch<HomeAppsController>()
        .ids
        .map(visible.byId) // hidden or uninstalled -> null -> dropped
        .whereType<AppInfo>()
        .toList();
    final layout = context.watch<HomeLayoutController>();
    final standard = layout.mode == HomeMode.standard;
    final sidePadding = StandardHome.sidePaddingFor(layout.grid, MediaQuery.sizeOf(context).width);

    // As the home screen, Back does nothing (except leave edit mode). Opened
    // as a normal app, it exits.
    final isDefaultHome = context.watch<HomeRoleController>().isDefaultHome;
    return PopScope(
      canPop: !isDefaultHome && !layout.editing,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) layout.setEditing(false);
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        // The keyboard (from quick search, drawn over home) must not shrink
        // home: fewer grid rows would push items aside and save that.
        resizeToAvoidBottomInset: false,
        // Fade home content out while anything (drawer, settings) is on top:
        // the drawer is see-through, and the wallpaper alone looks cleaner.
        // (isCurrent, not secondaryAnimation: Flutter only drives that between
        // matching route types, and the drawer uses a custom route.) Shown
        // while an app is dragged out of a folder, whose route stays on top,
        // hidden, until it's dropped (see showContainer).
        body: AnimatedOpacity(
          opacity: (ModalRoute.of(context)?.isCurrent ?? true) || layout.dragging ? 1 : 0,
          duration: const Duration(milliseconds: 160),
          child: HomeOverview(
            child: _HomeGestures(
              enabled: !layout.editing,
              standard: standard,
              onOpenDrawer: ({required focusSearch}) => _openDrawer(context, focusSearch: focusSearch),
              // Everything lines up at the screen margin. Grids carry half a
              // gutter around each item themselves, so they're inset by the
              // margin minus that. Standard-mode pages span the full width (and
              // inset their own grid) so page swipes and the drag-to-flip edges
              // reach the real screen edges.
              child: SafeArea(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (standard)
                      const Expanded(child: StandardHome())
                    else ...[
                      const Spacer(),
                      if (layout.widgets.isNotEmpty)
                        Flexible(
                          flex: 1000,
                          child: Padding(
                            padding: EdgeInsets.symmetric(horizontal: sidePadding),
                            child: const _HomeWidgets(),
                          ),
                        ),
                      if (pinned.isNotEmpty)
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: sidePadding),
                          child: _PinnedGrid(apps: pinned),
                        ),
                    ],
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: Spacing.screenMargin),
                      child: SearchWidget(onOpenSearch: () => _openDrawer(context, focusSearch: true)),
                    ),
                    // As wide as the app grid, so its icons line up with the
                    // grid's columns (see Dock).
                    Padding(
                      padding: EdgeInsets.fromLTRB(sidePadding, Spacing.gutter, sidePadding, 0),
                      child: HomeOverview.hiddenWhenOpen(const Dock()),
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Home-screen gestures on empty space (app icons handle their own taps):
/// - fling up (drawer mode only): open the drawer
/// - swipe down on the right half: the phone's control center (quick
///   settings)
/// - swipe down on the left half: notifications; in drawer mode, from the
///   lower half, quick search instead
/// - long-press: the overview, with wallpaper and settings
/// - tap: finish resizing the search widget, if it's being resized
///
/// Swipes down must also travel [_minDownDistance], so a small accidental drag
/// doesn't open anything.
class _HomeGestures extends StatefulWidget {
  const _HomeGestures({required this.enabled, required this.standard, required this.onOpenDrawer, required this.child});

  /// Off in edit mode, where drags move items.
  final bool enabled;

  /// Standard mode: swipes down anywhere open notifications / quick
  /// settings (no swipe-down quick search).
  final bool standard;
  final void Function({required bool focusSearch}) onOpenDrawer;
  final Widget child;

  @override
  State<_HomeGestures> createState() => _HomeGesturesState();
}

class _HomeGesturesState extends State<_HomeGestures> {
  static const _minFlingVelocity = 300.0;

  /// 1 cm: Flutter's logical pixels are 160 per inch.
  static const _minDownDistance = 160 / 2.54;

  /// Where the current vertical drag started, as a fraction of the screen size.
  Offset _dragStart = Offset.zero;

  /// How far the current drag has moved down, in logical pixels.
  double _dragDown = 0;

  @override
  Widget build(BuildContext context) {
    // In edit mode the swipes must not even be listened for: a listening
    // vertical-drag recognizer wins the gesture arena against the resize
    // handles' vertical drags, so height couldn't be changed.
    final enabled = widget.enabled;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onVerticalDragStart: enabled
          ? (details) {
              final size = MediaQuery.sizeOf(context);
              _dragStart = Offset(details.globalPosition.dx / size.width, details.globalPosition.dy / size.height);
              _dragDown = 0;
            }
          : null,
      onVerticalDragUpdate: enabled ? (details) => _dragDown += details.delta.dy : null,
      onVerticalDragEnd: enabled
          ? (details) {
              final velocity = details.primaryVelocity ?? 0;
              if (velocity < -_minFlingVelocity) {
                if (widget.standard) return; // no drawer, and no quick search, in standard mode
                widget.onOpenDrawer(focusSearch: false);
              } else if (velocity > _minFlingVelocity && _dragDown >= _minDownDistance) {
                if (_dragStart.dx >= 0.5) {
                  // The phone's own control center (quick settings).
                  context.read<LauncherPlatform>().expandQuickSettings();
                } else if (!widget.standard && _dragStart.dy >= 0.5) {
                  widget.onOpenDrawer(focusSearch: true);
                } else {
                  context.read<LauncherPlatform>().expandNotifications();
                }
              }
            }
          : null,
      // Only while resizing: otherwise taps must stay unclaimed, so they reach
      // app widgets (Android views only get the touches Flutter leaves).
      onTap: context.select<SearchWidgetController, bool>((c) => c.isResizing)
          ? () => context.read<SearchWidgetController>().stopResizing()
          : null,
      onLongPress: enabled
          ? () {
              HomeOverview.of(context).open();
            }
          : null,
      child: widget.child,
    );
  }
}

/// Drawer mode's widgets, above the pinned apps, each its size in cells of
/// the home grid, filling rows left to right. Long-press one for its menu.
class _HomeWidgets extends StatelessWidget {
  const _HomeWidgets();

  @override
  Widget build(BuildContext context) {
    final layout = context.watch<HomeLayoutController>();
    final spec = layout.grid;
    return LayoutBuilder(
      builder: (context, box) {
        final cellWidth = box.maxWidth / spec.columns;
        final cell = Size(cellWidth, spec.cellHeightFor(cellWidth));
        layout.cellSize = cell; // For sizing new widgets (not saved).
        // App widgets keep the room they need on these cells.
        WidgetsBinding.instance.addPostFrameCallback((_) => layout.fitWidgetsTo(cell));
        // Clipped, not scrolled: a scroll view would take the home swipes.
        return SingleChildScrollView(
          physics: const NeverScrollableScrollPhysics(),
          reverse: true,
          child: Wrap(
            children: [
              for (final w in layout.widgets)
                SizedBox(
                  key: ValueKey(w.key),
                  width: math.min(w.cols, spec.columns) * cell.width,
                  height: w.rows * cell.height,
                  child: _WidgetLongPress(
                    item: w,
                    child: HomeWidgetView(
                      item: w,
                      grid: spec,
                      cols: math.min(w.cols, spec.columns),
                      rows: w.rows,
                      iconShape: layout.iconShape,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _WidgetLongPress extends StatelessWidget {
  const _WidgetLongPress({required this.item, required this.child});

  final WidgetItem item;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPress: () {
        HapticFeedback.mediumImpact();
        showWidgetActions(context, item);
      },
      child: child,
    );
  }
}

class _PinnedGrid extends StatelessWidget {
  const _PinnedGrid({required this.apps});

  final List<AppInfo> apps;

  @override
  Widget build(BuildContext context) {
    final layout = context.watch<HomeLayoutController>();
    final spec = layout.grid;
    return GridView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: HomeGridDelegate(spec),
      children: [
        for (final app in apps)
          AppTile(
            app: app,
            iconSize: spec.iconSize,
            labelSize: spec.labelSize,
            showLabel: layout.showLabels,
            onTap: () => openApp(context, app),
            onLongPress: () => showAppActions(context, app),
          ),
      ],
    );
  }
}
