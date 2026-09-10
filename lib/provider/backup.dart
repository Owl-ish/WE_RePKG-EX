import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:we_repkg/constants/keys.dart';
import 'package:we_repkg/cores/backup.dart';
import 'package:we_repkg/models/enums.dart';
import 'package:we_repkg/provider/filter.dart';
import 'package:we_repkg/provider/system.dart';
import 'package:we_repkg/utils/backup_diff.dart';
import 'package:we_repkg/utils/backup_tiles.dart';
import 'package:we_repkg/utils/storage.dart';

part 'backup.g.dart';

/// How far the running scan has got, for the tab to show while it waits.
///
/// A notifier rather than provider state because the count moves every few
/// folders; only the progress line needs those rebuilds.
@Riverpod(keepAlive: true)
ValueNotifier<BackupScanProgress?> backupScanProgress(Ref ref) {
  final ValueNotifier<BackupScanProgress?> progress =
      ValueNotifier<BackupScanProgress?>(null);
  ref.onDispose(progress.dispose);
  return progress;
}

/// The whole comparison, run when the backup tab first asks for it.
///
/// Kept alive so remounting the tab does not repeat the filesystem scan. The
/// four watched paths refresh it when configuration changes; backup mutations
/// invalidate it explicitly.
@Riverpod(keepAlive: true)
Future<BackupScan> backupScan(Ref ref) async {
  final String? backupRoot = ref.watch(backupRootProvider);
  final ValueNotifier<BackupScanProgress?> progress = ref.watch(
    backupScanProgressProvider,
  );
  final BackupScan scan;
  try {
    scan = await scanBackup(
      backupRoot: backupRoot,
      liveWorkshopPath: ref.watch(wallpaperPathProvider),
      liveMyProjectsPath: ref.watch(myProjectsLibraryProvider),
      acfPath: ref.watch(acfPathProvider),
      onProgress: (BackupScanProgress value) => progress.value = value,
    );
  } catch (_) {
    progress.value = null;
    rethrow;
  }
  return scan;
}

/// The scan's cards in grid order, each with the title and preview to draw.
///
/// Kept apart from the scan so face reads cannot delay the counts, and so an
/// unreadable `project.json` costs a picture rather than a card.
@Riverpod(keepAlive: true)
Future<List<BackupTile>> backupTiles(Ref ref) async {
  final BackupScan scan = await ref.watch(backupScanProvider.future);
  // An ignored content update can belong to a wallpaper that Reconcile owns.
  // Read its face too so Ignored never loses a detection to pill precedence.
  final Map<BackupCard, BackupState> faceCards = <BackupCard, BackupState>{
    ...scan.cards,
    for (final BackupCard card in scan.ignoredUpdates)
      if (!scan.cards.containsKey(card)) card: BackupState.updateDismissed,
  };
  // Keep the scan's final preparing state while the short title/preview read
  // finishes, so the tab has one continuous loading phase instead of a second
  // progress bar.
  final ValueNotifier<BackupScanProgress?> progress = ref.watch(
    backupScanProgressProvider,
  );
  final Map<BackupCard, CardFace> faces;
  try {
    faces = await readCardFaces(
      backupRoot: ref.watch(backupRootProvider),
      liveWorkshopPath: ref.watch(wallpaperPathProvider),
      liveMyProjectsPath: ref.watch(myProjectsLibraryProvider),
      cards: faceCards,
      presence: scan.presence,
    );
  } catch (_) {
    // A read that threw must not leave its last count sitting on the line for
    // the next thing that waits to inherit.
    progress.value = null;
    rethrow;
  }
  // Keep the final preparing state until the completed tiles replace the
  // progress view. Clearing it here can win the frame and hide that state.
  final List<BackupTile> tiles = <BackupTile>[
    for (final BackupCard card in sortedCards(faceCards))
      (card: card, state: faceCards[card]!, face: faces[card]),
  ];
  return tiles;
}

