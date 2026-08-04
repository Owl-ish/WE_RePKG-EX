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

/// The inclusive range of tiles a shift-click covers, for `sublist(begin, end + 1)`.
///
/// [anchor] is where the range starts, taken from the last ctrl-click or the
/// last checked tile, and is null when nothing is checked. It can point past
/// the end, or at -1 for a tile no longer in the list, because changing the
/// filter or the search term reshuffles the list it was recorded against.
({int begin, int end}) shiftRange({
  required int? anchor,
  required int target,
  required int count,
}) {
  // end below begin, so the caller's sublist comes out empty.
  if (count <= 0) return (begin: 0, end: -1);
  final int start = anchor ?? 0;
  final int begin = min(start, target).clamp(0, count - 1);
  return (begin: begin, end: max(start, target).clamp(begin, count - 1));
}

/// Top-left of the cell at [index], relative to the first cell.
///
/// Mirrors the same stride [coveredTiles] walks, so the marquee and the search
/// reflow cannot disagree about where a wallpaper sits.
Offset cellOrigin(
  int index, {
  required int columns,
  required double tile,
  required double spacing,
}) {
  final int stride = columns < 1 ? 1 : columns;
  final double step = tile + spacing;
  return Offset((index % stride) * step, (index ~/ stride) * step);
}
