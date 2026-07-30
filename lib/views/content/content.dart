import 'dart:math';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:we_repkg/constants/i10n.dart';
import 'package:we_repkg/constants/nums.dart';
import 'package:we_repkg/cores/wallpaper.dart';
import 'package:we_repkg/models/enums.dart';
import 'package:we_repkg/models/filter.dart';
import 'package:we_repkg/models/wallpaper.dart';
import 'package:we_repkg/provider/filter.dart';
import 'package:we_repkg/utils/modifier_keys.dart';
import 'package:we_repkg/provider/navigation.dart';
import 'package:we_repkg/provider/system.dart';
import 'package:we_repkg/provider/wallpaper.dart';
import 'package:we_repkg/utils/grid_selection.dart';
import 'package:we_repkg/views/states/empty.dart';
import 'package:we_repkg/views/states/no_results.dart';
import 'package:we_repkg/widgets/scroll_edge_controls.dart';
import 'package:we_repkg/widgets/smooth_wheel_scroll.dart';

import 'item.dart';

class ContentView extends ConsumerStatefulWidget {
  const ContentView({super.key});

  static const Key topScrollHoverKey = ValueKey<String>(
    'scroll-top-hover-zone',
  );
  static const Key bottomScrollHoverKey = ValueKey<String>(
    'scroll-bottom-hover-zone',
  );

  @override
  ConsumerState<ContentView> createState() => _ContentViewState();
}

