import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/models/app_info.dart';
import '../../core/models/icon_shape.dart';
import '../../core/theme/home_grid.dart';
import '../../core/widgets/app_icon.dart';
import '../appearance/wallpaper_glass.dart';
import 'corner_shapes.dart';
import '../widgets/home_widget_view.dart';
import 'home_layout.dart';

/// A container on a home page: its apps at normal home icon size on a
/// rounded panel. If there are more apps than fit, the last spot shows a
/// small cluster of the rest. Tap an icon to launch it; anywhere else opens
/// it.
///
/// Its panel takes exactly a widget's frame for its span (its cells less a
/// small inset; see HomeWidgetView.frameIn), so containers and widgets line
/// up with each other and sit evenly in their rows: as far from the row
/// above as from the row below.
///
/// Inside, its icons are spaced evenly: the gaps between icons equal the
/// panel's padding, across and down (see [iconsIn]). How many icons fit in
/// a row follows from that, not from the cells it spans: a 4 × 1 container
/// on the 4 × 8 grid holds 6 icons ~9–11dp apart, rather than 4 icons a
/// home cell apart behind 11dp of padding.
///
/// Its name sits inside the panel's top, from two rows up; a one-row panel
/// has no room for it without crowding its icons (the name is shown when
/// it's opened).
class AppContainerTile extends StatelessWidget {
  const AppContainerTile({
    super.key,
    required this.container,
    required this.apps,
    required this.grid,
    this.iconShape = IconShape.system,
    this.showName = true,
    this.onOpen,
    this.onLongPress,
    this.onLaunch,
    this.settledSize,
  });

  /// How long a resized group takes to reach its new size: its frame on the
  /// home grid and its icons move together, on this and [resizeCurve].
  static const resizeDuration = Duration(milliseconds: 220);
  static const resizeCurve = Curves.easeOutCubic;

  /// The size its frame is animating to (its cells), when known: icons are
  /// laid out once for that, at their final size, and glide there with the
  /// frame instead of being re-laid out (and re-decoded) at every in-between
  /// size. Null: laid out for the size it's given.
  final Size? settledSize;

  final AppContainer container;

  /// Icon and label sizes: the same as apps on the home screen.
  final HomeGrid grid;

  /// The app icons' shape, which limits how round the corners get.
  final IconShape iconShape;

  /// Its name under it; off with the home screen's app names (the line stays,
  /// empty, so nothing shifts).
  final bool showName;

  /// The container's apps that are visible, in order.
  final List<AppInfo> apps;
  final VoidCallback? onOpen;
  final VoidCallback? onLongPress;
  final void Function(AppInfo app)? onLaunch;

  /// Panel margin around the outermost icons, and the gap between icons,
  /// scaled with the icon size (12 at the large grid's 56dp icons).
  static double pad(HomeGrid grid) => (grid.iconSize * 0.22).roundToDouble();

  /// Top of the icon of an app tile centred in a cell [cellHeight] high.
  static double iconTop(HomeGrid grid, double cellHeight) => (cellHeight - grid.tileHeight) / 2 + 8;

  /// Where a home app's icon sits inside cell ([col], [row]) of a grid of
  /// [cell]s; a folder's tile is exactly this.
  static Rect iconRect(HomeGrid grid, Size cell, int col, int row) => Rect.fromLTWH(
    col * cell.width + (cell.width - grid.iconSize) / 2,
    row * cell.height + iconTop(grid, cell.height),
    grid.iconSize,
    grid.iconSize,
  );

  /// The panel of a [cols] x [rows] container drawn in a [frame] of its
  /// cells: a widget's frame for that span. Fractional spans give the sizes
  /// in between while resizing.
  static Rect panelRect(HomeGrid grid, Size frame, double cols, double rows) =>
      HomeWidgetView.frameIn(grid, frame, cols, rows);

  /// The least gap between icons in a container (and between them and its
  /// edges): 8dp at 52dp icons.
  static double minGap(HomeGrid grid) => grid.iconSize * 0.15;

