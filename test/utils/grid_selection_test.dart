import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:we_repkg/utils/grid_selection.dart';

void main() {
  // A 3-wide grid of 100px tiles, 10px apart, starting at (20, 10). Columns sit
  // at x 20, 130, 240; rows at y 10, 120, 230.
  const Offset origin = Offset(20, 10);
  const double tile = 100;
  const double spacing = 10;

  Set<int> hit(Rect box, {int count = 9, int columns = 3}) => coveredTiles(
    box,
    origin: origin,
    columns: columns,
    tile: tile,
    spacing: spacing,
    count: count,
  );

  test('a box over one tile picks only that tile', () {
    expect(hit(const Rect.fromLTWH(140, 130, 20, 20)), <int>{4});
  });

  test('a box spanning two columns picks both', () {
    expect(hit(const Rect.fromLTWH(90, 30, 100, 20)), <int>{0, 1});
  });

  test('a box in the gap between tiles picks nothing', () {
    // x 120..130 and y 110..120 are spacing, owned by no tile.
    expect(hit(const Rect.fromLTWH(121, 111, 8, 8)), isEmpty);
  });

  test('a box over everything picks every tile', () {
    expect(hit(const Rect.fromLTWH(0, 0, 1000, 1000)), <int>{
      0, 1, 2, 3, 4, 5, 6, 7, 8, //
    });
  });

  test('a short last row stops at the end of the list', () {
    // Seven wallpapers in a 3-wide grid: the last row holds one.
    expect(hit(const Rect.fromLTWH(0, 230, 1000, 100), count: 7), <int>{6});
  });

  test('dragging past the last row picks nothing extra', () {
    expect(hit(const Rect.fromLTWH(0, 900, 1000, 100), count: 7), isEmpty);
  });

  test('a box left of the grid picks nothing', () {
    expect(hit(const Rect.fromLTWH(0, 30, 15, 20)), isEmpty);
  });

  test('an empty library is not an error', () {
    expect(hit(const Rect.fromLTWH(0, 0, 1000, 1000), count: 0), isEmpty);
  });

  test('touching a single pixel of a tile counts', () {
    // Tile 0 ends at x 120. A box starting at 119 still clips it.
    expect(hit(const Rect.fromLTWH(119, 30, 2, 20)), <int>{0});
  });

  group('cellOrigin', () {
    Offset at(int index) =>
        cellOrigin(index, columns: 4, tile: 100, spacing: 8);

    test('walks across a row then wraps', () {
      expect(at(0), Offset.zero);
      expect(at(1), const Offset(108, 0));
      expect(at(3), const Offset(324, 0));
      expect(at(4), const Offset(0, 108));
      expect(at(9), const Offset(108, 216));
    });

    // The reflow slides a tile by the difference between two of these, and the
    // marquee hit-tests against the same stride. If they drift apart the box
    // selects one wallpaper while the animation moves another.
    test('agrees with the stride coveredTiles walks', () {
      const Offset origin = Offset(16, 12);
      for (final int index in <int>[0, 5, 7, 11]) {
        final Offset cell = at(index) + origin;
        expect(
          coveredTiles(
            Rect.fromLTWH(cell.dx + 1, cell.dy + 1, 2, 2),
            origin: origin,
            columns: 4,
            tile: 100,
            spacing: 8,
            count: 12,
          ),
          <int>{index},
          reason: 'index $index',
        );
      }
    });

    test('treats a zero column count as one', () {
      expect(
        cellOrigin(2, columns: 0, tile: 100, spacing: 8),
        const Offset(0, 216),
      );
    });
  });
}
