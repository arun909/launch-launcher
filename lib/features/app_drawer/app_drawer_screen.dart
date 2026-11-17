import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/apps/app_search.dart';
import '../../core/apps/apps_controller.dart';
import '../../core/models/app_info.dart';
import '../../core/theme/spacing.dart';
import '../../core/widgets/home_grid_delegate.dart';
import '../../core/widgets/app_icon.dart';
import '../app_actions/app_actions_sheet.dart';
import '../appearance/wallpaper_blur.dart';
import 'search_bar_metrics.dart';
import '../hidden_apps/visible_apps.dart';
import '../standard_home/home_layout_controller.dart';

/// All visible apps in a grid, with search-as-you-type.
///
/// Reads only [VisibleApps], so hidden apps never appear here or in search.
class AppDrawerScreen extends StatefulWidget {
  const AppDrawerScreen({super.key});

  @override
  State<AppDrawerScreen> createState() => _AppDrawerScreenState();
}

class _AppDrawerScreenState extends State<AppDrawerScreen> {
  final _search = TextEditingController();
  String _query = '';

  bool get _searching => _query.trim().isNotEmpty;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// Launches [app] and closes the drawer behind it, so returning from the
  /// app lands on the home screen (as in most launchers).
  Future<void> _launch(AppInfo app) async {
    final launched = await openApp(context, app);
    if (launched && mounted) Navigator.of(context).maybePop();
  }

  /// Height of the bottom search area (padding + bar), excluding the system
  /// inset below it.
  static const _searchAreaHeight = 8 + searchBarHeight + searchBarLift;

  @override
  Widget build(BuildContext context) {
    final isLoaded = context.select<AppsController, bool>((c) => c.isLoaded);
    final apps = filterApps(context.watch<VisibleApps>().apps, _query);
    final insets = MediaQuery.paddingOf(context);
    final searchArea = _searchAreaHeight + insets.bottom;

    // The grid runs full-height and fades out into the status bar and the
    // search bar, instead of being cut off at a hard edge.
    return WallpaperBlur(
      child: Scaffold(
        backgroundColor: WallpaperBlur.tint(context, unblurred: 0.82, blurred: 0.45),
        body: Stack(
          children: [
            Positioned.fill(
              child: _buildGrid(isLoaded, apps, top: insets.top, bottom: searchArea),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              // Search bar at the bottom, in thumb reach and next to the keyboard.
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, searchBarLift),
                  child: SearchBar(
                    controller: _search,
                    constraints: const BoxConstraints(minHeight: searchBarHeight),
                    textStyle: const WidgetStatePropertyAll(TextStyle(fontSize: 17)),
                    hintText: 'Search apps',
                    leading: const Icon(Icons.search),
                    trailing: [
                      if (_query.isNotEmpty)
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => setState(() {
                            _search.clear();
                            _query = '';
                          }),
                        ),
                    ],
                    onChanged: (q) => setState(() => _query = q),
                    // Enter launches the top result, launcher-style.
                    onSubmitted: (_) {
                      if (apps.isNotEmpty) _launch(apps.first);
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// [top] and [bottom] are the heights of the status bar and search area the
  /// grid scrolls behind.
  Widget _buildGrid(bool isLoaded, List<AppInfo> apps, {required double top, required double bottom}) {
    if (!isLoaded) return const Center(child: CircularProgressIndicator());
    if (apps.isEmpty) {
      return Padding(
        padding: EdgeInsets.only(top: top, bottom: bottom),
        child: Center(
          child: Text(
            _query.isEmpty ? 'No apps' : 'No apps match "$_query"',
            style: const TextStyle(color: Colors.white70),
          ),
        ),
      );
    }
    // While searching, fill from the bottom so the best match sits right above
    // the search bar; browsing keeps the normal top-down alphabetical grid.
    final searching = _searching;
    final spec = context.watch<HomeLayoutController>().grid;
    // Pull down at the top of the list to close the drawer (browsing only:
    // reversed, that overscroll would be a swipe up from the bottom).
    return NotificationListener<OverscrollNotification>(
      onNotification: (n) {
        if (!searching && n.overscroll < -12 && n.metrics.pixels <= 0 && n.dragDetails != null) {
          Navigator.maybePop(context);
          return true;
        }
        return false;
      },
      child: _EdgeFade(
        top: top,
        bottom: bottom,
        child: GridView.builder(
          reverse: searching,
          // Clear of the fade at rest (tiles add 8px of their own padding).
          // Sides and gaps: the standard margin and gutter, minus the 4px
          // each tile already pads itself with.
          // Sides like the home grid's, so apps sit the same distance from
          // the edges and from each other (HomeGridDelegate).
          padding: EdgeInsets.fromLTRB(
            Spacing.screenMargin - Spacing.halfGutter,
            top + _EdgeFade.length - 8,
            Spacing.screenMargin - Spacing.halfGutter,
            bottom + _EdgeFade.length - 8,
          ),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          physics: const ClampingScrollPhysics(),
          // Same apps per row, icon size and spacing as the home screen.
          gridDelegate: HomeGridDelegate(spec),
          itemCount: apps.length,
          itemBuilder: (context, i) {
            final app = apps[i];
            return AppTile(
              key: ValueKey(app.id),
              app: app,
              iconSize: spec.iconSize,
              labelSize: spec.labelSize,
              onTap: () => _launch(app),
              onLongPress: () => showAppActions(context, app),
            );
          },
        ),
      ),
    );
  }
}

/// Fades [child] to fully transparent over [length] pixels as it reaches the
/// [top] and [bottom] bars, and hides it behind them. Fully transparent means
/// there's no edge left to see, unlike a tinted or blurred bar.
class _EdgeFade extends StatelessWidget {
  const _EdgeFade({required this.top, required this.bottom, required this.child});

  final double top;
  final double bottom;
  final Widget child;

  static const length = 28.0;

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (bounds) {
        final h = bounds.height;
        return LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: const [
            Colors.transparent,
            Colors.transparent,
            Colors.white,
            Colors.white,
            Colors.transparent,
            Colors.transparent,
          ],
          stops: [
            0,
            (top / h).clamp(0.0, 0.5),
            ((top + length) / h).clamp(0.0, 0.5),
            ((h - bottom - length) / h).clamp(0.5, 1.0),
            ((h - bottom) / h).clamp(0.5, 1.0),
            1,
          ],
        ).createShader(bounds);
      },
      child: child,
    );
  }
}
