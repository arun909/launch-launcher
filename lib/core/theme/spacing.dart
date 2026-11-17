/// Layout spacing shared by app-listing surfaces, on Material's 8dp grid.
///
/// - [screenMargin]: space between the screen edge and content (Material 3
///   uses 16 for compact windows and 24 for medium; a launcher grid with
///   few, large targets reads calmer with more).
/// - [gutter]: space between neighbouring items.
///   Grids give each item half of it on every side, so two items end up a
///   full gutter apart and the outer items [screenMargin] from the edge.
abstract final class Spacing {
  static const screenMargin = 32.0;
  static const gutter = 24.0;
  static const halfGutter = gutter / 2;
}
