import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'home_layout_controller.dart';

/// Asks, then tidies up the home screen (see [HomeLayoutController.tidyUp]).
Future<void> confirmTidyUp(BuildContext context) async {
  final layout = context.read<HomeLayoutController>();
  final ok = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      icon: const Icon(Icons.auto_awesome_mosaic_outlined),
      title: const Text('Tidy up home screen?'),
      content: const Text(
        'All folders and containers are removed and every app is lined up A–Z from the first page, '
        'using as few pages as possible.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Tidy up')),
      ],
    ),
  );
  if (ok != true) return;
  layout.tidyUp();
}