/// The names waiting to be reconciled, each with the title and preview to draw.
///
/// Apart from [backupTiles] because Reconcile has its own names and only renders
/// behind its own pill.
@Riverpod(keepAlive: true)
Future<List<ReconcileTile>> backupReconcileTiles(Ref ref) async {
  final BackupScan scan = await ref.watch(backupScanProvider.future);
  final Map<String, CardFace> faces = await readReconcileFaces(
    backupRoot: ref.watch(backupRootProvider),
    liveWorkshopPath: ref.watch(wallpaperPathProvider),
    liveMyProjectsPath: ref.watch(myProjectsLibraryProvider),
    entries: scan.reconcile,
  );
  return <ReconcileTile>[
    for (final ReconcileEntry entry in scan.reconcile)
      (entry: entry, face: faces[entry.name]),
  ];
}

/// What is typed in the backup tab's search box.
///
/// Its own, not the wallpaper tab's. That grid shows one library at a time and
/// this one shows both plus what has vanished, so a term left behind on one tab
/// would quietly empty the other.
@Riverpod(keepAlive: true)
class BackupSearch extends _$BackupSearch {
  @override
  String build() => '';

  void update(String text) => state = text;
}

/// Which top-level Backup pill owns the grid right now.
typedef BackupShown = ({BackupState state, bool reconcile, bool ignored});

/// Session state rather than a setting: the pills are how the tab is being
/// looked at now, and returning to a grid narrowed by a pill switched off days
/// ago is how a wallpaper goes missing quietly.
///
/// Opens on the worst state that holds something, which on a library with work
/// waiting is the one with an obvious next step. Every other pill holding
/// anything glows for itself, so nothing is hidden by starting narrow.
@Riverpod(keepAlive: true)
class BackupStateFilter extends _$BackupStateFilter {
  static const BackupShown _opening = (
    state: BackupState.notBackedUp,
    reconcile: false,
    ignored: false,
  );
  BackupShown _shown = _opening;

  @override
  BackupShown build() {
    // Returning the scan-adjusted selection lets Riverpod publish it after the
    // dependency rebuild. A listener that assigned state here could fire while
    // Flutter was building the Backup toolbar.
    _shown = switch (ref.watch(backupScanProvider)) {
      AsyncData<BackupScan>(:final BackupScan value) => _holding(_shown, value),
      _ => _shown,
    };
    return _shown;
  }

  /// Keeps a non-empty pill selected, falling back in priority order.
  static BackupShown _holding(BackupShown shown, BackupScan scan) {
    final totals = backupPillCounts(
      states: scan.cards.values,
      ignoredUpdates: scan.ignoredUpdates,
      reconcile: scan.reconcile,
    );
    final int activeReconcile = totals.reconcile;
    final int ignored = totals.ignored;
    if (shown.reconcile && activeReconcile > 0) return shown;
    if (shown.ignored && ignored > 0) return shown;
    final Map<BackupState, int> counts = totals.states;
    if (!shown.reconcile &&
        !shown.ignored &&
        shown.state != BackupState.updateDismissed &&
        counts[shown.state]! > 0) {
      return shown;
    }
    for (final BackupState state in backupStateOrder) {
      if (state == BackupState.updateDismissed || state == BackupState.synced) {
        continue;
      }
      if (counts[state]! > 0) {
        return (state: state, reconcile: false, ignored: false);
      }
    }
    if (activeReconcile > 0) {
      return (state: shown.state, reconcile: true, ignored: false);
    }
    if (counts[BackupState.synced]! > 0) {
      return (state: BackupState.synced, reconcile: false, ignored: false);
    }
    if (ignored > 0) {
      return (state: shown.state, reconcile: false, ignored: true);
    }
    return _opening;
  }

  /// One at a time, the way tabs behave: the grid shows the state picked and
  /// nothing else, and is never left showing everything or nothing.
  void show(BackupState state) {
    _shown = (state: state, reconcile: false, ignored: false);
    this.state = _shown;
  }

  /// Swaps the grid over. The state pills are left as they were because picking
  /// one is what takes the grid back.
  void showReconcile() {
    _shown = (state: state.state, reconcile: true, ignored: false);
    state = _shown;
  }

  void showIgnored() {
    _shown = (state: state.state, reconcile: false, ignored: true);
    state = _shown;
  }
}

