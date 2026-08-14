import 'dart:math';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:we_repkg/constants/i10n.dart';
import 'package:we_repkg/constants/nums.dart';
import 'package:we_repkg/utils/grid_selection.dart';
import 'package:we_repkg/utils/modifier_keys.dart';
import 'package:we_repkg/widgets/scroll_edge_controls.dart';
import 'package:we_repkg/widgets/smooth_wheel_scroll.dart';

/// Where the grid put its tiles, for a caller that has to place something of its
/// own against the same cells.
typedef GridGeometry = ({int columns, double tile, double spacing});

/// A scrolling grid of equal square tiles that can be selected by dragging a box
/// over it.
///
/// Owns the scrolling, the marquee, the autoscroll at the edges and the endpoint
/// buttons. It knows nothing about what a tile holds: the caller supplies the
/// widget, the ids the selection is written in, and where to write it.
class SelectionGrid extends StatefulWidget {
  const SelectionGrid({
    super.key,
    required this.id,
    required this.itemCount,
    required this.idAt,
    required this.itemBuilder,
    required this.currentSelection,
    required this.onSelectionChanged,
    this.padding = const EdgeInsets.symmetric(
      horizontal: LayoutNums.edgeInset,
      vertical: LayoutNums.contentGap,
    ),
  });

  /// Names this grid's stored scroll position, and labels its controller.
  final String id;

  final int itemCount;

  /// The id of the tile at [index], which is what a selection is written in.
  final String Function(int index) idAt;

  final Widget Function(BuildContext context, int index, GridGeometry geometry)
  itemBuilder;

  /// Read when a ctrl-drag starts, so the box adds to what is already selected.
  /// A callback rather than a value: reading it up front would tie the grid to
  /// the selection and rebuild every tile on every write.
  final Set<String> Function() currentSelection;

  /// A drag writes after the frame, so its last write can arrive once this grid
  /// has gone; a click writes as it happens. Guard it on the caller's own
  /// lifetime, not the grid's.
  final void Function(Set<String> ids) onSelectionChanged;

  /// Inset around the tiles. The marquee measures from here, so a caller that
  /// is already inside a padded area passes its own rather than being indented
  /// twice.
  final EdgeInsets padding;

  @override
  State<SelectionGrid> createState() => _SelectionGridState();
}

