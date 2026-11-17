import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/apps/app_search.dart';
import '../../core/models/app_info.dart';
import '../../core/widgets/app_icon.dart';
import '../app_actions/app_actions_sheet.dart';
import '../appearance/wallpaper_blur.dart';
import 'search_bar_metrics.dart';
import '../hidden_apps/visible_apps.dart';

/// Search-only overlay: no app grid, just a search field at the bottom with
/// the best matches in a row right above it (and so right above the keyboard),
/// where the thumb already is.
///
/// Reads only [VisibleApps], so hidden apps never appear in results.
class QuickSearchScreen extends StatefulWidget {
  const QuickSearchScreen({super.key});

  /// How many matches the result row shows.
  static const maxResults = 5;

  @override
  State<QuickSearchScreen> createState() => _QuickSearchScreenState();
}

class _QuickSearchScreenState extends State<QuickSearchScreen> {
  final _search = TextEditingController();
  String _query = '';

  /// Tallest the keyboard has been, to notice it starting to hide.
  double _keyboardPeak = 0;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// Launches [app] and closes the search behind it, so returning from the
  /// app lands on the home screen.
  Future<void> _launch(AppInfo app) async {
    final launched = await openApp(context, app);
    // Hiding the keyboard may have closed us already; don't pop what's below.
    if (launched && mounted && (ModalRoute.of(context)?.isCurrent ?? false)) Navigator.of(context).maybePop();
  }

  /// Closes search when the keyboard goes away. Android spends the first Back
  /// press on hiding the keyboard (it never reaches us), and this screen is
  /// pointless without one, so that Back press closes it too.
  ///
  /// Closes as soon as the keyboard *starts* hiding (not once it's gone), so
  /// the screen fades out together with the keyboard in one motion. Small
  /// shrinks (e.g. switching keyboard layouts) don't count.
  void _closeWhenKeyboardHides(BuildContext context) {
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    if (inset > _keyboardPeak) _keyboardPeak = inset;
    if (_keyboardPeak > 0 && inset < _keyboardPeak * 0.75) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // Not if we're already closing (e.g. an app was just launched).
        if (mounted && (ModalRoute.of(context)?.isCurrent ?? false)) Navigator.maybePop(context);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    _closeWhenKeyboardHides(context);
    final matches = _query.trim().isEmpty
        ? const <AppInfo>[]
        : filterApps(context.watch<VisibleApps>().apps, _query).take(QuickSearchScreen.maxResults).toList();

    return WallpaperBlur(
      child: Scaffold(
        backgroundColor: WallpaperBlur.tint(context, unblurred: 0.6, blurred: 0.35),
        body: SafeArea(
          child: Column(
            children: [
              // Empty space above: tap or swipe down to close.
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => Navigator.maybePop(context),
                  onVerticalDragEnd: (d) {
                    if ((d.primaryVelocity ?? 0) > 300) Navigator.maybePop(context);
                  },
                ),
              ),
              _ResultRow(query: _query, matches: matches, onLaunch: _launch),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, searchBarLift),
                child: SearchBar(
                  controller: _search,
                  constraints: const BoxConstraints(minHeight: searchBarHeight),
                  textStyle: const WidgetStatePropertyAll(TextStyle(fontSize: 17)),
                  autoFocus: true,
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
                    if (matches.isNotEmpty) _launch(matches.first);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The matches, side by side in fixed slots. The top match (what Enter opens)
/// is highlighted and always sits in the first slot.
class _ResultRow extends StatelessWidget {
  const _ResultRow({required this.query, required this.matches, required this.onLaunch});

  final String query;
  final List<AppInfo> matches;
  final void Function(AppInfo) onLaunch;

  @override
  Widget build(BuildContext context) {
    if (query.trim().isEmpty) return const SizedBox.shrink();
    if (matches.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text('No apps match "$query"', style: const TextStyle(color: Colors.white70)),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          for (var i = 0; i < QuickSearchScreen.maxResults; i++)
            Expanded(
              child: i < matches.length
                  ? DecoratedBox(
                      decoration: BoxDecoration(
                        color: i == 0 ? Colors.white.withValues(alpha: 0.14) : null,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: AppTile(
                        key: ValueKey(matches[i].id),
                        app: matches[i],
                        onTap: () => onLaunch(matches[i]),
                        onLongPress: () => showAppActions(context, matches[i]),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
        ],
      ),
    );
  }
}
