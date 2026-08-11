import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:we_repkg/cores/wallpaper.dart';
import 'package:we_repkg/models/enums.dart';
import 'package:we_repkg/models/filter.dart';
import 'package:we_repkg/models/wallpaper.dart';
import 'package:we_repkg/provider/filter.dart';
import 'package:we_repkg/provider/navigation.dart';
import 'package:we_repkg/provider/system.dart';
import 'package:we_repkg/provider/wallpaper.dart';
import 'package:we_repkg/utils/grid_selection.dart';
import 'package:we_repkg/views/states/empty.dart';
import 'package:we_repkg/views/states/no_results.dart';
import 'package:we_repkg/widgets/selection_grid.dart';

import 'item.dart';

class ContentView extends ConsumerStatefulWidget {
  const ContentView({super.key});

  @override
  ConsumerState<ContentView> createState() => _ContentViewState();
}

class _ContentViewState extends ConsumerState<ContentView>
    with TickerProviderStateMixin {
  static const ValueKey<String> _gridTransitionKey = ValueKey<String>(
    'wallpaper-grid-content',
  );

  late final AnimationController _entranceController;
  bool _entranceComplete = true;
  int _entranceStartToken = 0;

  /// The wallpapers the grid is currently showing, so a reflow can tell where
  /// each one sat before the results changed.
  List<WallpaperInfo> _tiles = const <WallpaperInfo>[];

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
    for (final wave in _entranceWaves) {
      wave.t.dispose();
    }
    _entranceController.dispose();
    _reflowController.dispose();
    super.dispose();
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
  Widget _reflowed(Widget tile, String id, int index, GridGeometry geometry) {
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
            final Offset was =
                _cellOrigin(from, geometry) - _cellOrigin(index, geometry);
            if (was.dy.abs() >
                _reflowMaxRows * (geometry.tile + geometry.spacing)) {
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

  Offset _cellOrigin(int index, GridGeometry geometry) => cellOrigin(
    index,
    columns: geometry.columns,
    tile: geometry.tile,
    spacing: geometry.spacing,
  );

  Widget _buildGrid(List<WallpaperInfo> list) {
    _tiles = list;
    return SelectionGrid(
      key: _gridTransitionKey,
      id: 'wallpaper-grid',
      itemCount: list.length,
      idAt: (index) => list[index].id,
      // Every selected id, not checkedWallpaperListProvider: that one is
      // filtered, and anything selected before the filter changed would be
      // missing from the baseline and get deselected.
      currentSelection: () => ref.read(checkedIdsProvider),
      onSelectionChanged: (ids) {
        if (mounted) ref.read(checkedIdsProvider.notifier).setExactly(ids);
      },
      itemBuilder: (context, index, geometry) {
        final WallpaperInfo wallpaper = list[index];
        // The laid-out extent, not maxCrossAxisExtent: the tile is narrower
        // than 180 whenever the columns do not divide the window evenly, and
        // this is what the preview decodes at.
        final Widget item = ImageItem(
          key: ValueKey(wallpaper.id),
          width: geometry.tile,
          index: index,
          wallpaper: wallpaper,
        );
        final Widget reflowed = _reflowed(item, wallpaper.id, index, geometry);
        if (_entranceComplete) return reflowed;

        // Tiles on the same diagonal move together. Capped, or off-screen rows
        // sit waiting their turn.
        final wave =
            _entranceWaves[((index ~/ geometry.columns) +
                    (index % geometry.columns))
                .clamp(0, _entranceWaves.length - 1)];

        return FadeTransition(
          opacity: wave.t,
          // Now that this replays on every search, a fade to zero dropping
          // tiles from the accessibility tree would upset Windows' bridge far
          // more often.
          alwaysIncludeSemantics: true,
          child: ScaleTransition(
            scale: wave.scale,
            child: SlideTransition(position: wave.position, child: reflowed),
          ),
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
