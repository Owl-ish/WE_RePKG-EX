import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:we_repkg/constants/i10n.dart';
import 'package:we_repkg/constants/nums.dart';
import 'package:we_repkg/cores/wallpaper.dart';
import 'package:we_repkg/models/enums.dart';
import 'package:we_repkg/models/wallpaper.dart';
import 'package:we_repkg/provider/navigation.dart';
import 'package:we_repkg/provider/system.dart';
import 'package:we_repkg/provider/wallpaper.dart';
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
    with SingleTickerProviderStateMixin {
  static const ValueKey<String> _gridTransitionKey = ValueKey<String>(
    'wallpaper-grid-content',
  );

  late final SmoothWheelScrollController _scrollController;
  late final ValueNotifier<bool> _topScrollControlActive;
  late final ValueNotifier<bool> _bottomScrollControlActive;
  late final AnimationController _entranceController;
  bool _entranceComplete = true;
  int _entranceStartToken = 0;

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

    // A library can finish scanning while Settings is visible and this view is
    // unmounted. Consume the one-shot request only after Extract mounts, then
    // replay immediately if the scan has already completed. If it is still
    // running, the currentState listener in build starts the same entrance when
    // completion arrives.
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
      // Only scan when there is nothing to show.
      //
      // wallpaperListProvider is keepAlive, so it outlives this widget. Any
      // remount that scanned again would append a second copy of the whole
      // library to the list already in the provider, and the count would climb
      // by the library's size each time. Refreshing deliberately goes through
      // refreshWallpaper, which clears before it adds.
      if (ref.read(wallpaperListProvider).isNotEmpty) return;
      List<WallpaperInfo> wallpapers = await getAllFile(ref);
      ref.read(wallpaperListProvider.notifier).addAll(wallpapers);
    });
  }

  @override
  void dispose() {
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

    // Wait until the zero-progress transition widgets are mounted. Starting
    // synchronously can consume the opening frames before the grid exists.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          startToken != _entranceStartToken ||
          !ref.read(currentStateProvider).isComplete) {
        return;
      }
      _entranceController.forward();
    });
  }

  Widget _buildGrid(List<WallpaperInfo> list) {
    const double width = 180;
    const double spacing = 8;
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

        return Stack(
          key: const ValueKey<String>('wallpaper-content-stack'),
          children: [
            GridView.builder(
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

                // Items on the same top-left-to-bottom-right diagonal move
                // together. Capping the wave keeps off-screen rows from waiting.
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
          // The grid supplies its own diagonal entrance. A second full-grid
          // fade would flatten the wave and make it much less noticeable.
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
