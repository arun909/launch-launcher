import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/apps/apps_controller.dart';
import '../../core/platform/standby_platform.dart';
import '../../core/routing/app_routes.dart';
import '../../core/widgets/app_icon.dart';
import 'hidden_apps_controller.dart';

/// Settings > Hidden apps: the only place hidden apps are listed.
class HiddenAppsScreen extends StatelessWidget {
  const HiddenAppsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final all = context.watch<AppsController>().apps;
    final hidden = context.watch<HiddenAppsController>();
    final hiddenApps = all.where((a) => hidden.isHidden(a.id)).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Hidden apps')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.pushNamed(context, AppRoutes.manageApps),
        icon: const Icon(Icons.visibility_off_outlined),
        label: const Text('Choose apps to hide'),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          const _HidingNote(),
          const _NotificationsSwitch(),
          if (hiddenApps.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: Text('No hidden apps')),
            ),
          for (final app in hiddenApps)
            ListTile(
              leading: AppIcon(app: app, size: 40),
              title: Text(app.label),
              subtitle: Text(app.packageName, maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: TextButton(onPressed: () => hidden.unhide(app.id), child: const Text('Unhide')),
            ),
        ],
      ),
    );
  }
}

class _HidingNote extends StatelessWidget {
  const _HidingNote();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.all(16),
      color: scheme.secondaryContainer,
      child: const Padding(
        padding: EdgeInsets.all(16),
        child: Text(
          'Hidden apps are removed from the home screen and app drawer in this '
          'launcher only; typing a name in the Instant widget\'s search still '
          'finds them. They are still installed, can still run in the '
          'background, and still appear in Android Settings.',
        ),
      ),
    );
  }
}

/// Whether hidden apps' notifications still show (on by default). Turning
/// it off needs notification access, the same the music widget uses; until
/// it's given, the subtitle says so and tapping opens that setting.
class _NotificationsSwitch extends StatefulWidget {
  const _NotificationsSwitch();

  @override
  State<_NotificationsSwitch> createState() => _NotificationsSwitchState();
}

class _NotificationsSwitchState extends State<_NotificationsSwitch> with WidgetsBindingObserver {
  bool? _access;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Back from Android's notification-access page.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<void> _check() async {
    final access = await context.read<StandbyPlatform>().hasMediaAccess();
    if (mounted) setState(() => _access = access);
  }

  @override
  Widget build(BuildContext context) {
    final hidden = context.watch<HiddenAppsController>();
    final show = hidden.showNotifications;
    final needsAccess = !show && _access == false;
    return SwitchListTile(
      secondary: Icon(show ? Icons.notifications_outlined : Icons.notifications_off_outlined),
      title: const Text('Show notifications'),
      subtitle: Text(
        show
            ? 'Hidden apps still notify you'
            : needsAccess
            ? 'Allow notification access so the launcher can dismiss them'
            : 'Notifications from hidden apps are dismissed',
      ),
      value: show,
      onChanged: (on) async {
        await hidden.setShowNotifications(on);
        if (!on && _access != true && context.mounted) await context.read<StandbyPlatform>().openMediaAccess();
      },
    );
  }
}