@Riverpod(keepAlive: true)
class BackupSortOrder extends _$BackupSortOrder {
  @override
  BackupSortType build() => StorageUtil.getInt(AppKeys.backupSortType) == 2
      ? BackupSortType.date
      : BackupSortType.name;

  void update(BackupSortType type) async {
    state = type;
    // Preserve persisted values 1 = name and 2 = date for compatibility; any
    // other stored value falls back to name when read above.
    await StorageUtil.setInt(
      AppKeys.backupSortType,
      type == BackupSortType.date ? 2 : 1,
    );
  }
}

@Riverpod(keepAlive: true)
class BackupSortAscending extends _$BackupSortAscending {
  @override
  bool build() => StorageUtil.getBool(AppKeys.backupSortAscending);

  void update() async {
    state = !state;
    await StorageUtil.setBool(AppKeys.backupSortAscending, state);
  }
}

/// The cards the grid draws. Apart from [backupTiles] so typing only re-filters
/// the in-memory list instead of repeating face reads.
@Riverpod(keepAlive: true)
AsyncValue<List<BackupTile>> backupVisibleTiles(Ref ref) {
  return ref.watch(backupTilesProvider).whenData((List<BackupTile> tiles) {
    final BackupShown shown = ref.watch(backupStateFilterProvider);
    if (shown.ignored) {
      final Set<String> ignoredIds = <String>{
        for (final BackupCard card
            in ref.watch(backupScanProvider).requireValue.ignoredUpdates)
          card.id,
      };
      return visibleBackupTilesMatching(
        tiles: <BackupTile>[
          for (final BackupTile tile in tiles)
            if (ignoredIds.contains(tile.card.id))
              (
                card: tile.card,
                state: BackupState.updateDismissed,
                face: tile.face,
              ),
        ],
        include: (BackupTile _) => true,
        needle: ref.watch(backupSearchProvider).trim().toLowerCase(),
        filter: ref.watch(filterStateProvider),
        sort: ref.watch(backupSortOrderProvider),
        ascending: ref.watch(backupSortAscendingProvider),
      );
    }
    return visibleBackupTiles(
      tiles: tiles,
      state: shown.state,
      needle: ref.watch(backupSearchProvider).trim().toLowerCase(),
      filter: ref.watch(filterStateProvider),
      sort: ref.watch(backupSortOrderProvider),
      ascending: ref.watch(backupSortAscendingProvider),
    );
  });
}

/// The reconcile tiles the grid draws, under the same search, filter and order.
@Riverpod(keepAlive: true)
AsyncValue<List<ReconcileTile>> backupVisibleReconcileTiles(Ref ref) {
  return ref.watch(backupReconcileTilesProvider).whenData((
    List<ReconcileTile> tiles,
  ) {
    final BackupShown shown = ref.watch(backupStateFilterProvider);
    return visibleReconcileTiles(
      tiles: <ReconcileTile>[
        for (final ReconcileTile tile in tiles)
          if (shown.ignored
              ? tile.entry.ignoredReasons.isNotEmpty
              : tile.entry.activeReasons.isNotEmpty)
            tile,
      ],
      needle: ref.watch(backupSearchProvider).trim().toLowerCase(),
      filter: ref.watch(filterStateProvider),
      sort: ref.watch(backupSortOrderProvider),
      ascending: ref.watch(backupSortAscendingProvider),
    );
  });
}