  /// Where [apps] icons go in a container's [area] (its panel, less its name
  /// line if shown): as many per row and as many rows as make the gaps
  /// across closest to the gaps down, each axis spaced evenly (the space at
  /// the edges equal to the space between icons), never closer than
  /// [minGap]. Fewer apps than spots: just the rows they need, and a lone
  /// row spread across.
  static ContainerIcons iconsIn(HomeGrid grid, Rect area, int apps) {
    final icon = grid.iconSize, least = minGap(grid);
    double gap(double extent, int n) => (extent - n * icon) / (n + 1);
    int most(double extent) => math.max(1, ((extent - least) / (icon + least)).floor());
    var (perRow, rows) = (1, 1);
    var best = double.infinity;
    for (var n = 1; n <= most(area.width); n++) {
      for (var m = 1; m <= most(area.height); m++) {
        final miss = (gap(area.width, n) - gap(area.height, m)).abs();
        // Near-equal spacing: the one holding more apps.
        if (miss < best - 1.5 || (miss < best + 1.5 && n * m > perRow * rows)) {
          (perRow, rows, best) = (n, m, math.min(best, miss));
        }
      }
    }
    final n = math.max(1, apps);
    if (n < perRow * rows) {
      rows = math.max(1, (n / perRow).ceil());
      if (rows == 1) perRow = n;
    }
    return ContainerIcons(area, icon, perRow, rows, gap(area.width, perRow), gap(area.height, rows));
  }

  /// Height of the name line inside a container's panel, with its spacing.
  static const nameLine = HomeGrid.labelLineHeight + 6;

  /// How round app icons are: corner radius as a fraction of their size.
  /// The phone's own mask isn't known here; it's taken as 20%, the least
  /// rounded of the common ones (rounded square 20-25%, squircle about 30%,
  /// circle 50%), so the limits below hold for any of them.
  static double iconRoundness(IconShape shape) => (shape.radius ?? 20) / 100;

  /// The largest corner radius a panel can have while an icon in its corner,
  /// [inset] in from both edges and with corners of [iconRadius], stays
  /// wholly inside it.
  ///
  /// The icon's corner arc (centre inset + iconRadius in from both edges) must
  /// lie within the panel's (centre r in): √2·(r − inset − iconRadius) +
  /// iconRadius ≤ r, which gives r ≤ (2 + √2)·inset + iconRadius. The panel's
  /// continuous corners cut no deeper than a circular arc of the same radius,
  /// so it holds for them too.
  static double fitRadius(double inset, double iconRadius) => (2 + math.sqrt2) * inset + iconRadius;

  /// The most a folder's corners can be rounded: its mini icons stay inside.
  static double folderMaxRadius(HomeGrid grid, IconShape shape) => math.min(
    grid.iconSize / 2,
    fitRadius(FolderTile.inset, FolderTile.tinySize(grid.iconSize) * iconRoundness(shape)),
  );

  /// Folders and containers come in three roundnesses only: square, the
  /// most that fits ([folderMaxRadius] / [containerMaxRadius]), and halfway
  /// between. Drawn radii, smallest first.
  static List<double> radiiFor(bool folder, HomeGrid grid, IconShape shape) {
    final full = folder ? folderMaxRadius(grid, shape) : containerMaxRadius(grid, shape);
    return [0, (full / 2).roundToDouble(), full];
  }

  /// Names of [radiiFor], in the same order.
  static const radiusNames = ['Square', 'Soft', 'Rounded'];

  /// The allowed radius nearest to [radius].
  static double nearestRadius(double radius, bool folder, HomeGrid grid, IconShape shape) =>
      radiiFor(folder, grid, shape).reduce((a, b) => (radius - a).abs() <= (radius - b).abs() ? a : b);

  /// Containers round no further than this: Material 3's Extra large step
  /// (and their default), well short of a pill or circle.
  static const containerCornerCap = 28.0;

  /// The most a container's corners can be rounded: up to [containerCornerCap],
  /// and only while its icons stay inside.
  static double containerMaxRadius(HomeGrid grid, IconShape shape) =>
      math.min(containerCornerCap, fitRadius(pad(grid), grid.iconSize * iconRoundness(shape)));

  /// Corner radius [c] is drawn with: the nearest of [radiiFor], so ones
  /// saved with any other radius line up with the three steps.
  static double radiusOf(AppContainer c, HomeGrid grid, IconShape shape) =>
      nearestRadius(c.radiusAt(grid.iconSize), c.isFolder, grid, shape);

