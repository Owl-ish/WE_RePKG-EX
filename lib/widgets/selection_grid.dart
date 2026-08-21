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

/// One grouped stretch of [SelectionGrid]. The grid still owns scrolling and
/// tile layout; callers only supply optional section chrome around a flat slice
/// of the item list.
class SelectionGridSection {
  const SelectionGridSection({
    required this.itemCount,
    this.beforeHeader,
    this.beforeHeaderExtent,
    this.header,
    this.headerExtent,
    this.headerPinned = false,
    this.gridPadding = const EdgeInsets.only(
      top: LayoutNums.contentGap,
      bottom: LayoutNums.sectionGap,
    ),
  }) : assert(beforeHeader == null || beforeHeaderExtent != null),
       assert(header == null || headerExtent != null);

  final int itemCount;
  final Widget? beforeHeader;
  final double? beforeHeaderExtent;
  final Widget? header;
  final double? headerExtent;
  final bool headerPinned;
  final EdgeInsets gridPadding;
}

class _SelectionGridHeaderDelegate extends SliverPersistentHeaderDelegate {
  const _SelectionGridHeaderDelegate({
    required this.extent,
    required this.child,
  });

  final double extent;
  final Widget child;

  @override
  double get minExtent => extent;

  @override
  double get maxExtent => extent;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) => RepaintBoundary(child: child);

  @override
  bool shouldRebuild(covariant _SelectionGridHeaderDelegate oldDelegate) =>
      oldDelegate.extent != extent || oldDelegate.child != child;
}

/// One-shot replay latch shared by tabs that use the grid entrance. A request
/// survives loading, but once a grid takes it, ordinary rebuilds cannot replay
/// it.
class GridEntranceReplay {
  int _token = 0;
  bool _owed = false;

  int get token => _token;

  /// Returns whether this request changed the latch from idle to owed.
  bool request() {
    if (_owed) return false;
    _token++;
    _owed = true;
    return true;
  }

  /// Gives the pending replay to the next ready grid exactly once.
  bool take() {
    final bool owed = _owed;
    _owed = false;
    return owed;
  }

  /// Uses up a replay when there are deliberately no tiles to animate.
  void discard() => _owed = false;
}

/// One diagonal of the shared grid entrance: when it runs and where its tiles
/// come from.
typedef _GridEntranceWave = ({
  CurvedAnimation t,
  Animation<double> scale,
  Animation<Offset> position,
});

/// Total time for one shared grid entrance.
const Duration gridEntranceDuration = Duration(milliseconds: 900);

/// Number of diagonals staggered across one entrance.
const int _gridEntranceWaveCount = 12;

/// Builds the diagonal wave animations shared by regular and grouped grids.
List<_GridEntranceWave> _buildGridEntranceWaves(Animation<double> parent) =>
    List<_GridEntranceWave>.generate(_gridEntranceWaveCount, (int wave) {
      final double start = (wave * .06).clamp(0, .66);
      final CurvedAnimation t = CurvedAnimation(
        parent: parent,
        curve: Interval(
          start,
          (start + .34).clamp(0, 1),
          curve: Curves.easeOutCubic,
        ),
      );
      return (
        t: t,
        scale: TweenSequence<double>(<TweenSequenceItem<double>>[
          TweenSequenceItem<double>(
            tween: Tween<double>(
              begin: .88,
              end: 1.04,
            ).chain(CurveTween(curve: Curves.easeOutCubic)),
            weight: 70,
          ),
          TweenSequenceItem<double>(
            tween: Tween<double>(
              begin: 1.04,
              end: 1,
            ).chain(CurveTween(curve: Curves.easeInOut)),
            weight: 30,
          ),
        ]).animate(t),
        position: TweenSequence<Offset>(<TweenSequenceItem<Offset>>[
          TweenSequenceItem<Offset>(
            tween: Tween<Offset>(
              begin: const Offset(0, .055),
              end: const Offset(0, -.012),
            ).chain(CurveTween(curve: Curves.easeOutCubic)),
            weight: 70,
          ),
          TweenSequenceItem<Offset>(
            tween: Tween<Offset>(
              begin: const Offset(0, -.012),
              end: Offset.zero,
            ).chain(CurveTween(curve: Curves.easeInOut)),
            weight: 30,
          ),
        ]).animate(t),
      );
    });

