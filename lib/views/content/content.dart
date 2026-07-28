import 'dart:math';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:we_repkg/constants/i10n.dart';
import 'package:we_repkg/constants/nums.dart';
import 'package:we_repkg/cores/wallpaper.dart';
import 'package:we_repkg/models/enums.dart';
import 'package:we_repkg/models/wallpaper.dart';
import 'package:we_repkg/provider/navigation.dart';
import 'package:we_repkg/provider/system.dart';
import 'package:we_repkg/provider/wallpaper.dart';
import 'package:we_repkg/utils/grid_selection.dart';
import 'package:we_repkg/views/states/empty.dart';
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

  @override
  void initState() {
    super.initState();
    _scrollController = SmoothWheelScrollController(
      debugLabel: 'wallpaper-grid',
    );
    _topScrollControlActive = ValueNotifier<bool>(false);
    _bottomScrollControlActive = ValueNotifier<bool>(false);
    _entranceController =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 900),
        )..addStatusListener((status) {
          if (status == AnimationStatus.completed && mounted) {
            setState(() => _entranceComplete = true);
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
      ref.read(wallpaperListProvider.notifier).addAll(wallpapers);
    });
  }

  @override
  void dispose() {
    _autoScroll?.dispose();
    _marquee.dispose();
    _topScrollControlActive.dispose();
    _bottomScrollControlActive.dispose();
    _entranceController.dispose();
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

  void _startGridEntrance() {
    final int startToken = ++_entranceStartToken;
    _entranceController
      ..stop()
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

    // One write per frame. Each one refilters and re-sorts the whole library,
    // and a fast mouse reports twice a frame.
    if (_dragWriteQueued) return;
    _dragWriteQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _dragWriteQueued = false;
      if (mounted) {
        ref.read(wallpaperListProvider.notifier).setCheckedExactly(_dragIds);
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
    const double width = 180;
    const double spacing = _gridSpacing;
    return LayoutBuilder(
      key: _gridTransitionKey,
      builder: (context, constraints) {
        final double gridWidth =
            (constraints.maxWidth - (LayoutNums.edgeInset * 2)).clamp(
              0,
              double.infinity,
            );
        final int columnCount = (gridWidth / (width + spacing)).ceil().clamp(
          1,
          1000,
        );

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
              onPanStart: (d) {
                _dragPointer = d.localPosition;
                _dragFrom = _toGrid(d.localPosition);
                // Cleared per drag, or repeating a rectangle matches the last
                // drag's set and writes nothing.
                _dragIds = <String>{};
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
                  maxCrossAxisExtent: width,
                ),
                scrollCacheExtent: const ScrollCacheExtent.pixels(500),
                itemBuilder: (context, index) {
                  final WallpaperInfo wallpaper = list[index];
                  final Widget tile = ImageItem(
                    key: ValueKey(wallpaper.id),
                    width: width,
                    index: index,
                    wallpaper: wallpaper,
                  );
                  if (_entranceComplete) return tile;

                  // Tiles on the same diagonal move together. Capped, or
                  // off-screen rows sit waiting their turn.
                  final int row = index ~/ columnCount;
                  final int column = index % columnCount;
                  final int wave = (row + column).clamp(0, 11);
                  final double start = (wave * .06).clamp(0, .66);
                  final double end = (start + .34).clamp(0, 1);
                  final Animation<double> entrance = CurvedAnimation(
                    parent: _entranceController,
                    curve: Interval(start, end, curve: Curves.easeOutCubic),
                  );
                  final Animation<double> scale = TweenSequence<double>([
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
                  ]).animate(entrance);
                  final Animation<Offset> position = TweenSequence<Offset>([
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
                  ]).animate(entrance);

                  return FadeTransition(
                    opacity: entrance,
                    child: ScaleTransition(
                      scale: scale,
                      child: SlideTransition(position: position, child: tile),
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

    final RunState runState = ref.watch(currentStateProvider);
    final List<WallpaperInfo> list = ref.watch(filterWallpaperListProvider);
    final Widget content = runState.isComplete
        ? _buildGrid(list)
        : EmptyView(key: ValueKey<RunState>(runState), runState: runState);

    return Expanded(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        reverseDuration: const Duration(milliseconds: 180),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        transitionBuilder: (child, animation) {
          // The grid has its own diagonal entrance; a second fade flattens it.
          if (child.key == _gridTransitionKey) return child;
          return FadeTransition(opacity: animation, child: child);
        },
        layoutBuilder: (currentChild, previousChildren) {
          return Stack(
            fit: StackFit.expand,
            children: [...previousChildren, ?currentChild],
          );
        },
        child: content,
      ),
    );
  }
}