  /// How deep a flower's petals dip, as a fraction of its radius.
  static const flowerDepth = 0.085;

  /// Petals for a flower of [apps] apps: one per app, doubled until there
  /// are at least six (fewer would look like a clover, not a flower).
  static int petalsFor(int apps) {
    var p = math.max(1, apps);
    while (p < 6) {
      p *= 2;
    }
    return p;
  }

  /// Petals for a flower whose icons are at [spots] round [centre]: one per
  /// icon of the outermost ring (see [petalsFor]).
  static int petalsAround(Offset centre, List<Offset> spots) {
    if (spots.isEmpty) return 8;
    final far = spots.map((p) => (p - centre).distance).reduce(math.max);
    return petalsFor(spots.where((p) => (p - centre).distance > far - 1).length);
  }

  /// Whether a triangle suits [apps] apps: one in each corner and the rest
  /// evenly along its sides takes 3, 6, 9… apps.
  static bool triangleFits(int apps) => apps >= 3 && apps % 3 == 0;

  /// The shape [c] is drawn in: a triangle only with 3, 6, 9… apps (one
  /// whose count changed since is a circle meanwhile).
  static FolderShape shapeOf(AppContainer c, int apps) =>
      c.folderShape == FolderShape.triangle && !triangleFits(apps) ? FolderShape.circle : c.folderShape;

  /// The square span a shaped container of [apps] apps takes: the
  /// smallest from 2 × 2 up to [most] (the grid's columns) in which they all
  /// fit at full icon size, worked out with the real cells ([cell]) of
  /// [grid]; [most] if none.
  static int shapedSpan(FolderShape shape, int apps, HomeGrid grid, Size cell, int most) {
    final top = math.max(2, most);
    for (var k = 2; k <= top; k++) {
      final panel = HomeWidgetView.frameIn(grid, Size(cell.width * k, cell.height * k), k.toDouble(), k.toDouble());
      final box = Offset.zero & Size.square(panel.shortestSide);
      final (spots, icon) = shapeLayout(shape, box, apps, grid);
      if (spots.length >= apps && icon >= grid.iconSize - 0.5) return k;
    }
    return top;
  }

  /// Icon centres and size for a [shape]d container of [apps] apps in [box]
  /// (a square), set by its size alone: round its edge while that's snug,
  /// filling it once it's resized big enough that the edge would leave a
  /// wide empty middle (see [ringSpots], [filledRingSpots], [triangleLayout],
  /// [filledTriangleLayout]). Fewer spots than apps: the last one shows the
  /// rest.
  static (List<Offset>, double) shapeLayout(FolderShape shape, Rect box, int apps, HomeGrid grid) {
    final icon = grid.iconSize, p = pad(grid);
    final depth = shape == FolderShape.flower ? flowerDepth : 0.0;
    final step = icon + math.max(p * 0.5, 5.0);
    if (shape == FolderShape.triangle) {
      final (spots, size) = triangleLayout(box, apps, icon);
      final sideGap = spots.length > 1 ? (spots[1] - spots[0]).distance : 0.0;
      return sideGap > step * 2.2 ? filledTriangleLayout(box, apps, icon) : (spots, size);
    }
    final r = box.shortestSide / 2 * (1 - depth) - icon / 2 - p * 0.5;
    final fill = math.max(1, apps) >= 4 && r - icon / 2 > step * 1.35;
    return fill
        ? filledRingSpots(box, apps, icon, p, depth: depth)
        : (ringSpots(box, apps, icon, p, depth: depth), icon);
  }

