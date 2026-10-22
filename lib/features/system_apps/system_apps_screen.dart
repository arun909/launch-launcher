import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/platform/system_apps_platform.dart';
import 'app_risk.dart';
import 'system_apps_controller.dart';

/// Settings > Disable system apps.
///
/// The list is readable without Shizuku; switching apps off or on needs it.
class SystemAppsScreen extends StatefulWidget {
  const SystemAppsScreen({super.key});

  @override
  State<SystemAppsScreen> createState() => _SystemAppsScreenState();
}

class _SystemAppsScreenState extends State<SystemAppsScreen> {
  late final AppLifecycleListener _lifecycle;
  String _query = '';

  @override
  void initState() {
    super.initState();
    final controller = context.read<SystemAppsController>();
    controller.refresh();
    // Coming back from the Shizuku app: it may have just been started.
    _lifecycle = AppLifecycleListener(onResume: controller.refreshStatus);
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SystemAppsController>();
    final q = _query.trim().toLowerCase();
    final apps = controller.apps
        .where((a) => q.isEmpty || a.label.toLowerCase().contains(q) || a.packageName.contains(q))
        .toList();

    final disabled = apps.where((a) => !a.enabled).toList();
    final byLevel = <RiskLevel, List<SystemApp>>{for (final l in RiskLevel.values) l: []};
    for (final app in apps.where((a) => a.enabled)) {
      byLevel[assessRisk(app).level]!.add(app);
    }
    final restorable = controller.apps.where(
      (a) => !a.enabled && controller.disabledByUs.contains(a.packageName),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Disable system apps'),
        actions: [
          IconButton(tooltip: 'Refresh', icon: const Icon(Icons.refresh), onPressed: controller.refresh),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: controller.refresh,
        child: ListView(
          children: [
            const _InfoCard(),
            if (controller.status != null && !controller.isReady)
              _ShizukuSetupCard(status: controller.status!),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: SearchBar(
                hintText: 'Filter',
                leading: const Icon(Icons.search),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            if (controller.isLoading && controller.apps.isEmpty)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              ),
            if (controller.loadError != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text('Could not list apps: ${controller.loadError}'),
              ),
            if (disabled.isNotEmpty) ...[
              const _Header('Disabled'),
              if (restorable.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.restore),
                    label: Text('Re-enable all ${restorable.length} disabled by this app'),
                    onPressed: controller.isReady ? () => _enableAll(context) : null,
                  ),
                ),
              for (final app in disabled) _SystemAppTile(app: app),
            ],
            if (byLevel[RiskLevel.safe]!.isNotEmpty) ...[
              const _Header('Safe to disable if you don\'t use them'),
              for (final app in byLevel[RiskLevel.safe]!) _SystemAppTile(app: app),
            ],
            if (byLevel[RiskLevel.caution]!.isNotEmpty) ...[
              const _Header('Check first: other features may depend on these'),
              for (final app in byLevel[RiskLevel.caution]!) _SystemAppTile(app: app),
            ],
            if (byLevel[RiskLevel.protected]!.isNotEmpty) ...[
              const _Header('Protected: disabling would break the phone'),
              for (final app in byLevel[RiskLevel.protected]!) _SystemAppTile(app: app),
            ],
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Future<void> _enableAll(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final failed = await context.read<SystemAppsController>().enableAllDisabledByUs();
    messenger.showSnackBar(
      SnackBar(content: Text(failed.isEmpty ? 'All re-enabled' : 'Failed: ${failed.join(', ')}')),
    );
  }
}

class _SystemAppTile extends StatelessWidget {
  const _SystemAppTile({required this.app});

  final SystemApp app;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SystemAppsController>();
    final risk = assessRisk(app);
    final busy = controller.isBusy(app.packageName);
    // Re-enabling is always allowed; disabling a protected app never is.
    final canToggle = controller.isReady && !busy && (!app.enabled || risk.level != RiskLevel.protected);

    return ListTile(
      leading: Opacity(
        opacity: app.enabled ? 1 : 0.4,
        child: Image.memory(app.icon, width: 40, height: 40, gaplessPlayback: true),
      ),
      title: Text(app.label),
      subtitle: Text(
        risk.reason == null ? app.packageName : '${app.packageName}\n${risk.reason}',
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
      isThreeLine: risk.reason != null,
      trailing: busy
          ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
          : Switch(value: app.enabled, onChanged: canToggle ? (on) => _toggle(context, on, risk) : null),
    );
  }

  Future<void> _toggle(BuildContext context, bool enable, AppRisk risk) async {
    final controller = context.read<SystemAppsController>();
    final messenger = ScaffoldMessenger.of(context);
    if (!enable && !await _confirmDisable(context, risk)) return;
    final error = await controller.setEnabled(app, enabled: enable);
    messenger.showSnackBar(
      SnackBar(
        content: Text(error ?? '${app.label} ${enable ? 'enabled' : 'disabled'}'),
        action: error == null && !enable
            ? SnackBarAction(label: 'Undo', onPressed: () => controller.setEnabled(app, enabled: true))
            : null,
      ),
    );
  }

  Future<bool> _confirmDisable(BuildContext context, AppRisk risk) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Disable ${app.label}?'),
        content: Text(
          [
            if (risk.level == RiskLevel.caution) '⚠ ${risk.reason}\n',
            'It will disappear from every launcher and can\'t run, update or send '
                'notifications until you re-enable it here. Nothing is deleted.',
          ].join('\n'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Disable')),
        ],
      ),
    );
    return result ?? false;
  }
}

class _ShizukuSetupCard extends StatelessWidget {
  const _ShizukuSetupCard({required this.status});

  final ShizukuStatus status;

  @override
  Widget build(BuildContext context) {
    final controller = context.read<SystemAppsController>();
    final (String text, String button, VoidCallback action) = switch (status) {
      ShizukuStatus.notInstalled => (
        'Disabling system apps needs Shizuku, a free helper app that grants adb-level '
            'access without root. Install it from the Play Store.',
        'Get Shizuku',
        controller.openShizuku,
      ),
      ShizukuStatus.notRunning => (
        'Shizuku is installed but not running. Open it and tap "Start" under '
            '"Start via Wireless debugging". It must be restarted after each reboot.',
        'Open Shizuku',
        controller.openShizuku,
      ),
      ShizukuStatus.unsupported => (
        'Your Shizuku version is too old. Update it from the Play Store.',
        'Open Shizuku',
        controller.openShizuku,
      ),
      ShizukuStatus.permissionNeeded => (
        'Shizuku is running. Allow this app to use it.',
        'Grant permission',
        controller.requestPermission,
      ),
      ShizukuStatus.ready => ('', '', () {}),
    };

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      color: Theme.of(context).colorScheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(text),
            const SizedBox(height: 12),
            FilledButton(onPressed: action, child: Text(button)),
          ],
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(16),
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: const Padding(
        padding: EdgeInsets.all(16),
        child: Text(
          'Unlike hiding, disabling works in every launcher: the app disappears and '
          'can\'t run until you re-enable it here. Nothing is deleted, and a factory '
          'reset re-enables everything.',
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(color: Theme.of(context).colorScheme.primary),
      ),
    );
  }
}
