import 'package:flutter/foundation.dart';

/// How app icons are masked: the phone's own mask, or a rounded square with a
/// user-chosen corner radius (from a plain square up to a circle).
///
/// Applied natively when icons are rendered, so a change re-renders every
/// icon (see `AppsController.setIconShape`). [radius] is sent over the
/// platform channel; keep it in sync with `InstalledAppsSource.loadIcons`.
@immutable
class IconShape {
  const IconShape.rounded(int this.radius) : assert(radius >= 0 && radius <= maxRadius);

  const IconShape._system() : radius = null;

  /// The phone's own icon mask, as Android renders it.
  static const system = IconShape._system();

  /// Circle, like Pixel launchers.
  static const circle = IconShape.rounded(maxRadius);

  /// [radius] at which the corners meet and the icon is a circle.
  static const maxRadius = 50;

  /// Corner radius as a percentage of the icon size (0 = square,
  /// [maxRadius] = circle), or null to keep the phone's own mask.
  final int? radius;

  bool get isSystem => radius == null;

  String get label => switch (radius) {
    null => 'System default',
    0 => 'Square',
    maxRadius => 'Round',
    final r => 'Rounded · $r%',
  };

  /// Stable string form for prefs and the icon cache.
  String encode() => radius?.toString() ?? 'system';

  /// Parses [encode] output, falling back to [system] for unknown values.
  static IconShape decode(String? value) {
    if (value == 'circle') return circle; // stored by the first version of this setting
    final r = int.tryParse(value ?? '');
    return r == null ? system : IconShape.rounded(r.clamp(0, maxRadius));
  }

  @override
  bool operator ==(Object other) => other is IconShape && other.radius == radius;

  @override
  int get hashCode => radius.hashCode;

  @override
  String toString() => 'IconShape(${encode()})';
}