  /// Icon centres and size for a filled circle (or flower: [depth]) in
  /// [box]: rings out from the middle (a centre icon or a small ring, then
  /// rings each an icon and a gap further out), the apps shared so each
  /// ring is evenly full, the outer ring the fullest; the most compact such
  /// set that, spread out to reach the edge, leaves the narrowest empty
  /// band anywhere: no empty middle and no empty rim, at any size. Icons shrink a little (to 80% at most) where that's what
  /// it takes to fit.
  static (List<Offset>, double) filledRingSpots(Rect box, int apps, double icon, double pad, {double depth = 0}) {
    final c = box.center;
    final n = math.max(1, apps);
    if (n == 1) return ([c], icon);
    List<Offset>? at(double size) {
      final s = size + math.max(pad * 0.5, 5.0);
      final most = box.shortestSide / 2 * (1 - depth) - size / 2 - pad * 0.5;
      double chord(int k) => k <= 1 ? 0 : s / (2 * math.sin(math.pi / k));
      (List<int>, List<double>, bool)? best;
      var bestScore = double.infinity;
      for (final centre in [true, false]) {
        final rest = n - (centre ? 1 : 0);
        for (var rings = 1; rings <= 5; rings++) {
          if (rest < rings) break;
          // Share the apps out in proportion to each ring's size.
          final guess = [for (var j = 0; j < rings; j++) centre ? (j + 1).toDouble() : j + 0.5];
          final total = guess.reduce((a, b) => a + b);
          // Each ring of a set holds at least 3 (fewer reads as stray icons).
          final least = rings > 1 ? 3 : 1;
          final counts = [for (final g in guess) math.max(least, (rest * g / total).floor())];
          var left = rest - counts.reduce((a, b) => a + b);
          for (var j = rings - 1; left > 0; j = (j - 1 + rings) % rings, left--) {
            counts[j]++;
          }
          if (left < 0) continue;
          final radii = <double>[];
          for (var j = 0; j < rings; j++) {
            final inner = j == 0 ? (centre ? s : 0.0) : radii[j - 1] + s;
            radii.add(math.max(inner, chord(counts[j])));
          }
          if (radii.last > most + 0.5) continue;
          // Spread out to the edge, its widest empty band (the middle, or
          // between two rings) as narrow as can be: evenly filled.
          final gaps = [
            centre ? radii.first : radii.first + s / 2,
            for (var j = 1; j < rings; j++) radii[j] - radii[j - 1],
          ];
          final score = gaps.reduce(math.max) * (radii.last > 0 ? most / radii.last : 1);
          if (score < bestScore - 0.5) (best, bestScore) = ((counts, radii, centre), score);
        }
      }
      if (best == null) return null;
      final (counts, radii, centre) = best;
      // Spread out to the edge: the same rings, scaled to reach it.
      final grow = radii.last > 0 ? most / radii.last : 1.0;
      return [
        if (centre) c,
        for (var j = 0; j < counts.length; j++)
          for (var i = 0; i < counts[j]; i++)
            c +
                Offset(
                      math.sin(2 * math.pi * i / counts[j] + (j.isOdd ? math.pi / counts[j] : 0)),
                      -math.cos(2 * math.pi * i / counts[j] + (j.isOdd ? math.pi / counts[j] : 0)),
                    ) *
                    (radii[j] * grow),
      ];
    }

    for (var size = icon; size >= icon * 0.8; size -= 2) {
      final spots = at(size);
      if (spots != null) return (spots, size);
    }
    final smallest = (icon * 0.8).roundToDouble();
    return (ringSpots(box, n, smallest, pad, depth: depth), smallest);
  }

  /// Icon centres and size for a filled triangle in [box] (a square, the
  /// point at its top middle): rows of 1, 2, 3… from the point down, on a
  /// lattice inside the triangle shrunk so each icon keeps clear of its
  /// sides; a part-filled last row centred. Icons shrink a little (to 72% at
  /// most) where that's what it takes to fit.
  static (List<Offset>, double) filledTriangleLayout(Rect box, int apps, double icon) {
    final v = RoundedTriangleBorder.cornersIn(box, optical: false);
    final a = (v[1] - v[2]).distance, b = (v[0] - v[2]).distance, cc = (v[0] - v[1]).distance;
    final incentre = (v[0] * a + v[1] * b + v[2] * cc) / (a + b + cc);
    final inradius = box.width * box.height / (a + b + cc);
    final want = math.max(1, apps);
    var k = 1;
    while (k * (k + 1) ~/ 2 < want) {
      k++;
    }
    List<Offset>? at(double size) {
      final f = ((inradius - size / 2 - 5) / inradius).clamp(0.0, 1.0);
      final top = incentre + (v[0] - incentre) * f;
      final right = incentre + (v[1] - incentre) * f;
      final left = incentre + (v[2] - incentre) * f;
      if (k > 1 && (right - left).distance / (k - 1) < size + 4) return null;
      if (k == 1) return [incentre];
      return [
        for (var r = 0; r < k; r++)
          for (var j = 0, inRow = r < k - 1 ? r + 1 : want - (k - 1) * k ~/ 2; j < inRow; j++)
            r == 0
                ? top
                : Offset.lerp(
                    Offset.lerp(top, left, r / (k - 1))!,
                    Offset.lerp(top, right, r / (k - 1))!,
                    (j + (r + 1 - inRow) / 2) / r,
                  )!,
      ];
    }

    for (var size = icon; size >= icon * 0.72; size -= 2) {
      final spots = at(size);
      if (spots != null) return (spots, size);
    }
    // Too many for even the smallest: round its edge instead.
    return triangleLayout(box, apps - apps % 3, icon);
  }

