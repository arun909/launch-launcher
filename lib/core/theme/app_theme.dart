import 'package:flutter/material.dart';

/// Single place for theming. A future "theme" feature should replace this
/// with a provider-driven ThemeData rather than styling widgets individually.
abstract final class AppTheme {
  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(seedColor: Colors.teal, brightness: Brightness.dark);
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      // Settings screens are opaque; home and drawer override to transparent.
      scaffoldBackgroundColor: scheme.surface,
    );
  }
}