/// Wraps one tile in its diagonal of the shared entrance.
Widget _gridEntranceTile({
  required bool done,
  required List<_GridEntranceWave> waves,
  required int index,
  required int columns,
  required Widget child,
}) {
  if (done) return child;
  final _GridEntranceWave wave =
      waves[((index ~/ columns) + (index % columns)).clamp(
        0,
        _gridEntranceWaveCount - 1,
      )];
  return FadeTransition(
    opacity: wave.t,
    alwaysIncludeSemantics: true,
    child: ScaleTransition(
      scale: wave.scale,
      child: SlideTransition(position: wave.position, child: child),
    ),
  );
}

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
    this.entranceToken = 0,
    this.entranceOnMount = true,
    this.reflowIdentity,
    this.sections = const <SelectionGridSection>[],
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

  /// Change this to play the entrance again on a grid that is already up.
  final int entranceToken;

  /// Whether appearing is itself worth an entrance. Off for a caller that
  /// leaves and comes back to content that has not changed: the tiles arriving
  /// again would say something happened when nothing did.
  final bool entranceOnMount;

  /// Lists under different identities are replacements rather than rearrangements.
  /// Changing this accepts the new ids immediately instead of animating them from
  /// the previous list. Search and sort can keep the same identity and still reflow.
  final Object? reflowIdentity;

  /// Optional grouped presentation. [itemCount], [idAt], and [itemBuilder]
  /// still describe one flat list; sections only partition that list visually.
  /// Grouped mode intentionally keeps the current Backup behavior of click/
  /// ctrl/shift selection without adding marquee selection across headers.
  final List<SelectionGridSection> sections;

  @override
  State<SelectionGrid> createState() => _SelectionGridState();
}

