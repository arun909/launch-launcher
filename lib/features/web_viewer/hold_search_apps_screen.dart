import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/platform/instant_platform.dart';

/// Which places hold-to-search's bar shows, and in what order: switch them
/// on or off, drag to reorder. Saved as it changes; the next hold shows it.
class HoldSearchAppsScreen extends StatefulWidget {
  const HoldSearchAppsScreen({super.key});

  @override
  State<HoldSearchAppsScreen> createState() => _HoldSearchAppsScreenState();
}

class _HoldSearchAppsScreenState extends State<HoldSearchAppsScreen> {
  List<HoldSearchPlace>? _places;

  @override
  void initState() {
    super.initState();
    context.read<InstantPlatform>().holdSearchPlaces().then((p) {
      if (mounted) setState(() => _places = p);
    });
  }

  void _save() {
    final ids = [for (final p in _places!) if (p.shown) p.id];
    context.read<InstantPlatform>().setHoldSearchPlaces(ids);
  }

  void _toggle(int i, bool on) {
    HapticFeedback.selectionClick();
    setState(() => _places![i] = _places![i].copyWith(shown: on));
    _save();
  }

  void _reorder(int from, int to) {
    setState(() => _places!.insert(to, _places!.removeAt(from)));
    _save();
  }

  @override
  Widget build(BuildContext context) {
    final places = _places;
    final shownCount = places?.where((p) => p.shown).length ?? 0;
    return Scaffold(
      appBar: AppBar(title: const Text('Apps in the search bar')),
      body: places == null
          ? const Center(child: CircularProgressIndicator())
          : ReorderableListView.builder(
              header: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: Text(
                  'Switch on the places to search from the hold-to-search bar. Drag to change their order: '
                  'the first one is used when you press search on the keyboard. '
                  '$shownCount shown${shownCount > 6 ? ' (more than six scroll sideways)' : ''}.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              itemCount: places.length,
              onReorderItem: _reorder,
              itemBuilder: (context, i) {
                final p = places[i];
                return SwitchListTile(
                  key: ValueKey(p.id),
                  secondary: SizedBox.square(
                    dimension: 40,
                    child: p.icon == null ? const Icon(Icons.search) : ClipOval(child: Image.memory(p.icon!, gaplessPlayback: true)),
                  ),
                  title: Text(p.label),
                  subtitle: p.installed ? null : const Text('Web only (app not installed)'),
                  value: p.shown,
                  onChanged: (on) => _toggle(i, on),
                );
              },
            ),
    );
  }
}
