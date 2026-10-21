import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/apps/app_search.dart';
import '../../core/apps/apps_controller.dart';
import '../../core/models/app_info.dart';
import '../../core/widgets/app_icon.dart';
import '../app_actions/app_actions_sheet.dart';
import '../hidden_apps/visible_apps.dart';

/// All visible apps in a grid, with search-as-you-type.
///
/// Reads only [VisibleApps], so hidden apps never appear here or in search.
class AppDrawerScreen extends StatefulWidget {
  const AppDrawerScreen({super.key, this.autofocusSearch = false});

  final bool autofocusSearch;

  @override
  State<AppDrawerScreen> createState() => _AppDrawerScreenState();
}

class _AppDrawerScreenState extends State<AppDrawerScreen> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isLoaded = context.select<AppsController, bool>((c) => c.isLoaded);
    final apps = filterApps(context.watch<VisibleApps>().apps, _query);

    return Scaffold(
      backgroundColor: Colors.black.withValues(alpha: 0.82),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: SearchBar(
                controller: _search,
                autoFocus: widget.autofocusSearch,
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
                  if (apps.isNotEmpty) openApp(context, apps.first);
                },
              ),
            ),
            Expanded(child: _buildGrid(isLoaded, apps)),
          ],
        ),
      ),
    );
  }

  Widget _buildGrid(bool isLoaded, List<AppInfo> apps) {
    if (!isLoaded) return const Center(child: CircularProgressIndicator());
    if (apps.isEmpty) {
      return Center(
        child: Text(
          _query.isEmpty ? 'No apps' : 'No apps match "$_query"',
          style: const TextStyle(color: Colors.white70),
        ),
      );
    }
    // Pull down at the top of the list to close the drawer.
    return NotificationListener<OverscrollNotification>(
      onNotification: (n) {
        if (n.overscroll < -12 && n.metrics.pixels <= 0 && n.dragDetails != null) {
          Navigator.maybePop(context);
          return true;
        }
        return false;
      },
      child: GridView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        physics: const ClampingScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
          childAspectRatio: 0.82,
        ),
        itemCount: apps.length,
        itemBuilder: (context, i) {
          final app = apps[i];
          return AppTile(
            key: ValueKey(app.id),
            app: app,
            onTap: () => openApp(context, app),
            onLongPress: () => showAppActions(context, app),
          );
        },
      ),
    );
  }
}
