import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:we_repkg/cores/wallpaper.dart';
import 'package:we_repkg/models/enums.dart';
import 'package:we_repkg/models/wallpaper.dart';
import 'package:we_repkg/provider/navigation.dart';
import 'package:we_repkg/provider/system.dart';
import 'package:we_repkg/provider/wallpaper.dart';
import 'package:we_repkg/views/states/empty.dart';
import 'package:we_repkg/views/states/no_results.dart';
import 'package:we_repkg/widgets/selection_grid.dart';

import 'item.dart';

class ContentView extends ConsumerStatefulWidget {
  const ContentView({super.key});

  @override
  ConsumerState<ContentView> createState() => _ContentViewState();
}

class _ContentViewState extends ConsumerState<ContentView> {
  static const ValueKey<String> _gridTransitionKey = ValueKey<String>(
    'wallpaper-grid-content',
  );

  /// Bumped to play the grid's entrance again on a grid that is already up.
  int _entranceToken = 0;

  /// Whether the next grid to appear should play the entrance. False on the way
  /// back from the backup area, where the library is the one already seen.
  bool _entranceOwed = false;

  @override
  void initState() {
    super.initState();
    // A scan can finish while this view is unmounted, so the request waits
    // until it mounts. Still running, and the listener in build picks it up.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final bool replay = ref
          .read(currentSectionProvider.notifier)
          .consumeExtractEntrance();
      if (replay && ref.read(currentStateProvider).isComplete) {
        setState(_owe);
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

  /// The library is new, so whichever grid shows it plays the entrance: the one
  /// already up on this token, or the next one to appear.
  void _owe() {
    _entranceToken++;
    _entranceOwed = true;
  }

  Widget _buildGrid(List<WallpaperInfo> list) {
    if (_entranceOwed) {
      // Cleared once a grid has taken it, and not through setState: nothing on
      // screen reads it after the grid is up.
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _entranceOwed = false,
      );
    }
    return SelectionGrid(
      key: _gridTransitionKey,
      id: 'wallpaper-grid',
      entranceToken: _entranceToken,
      entranceOnMount: _entranceOwed,
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
        return ImageItem(
          key: ValueKey(wallpaper.id),
          width: geometry.tile,
          index: index,
          wallpaper: wallpaper,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<RunState>(currentStateProvider, (previous, next) {
      if (next.isComplete && previous?.isComplete != true) setState(_owe);
    });

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