class _SelectionGridState extends State<SelectionGrid>
    with TickerProviderStateMixin {
  static const SelectionEngine<String> _selection = SelectionEngine<String>();

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
  bool _dragAddsToSelection = false;

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

  /// Tiles arrive in diagonal waves rather than all at once.
  late final AnimationController _entrance;
  bool _entranceDone = false;
  int _entranceRun = 0;

  /// Where each tile sat before the list last changed, and the reflow that
  /// carries it to where it sits now. Empty except while one is running.
  late final AnimationController _reflow;
  Map<String, int> _reflowFrom = const <String, int>{};
  List<String> _shown = const <String>[];

  /// The furthest any tile has to travel this reflow, in places rather than
  /// rows: the columns are not known until the grid lays out.
  int _reflowJump = 0;

  static const Duration _reflowDuration = Duration(milliseconds: 340);

  /// Past this many rows a slide reads as a tile flying across the window, so
  /// the whole grid fades instead.
  static const int _reflowMaxRows = 3;

  /// One per diagonal, built once and shared with grouped grids elsewhere.
  late final List<_GridEntranceWave> _entranceWaves = _buildGridEntranceWaves(
    _entrance,
  );

  @override
  void initState() {
    super.initState();
    _scrollController = SmoothWheelScrollController(debugLabel: widget.id);
    _topScrollControlActive = ValueNotifier<bool>(false);
    _bottomScrollControlActive = ValueNotifier<bool>(false);
    _entrance = AnimationController(vsync: this, duration: gridEntranceDuration)
      ..addStatusListener((AnimationStatus status) {
        if (status == AnimationStatus.completed && mounted) {
          setState(() => _entranceDone = true);
        }
      });
    _reflow = AnimationController(vsync: this, duration: _reflowDuration)
      ..addStatusListener((AnimationStatus status) {
        if (status == AnimationStatus.completed && mounted) {
          setState(() => _reflowFrom = const <String, int>{});
        }
      });
    _shown = _ids();
    if (widget.entranceOnMount) {
      _startEntrance();
    } else {
      // Or the tiles sit at the entrance's first frame, which is invisible.
      _entranceDone = true;
    }
  }

  @override
  void didUpdateWidget(SelectionGrid old) {
    super.didUpdateWidget(old);
    final bool replayEntrance = widget.entranceToken != old.entranceToken;
    if (replayEntrance) {
      _startEntrance();
      _acceptListWithoutReflow();
      return;
    }
    if (widget.reflowIdentity != old.reflowIdentity) {
      _finishEntrance();
      _acceptListWithoutReflow();
      return;
    }
    // Section headers change the main-axis geometry, so grouped lists do not
    // pretend their flat indexes describe a reflow path through those headers.
    if (widget.sections.isNotEmpty || old.sections.isNotEmpty) {
      _acceptListWithoutReflow();
      return;
    }
    _reflowIfListMoved();
  }

  void _acceptListWithoutReflow() {
    _reflow.stop();
    _reflowFrom = const <String, int>{};
    _shown = _ids();
  }

  List<String> _ids() => <String>[
    for (int i = 0; i < widget.itemCount; i++) widget.idAt(i),
  ];

  /// Slides what survived a search, a filter or a re-order from where it was to
  /// where it is now.
  ///
  /// Worked out from the ids rather than told by the caller, so no caller has to
  /// remember to say the list moved, and a rebuild that leaves it alone costs
  /// one comparison.
  void _reflowIfListMoved() {
    final List<String> now = _ids();
    if (listEquals(now, _shown)) return;
    final List<String> was = _shown;
    _shown = now;
    if (!_entranceDone) _finishEntrance();
    // Nothing to come from, so the tiles simply appear. Any reflow still
    // running belonged to the list that has just gone.
    if (was.isEmpty) {
      _reflowFrom = const <String, int>{};
      return;
    }
    _reflowFrom = <String, int>{for (int i = 0; i < was.length; i++) was[i]: i};
    _reflowJump = 0;
    for (int i = 0; i < now.length; i++) {
      final int? from = _reflowFrom[now[i]];
      if (from != null) _reflowJump = max(_reflowJump, (from - i).abs());
    }
    _reflow.forward(from: 0);
  }

  void _finishEntrance() {
    _entranceRun++;
    _entrance.stop();
    _entranceDone = true;
  }

  void _startEntrance() {
    final int run = ++_entranceRun;
    _entrance
      ..stop()
      ..value = 0;
    _entranceDone = false;
    // Starting synchronously burns the opening frames before the grid exists.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && run == _entranceRun) _entrance.forward();
    });
  }

  @override
  void dispose() {
    for (final _GridEntranceWave wave in _entranceWaves) {
      wave.t.dispose();
    }
    _entrance.dispose();
    _reflow.dispose();
    _autoScroll?.dispose();
    _marquee.dispose();
    _topScrollControlActive.dispose();
    _bottomScrollControlActive.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// A tile mid-reflow: either every tile that was already up slides from where
  /// it sat, or none of them does and the grid grows into place. One decision
  /// for the lot, or a search that moves half the tiles a row and half of them
  /// a hundred reads as the animation misfiring. A tile that has just matched
  /// has nowhere to slide from and always grows.
  ///
  /// Always the same widgets, whether or not a reflow is running. Wrapping and
  /// unwrapping re-parents the image inside, and an image rebuilt into a new
  /// position paints its white background for a frame before the picture
  /// returns, which reads as the whole grid flashing.
  Widget _reflowed(Widget tile, String id, int index, GridGeometry geometry) {
    return AnimatedBuilder(
      animation: _reflow,
      builder: (BuildContext context, Widget? child) {
        double opacity = 1;
        double scale = 1;
        Offset shift = Offset.zero;

        if (_reflowFrom.isNotEmpty) {
          final double t = Curves.easeOutCubic.transform(_reflow.value);
          final int? from = _reflowFrom[id];
          final bool slides =
              from != null && _reflowJump <= _reflowMaxRows * geometry.columns;
          if (slides) {
            shift =
                (_cellAt(from, geometry) - _cellAt(index, geometry)) * (1 - t);
          } else {
            opacity = t;
            scale = .82 + .18 * t;
          }
        }

        return Transform.translate(
          offset: shift,
          // alwaysIncludeSemantics: reaching zero would drop the tile from the
          // accessibility tree, which is what upsets Windows' bridge.
          child: Opacity(
            opacity: opacity,
            alwaysIncludeSemantics: true,
            child: Transform.scale(scale: scale, child: child),
          ),
        );
      },
      child: tile,
    );
  }

  Offset _cellAt(int index, GridGeometry geometry) => cellOrigin(
    index,
    columns: geometry.columns,
    tile: geometry.tile,
    spacing: geometry.spacing,
  );

  /// A tile arriving: past its resting place, then back to it.
  Widget _arriving(int index, int columns, Widget tile) => _gridEntranceTile(
    done: _entranceDone,
    waves: _entranceWaves,
    index: index,
    columns: columns,
    child: tile,
  );

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

    final Set<String> ids = <String>{
      for (final section in _sectionGrids())
        for (final int localIndex in coveredTiles(
          box,
          origin: section.origin,
          columns: _columns,
          tile: _tileExtent,
          spacing: _spacing,
          count: section.count,
        ))
          widget.idAt(section.start + localIndex),
    };
    if (_dragIds != null && setEquals(ids, _dragIds)) return;
    _dragIds = ids;
    _dragWanted = _selection.marquee(
      current: _dragBaseline,
      hits: ids,
      additive: _dragAddsToSelection,
    );

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
    if (at == null) return;
    final bool hitItem = _sectionGrids().any(
      (section) => hitsTile(
        at,
        origin: section.origin,
        columns: _columns,
        tile: _tileExtent,
        spacing: _spacing,
        count: section.count,
      ),
    );
    if (!_selection.clearsOnEmpty(
      control: isCtrlPressed,
      shift: isShiftPressed,
      hitItem: hitItem,
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

  List<SelectionGridSection> _sections() => widget.sections.isNotEmpty
      ? widget.sections
      : <SelectionGridSection>[
          SelectionGridSection(
            itemCount: widget.itemCount,
            gridPadding: widget.padding,
          ),
        ];

  double _gridHeight(int itemCount) {
    if (itemCount == 0) return 0;
    final int rows = (itemCount + _columns - 1) ~/ _columns;
    return rows * _tileExtent + (rows - 1) * _spacing;
  }

  Iterable<({int start, int count, Offset origin})> _sectionGrids() sync* {
    int start = 0;
    double top = 0;
    for (final SelectionGridSection section in _sections()) {
      if (section.beforeHeader != null) top += section.beforeHeaderExtent!;
      if (section.header != null) top += section.headerExtent!;
      final Offset origin = Offset(
        section.gridPadding.left,
        top + section.gridPadding.top,
      );
      yield (start: start, count: section.itemCount, origin: origin);
      start += section.itemCount;
      top =
          origin.dy +
          _gridHeight(section.itemCount) +
          section.gridPadding.bottom;
    }
  }

  Widget _scrollView(int columnCount, GridGeometry geometry) {
    final bool grouped = widget.sections.isNotEmpty;
    final List<SelectionGridSection> sections = _sections();
    int start = 0;
    final List<Widget> groups = <Widget>[];
    for (final SelectionGridSection section in sections) {
      final int sectionStart = start;
      start += section.itemCount;
      groups.add(
        SliverMainAxisGroup(
          slivers: <Widget>[
            if (section.beforeHeader case final Widget beforeHeader)
              SliverToBoxAdapter(
                child: SizedBox(
                  height: section.beforeHeaderExtent,
                  child: beforeHeader,
                ),
              ),
            if (section.header case final Widget header)
              if (section.headerPinned && section.headerExtent != null)
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _SelectionGridHeaderDelegate(
                    extent: section.headerExtent!,
                    child: header,
                  ),
                )
              else
                SliverToBoxAdapter(
                  child: SizedBox(height: section.headerExtent, child: header),
                ),
            SliverPadding(
              padding: section.gridPadding,
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  crossAxisSpacing: _spacing,
                  mainAxisSpacing: _spacing,
                  maxCrossAxisExtent: _maxExtent,
                ),
                delegate: SliverChildBuilderDelegate(
                  (BuildContext context, int localIndex) {
                    final int index = sectionStart + localIndex;
                    Widget child = widget.itemBuilder(context, index, geometry);
                    if (!grouped) {
                      child = _reflowed(
                        child,
                        widget.idAt(index),
                        index,
                        geometry,
                      );
                    }
                    return _arriving(
                      grouped ? localIndex : index,
                      columnCount,
                      child,
                    );
                  },
                  childCount: section.itemCount,
                  addAutomaticKeepAlives: false,
                ),
              ),
            ),
          ],
        ),
      );
    }
    if (start != widget.itemCount) {
      throw FlutterError(
        'SelectionGrid sections contain $start items, '
        'but itemCount is ${widget.itemCount}.',
      );
    }
    return CustomScrollView(
      key: PageStorageKey<String>(widget.id),
      controller: _scrollController,
      scrollCacheExtent: const ScrollCacheExtent.pixels(500),
      slivers: groups,
    );
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

        final Widget scrollView = _scrollView(columnCount, geometry);

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
                _dragAddsToSelection = isCtrlPressed;
                _dragBaseline = _dragAddsToSelection
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
              child: scrollView,
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