  /// Centres of the icons of a circle (or flower: [depth]) container in
  /// [box] (a square): evenly round one ring, the first at the top, as far
  /// out as keeps each icon clear of the edge. Never more than fit round
  /// it: the list says how many.
  static List<Offset> ringSpots(Rect box, int apps, double icon, double pad, {double depth = 0}) {
    final c = box.center;
    final gap = math.max(pad * 0.5, 5.0);
    final r = box.shortestSide / 2 * (1 - depth) - icon / 2 - pad * 0.5;
    bool fits(int k) => k <= 1 || 2 * r * math.sin(math.pi / k) >= icon + gap - 0.5;
    var most = 1;
    while (most < 24 && fits(most + 1)) {
      most++;
    }
    final n = math.min(math.max(1, apps), most);
    if (n == 1) return [c];
    return [for (var i = 0; i < n; i++) c + Offset(math.sin(2 * math.pi * i / n), -math.cos(2 * math.pi * i / n)) * r];
  }

  /// Icon centres and size for a triangle container of [apps] apps (3, 6,
  /// 9…) in [box] (a square, the point at its top middle): one in each
  /// corner and the rest evenly along the sides, on the triangle shrunk so
  /// each icon keeps a clear margin from its edges. Icons shrink a little
  /// (to 72% at most) where that's what it takes to fit.
  static (List<Offset>, double) triangleLayout(Rect box, int apps, double icon) {
    final v = RoundedTriangleBorder.cornersIn(box, optical: false);
    final a = (v[1] - v[2]).distance, b = (v[0] - v[2]).distance, cc = (v[0] - v[1]).distance;
    final incentre = (v[0] * a + v[1] * b + v[2] * cc) / (a + b + cc);
    final inradius = box.width * box.height / (a + b + cc);
    final perSide = math.max(1, apps ~/ 3);
    List<Offset>? at(double size) {
      final f = ((inradius - size / 2 - 5) / inradius).clamp(0.0, 1.0);
      final corners = [for (final p in v) incentre + (p - incentre) * f];
      final shortest = (corners[1] - corners[2]).distance;
      if (shortest / perSide < size + 4) return null;
      return [
        for (var s = 0; s < 3; s++)
          for (var j = 0; j < perSide; j++) Offset.lerp(corners[s], corners[(s + 1) % 3], j / perSide)!,
      ];
    }

    for (var size = icon; size >= icon * 0.72; size -= 2) {
      final spots = at(size);
      if (spots != null) return (spots, size);
    }
    // Too many for even the smallest: the corners only.
    final smallest = (icon * 0.72).roundToDouble();
    return ([for (final p in v) incentre + (p - incentre) * ((inradius - smallest / 2 - 5) / inradius)], smallest);
  }

  /// [GroupStyle.material]'s surface (M3 dark surfaceContainer, neutral).
  static const materialSurface = Color(0xFF1E1F23);

  /// [GroupStyle.materialLight]'s surface (M3 light surfaceContainer, neutral).
  static const materialLightSurface = Color(0xFFEFF0F4);

