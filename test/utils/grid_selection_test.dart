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

  group('hitsTile', () {
    bool at(Offset point, {int count = 9}) => hitsTile(
      point,
      origin: origin,
      columns: 3,
      tile: tile,
      spacing: spacing,
      count: count,
    );

    test('a click on a tile is not empty space', () {
      expect(at(const Offset(60, 60)), isTrue);
    });

    test('a click past the last row is empty space', () {
      expect(at(const Offset(60, 900)), isFalse);
      // Seven wallpapers, so the last row holds one and the rest of it is bare.
      expect(at(const Offset(180, 300), count: 7), isFalse);
    });

    test('a click left of the first column is empty space', () {
      expect(at(const Offset(2, 60)), isFalse);
    });

    // Treating the seam as empty space threw the whole selection away.
    test('a click in the seam between two tiles counts as a tile', () {
      expect(at(const Offset(125, 60)), isTrue);
      expect(at(const Offset(60, 115)), isTrue);
    });

    test('an empty grid is empty space', () {
      expect(at(const Offset(60, 60), count: 0), isFalse);
    });
  });

  group('SelectionEngine', () {
    const SelectionEngine<String> selection = SelectionEngine<String>();
    const List<String> ids = <String>['a', 'b', 'c', 'd', 'e'];

    test('plain click selects one and clicking it again clears it', () {
      expect(
        selection.click(
          ordered: ids,
          current: <String>{'a', 'c'},
          target: 1,
          control: false,
          shift: false,
        ),
        <String>{'b'},
      );
      expect(
        selection.click(
          ordered: ids,
          current: <String>{'b'},
          target: 1,
          control: false,
          shift: false,
        ),
        isEmpty,
      );
    });

    test('ctrl toggles without dropping the rest of the selection', () {
      expect(
        selection.click(
          ordered: ids,
          current: <String>{'a', 'c'},
          target: 3,
          control: true,
          shift: false,
        ),
        <String>{'a', 'c', 'd'},
      );
      expect(
        selection.click(
          ordered: ids,
          current: <String>{'a', 'c'},
          target: 2,
          control: true,
          shift: false,
        ),
        <String>{'a'},
      );
    });

    test('shift replaces the current selection with the anchor range', () {
      expect(
        selection.click(
          ordered: ids,
          current: <String>{'e'},
          target: 3,
          control: false,
          shift: true,
          anchor: 'b',
        ),
        <String>{'b', 'c', 'd'},
      );
    });

    test('ctrl+shift adds the anchor range to the current selection', () {
      expect(
        selection.click(
          ordered: ids,
          current: <String>{'a'},
          target: 3,
          control: true,
          shift: true,
          anchor: 'b',
        ),
        <String>{'a', 'b', 'c', 'd'},
      );
    });

    test('an identity anchor follows its item through a re-order', () {
      expect(
        selection.click(
          ordered: const <String>['d', 'c', 'b', 'a'],
          current: <String>{'a', 'd'},
          target: 2,
          control: false,
          shift: true,
          anchor: 'd',
        ),
        <String>{'d', 'c', 'b'},
      );
    });

    test('marquee replaces normally and adds while ctrl is held', () {
      expect(
        selection.marquee(
          current: <String>{'e'},
          hits: <String>['a', 'b'],
          additive: false,
        ),
        <String>{'a', 'b'},
      );
      expect(
        selection.marquee(
          current: <String>{'e'},
          hits: <String>['a', 'b'],
          additive: true,
        ),
        <String>{'a', 'b', 'e'},
      );
    });

    test('empty-space clearing is suppressed by modifiers or an item hit', () {
      expect(
        selection.clearsOnEmpty(control: false, shift: false, hitItem: false),
        isTrue,
      );
      expect(
        selection.clearsOnEmpty(control: true, shift: false, hitItem: false),
        isFalse,
      );
      expect(
        selection.clearsOnEmpty(control: false, shift: true, hitItem: false),
        isFalse,
      );
      expect(
        selection.clearsOnEmpty(control: false, shift: false, hitItem: true),
        isFalse,
      );
    });
  });

  group('FileTreeSelectionAdapter', () {
    final FileTreeSelectionAdapter<String> selection =
        FileTreeSelectionAdapter<String>();
    const List<String> visible = <String>['a.txt', 'b.txt', 'c.txt', 'd.txt'];

    test(
      'plain click selects one row and moves the anchor to its identity',
      () {
        final result = selection.click(
          visible: visible,
          current: <String>{'a.txt', 'c.txt'},
          target: 'b.txt',
          control: false,
          shift: false,
          anchor: 'a.txt',
        );

        expect(result.selected, <String>{'b.txt'});
        expect(result.anchor, 'b.txt');
      },
    );

    test(
      'plain click on the only selected row clears selection and anchor',
      () {
        final result = selection.click(
          visible: visible,
          current: <String>{'b.txt'},
          target: 'b.txt',
          control: false,
          shift: false,
          anchor: 'b.txt',
        );

        expect(result.selected, isEmpty);
        expect(result.anchor, isNull);
      },
    );

    test('ctrl toggles one row and makes it the next Shift anchor', () {
      final result = selection.click(
        visible: visible,
        current: <String>{'a.txt', 'c.txt'},
        target: 'c.txt',
        control: true,
        shift: false,
        anchor: 'a.txt',
      );

      expect(result.selected, <String>{'a.txt'});
      expect(result.anchor, 'c.txt');
    });

    test('shift uses visible row order and preserves the identity anchor', () {
      final result = selection.click(
        visible: visible,
        current: <String>{'d.txt'},
        target: 'c.txt',
        control: false,
        shift: true,
        anchor: 'a.txt',
      );

      expect(result.selected, <String>{'a.txt', 'b.txt', 'c.txt'});
      expect(result.anchor, 'a.txt');
    });

    test('ctrl+shift adds the visible anchor range', () {
      final result = selection.click(
        visible: visible,
        current: <String>{'d.txt'},
        target: 'c.txt',
        control: true,
        shift: true,
        anchor: 'a.txt',
      );

      expect(result.selected, <String>{'a.txt', 'b.txt', 'c.txt', 'd.txt'});
      expect(result.anchor, 'a.txt');
    });

    test('collapsed descendants stay out of Shift ranges', () {
      const List<String> collapsed = <String>['a.txt', 'c.txt'];
      final result = selection.click(
        visible: collapsed,
        current: <String>{'a.txt'},
        target: 'c.txt',
        control: false,
        shift: true,
        anchor: 'a.txt',
      );

      expect(result.selected, <String>{'a.txt', 'c.txt'});
      expect(result.selected, isNot(contains('b.txt')));
    });

    test('a target outside the visible tree leaves state unchanged', () {
      final result = selection.click(
        visible: visible,
        current: <String>{'a.txt', 'b.txt'},
        target: 'hidden.txt',
        control: false,
        shift: false,
        anchor: 'a.txt',
      );

      expect(result.selected, <String>{'a.txt', 'b.txt'});
      expect(result.anchor, 'a.txt');
    });

    test('plain empty-space click clears while modifiers preserve state', () {
      final cleared = selection.emptySpaceClick(
        current: <String>{'a.txt', 'b.txt'},
        control: false,
        shift: false,
        anchor: 'b.txt',
      );
      final ctrl = selection.emptySpaceClick(
        current: <String>{'a.txt', 'b.txt'},
        control: true,
        shift: false,
        anchor: 'b.txt',
      );
      final shift = selection.emptySpaceClick(
        current: <String>{'a.txt', 'b.txt'},
        control: false,
        shift: true,
        anchor: 'b.txt',
      );

      expect(cleared.selected, isEmpty);
      expect(cleared.anchor, isNull);
      expect(ctrl.selected, <String>{'a.txt', 'b.txt'});
      expect(ctrl.anchor, 'b.txt');
      expect(shift.selected, <String>{'a.txt', 'b.txt'});
      expect(shift.anchor, 'b.txt');
    });
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

  group('shiftRange', () {
    test('an anchor above the click extends down to it', () {
      expect(shiftRange(anchor: 2, target: 7, count: 10), (begin: 2, end: 7));
    });

    test('an anchor below the click extends up to it', () {
      expect(shiftRange(anchor: 7, target: 2, count: 10), (begin: 2, end: 7));
    });

    test('an anchor past the end of a filtered list is pulled back in', () {
      // 40 wallpapers were showing when the anchor was taken; the filter now
      // leaves 5. Unclamped this slices past the end and throws RangeError.
      expect(shiftRange(anchor: 37, target: 1, count: 5), (begin: 1, end: 4));
    });

    test('a click below an anchor that is past the end still starts at it', () {
      expect(shiftRange(anchor: 37, target: 4, count: 5), (begin: 4, end: 4));
    });

    test('nothing checked selects everything up to the click', () {
      expect(shiftRange(anchor: null, target: 3, count: 10), (
        begin: 0,
        end: 3,
      ));
    });

    test(
      'an anchor on a wallpaper the filter dropped selects from the top',
      () {
        // indexOf returns -1 for a checked wallpaper no longer in the list.
        expect(shiftRange(anchor: -1, target: 3, count: 10), (
          begin: 0,
          end: 3,
        ));
      },
    );

    test('an empty list yields a range that slices to nothing', () {
      final range = shiftRange(anchor: 4, target: 0, count: 0);
      expect(<String>[].sublist(range.begin, range.end + 1), isEmpty);
    });
  });
}
