import 'dart:math' as math;

/// App-grid presets: how many apps per row, and the icon and label sizes that
/// go with that many.
///
/// Sources:
/// - Android's own launcher (AOSP Launcher3, res/xml/device_profiles.xml)
///   gives phone grids of 4 and 5 columns with icons of 48–56dp; 6 columns
///   appears only on tablets there. 4 and 5 columns both use 52dp, one 4dp
///   step below Launcher3's largest, so eight rows fit; 5 columns then has
///   ~22dp between icons (Launcher3's 5-column 48dp leaves ~26dp). 6 (a
///   dense phone grid it doesn't define) uses 44dp, the smallest step on the
///   4dp grid that's still a comfortable tap target on its own.
/// - The 4- and 5-column grids have a fixed 8 rows ([rows]) that share the
///   whole height: square cells left most of a row empty above the dock (7
///   rows of ~93dp in ~722dp). Rows come out ~90dp on a 20:9 phone. Where 8
///   don't fit (a short screen, landscape) it falls back to as many square
///   rows as fit.
/// - Spacing: cells are as tall as they are wide, so icons are exactly as far
///   apart down as across (the even rhythm of iOS and Pixel home screens).
///   Only where a tile (icon + label) wouldn't fit is a cell made taller.
///   Rows are then as many as the screen's height holds, which on a phone
///   is more rows than columns (e.g. 5 × 7 on a 20:9 screen; see [rowsFor]).
/// - Labels use the Material 3 type scale: Label Medium (12sp, 16 line) with
///   large icons, Label Small (11sp, 16 line) with the denser grids.
/// - Every tap target (a whole grid cell) stays at least 48 × 48dp, the
///   Material / Android accessibility minimum.
/// - The dock holds 5 apps, or 6 with the 6-column grid: one under each
///   column, like Android's hotseat.
enum HomeGrid {
  large(columns: 4, baseIconSize: 52, labelSize: 12, label: 'Large', dockApps: 5, rows: 8),
  medium(columns: 5, baseIconSize: 52, labelSize: 11, label: 'Medium', dockApps: 5, rows: 8),
  compact(columns: 6, baseIconSize: 44, labelSize: 11, label: 'Compact', dockApps: 6);

  const HomeGrid({
    required this.columns,
    required this.baseIconSize,
    required this.labelSize,
    required this.label,
    required this.dockApps,
    this.rows,
  });

  final int columns;

  /// The grid's own icon size, before [iconScale].
  final double baseIconSize;

  /// App icon size: the grid's, scaled by the user's icon size setting
  /// ([iconScale]), to whole dp.
  double get iconSize => (baseIconSize * iconScale).roundToDouble();

  /// The user's app icon size, as a factor of the grid's (see
  /// HomeLayoutController.setIconScale, which sets it and redraws
  /// everything): from [minIconScale] to [maxIconScale]. Kept within ±15%
  /// so every tile still fits its cell and the gaps stay comfortable.
  static double iconScale = 1;
  static const minIconScale = 0.85;
  static const maxIconScale = 1.15;
  final double labelSize;
  final String label;

  /// Most apps the dock holds with this grid.
  final int dockApps;

  /// A fixed number of rows sharing the grid's whole height; null for as
  /// many square rows as fit (see [rowsFor], [cellHeightIn]).
  final int? rows;

  /// Whether the fixed [rows] fit in [height]: each gets at least a tile.
  bool _fixedRowsFit(double height) => rows != null && height / rows! >= tileHeight;

  /// Line height of an app label (Material 3 Label Small / Medium).
  static const labelLineHeight = 16.0;

  /// Least space between one tile's label and the next tile.
  static const minRowGap = 4.0;

  /// Height of an app tile: padding, icon, gap, one label line, padding.
  double get tileHeight => 8 + iconSize + 6 + labelLineHeight + 8;

  /// Height of a cell [cellWidth] wide: square (equal spacing down and
  /// across), unless a tile needs more.
  double cellHeightFor(double cellWidth) => math.max(cellWidth, tileHeight + minRowGap);

  /// Rows of cells [cellWidth] wide that fit in [height]: the fixed [rows]
  /// if they fit, otherwise as many square rows as fit.
  int rowsFor(double height, double cellWidth) =>
      _fixedRowsFit(height) ? rows! : math.max(1, (height / cellHeightFor(cellWidth)).floor());

  /// Height of a home-grid cell [cellWidth] wide in a grid [height] tall:
  /// an equal share of the height with fixed [rows] (no space left over),
  /// otherwise [cellHeightFor].
  double cellHeightIn(double height, double cellWidth) =>
      _fixedRowsFit(height) ? height / rows! : cellHeightFor(cellWidth);

  /// "4 × 7" style name for a grid area of [width] × [height].
  String sizeIn(double width, double height) => '$columns × ${rowsFor(height, width / columns)}';

  static HomeGrid fromName(String? name) => values.asNameMap()[name] ?? large;
}