class _ContentViewState extends ConsumerState<ContentView>
    with TickerProviderStateMixin {
  static const ValueKey<String> _gridTransitionKey = ValueKey<String>(
    'wallpaper-grid-content',
  );

  late final SmoothWheelScrollController _scrollController;
  late final ValueNotifier<bool> _topScrollControlActive;
  late final ValueNotifier<bool> _bottomScrollControlActive;
  late final AnimationController _entranceController;
  bool _entranceComplete = true;
  int _entranceStartToken = 0;

  /// Drag rectangle in grid coordinates, so it stays on the wallpapers under it
  /// while the list scrolls. A notifier, or repainting it would rebuild two
  /// thousand tiles behind it.
  final ValueNotifier<Rect?> _marquee = ValueNotifier<Rect?>(null);

  Offset? _dragFrom;

  /// Viewport coordinates, so autoscroll can redraw without the mouse moving.
  Offset _dragPointer = Offset.zero;

  Set<String> _dragIds = <String>{};

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
  List<WallpaperInfo> _tiles = const <WallpaperInfo>[];

  static const double _autoScrollZone = 60;
  static const double _autoScrollSpeed = 1100;

  static const Duration _fullEntranceDuration = Duration(milliseconds: 900);

  /// One per diagonal. The maths depends only on the wave, so building these per
  /// tile per rebuild made a few thousand short-lived objects a frame.
  late final List<
    ({CurvedAnimation t, Animation<double> scale, Animation<Offset> position})
  >
  _entranceWaves = List.generate(12, (wave) {
    final double start = (wave * .06).clamp(0, .66);
    final CurvedAnimation t = CurvedAnimation(
      parent: _entranceController,
      curve: Interval(
        start,
        (start + .34).clamp(0, 1),
        curve: Curves.easeOutCubic,
      ),
    );
    return (
      t: t,
      scale: TweenSequence<double>([
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
      position: TweenSequence<Offset>([
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

  /// Search reflow. Where each wallpaper sat before the results changed, so a
  /// tile that survived can start from its old cell and slide into its new one
  /// while the ones that went fade away. Empty except while reflowing.
  late final AnimationController _reflowController;
  Map<String, int> _reflowFrom = const <String, int>{};
  static const Duration _reflowDuration = Duration(milliseconds: 340);

  /// Past this many rows a slide reads as a tile flying across the window, so
  /// those fade in place instead.
  static const int _reflowMaxRows = 3;

  @override
  void initState() {
    super.initState();
    _scrollController = SmoothWheelScrollController(
      debugLabel: 'wallpaper-grid',
    );
    _topScrollControlActive = ValueNotifier<bool>(false);
    _bottomScrollControlActive = ValueNotifier<bool>(false);
    _entranceController =
        AnimationController(vsync: this, duration: _fullEntranceDuration)
          ..addStatusListener((status) {
            if (status == AnimationStatus.completed && mounted) {
              setState(() => _entranceComplete = true);
            }
          });
    _reflowController =
        AnimationController(vsync: this, duration: _reflowDuration)
          ..addStatusListener((status) {
            if (status == AnimationStatus.completed && mounted) {
              setState(() => _reflowFrom = const <String, int>{});
            }
          });

    // A scan can finish while this view is unmounted, so the request waits
    // until it mounts. Still running, and the listener in build picks it up.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final bool replay = ref
          .read(currentSectionProvider.notifier)
          .consumeExtractEntrance();
      if (replay &&
          ref.read(currentStateProvider).isComplete &&
          _entranceComplete) {
        _startGridEntrance();
      }
    });

    Future.delayed(Duration.zero, () async {
      // The provider is keepAlive, so scanning again on remount would append a
      // second copy of the library. Refresh goes through refreshWallpaper,
      // which clears first.
      if (ref.read(wallpaperListProvider).isNotEmpty) return;
      List<WallpaperInfo> wallpapers = await getAllFile(ref);
      // The scan outlives this view if the nav rail swapped it for Backup, and
      // reading ref after that throws rather than being ignored.
      if (!mounted) return;
      ref.read(wallpaperListProvider.notifier).addAll(wallpapers);
    });
  }

  @override
  void dispose() {
    _autoScroll?.dispose();
    _marquee.dispose();
    _topScrollControlActive.dispose();
    _bottomScrollControlActive.dispose();
    for (final wave in _entranceWaves) {
      wave.t.dispose();
    }
    _entranceController.dispose();
    _reflowController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Widget _scrollControlHoverZone({
    required Key key,
    required ValueNotifier<bool> active,
    required ScrollEdge edge,
    required String tooltip,
  }) {
    return MouseRegion(
      key: key,
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

  void _startGridEntrance({Duration duration = _fullEntranceDuration}) {
    final int startToken = ++_entranceStartToken;
    _entranceController
      ..stop()
      ..duration = duration
      ..value = 0;
    setState(() => _entranceComplete = false);

    // Starting synchronously burns the opening frames before the grid exists.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          startToken != _entranceStartToken ||
          !ref.read(currentStateProvider).isComplete) {
        return;
      }
      _entranceController.forward();
    });
  }

  /// A tile mid-reflow: one that was already on screen slides in from wherever
  /// it used to sit, one that has just matched grows into place.
  ///
  /// Always the same widgets, whether or not a reflow is running. Wrapping and
  /// unwrapping re-parents the Image inside, and an Image rebuilt into a new
  /// position paints its white background for a frame before the picture
  /// returns, which reads as the whole grid flashing.
  Widget _reflowed(Widget tile, String id, int index) {
    return AnimatedBuilder(
      animation: _reflowController,
      builder: (context, child) {
        double opacity = 1;
        double scale = 1;
        Offset shift = Offset.zero;

        if (_reflowFrom.isNotEmpty) {
          final double t = Curves.easeOutCubic.transform(
            _reflowController.value,
          );
          final int? from = _reflowFrom[id];
          if (from == null) {
            opacity = t;
            scale = .82 + .18 * t;
          } else {
            final Offset was = _cellOrigin(from) - _cellOrigin(index);
            if (was.dy.abs() > _reflowMaxRows * (_tileExtent + _gridSpacing)) {
              opacity = t;
            } else {
              shift = was * (1 - t);
            }
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

  /// Snapshots where every wallpaper sits, then runs the reflow against it.
  /// Called before the rebuild, so `_tiles` is still the outgoing list.
  void _startReflow() {
    if (_tiles.isEmpty) return;
    setState(() {
      _reflowFrom = <String, int>{
        for (int i = 0; i < _tiles.length; i++) _tiles[i].id: i,
      };
    });
    _reflowController.forward(from: 0);
  }

  Offset _cellOrigin(int index) => cellOrigin(
    index,
    columns: _columns,
    tile: _tileExtent,
    spacing: _gridSpacing,
  );

  /// Viewport point to grid point: the grid keeps scrolling under the pointer,
  /// so the rectangle is stored against the wallpapers, not the window.
  Offset _toGrid(Offset local) => local + Offset(0, _scrollController.offset);

  void _updateDrag() {
    final Offset? from = _dragFrom;
    if (from == null) return;
    final Rect box = Rect.fromPoints(from, _toGrid(_dragPointer));
    _marquee.value = box;

    final Set<String> ids = coveredTiles(
      box,
      origin: const Offset(LayoutNums.edgeInset, LayoutNums.contentGap),
      columns: _columns,
      tile: _tileExtent,
      spacing: _gridSpacing,
      count: _tiles.length,
    ).map((i) => _tiles[i].id).toSet();
    if (setEquals(ids, _dragIds)) return;
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
      if (mounted) {
        ref.read(wallpaperListProvider.notifier).setCheckedExactly(_dragWanted);
      }
    });
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

  static const double _gridSpacing = 8;

  Widget _buildGrid(List<WallpaperInfo> list) {
    const double maxExtent = 180;
    const double spacing = _gridSpacing;
    return LayoutBuilder(
      key: _gridTransitionKey,
      builder: (context, constraints) {
        final double gridWidth =
            (constraints.maxWidth - (LayoutNums.edgeInset * 2)).clamp(
              0,
              double.infinity,
            );
        final int columnCount = (gridWidth / (maxExtent + spacing))
            .ceil()
            .clamp(1, 1000);

        final double tile =
            (gridWidth - (spacing * (columnCount - 1))) / columnCount;

        _viewportHeight = constraints.maxHeight;
        _columns = columnCount;
        _tileExtent = tile;
        _tiles = list;

        return Stack(
          key: const ValueKey<String>('wallpaper-content-stack'),
          children: [
            // Mouse drags do not scroll a desktop list, so a pan here is free
            // to mean selection. A tap on a tile resolves before this sees any
            // movement.
            GestureDetector(
              behavior: HitTestBehavior.translucent,
              // Anchor the box where the button went down, not where the pan
              // won the arena, which on a fast drag is a tile or two away.
              dragStartBehavior: DragStartBehavior.down,
              onPanStart: (d) {
                _dragPointer = d.localPosition;
                _dragFrom = _toGrid(d.localPosition);
                // Cleared per drag, or repeating a rectangle matches the last
                // drag's set and writes nothing.
                _dragIds = <String>{};
                // The whole library, not checkedWallpaperListProvider: that one
                // is filtered, and anything selected before the filter changed
                // would be missing from the baseline and get deselected.
                _dragBaseline = isCtrlPressed
                    ? <String>{
                        for (final e in ref.read(wallpaperListProvider))
                          if (e.checked) e.id,
                      }
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
                key: const PageStorageKey<String>('wallpaper-grid'),
                controller: _scrollController,
                itemCount: list.length,
                padding: const EdgeInsets.symmetric(
                  horizontal: LayoutNums.edgeInset,
                  vertical: LayoutNums.contentGap,
                ),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  crossAxisSpacing: spacing,
                  mainAxisSpacing: spacing,
                  maxCrossAxisExtent: maxExtent,
                ),
                scrollCacheExtent: const ScrollCacheExtent.pixels(500),
                // No tile keeps itself alive, so the wrapper is pure overhead.
                addAutomaticKeepAlives: false,
                itemBuilder: (context, index) {
                  final WallpaperInfo wallpaper = list[index];
                  // The laid-out extent, not maxCrossAxisExtent: the tile is
                  // narrower than 180 whenever the columns do not divide the
                  // window evenly, and this is what the preview decodes at.
                  final Widget item = ImageItem(
                    key: ValueKey(wallpaper.id),
                    width: tile,
                    index: index,
                    wallpaper: wallpaper,
                  );
                  final Widget reflowed = _reflowed(item, wallpaper.id, index);
                  if (_entranceComplete) return reflowed;

                  // Tiles on the same diagonal move together. Capped, or
                  // off-screen rows sit waiting their turn.
                  final wave =
                      _entranceWaves[((index ~/ columnCount) +
                              (index % columnCount))
                          .clamp(0, _entranceWaves.length - 1)];

                  return FadeTransition(
                    opacity: wave.t,
                    // Now that this replays on every search, a fade to zero
                    // dropping tiles from the accessibility tree would upset
                    // Windows' bridge far more often.
                    alwaysIncludeSemantics: true,
                    child: ScaleTransition(
                      scale: wave.scale,
                      child: SlideTransition(
                        position: wave.position,
                        child: reflowed,
                      ),
                    ),
                  );
                },
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
                  key: ContentView.topScrollHoverKey,
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
                  key: ContentView.bottomScrollHoverKey,
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

  @override
  Widget build(BuildContext context) {
    ref.listen<RunState>(currentStateProvider, (previous, next) {
      if (next.isComplete && previous?.isComplete != true) {
        _startGridEntrance();
      }
    });

    // Listening to what the user changed rather than to the filtered list: that
    // list is rebuilt by every selection write too, and reflowing the grid each
    // time a wallpaper is ticked would be unbearable.
    ref.listen<String>(searchContentProvider, (previous, next) {
      if (previous == next) return;
      _startReflow();
    });
    ref.listen<WallpaperFilter>(
      filterStateProvider,
      (previous, next) => _startReflow(),
    );

    final RunState runState = ref.watch(currentStateProvider);
    final List<WallpaperInfo> list = ref.watch(filterWallpaperListProvider);
    // A search that matches nothing used to leave the grid area blank, which
    // against a light theme read as the window flashing. Only when the library
    // itself has wallpapers: refreshing or changing the library path empties
    // the list for a moment, and swapping the whole grid out and back for that
    // is both a flicker and a few hundred semantics nodes leaving mid-animation.
    final bool libraryLoaded = ref.watch(wallpaperListProvider).isNotEmpty;
    final Widget content = !runState.isComplete
        ? EmptyView(key: ValueKey<RunState>(runState), runState: runState)
        : list.isEmpty && libraryLoaded
        ? const NoResultsView(key: NoResultsView.viewKey)
        : _buildGrid(list);

    return Expanded(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        reverseDuration: const Duration(milliseconds: 180),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        transitionBuilder: (child, animation) {
          // The grid has its own diagonal entrance; a second fade flattens it.
          if (child.key == _gridTransitionKey) return child;
          return FadeTransition(
            opacity: animation,
            alwaysIncludeSemantics: true,
            child: child,
          );
        },
        layoutBuilder: (currentChild, previousChildren) {
          return Stack(
            fit: StackFit.expand,
            children: [
              // The outgoing view cannot be reached, and dropping its semantics
              // in one go beats losing them a few at a time as it fades, which
              // is what leaves the Windows AXTree broken.
              for (final Widget child in previousChildren)
                ExcludeSemantics(child: child),
              ?currentChild,
            ],
          );
        },
        child: content,
      ),
    );
  }
}
