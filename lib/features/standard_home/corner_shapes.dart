import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Corner rules shared by every rounded surface in standard mode.
///
/// - Shape: continuous corners (a superellipse, as Apple uses for icons and
///   its UI). A plain circular arc changes curvature abruptly where it meets
///   the straight edge; a superellipse eases into the curve, which reads as
///   smoother at the same radius.
/// - Steps: the Material 3 shape scale (none 0, extra small 4, small 8,
///   medium 12, large 16, large increased 20, extra large 28, extra large
///   increased 32, extra extra large 48, full). Dragging a radius snaps to
///   these.
/// - Nesting: concentric corners. Something drawn around a shape at distance
///   d gets radius r + d; something inside at inset d gets r - d (never
///   below 0), so the curves stay parallel.
abstract final class CornerShapes {
  /// Material 3 shape scale steps, with their token names.
  static const steps = <(double, String)>[
    (0, 'None'),
    (4, 'Extra small'),
    (8, 'Small'),
    (12, 'Medium'),
    (16, 'Large'),
    (20, 'Large increased'),
    (28, 'Extra large'),
    (32, 'Extra large increased'),
    (48, 'Extra extra large'),
  ];

  /// How close (in radius units) a dragged radius must come to a step to
  /// snap onto it.
  static const snapDistance = 2.5;

  /// [radius] snapped to the nearest step within [snapDistance], or to
  /// [full] (the maximum, a fully rounded shape) when that close to it.
  static double snap(double radius, {required double full}) {
    if ((radius - full).abs() <= snapDistance) return full;
    for (final (step, _) in steps) {
      if (step < full && (radius - step).abs() <= snapDistance) return step;
    }
    return radius;
  }

  /// Name of [radius] on the Material 3 scale ("Large · 16"), or just the
  /// number between steps. At [full], [fullName].
  static String label(double radius, {required double full, String fullName = 'Full'}) {
    if (radius >= full) return fullName;
    for (final (step, name) in steps) {
      if (step == radius) return step == 0 ? name : '$name · ${step.round()}';
    }
    return '${radius.round()}';
  }

  /// A continuous-corner (superellipse) shape.
  static ShapeBorder shape(double radius, {BorderSide side = BorderSide.none}) =>
      RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(radius < 0 ? 0 : radius), side: side);

  /// Radius for an outline drawn [distance] outside a shape of [radius]
  /// (negative [distance]: inside it), keeping the curves concentric.
  static double concentric(double radius, double distance) => (radius + distance).clamp(0.0, double.infinity);
}

/// A triangle, point up, with round corners ([cornerFraction] of its
/// box's width), for triangle folders.
///
/// Optically sized: a triangle covers half its box, so drawn inside it, it
/// looks far smaller than a square or circle of the same size. It reaches a
/// little past its box (10% at the sides, 12% above) to read as the same
/// size, and sits a little high, its base at 94%, so its weight (low in a
/// triangle) is centred.
class RoundedTriangleBorder extends OutlinedBorder {
  const RoundedTriangleBorder({super.side, this.cornerFraction = 0.16, this.optical = true});

  final double cornerFraction;

  /// Reaches past its box to look the size of a square or circle (a
  /// folder); false: exactly in its box (point at the top middle, base
  /// along the bottom), for a container, which must keep to its cells.
  final bool optical;

  /// Its three corners for a box of [rect], clockwise from the top.
  static List<Offset> cornersIn(Rect rect, {bool optical = true}) {
    final w = rect.width, h = rect.height;
    if (!optical) return [Offset(rect.center.dx, rect.top), rect.bottomRight, rect.bottomLeft];
    return [
      Offset(rect.center.dx, rect.top - 0.12 * h),
      Offset(rect.right + 0.1 * w, rect.top + 0.94 * h),
      Offset(rect.left - 0.1 * w, rect.top + 0.94 * h),
    ];
  }

  Path _path(Rect rect) {
    final pts = cornersIn(rect, optical: optical);
    final r = rect.width * cornerFraction;
    final path = Path();
    for (var i = 0; i < pts.length; i++) {
      final p = pts[i], prev = pts[(i + pts.length - 1) % pts.length], next = pts[(i + 1) % pts.length];
      final a = prev - p, b = next - p;
      final ua = a / a.distance, ub = b / b.distance;
      final angle = math.acos((ua.dx * ub.dx + ua.dy * ub.dy).clamp(-1.0, 1.0));
      final d = r / math.tan(angle / 2);
      final start = p + ua * d, end = p + ub * d;
      if (i == 0) {
        path.moveTo(start.dx, start.dy);
      } else {
        path.lineTo(start.dx, start.dy);
      }
      path.arcToPoint(end, radius: Radius.circular(r));
    }
    return path..close();
  }

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(side.width);

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) => _path(rect.deflate(side.width));

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) => _path(rect);

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (side.style == BorderStyle.none || side.width == 0) return;
    canvas.drawPath(_path(rect.deflate(side.width / 2)), side.toPaint());
  }

  @override
  ShapeBorder scale(double t) =>
      RoundedTriangleBorder(side: side.scale(t), cornerFraction: cornerFraction, optical: optical);

  @override
  RoundedTriangleBorder copyWith({BorderSide? side}) =>
      RoundedTriangleBorder(side: side ?? this.side, cornerFraction: cornerFraction, optical: optical);

  @override
  bool operator ==(Object other) =>
      other is RoundedTriangleBorder &&
      other.side == side &&
      other.cornerFraction == cornerFraction &&
      other.optical == optical;

  @override
  int get hashCode => Object.hash(side, cornerFraction, optical);
}

/// A circle with a soft, wavy edge: [petals] smooth lobes, the first at the
/// top, dipping [depth] (a fraction of the radius) between them. For flower
/// folders and containers, whose apps sit one in each petal.
class FlowerBorder extends OutlinedBorder {
  const FlowerBorder({super.side, this.petals = 8, this.depth = 0.07});

  final int petals;
  final double depth;

  /// The radius, as a fraction of the full one, at angle [t] from the top.
  double reach(double t) => 1 - depth * (1 - math.cos(petals * t)) / 2;

  Path _path(Rect rect) {
    final c = rect.center, r = rect.shortestSide / 2;
    final steps = petals * 24;
    final path = Path();
    for (var i = 0; i <= steps; i++) {
      final t = 2 * math.pi * i / steps;
      final p = c + Offset(math.sin(t), -math.cos(t)) * (r * reach(t));
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    return path..close();
  }

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(side.width);

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) => _path(rect.deflate(side.width));

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) => _path(rect);

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (side.style == BorderStyle.none || side.width == 0) return;
    canvas.drawPath(_path(rect.deflate(side.width / 2)), side.toPaint());
  }

  @override
  ShapeBorder scale(double t) => FlowerBorder(side: side.scale(t), petals: petals, depth: depth);

  @override
  FlowerBorder copyWith({BorderSide? side}) => FlowerBorder(side: side ?? this.side, petals: petals, depth: depth);

  @override
  bool operator ==(Object other) =>
      other is FlowerBorder && other.side == side && other.petals == petals && other.depth == depth;

  @override
  int get hashCode => Object.hash(side, petals, depth);
}