  /// The panel's look; shared with the opened container so they match.
  /// Continuous (superellipse) corners, see [CornerShapes].
  /// [folderShape]: a folder's circle or triangle instead of the rounded
  /// rectangle.
  static ShapeDecoration decoration(
    double radius, [
    GroupStyle style = GroupStyle.light,
    int? color,
    FolderShape folderShape = FolderShape.rounded,
    bool optical = true,
    int petals = 8,
  ]) {
    final (fill, outline) = switch (style) {
      GroupStyle.light => (Colors.white.withValues(alpha: 0.16), 0.12),
      GroupStyle.dark => (Colors.black.withValues(alpha: 0.38), 0.08),
      // Mostly the blur (see GroupBackground); a faint frost and a bright rim.
      GroupStyle.glass => (Colors.white.withValues(alpha: 0.12), 0.30),
      GroupStyle.color => (Color(color ?? AppContainer.defaultColor).withValues(alpha: 0.5), 0.16),
      GroupStyle.material => (materialSurface, 0.0),
      GroupStyle.materialLight => (materialLightSurface, 0.0),
    };
    final side = outline == 0 ? BorderSide.none : BorderSide(color: Colors.white.withValues(alpha: outline));
    return ShapeDecoration(
      color: fill,
      shape: switch (folderShape) {
        FolderShape.rounded => CornerShapes.shape(radius, side: side),
        FolderShape.circle => CircleBorder(side: side),
        FolderShape.flower => FlowerBorder(side: side, petals: petals, depth: flowerDepth),
        // A container's triangle, bigger, takes crisper corners.
        FolderShape.triangle => RoundedTriangleBorder(
          side: side,
          optical: optical,
          cornerFraction: optical ? 0.16 : 0.1,
        ),
      },
    );
  }

