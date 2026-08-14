import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:we_repkg/constants/i10n.dart';
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
/// A notifier rather than provider state: the count moves every few folders,
/// and rebuilding the tab that often to redraw one line of text would be worse
/// than the silence it replaces. Only the line itself listens.
@Riverpod(keepAlive: true)
ValueNotifier<BackupScanProgress?> backupScanProgress(Ref ref) {
  final ValueNotifier<BackupScanProgress?> progress =
      ValueNotifier<BackupScanProgress?>(null);
  ref.onDispose(progress.dispose);
  return progress;
}

/// The whole comparison, run when the backup tab first asks for it.
///
/// Kept alive because leaving the tab unmounts the view and rescanning both
/// libraries is seconds of disk work. Watching the four paths is what refreshes
/// it when one of them changes; anything that writes to the backup invalidates
/// it by hand.
@Riverpod(keepAlive: true)
Future<BackupScan> backupScan(Ref ref) async {
  final String? backupRoot = ref.watch(backupRootProvider);
  final ValueNotifier<BackupScanProgress?> progress = ref.watch(
    backupScanProgressProvider,
  );
  final BackupScan scan = await scanBackup(
    backupRoot: backupRoot,
    liveWorkshopPath: ref.watch(wallpaperPathProvider),
    liveMyProjectsPath: ref.watch(myProjectsLibraryProvider),
    acfPath: ref.watch(acfPathProvider),
    onProgress: (BackupScanProgress value) => progress.value = value,
  );
  progress.value = null;
  // A Workshop card whose backup already matches live earns its baseline here.
  // Failing to write it must never cost the user the scan: a read-only backup
  // drive would otherwise replace the vanished list with an error string, and
  // nothing in this feature is allowed to weaken that tier. A lost baseline is
  // earned again on the next scan.
  try {
    await seedBackupRecords(backupRoot, scan.seeds);
  } catch (e) {
    debugPrint('${tr(AppI10n.errorSeedBackupRecordsFailed)} $e');
  }
  return scan;
}

/// The scan's cards in grid order, each with the title and preview to draw.
///
/// Kept apart from the scan so that reading a few thousand `project.json` files
/// cannot delay the counts, and so an unreadable one costs a picture rather
/// than a card.
@Riverpod(keepAlive: true)
Future<List<BackupTile>> backupTiles(Ref ref) async {
  final BackupScan scan = await ref.watch(backupScanProvider.future);
  final Map<BackupCard, CardFace> faces = await readCardFaces(
    backupRoot: ref.watch(backupRootProvider),
    liveWorkshopPath: ref.watch(wallpaperPathProvider),
    liveMyProjectsPath: ref.watch(myProjectsLibraryProvider),
    cards: scan.cards,
  );
  return <BackupTile>[
    for (final BackupCard card in sortedCards(scan.cards))
      (card: card, state: scan.cards[card]!, face: faces[card]),
  ];
}

/// The names waiting to be reconciled, each with the title and preview to draw.
///
/// Apart from [backupTiles]: a few hundred folders against several thousand,
/// and they only ever show behind their own pill.
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

/// Which state pills are lit, and whether the reconcile pill has taken over.
typedef BackupShown = ({Set<BackupState> states, bool reconcile});

/// Session state rather than a setting: the pills are how the tab is being
/// looked at now, and returning to a grid narrowed by a pill switched off days
/// ago is how a wallpaper goes missing quietly.
///
/// Opens on the one state with an obvious next step. Every other pill holding
/// anything glows for itself, so nothing is hidden by starting narrow.
@Riverpod(keepAlive: true)
class BackupStateFilter extends _$BackupStateFilter {
  @override
  BackupShown build() =>
      (states: <BackupState>{BackupState.notBackedUp}, reconcile: false);

  /// Lights or clears one state. Doing it while the reconcile pill holds the
  /// grid shows that state alone, because the other pills read as off there.
  void toggle(BackupState state) {
    if (this.state.reconcile) {
      this.state = (states: <BackupState>{state}, reconcile: false);
      return;
    }
    final Set<BackupState> next = this.state.states.toSet();
    next.contains(state) ? next.remove(state) : next.add(state);
    this.state = (states: next, reconcile: false);
  }

  /// Swaps the grid over. The pills keep what they had, so coming back out
  /// lands where it left.
  void toggleReconcile() =>
      state = (states: state.states, reconcile: !state.reconcile);
}

@Riverpod(keepAlive: true)
class BackupSortOrder extends _$BackupSortOrder {
  @override
  BackupSortType build() =>
      StorageUtil.getEnum(AppKeys.backupSortType, BackupSortType.values) ??
      BackupSortType.values.first;

  void update(BackupSortType type) async {
    state = type;
    await StorageUtil.setInt(AppKeys.backupSortType, type.index);
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

/// The cards the grid draws. Apart from [backupTiles] so that typing re-filters
/// a list in memory rather than re-reading a few thousand folders.
@Riverpod(keepAlive: true)
Future<List<BackupTile>> backupVisibleTiles(Ref ref) async {
  return visibleBackupTiles(
    tiles: await ref.watch(backupTilesProvider.future),
    states: ref.watch(backupStateFilterProvider).states,
    needle: ref.watch(backupSearchProvider).trim().toLowerCase(),
    filter: ref.watch(filterStateProvider),
    sort: ref.watch(backupSortOrderProvider),
    ascending: ref.watch(backupSortAscendingProvider),
  );
}

/// The reconcile tiles the grid draws, under the same search, filter and order.
@Riverpod(keepAlive: true)
Future<List<ReconcileTile>> backupVisibleReconcileTiles(Ref ref) async {
  return visibleReconcileTiles(
    tiles: await ref.watch(backupReconcileTilesProvider.future),
    needle: ref.watch(backupSearchProvider).trim().toLowerCase(),
    filter: ref.watch(filterStateProvider),
    sort: ref.watch(backupSortOrderProvider),
    ascending: ref.watch(backupSortAscendingProvider),
  );
}

/// Ids of whatever the grid is drawing, which is what the selection is pruned
/// against: a tile out of view is out of the selection.
@Riverpod(keepAlive: true)
Future<Set<String>> backupVisibleIds(Ref ref) async {
  if (ref.watch(backupStateFilterProvider).reconcile) {
    return <String>{
      for (final ReconcileTile tile in await ref.watch(
        backupVisibleReconcileTilesProvider.future,
      ))
        reconcileTileId(tile.entry.name),
    };
  }
  return <String>{
    for (final BackupTile tile in await ref.watch(
      backupVisibleTilesProvider.future,
    ))
      tile.card.id,
  };
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
        retain(value);
      }
    });
    return const <String>{};
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
