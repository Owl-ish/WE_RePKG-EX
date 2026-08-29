import 'package:we_repkg/models/enums.dart';
import 'package:we_repkg/models/filter.dart';
import 'package:we_repkg/utils/backup_diff.dart';
import 'package:we_repkg/utils/wallpaper_filter.dart';
import 'package:we_repkg/utils/wallpaper_search.dart';

/// One wallpaper in the backup grid. [face] is null for a folder with no
/// readable `project.json`, which the tile falls back to the folder name for.
typedef BackupTile = ({BackupCard card, BackupState state, CardFace? face});

/// One name waiting to be reconciled, drawn in the same grid behind its own
/// pill. A name, not a library, so it is one tile however many folders it has.
typedef ReconcileTile = ({ReconcileEntry entry, CardFace? face});

/// Selection ids for a reconcile tile, which is a name and no library and so
/// cannot collide with a card's `library/name`.
String reconcileTileId(String name) => 'reconcile/${name.toLowerCase()}';

/// Selection id for one ignored Reconcile warning. A wallpaper can have more
/// than one ignored warning, so the reason is part of its identity.
String ignoredReconcileTileId(String name, BackupReconcileReason reason) =>
    'ignored/${reason.name}/${reconcileTileId(name)}';

/// Number shown by the shared Ignored pill.
int ignoredDetectionCount({
  required Iterable<BackupCard> updates,
  required Iterable<ReconcileEntry> reconcile,
}) =>
    updates.length +
    reconcile.fold<int>(
      0,
      (int total, ReconcileEntry entry) => total + entry.ignoredReasons.length,
    );

/// The cards the grid draws: what the pills, the search box and the filter
/// button leave, in the chosen order.
List<BackupTile> visibleBackupTiles({
  required List<BackupTile> tiles,
  required BackupState state,
  required String needle,
  required WallpaperFilter filter,
  required BackupSortType sort,
  required bool ascending,
}) => visibleBackupTilesMatching(
  tiles: tiles,
  include: (BackupTile tile) => tile.state == state,
  needle: needle,
  filter: filter,
  sort: sort,
  ascending: ascending,
);

/// Shared filtering and sorting for normal state pills and Ignored.
List<BackupTile> visibleBackupTilesMatching({
  required List<BackupTile> tiles,
  required bool Function(BackupTile tile) include,
  required String needle,
  required WallpaperFilter filter,
  required BackupSortType sort,
  required bool ascending,
}) {
  final List<BackupTile> shown = <BackupTile>[
    for (final BackupTile tile in tiles)
      if (include(tile) &&
          _passes(
            face: tile.face,
            name: tile.card.name,
            needle: needle,
            filter: filter,
          ))
        tile,
  ];
  shown.sort(
    (BackupTile a, BackupTile b) => _compare(
      sort: sort,
      ascending: ascending,
      a: (name: a.card.name, library: a.card.library.key, face: a.face),
      b: (name: b.card.name, library: b.card.library.key, face: b.face),
    ),
  );
  return shown;
}

/// The reconcile tiles the grid draws. No state pills: the reconcile pill shows
/// them, and it shows all of them.
List<ReconcileTile> visibleReconcileTiles({
  required List<ReconcileTile> tiles,
  required String needle,
  required WallpaperFilter filter,
  required BackupSortType sort,
  required bool ascending,
}) {
  final List<ReconcileTile> shown = <ReconcileTile>[
    for (final ReconcileTile tile in tiles)
      if (_passes(
        face: tile.face,
        name: tile.entry.name,
        needle: needle,
        filter: filter,
      ))
        tile,
  ];
  shown.sort(
    (ReconcileTile a, ReconcileTile b) => _compare(
      sort: sort,
      ascending: ascending,
      a: (name: a.entry.name, library: '', face: a.face),
      b: (name: b.entry.name, library: '', face: b.face),
    ),
  );
  return shown;
}

bool _passes({
  required CardFace? face,
  required String name,
  required String needle,
  required WallpaperFilter filter,
}) {
  // A card with no readable project.json has no title to match on, and is still
  // found by its folder name.
  if (!matchesSearch(title: face?.title ?? '', id: name, needle: needle)) {
    return false;
  }
  return passesWallpaperFilter(
    type: face?.type ?? '',
    rating: face?.rating ?? '',
    filter: filter,
  );
}

typedef _Sortable = ({String name, String library, CardFace? face});

/// Each order has a natural direction: newest first or names from A, and the
/// toggle reverses it. Ties always break on name then library,
/// whichever way the list runs, so it holds still: shift-click and the marquee
/// index into these positions.
int _compare({
  required BackupSortType sort,
  required bool ascending,
  required _Sortable a,
  required _Sortable b,
}) {
  final int byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
  final int first = switch (sort) {
    BackupSortType.name => byName,
    BackupSortType.date => _byDate(a.face?.modified, b.face?.modified),
  };
  if (first != 0) return ascending ? -first : first;
  return byName != 0 ? byName : a.library.compareTo(b.library);
}

/// Newest first, undated last. Comparing undated equal to everything would make
/// the comparator intransitive and misplace the dated ones too.
int _byDate(DateTime? a, DateTime? b) {
  if (a == null) return b == null ? 0 : 1;
  if (b == null) return -1;
  return b.compareTo(a);
}
