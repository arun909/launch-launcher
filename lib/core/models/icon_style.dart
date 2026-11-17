import 'dart:convert';

import 'package:flutter/foundation.dart';

/// Where app icons come from.
enum IconSource {
  original('Original', "Each app's own icon"),
  themed('Themed', "Android's monochrome icons"),
  lawnicons('Lawnicons', 'Bold, rounded line icons'),
  arcticons('Arcticons', 'Thin, minimal line icons');

  const IconSource(this.label, this.description);

  final String label;
  final String description;

  /// True for the packs bundled in the app (assets/iconpacks).
  bool get isPack => this == lawnicons || this == arcticons;
}

/// The plate drawn behind line icons.
enum IconBackground {
  dark('Dark'),
  black('Black'),
  glass('Glass'),
  tinted('Tinted'),
  none('None');

  const IconBackground(this.label);

  final String label;
}

/// What apps get when no source has an icon for them.
enum IconFallback {
  themed('Monochrome', 'Android\'s monochrome icon, or one made from the app\'s icon'),
  letter('Letter', 'The first letter of the app name'),
  grayscale('Grayscale', 'The app\'s own icon without colour'),
  original('Original', 'The app\'s own icon');

  const IconFallback(this.label, this.description);

  final String label;
  final String description;
}

/// What goes behind an app's own icon when it doesn't fill the shape (older,
/// non-adaptive icons). Icons that do fill it are scaled to fill it.
enum LegacyBackground {
  plain('Plain', 'A white background'),
  tinted('Tinted', 'A soft tint of the app\'s own colour'),
  keep('Unchanged', 'As the app made it, without the shape');

  const LegacyBackground(this.label, this.description);

  final String label;
  final String description;
}

/// How app icons are drawn, apart from their shape ([IconShape]).
///
/// Rendered natively (`platform/icons/IconStyle.kt`; keep [toMap] in sync), so
/// a change re-renders every icon (see `AppsController.setIconStyle`).
@immutable
class IconStyle {
  const IconStyle({
    this.source = IconSource.original,
    this.fillGaps = true,
    this.background = IconBackground.dark,
    this.color = 0xFFFFFFFF,
    this.appColor = false,
    this.lineWeight = 1.0,
    this.glyphScale = 0.62,
    this.fallback = IconFallback.themed,
    this.legacyBackground = LegacyBackground.plain,
  });

  static const defaults = IconStyle();

  static const minLineWeight = 0.5;
  static const maxLineWeight = 3.0;
  static const minGlyphScale = 0.45;
  static const maxGlyphScale = 0.8;

  /// Soft colours that read well on a dark plate.
  static const palette = [
    0xFFFFFFFF, // white
    0xFFB8BCC4, // silver
    0xFF8FE3C6, // mint
    0xFF8EC9FF, // sky
    0xFFC3B2FF, // lavender
    0xFFFFC09A, // peach
    0xFFFF9EB5, // rose
    0xFFF2E38C, // lemon
  ];

  final IconSource source;

  /// When [source] has no icon for an app, try the other sources first.
  final bool fillGaps;
  final IconBackground background;

  /// Line colour (ARGB), unless [appColor].
  final int color;

  /// Tint each icon with a soft version of the app's own colour.
  final bool appColor;

  /// Multiplier of the pack's own line width.
  final double lineWeight;

  /// How much of the icon the drawing spans.
  final double glyphScale;
  final IconFallback fallback;
  final LegacyBackground legacyBackground;

  bool get isOriginal => source == IconSource.original;

  IconStyle copyWith({
    IconSource? source,
    bool? fillGaps,
    IconBackground? background,
    int? color,
    bool? appColor,
    double? lineWeight,
    double? glyphScale,
    IconFallback? fallback,
    LegacyBackground? legacyBackground,
  }) => IconStyle(
    source: source ?? this.source,
    fillGaps: fillGaps ?? this.fillGaps,
    background: background ?? this.background,
    color: color ?? this.color,
    appColor: appColor ?? this.appColor,
    lineWeight: lineWeight ?? this.lineWeight,
    glyphScale: glyphScale ?? this.glyphScale,
    fallback: fallback ?? this.fallback,
    legacyBackground: legacyBackground ?? this.legacyBackground,
  );

  /// Channel form; see `IconStyle.fromMap` in Kotlin.
  Map<String, Object> toMap() => {
    'pack': source.name,
    'fillGaps': fillGaps,
    'background': background.name,
    'color': color,
    'appColor': appColor,
    'lineWeight': lineWeight,
    'glyphScale': glyphScale,
    'fallback': fallback.name,
    'legacyBackground': legacyBackground.name,
  };

  /// Stable string form for prefs and the icon cache.
  String encode() => jsonEncode(toMap());

  /// Parses [encode] output; unknown or missing values fall back to defaults.
  static IconStyle decode(String? value) {
    if (value == null) return defaults;
    try {
      final map = jsonDecode(value) as Map<String, dynamic>;
      T pick<T extends Enum>(List<T> values, Object? name, T fallback) =>
          values.where((v) => v.name == name).firstOrNull ?? fallback;
      double number(Object? v, double fallback, double min, double max) =>
          v is num ? v.toDouble().clamp(min, max) : fallback;
      return IconStyle(
        source: pick(IconSource.values, map['pack'], defaults.source),
        fillGaps: map['fillGaps'] as bool? ?? defaults.fillGaps,
        background: pick(IconBackground.values, map['background'], defaults.background),
        color: map['color'] as int? ?? defaults.color,
        appColor: map['appColor'] as bool? ?? defaults.appColor,
        lineWeight: number(map['lineWeight'], defaults.lineWeight, minLineWeight, maxLineWeight),
        glyphScale: number(map['glyphScale'], defaults.glyphScale, minGlyphScale, maxGlyphScale),
        fallback: pick(IconFallback.values, map['fallback'], defaults.fallback),
        legacyBackground: pick(LegacyBackground.values, map['legacyBackground'], defaults.legacyBackground),
      );
    } catch (_) {
      return defaults;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is IconStyle &&
      other.source == source &&
      other.fillGaps == fillGaps &&
      other.background == background &&
      other.color == color &&
      other.appColor == appColor &&
      other.lineWeight == lineWeight &&
      other.glyphScale == glyphScale &&
      other.fallback == fallback &&
      other.legacyBackground == legacyBackground;

  @override
  int get hashCode =>
      Object.hash(source, fillGaps, background, color, appColor, lineWeight, glyphScale, fallback, legacyBackground);

  @override
  String toString() => 'IconStyle(${encode()})';
}