  /// [decoration] in [c]'s own style.
  static ShapeDecoration decorationOf(AppContainer c, double radius) => decoration(radius, c.style, c.color);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onOpen,
      onLongPress: onLongPress,
      child: LayoutBuilder(
        builder: (context, frame) {
          final cols = container.cols, rows = container.rows;
          final panel = panelRect(grid, frame.biggest, cols.toDouble(), rows.toDouble());
          // Where the icons go: laid out for the size it's settling to.
          final settled = panelRect(grid, settledSize ?? frame.biggest, cols.toDouble(), rows.toDouble());
          if (container.folderShape != FolderShape.rounded) return _shaped(panel, settled);
          final named = showName && rows >= 2;
          final area = named
              ? Rect.fromLTRB(settled.left, settled.top + nameLine, settled.right, settled.bottom)
              : settled;
          final layout = iconsIn(grid, area, apps.length);
          final iconSize = grid.iconSize;

          // With more apps than spots, the last spot is a cluster of the rest.
          final capacity = layout.capacity;
          final big = apps.length <= capacity ? apps : apps.sublist(0, capacity - 1);
          final rest = apps.sublist(big.length);
          final slots = <Widget>[
            for (final app in big)
              _BigIcon(
                key: ValueKey(app.id),
                app: app,
                size: iconSize,
                onTap: onLaunch == null ? null : () => onLaunch!(app),
              ),
            if (rest.isNotEmpty) _Cluster(key: const ValueKey(_Cluster), apps: rest, size: iconSize),
          ];

          return Stack(
            // The panel may reach a little past the cells (top), as may the name.
            clipBehavior: Clip.none,
            children: [
              Positioned.fromRect(
                rect: panel,
                child: GroupBackground(
                  container: container,
                  radius: radiusOf(container, grid, iconShape),
                  child: const SizedBox.expand(),
                ),
              ),
              for (final (i, slot) in slots.indexed)
                AnimatedPositioned.fromRect(
                  key: slot.key,
                  duration: AppContainerTile.resizeDuration,
                  curve: AppContainerTile.resizeCurve,
                  rect: layout.rectOf(i),
                  child: slot,
                ),
              if (named)
                Positioned(
                  left: panel.left + layout.gapX,
                  right: frame.maxWidth - panel.right + layout.gapX,
                  top: panel.top + 6,
                  child: Text(
                    container.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: container.style.ink,
                      fontSize: grid.labelSize,
                      shadows: container.style.isLightSurface
                          ? null
                          : const [Shadow(blurRadius: 4, color: Colors.black54)],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

extension on AppContainerTile {
  /// A circle, flower or triangle container: its shape in the largest square
  /// of its [panel], its icons round it (see [AppContainerTile.ringSpots],
  /// [AppContainerTile.triangleLayout]); more apps than fit, the last spot a
  /// cluster of the rest. No name line: the shape has no room for one.
  Widget _shaped(Rect panel, Rect settled) {
    Rect square(Rect r) => Rect.fromCenter(center: r.center, width: r.shortestSide, height: r.shortestSide);
    final box = square(panel), target = square(settled);
    final side = box.width;
    final shape = AppContainerTile.shapeOf(container, apps.length);
    final (spots, icon) = AppContainerTile.shapeLayout(shape, target, apps.length, grid);
    final capacity = spots.length;
    final big = apps.length <= capacity ? apps : apps.sublist(0, capacity - 1);
    final rest = apps.sublist(big.length);
    final slots = <Widget>[
      for (final app in big)
        _BigIcon(key: ValueKey(app.id), app: app, size: icon, onTap: onLaunch == null ? null : () => onLaunch!(app)),
      if (rest.isNotEmpty) _Cluster(key: const ValueKey(_Cluster), apps: rest, size: icon),
    ];
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fromRect(
          rect: box,
          child: GroupBackground(
            container: container,
            radius: side / 2,
            folderShape: shape,
            optical: false,
            petals: AppContainerTile.petalsAround(box.center, spots),
            child: const SizedBox.expand(),
          ),
        ),
        for (final (i, slot) in slots.indexed)
          if (i < spots.length)
            AnimatedPositioned.fromRect(
              key: slot.key,
              duration: AppContainerTile.resizeDuration,
              curve: AppContainerTile.resizeCurve,
              rect: Rect.fromCenter(center: spots[i], width: icon, height: icon),
              child: slot,
            ),
      ],
    );
  }
}

class _BigIcon extends StatelessWidget {
  const _BigIcon({super.key, required this.app, required this.size, this.onTap});

  final AppInfo app;
  final double size;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final icon = Tooltip(
      message: app.label,
      child: AppIcon(app: app, size: size),
    );
    if (onTap == null) return icon;
    return GestureDetector(behavior: HitTestBehavior.opaque, onTap: onTap, child: icon);
  }
}

/// Up to four tiny icons in a square of [size]; stands for "and more".
class _Cluster extends StatelessWidget {
  const _Cluster({super.key, required this.apps, required this.size});

  final List<AppInfo> apps;
  final double size;

  @override
  Widget build(BuildContext context) {
    final tiny = size * 0.42;
    final shown = apps.take(4).toList();
    return SizedBox.square(
      dimension: size,
      child: Wrap(
        alignment: WrapAlignment.center,
        runAlignment: WrapAlignment.center,
        spacing: size * 0.08,
        runSpacing: size * 0.08,
        children: [for (final app in shown) AppIcon(app: app, size: tiny)],
      ),
    );
  }
}

/// A folder on a home page: an app-icon-sized rounded tile with a mini grid of
/// up to nine of its apps, and its name underneath, like [AppTile].
class FolderTile extends StatelessWidget {
  const FolderTile({
    super.key,
    required this.folder,
    required this.apps,
    required this.grid,
    this.iconShape = IconShape.system,
    this.showName = true,
    this.onOpen,
    this.onLongPress,
  });

  final AppContainer folder;

  /// Sized like an app icon of this grid.
  final HomeGrid grid;

  /// The app icons' shape, which limits how round the corners get.
  final IconShape iconShape;

  /// Its name under it; off with the home screen's app names (the line stays,
  /// empty, so nothing shifts).
  final bool showName;

  /// The folder's apps that are visible, in order.
  final List<AppInfo> apps;
  final VoidCallback? onOpen;
  final VoidCallback? onLongPress;

  static const _gap = 2.0;

  /// Space from the tile's edge to its mini icons.
  static const inset = 5.0;

  /// Size of each mini icon in a tile [size] wide (three across).
  static double tinySize(double size) => (size - inset * 2 - _gap * 2) / 3;

  /// Where a circle's, flower's or triangle's mini icons go in a tile [size]
  /// square, paired with the apps they show:
  /// - circle / flower: up to five, evenly round a ring from the top, each
  ///   30% of the tile, clear of the edge (and the flower's petals);
  /// - triangle: three, one in each corner, each 28% of the tile, placed so
  ///   their corners stay clear of the sloping sides.
  static List<(AppInfo, Rect)> _shapedSpots(FolderShape shape, double size, List<AppInfo> apps) {
    final spots = <Rect>[];
    if (shape != FolderShape.triangle) {
      final t = size * 0.3;
      final n = apps.length.clamp(1, 5);
      final depth = shape == FolderShape.flower ? AppContainerTile.flowerDepth : 0.0;
      final r = n == 1 ? 0.0 : size / 2 * (1 - depth) - t / 2 - 2.5;
      final c = Offset(size / 2, size / 2);
      for (var i = 0; i < n; i++) {
        final p = c + Offset(math.sin(2 * math.pi * i / n), -math.cos(2 * math.pi * i / n)) * r;
        spots.add(Rect.fromCenter(center: p, width: t, height: t));
      }
    } else {
      final t = size * 0.28;
      for (final (cx, cy) in const [(0.5, 0.38), (0.3, 0.69), (0.7, 0.69)]) {
        spots.add(Rect.fromCenter(center: Offset(cx * size, cy * size), width: t, height: t));
      }
    }
    return [for (final (i, app) in apps.take(spots.length).indexed) (app, spots[i])];
  }

  @override
  Widget build(BuildContext context) {
    final size = grid.iconSize;
    final tiny = tinySize(size);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onOpen,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox.square(
              dimension: size,
              child: GroupBackground(
                container: folder,
                radius: AppContainerTile.radiusOf(folder, grid, iconShape),
                folderShape: folder.folderShape,
                petals: AppContainerTile.petalsFor(apps.length.clamp(1, 5)),
                child: switch (folder.folderShape) {
                  FolderShape.rounded => Padding(
                    padding: const EdgeInsets.all(inset),
                    child: Wrap(
                      spacing: _gap,
                      runSpacing: _gap,
                      children: [for (final app in apps.take(9)) AppIcon(app: app, size: tiny)],
                    ),
                  ),
                  _ => Stack(
                    children: [
                      for (final (app, rect) in _shapedSpots(folder.folderShape, size, apps))
                        Positioned.fromRect(
                          rect: rect,
                          child: AppIcon(app: app, size: rect.width),
                        ),
                    ],
                  ),
                },
              ),
            ),
            const SizedBox(height: 6),
            // A fixed line height keeps every tile exactly 90 high, so icons in
            // containers line up with these (see HomeGrid.tileHeight).
            SizedBox(
              height: HomeGrid.labelLineHeight,
              child: Text(
                showName ? folder.name : '',
                semanticsLabel: folder.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: grid.labelSize,
                  shadows: const [Shadow(blurRadius: 4, color: Colors.black54)],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A group's panel in its [GroupStyle], behind [child]. Glass blurs the
/// wallpaper behind it (see WallpaperGlass).
class GroupBackground extends StatelessWidget {
  const GroupBackground({
    super.key,
    required this.container,
    required this.radius,
    this.folderShape = FolderShape.rounded,
    this.optical = true,
    this.petals = 8,
    required this.child,
  });

  final AppContainer container;
  final double radius;

  /// A folder's own outline on the home screen; rounded everywhere else.
  final FolderShape folderShape;

  /// A triangle reaches past its box to look its size (folders); false for
  /// containers, kept to their cells (see RoundedTriangleBorder.optical).
  final bool optical;

  /// A flower's petals (see AppContainerTile.petalsFor).
  final int petals;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final decoration = AppContainerTile.decoration(
      radius,
      container.style,
      container.color,
      folderShape,
      optical,
      petals,
    );
    final panel = DecoratedBox(decoration: decoration, child: child);
    return switch (container.style) {
      GroupStyle.glass => WallpaperGlass(shape: decoration.shape, child: panel),
      _ => panel,
    };
  }
}

/// Where a container's icons sit: [perRow] × [rows] spots in [area], [gapX]
/// apart across (and from its sides) and [gapY] down (see
/// AppContainerTile.iconsIn).
@immutable
class ContainerIcons {
  const ContainerIcons(this.area, this.iconSize, this.perRow, this.rows, this.gapX, this.gapY);

  final Rect area;
  final double iconSize;
  final int perRow;
  final int rows;
  final double gapX;
  final double gapY;

  int get capacity => perRow * rows;

  /// Spot [i], filled row by row.
  Rect rectOf(int i) => Rect.fromLTWH(
    area.left + gapX + (i % perRow) * (iconSize + gapX),
    area.top + gapY + (i ~/ perRow) * (iconSize + gapY),
    iconSize,
    iconSize,
  );
}