class _SelectionGridState extends State<SelectionGrid>
    with TickerProviderStateMixin {
  late final SmoothWheelScrollController _scrollController;
  late final ValueNotifier<bool> _topScrollControlActive;
  late final ValueNotifier<bool> _bottomScrollControlActive;

  /// Drag rectangle in grid coordinates, so it stays on the tiles under it while
  /// the list scrolls. A notifier, or repainting it would rebuild two thousand
  /// tiles behind it.
  final ValueNotifier<Rect?> _marquee = ValueNotifier<Rect?>(null);

  Offset? _dragFrom;

  /// Where the last press landed, in grid coordinates. See [_clearIfEmpty].
  Offset? _tapAt;

  /// Viewport coordinates, so autoscroll can redraw without the mouse moving.
  Offset _dragPointer = Offset.zero;

  /// Null until the drag has worked a rectangle out, so a drag that covers
  /// nothing still writes once and puts the selection down.
  Set<String>? _dragIds;

  /// Selection the drag started from, kept when ctrl is held so a marquee adds
  /// rather than replaces. A click that twitches a pixel starts a drag, so
  /// replacing here is how a ctrl-click loses everything picked so far.
  Set<String> _dragBaseline = <String>{};

  /// Latest set the drag has worked out, waiting for the queued write.
  Set<String> _dragWanted = <String>{};
  bool _dragWriteQueued = false;

  /// A ticker, not a timer: a 16ms timer beats against vsync, so twice a second
  /// two ticks land in one frame and the grid lurches, and the speed ends up
  /// depending on the monitor's refresh rate.
  Ticker? _autoScroll;
  Duration _lastTick = Duration.zero;

  /// Grid geometry, refreshed by the builder. The ticker cannot close over the
  /// builder's locals: it outlives the rebuild that made them, and the grid
  /// rebuilds on every selection write.
  double _viewportHeight = 0;
  int _columns = 1;
  double _tileExtent = 0;

  static const double _autoScrollZone = 60;
  static const double _autoScrollSpeed = 1100;

  static const double _spacing = 8;
  static const double _maxExtent = 180;

  @override
  void initState() {
    super.initState();
    _scrollController = SmoothWheelScrollController(debugLabel: widget.id);
    _topScrollControlActive = ValueNotifier<bool>(false);
    _bottomScrollControlActive = ValueNotifier<bool>(false);
  }

  @override
  void dispose() {
    _autoScroll?.dispose();
    _marquee.dispose();
    _topScrollControlActive.dispose();
    _bottomScrollControlActive.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Widget _scrollControlHoverZone({
    required ValueNotifier<bool> active,
    required ScrollEdge edge,
    required String tooltip,
  }) {
    return MouseRegion(
      opaque: false,
      hitTestBehavior: HitTestBehavior.translucent,
      onEnter: (_) => active.value = true,
      onExit: (_) => active.value = false,
      child: SizedBox(
        width: 112,
        height: 80,
        child: Center(
          child: ScrollEdgeButton(
            controller: _scrollController,
            active: active,
            edge: edge,
            tooltip: tooltip,
          ),
        ),
      ),
    );
  }

  /// Viewport point to grid point: the grid keeps scrolling under the pointer,
  /// so the rectangle is stored against the tiles, not the window.
  Offset _toGrid(Offset local) => local + Offset(0, _scrollController.offset);

  void _updateDrag() {
    final Offset? from = _dragFrom;
    if (from == null) return;
    final Rect box = Rect.fromPoints(from, _toGrid(_dragPointer));
    _marquee.value = box;

    final Set<String> ids = coveredTiles(
      box,
      origin: widget.padding.topLeft,
      columns: _columns,
      tile: _tileExtent,
      spacing: _spacing,
      count: widget.itemCount,
    ).map(widget.idAt).toSet();
    if (_dragIds != null && setEquals(ids, _dragIds)) return;
    _dragIds = ids;
    _dragWanted = _dragBaseline.isEmpty
        ? ids
        : <String>{..._dragBaseline, ...ids};

    // One write per frame. Each one refilters and re-sorts the whole library,
    // and a fast mouse reports twice a frame. The callback reads the field
    // rather than closing over a set, or the second report of a frame would be
    // dropped and the selection would sit a rectangle behind the marquee.
    if (_dragWriteQueued) return;
    _dragWriteQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _dragWriteQueued = false;
      widget.onSelectionChanged(_dragWanted);
    });
  }

  /// Puts the selection down when a click lands past the tiles.
  ///
  /// Where the pointer went down decides, not which widget won the gesture: a
  /// tile's recogniser can hand the tap back while the tree is coming apart
  /// under it, and clearing on that would wipe the selection on a rebuild.
  void _clearIfEmpty() {
    final Offset? at = _tapAt;
    _tapAt = null;
    // A modifier is held to build a selection up, so a miss with one down is a
    // miss, not an instruction to put everything down.
    if (isCtrlPressed || isShiftPressed) return;
    if (at == null ||
        hitsTile(
          at,
          origin: widget.padding.topLeft,
          columns: _columns,
          tile: _tileExtent,
          spacing: _spacing,
          count: widget.itemCount,
        )) {
      return;
    }
    widget.onSelectionChanged(const <String>{});
  }

  /// Drag near an edge and the grid keeps scrolling, faster the closer you get,
  /// so a selection can run past one screenful.
  void _autoScrollTick(Duration elapsed) {
    final double seconds =
        (elapsed - _lastTick).inMicroseconds / Duration.microsecondsPerSecond;
    _lastTick = elapsed;
    if (!_scrollController.hasClients || seconds <= 0) return;

    final double overTop = _autoScrollZone - _dragPointer.dy;
    final double overBottom =
        _dragPointer.dy - (_viewportHeight - _autoScrollZone);
    final double push = overTop > 0 ? -overTop : max(0, overBottom);
    if (push == 0) return;

    final ScrollPosition at = _scrollController.position;
    final double step =
        (push / _autoScrollZone).clamp(-1, 1) * _autoScrollSpeed * seconds;
    final double next = (at.pixels + step).clamp(
      at.minScrollExtent,
      at.maxScrollExtent,
    );
    if (next == at.pixels) return;
    _scrollController.jumpTo(next);
    _updateDrag();
  }

  void _startAutoScroll() {
    if (_autoScroll != null) return;
    _lastTick = Duration.zero;
    _autoScroll = createTicker(_autoScrollTick)..start();
  }

  void _endDrag() {
    _autoScroll?.dispose();
    _autoScroll = null;
    _dragFrom = null;
    _marquee.value = null;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double gridWidth =
            (constraints.maxWidth - widget.padding.horizontal).clamp(
              0,
              double.infinity,
            );
        final int columnCount = (gridWidth / (_maxExtent + _spacing))
            .ceil()
            .clamp(1, 1000);

        final double tile =
            (gridWidth - (_spacing * (columnCount - 1))) / columnCount;

        _viewportHeight = constraints.maxHeight;
        _columns = columnCount;
        _tileExtent = tile;

        final GridGeometry geometry = (
          columns: columnCount,
          tile: tile,
          spacing: _spacing,
        );

        return Stack(
          children: [
            // Mouse drags do not scroll a desktop list, so a pan here is free
            // to mean selection. A tap on a tile resolves before this sees any
            // movement.
            GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTapDown: (d) => _tapAt = _toGrid(d.localPosition),
              onTap: _clearIfEmpty,
              onTapCancel: () => _tapAt = null,
              // Anchor the box where the button went down, not where the pan
              // won the arena, which on a fast drag is a tile or two away.
              dragStartBehavior: DragStartBehavior.down,
              onPanStart: (d) {
                _dragPointer = d.localPosition;
                _dragFrom = _toGrid(d.localPosition);
                // Cleared per drag, or repeating a rectangle matches the last
                // drag's set and writes nothing.
                _dragIds = null;
                _dragBaseline = isCtrlPressed
                    ? widget.currentSelection()
                    : <String>{};
              },
              onPanUpdate: (d) {
                _dragPointer = d.localPosition;
                // Armed here rather than on pan start: pressing inside the
                // bottom band and twitching a pixel would otherwise scroll away
                // on its own.
                _startAutoScroll();
                _updateDrag();
              },
              onPanEnd: (_) => _endDrag(),
              onPanCancel: _endDrag,
              child: GridView.builder(
                key: PageStorageKey<String>(widget.id),
                controller: _scrollController,
                itemCount: widget.itemCount,
                padding: widget.padding,
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  crossAxisSpacing: _spacing,
                  mainAxisSpacing: _spacing,
                  maxCrossAxisExtent: _maxExtent,
                ),
                scrollCacheExtent: const ScrollCacheExtent.pixels(500),
                // No tile keeps itself alive, so the wrapper is pure overhead.
                addAutomaticKeepAlives: false,
                itemBuilder: (context, index) =>
                    widget.itemBuilder(context, index, geometry),
              ),
            ),
            // Watches the scroll position too, or a wheel scroll mid-drag
            // leaves the rectangle stuck to the viewport.
            ListenableBuilder(
              listenable: Listenable.merge([_marquee, _scrollController]),
              builder: (context, _) {
                final Rect? box = _marquee.value;
                if (box == null) return const SizedBox.shrink();
                final Color colour = Theme.of(context).primaryColor;
                return Positioned.fromRect(
                  // Back to viewport coordinates to paint it.
                  rect: box.shift(Offset(0, -_scrollController.offset)),
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: colour.withValues(alpha: .18),
                        border: Border.all(color: colour),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                );
              },
            ),
            Positioned(
              left: 0,
              right: 0,
              top: 16,
              child: Center(
                child: _scrollControlHoverZone(
                  active: _topScrollControlActive,
                  edge: ScrollEdge.top,
                  tooltip: tr(AppI10n.homeScrollToTop),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 16,
              child: Center(
                child: _scrollControlHoverZone(
                  active: _bottomScrollControlActive,
                  edge: ScrollEdge.bottom,
                  tooltip: tr(AppI10n.homeScrollToBottom),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