/// Ids of whatever the grid is drawing, which is what the selection is pruned
/// against: a tile out of view is out of the selection.
@Riverpod(keepAlive: true)
AsyncValue<Set<String>> backupVisibleIds(Ref ref) {
  final BackupShown shown = ref.watch(backupStateFilterProvider);
  if (shown.ignored) {
    final AsyncValue<List<BackupTile>> updates = ref.watch(
      backupVisibleTilesProvider,
    );
    final AsyncValue<List<ReconcileTile>> reconcile = ref.watch(
      backupVisibleReconcileTilesProvider,
    );
    return switch ((updates, reconcile)) {
      (
        AsyncData<List<BackupTile>>(value: final List<BackupTile> updateTiles),
        AsyncData<List<ReconcileTile>>(
          value: final List<ReconcileTile> reconcileTiles,
        ),
      ) =>
        AsyncData<Set<String>>(<String>{
          for (final BackupTile tile in updateTiles) tile.card.id,
          for (final ReconcileTile tile in reconcileTiles)
            for (final BackupReconcileReason reason
                in tile.entry.ignoredReasons)
              ignoredReconcileTileId(tile.entry.name, reason),
        }),
      (
        AsyncError<List<BackupTile>>(
          :final Object error,
          :final StackTrace stackTrace,
        ),
        _,
      ) =>
        AsyncError<Set<String>>(error, stackTrace),
      (
        _,
        AsyncError<List<ReconcileTile>>(
          :final Object error,
          :final StackTrace stackTrace,
        ),
      ) =>
        AsyncError<Set<String>>(error, stackTrace),
      _ => const AsyncLoading<Set<String>>(),
    };
  }
  if (shown.reconcile) {
    return ref
        .watch(backupVisibleReconcileTilesProvider)
        .whenData(
          (List<ReconcileTile> tiles) => <String>{
            for (final ReconcileTile tile in tiles)
              reconcileTileId(tile.entry.name),
          },
        );
  }
  return ref
      .watch(backupVisibleTilesProvider)
      .whenData(
        (List<BackupTile> tiles) => <String>{
          for (final BackupTile tile in tiles) tile.card.id,
        },
      );
}

/// Which backup cards are selected, by [BackupCard.id].
///
/// Its own selection rather than the extract tab's: the two grids show
/// different things, and a wallpaper live in both libraries is two cards here
/// and one there.
@Riverpod(keepAlive: true)
class BackupSelection extends _$BackupSelection {
  @override
  Set<String> build() {
    // Here rather than in the grid: the whole chain is kept alive, so filtering
    // from the other tab or changing a path in settings moves what is on screen
    // while the backup tab is not even mounted.
    ref.listen(backupVisibleIdsProvider, (
      AsyncValue<Set<String>>? previous,
      AsyncValue<Set<String>> next,
    ) {
      if (next case AsyncData<Set<String>>(:final Set<String> value)) {
        _queueRetain(value);
      }
    });
    ref.onDispose(() {
      _pendingVisibleIds = null;
      _retainScheduled = false;
    });
    return const <String>{};
  }

  Set<String>? _pendingVisibleIds;
  bool _retainScheduled = false;

  void _queueRetain(Set<String> ids) {
    _pendingVisibleIds = ids;
    if (_retainScheduled) return;
    _retainScheduled = true;
    // The visible-list provider can rebuild while Flutter is building a tile.
    // Prune selection in a microtask instead of mutating it mid-build.
    Future<void>.microtask(() {
      _retainScheduled = false;
      final Set<String>? visible = _pendingVisibleIds;
      _pendingVisibleIds = null;
      if (visible != null) retain(visible);
    });
  }

  /// Which tile a shift range reaches back to. The id, not the position:
  /// re-ordering the grid moves every tile without dropping any.
  String? shiftAnchor;

  void setExactly(Set<String> ids) {
    // Nothing to reach back to from an empty selection, so a shift click after
    // one does not pick up a range from the tile last clicked.
    if (ids.isEmpty) shiftAnchor = null;
    if (setEquals(ids, state)) return;
    state = ids.toSet();
  }

  void toggle(String id) {
    shiftAnchor = id;
    state = state.contains(id)
        ? (state.toSet()..remove(id))
        : (state.toSet()..add(id));
  }

  /// What a plain left click does, matching the extract tab: selects only [id],
  /// and clears it when it was already the only one selected.
  void setExclusive(String id) {
    state = state.length == 1 && state.contains(id)
        ? const <String>{}
        : <String>{id};
    // Nothing to reach back to from an empty selection.
    shiftAnchor = state.isEmpty ? null : id;
  }

  /// Drops ids the grid is not drawing: a selected tile nobody can see can be
  /// neither cleared nor spared by the operations still to come.
  void retain(Set<String> ids) {
    if (shiftAnchor != null && !ids.contains(shiftAnchor)) shiftAnchor = null;
    final Set<String> kept = state.where(ids.contains).toSet();
    if (kept.length != state.length) state = kept;
  }
}
