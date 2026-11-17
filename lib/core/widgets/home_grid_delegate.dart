import 'package:flutter/rendering.dart';

import '../theme/home_grid.dart';

/// Lays a scrolling grid of app tiles out like the home screen: [grid]'s
/// columns, and cells as tall as wide (taller only if a tile needs it), so
/// apps are spaced the same everywhere (see [HomeGrid.cellHeightFor]).
class HomeGridDelegate extends SliverGridDelegate {
  const HomeGridDelegate(this.grid);

  final HomeGrid grid;

  @override
  SliverGridLayout getLayout(SliverConstraints constraints) {
    final width = constraints.crossAxisExtent / grid.columns;
    final height = grid.cellHeightFor(width);
    return SliverGridRegularTileLayout(
      crossAxisCount: grid.columns,
      mainAxisStride: height,
      crossAxisStride: width,
      childMainAxisExtent: height,
      childCrossAxisExtent: width,
      reverseCrossAxis: axisDirectionIsReversed(constraints.crossAxisDirection),
    );
  }

  @override
  bool shouldRelayout(HomeGridDelegate oldDelegate) => oldDelegate.grid != grid;
}
