import 'dart:math';
import 'dart:ui';

/// Indices of the tiles a rectangle touches, in a grid of equal square tiles.
///
/// [box] and [origin] are in grid coordinates: the viewport plus however far
/// the list has scrolled. Mirrors what SliverGridDelegateWithMaxCrossAxisExtent
/// lays out, so asking the widgets where they are would cost a tree walk per
/// pointer move to learn what a division already says.
Set<int> coveredTiles(
  Rect box, {
  required Offset origin,
  required int columns,
  required double tile,
  required double spacing,
  required int count,
}) {
  if (count <= 0 || columns <= 0) return const <int>{};

  final double step = tile + spacing;
  final int firstColumn = ((box.left - origin.dx) / step).floor().clamp(
    0,
    columns - 1,
  );
  final int lastColumn = ((box.right - origin.dx) / step).floor().clamp(
    0,
    columns - 1,
  );
  final int firstRow = max(0, ((box.top - origin.dy) / step).floor());
  final int lastRow = max(0, ((box.bottom - origin.dy) / step).floor());

  final Set<int> hit = <int>{};
  for (int row = firstRow; row <= lastRow; row++) {
    for (int column = firstColumn; column <= lastColumn; column++) {
      final int index = (row * columns) + column;
      if (index >= count) return hit;
      // The gaps between tiles belong to no tile, so a rectangle sitting
      // entirely in one selects nothing.
      final Rect cell = Rect.fromLTWH(
        origin.dx + (column * step),
        origin.dy + (row * step),
        tile,
        tile,
      );
      if (cell.overlaps(box)) hit.add(index);
    }
  }
  return hit;
}
