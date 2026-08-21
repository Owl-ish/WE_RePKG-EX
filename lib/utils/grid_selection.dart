import 'dart:math';
import 'dart:ui';

/// Domain-agnostic selection transitions shared by selectable surfaces.
///
/// The surface still owns hit testing and selection storage. This engine only
/// decides how plain clicks, Ctrl toggles, Shift ranges, marquee hits, and
/// empty-space clicks transform a caller-owned set of item ids.
class SelectionEngine<T> {
  const SelectionEngine({this.plainClickTogglesSingle = true});

  final bool plainClickTogglesSingle;

  /// Applies one primary-button click to [current].
  ///
  /// Shift replaces the current selection with the anchor-to-target range.
  /// Ctrl+Shift adds that range instead. [anchor] is the item identity rather
  /// than its position, so sorting or filtering cannot silently move it.
  Set<T> click({
    required List<T> ordered,
    required Set<T> current,
    required int target,
    required bool control,
    required bool shift,
    T? anchor,
  }) {
    if (target < 0 || target >= ordered.length) return current.toSet();
    final T id = ordered[target];

    if (shift) {
      final int held = anchor == null ? -1 : ordered.indexOf(anchor);
      final int fallback = ordered.lastIndexWhere(current.contains);
      final int? anchorIndex = held >= 0
          ? held
          : (fallback >= 0 ? fallback : null);
      final ({int begin, int end}) range = shiftRange(
        anchor: anchorIndex,
        target: target,
        count: ordered.length,
      );
      final Set<T> rangeIds = <T>{
        for (int i = range.begin; i <= range.end; i++) ordered[i],
      };
      return control ? <T>{...current, ...rangeIds} : rangeIds;
    }

    if (control) {
      final Set<T> next = current.toSet();
      next.contains(id) ? next.remove(id) : next.add(id);
      return next;
    }

    if (plainClickTogglesSingle &&
        current.length == 1 &&
        current.contains(id)) {
      return <T>{};
    }
    return <T>{id};
  }

  /// Applies the items touched by a drag/marquee selection.
  Set<T> marquee({
    required Set<T> current,
    required Iterable<T> hits,
    required bool additive,
  }) {
    final Set<T> touched = hits.toSet();
    return additive ? <T>{...current, ...touched} : touched;
  }

  /// Whether an empty-space primary click should put the selection down.
  bool clearsOnEmpty({
    required bool control,
    required bool shift,
    required bool hitItem,
  }) => !control && !shift && !hitItem;
}

/// Selection result returned by [FileTreeSelectionAdapter].
typedef FileTreeSelectionState<T> = ({Set<T> selected, T? anchor});

/// Adapts [SelectionEngine] to the visible linear order of an expandable tree.
///
/// The tree still owns expansion, row hit testing, keyboard navigation, focus,
/// and selection storage. Callers pass only the currently visible/selectable row
/// ids, so collapsed descendants cannot accidentally enter a Shift range.
class FileTreeSelectionAdapter<T> {
  FileTreeSelectionAdapter() : _selection = SelectionEngine<T>();

  final SelectionEngine<T> _selection;

  /// Applies a click to [target] using the tree's current visible row order.
  ///
  /// Anchors follow the same identity-based rules used by the grids: Ctrl moves
  /// the anchor to the clicked row, plain click moves or clears it, and Shift
  /// keeps the existing anchor.
  FileTreeSelectionState<T> click({
    required List<T> visible,
    required Set<T> current,
    required T target,
    required bool control,
    required bool shift,
    T? anchor,
  }) {
    final int index = visible.indexOf(target);
    if (index < 0) {
      return (selected: current.toSet(), anchor: anchor);
    }

    final Set<T> selected = _selection.click(
      ordered: visible,
      current: current,
      target: index,
      control: control,
      shift: shift,
      anchor: anchor,
    );

    T? nextAnchor = anchor;
    if (control && !shift) {
      nextAnchor = target;
    } else if (!shift) {
      nextAnchor = selected.isEmpty ? null : target;
    }

    return (selected: selected, anchor: nextAnchor);
  }

  /// Applies a primary click that tree hit testing already classified as empty.
  FileTreeSelectionState<T> emptySpaceClick({
    required Set<T> current,
    required bool control,
    required bool shift,
    T? anchor,
  }) {
    if (!_selection.clearsOnEmpty(
      control: control,
      shift: shift,
      hitItem: false,
    )) {
      return (selected: current.toSet(), anchor: anchor);
    }
    return (selected: <T>{}, anchor: null);
  }
}

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

/// Whether [point] lands on a tile, or in the seam beside one, in grid
/// coordinates.
///
/// The seams count, unlike in [coveredTiles]: a near miss between two tiles is
/// not somewhere the user aimed.
bool hitsTile(
  Offset point, {
  required Offset origin,
  required int columns,
  required double tile,
  required double spacing,
  required int count,
}) {
  // Half the gap, and a pixel over so the two edges meet rather than abut.
  final double reach = (spacing / 2) + 1;
  return coveredTiles(
    Rect.fromLTWH(point.dx - reach, point.dy - reach, reach * 2, reach * 2),
    origin: origin,
    columns: columns,
    tile: tile,
    spacing: spacing,
    count: count,
  ).isNotEmpty;
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
