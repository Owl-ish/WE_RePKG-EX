/// Which library a wallpaper folder sits in.
///
/// The key is what the records file uses, so it stays lowercase rather than
/// following the Dart constant.
enum WallpaperLibrary {
  workshop('workshop'),
  myProjects('myprojects');

  const WallpaperLibrary(this.key);

  final String key;
}

/// One card in the backup grid: a library and a folder name, never a folder
/// name alone.
///
/// A wallpaper under the same name in both libraries is two cards. The
/// myprojects copy is the one the author unpacks and edits, so it carries its
/// own version and its own state, and editing it leaves the Workshop original
/// alone.
class BackupCard {
  const BackupCard(this.library, this.name);

  final WallpaperLibrary library;
  final String name;

  /// Key for the records file. Windows forbids `/` in a folder name, which is
  /// what keeps the split unambiguous, and lowercased so that re-casing a
  /// folder updates its record rather than writing a second one beside it.
  String get id => '${library.key}/${name.toLowerCase()}';

  @override
  bool operator ==(Object other) =>
      other is BackupCard && other.library == library && other.name == name;

  @override
  int get hashCode => Object.hash(library, name);

  @override
  String toString() => '${library.key}/$name';
}

/// Where a wallpaper stands between the live libraries and the backup.
enum BackupState {
  /// Backed up and current, or backed up at a version nothing can compare.
  synced,
  notBackedUp,

  /// In the backup and in neither live library. Steam removes a delisted
  /// wallpaper without saying so, which is the case this whole tab exists for.
  vanished,
  updateAvailable,
  updateDismissed,
}

/// How many cards sit in each state, zero-filled so a caller can list every
/// state without checking for null.
Map<BackupState, int> countByState(Iterable<BackupState> states) {
  final Map<BackupState, int> counts = <BackupState, int>{
    for (final BackupState state in BackupState.values) state: 0,
  };
  for (final BackupState state in states) {
    counts[state] = counts[state]! + 1;
  }
  return counts;
}

/// A folder name whose backup layout does not mirror its live layout.
///
/// The four flags are what the card's presence matrix draws. Binning the
/// leftover and backing up the unprotected copy are two decisions about one
/// wallpaper, so a name gets one entry rather than one per mismatch.
class ReconcileEntry {
  const ReconcileEntry({
    required this.name,
    required this.states,
    required this.backupWorkshop,
    required this.backupMyProjects,
  });

  final String name;

  /// What each live copy would read as an ordinary card, one entry per live
  /// library. Carried here so a wallpaper waiting to be reconciled still shows
  /// an update rather than going quiet until the user gets to it.
  final Map<WallpaperLibrary, BackupState> states;

  final bool backupWorkshop;
  final bool backupMyProjects;

  bool get liveWorkshop => states.containsKey(WallpaperLibrary.workshop);
  bool get liveMyProjects => states.containsKey(WallpaperLibrary.myProjects);

  /// Backup copies with no live counterpart, which is what put the name here.
  ///
  /// This names the shape for the card's reason ribbon. It is not the set the
  /// keep checkboxes drive: every backup folder present gets one, orphan or
  /// not, or a card listing two backup copies would leave one unremovable.
  Set<WallpaperLibrary> get orphans => <WallpaperLibrary>{
    if (backupWorkshop && !liveWorkshop) WallpaperLibrary.workshop,
    if (backupMyProjects && !liveMyProjects) WallpaperLibrary.myProjects,
  };

  /// Live copies their own backup library does not hold, which is what gates
  /// the card's Back up action.
  Set<WallpaperLibrary> get needsBackup => <WallpaperLibrary>{
    for (final MapEntry<WallpaperLibrary, BackupState> entry in states.entries)
      if (entry.value == BackupState.notBackedUp) entry.key,
  };

  // Two possible keys and no null values, so looking both up compares the whole
  // map without needing a deep-equality helper.
  @override
  bool operator ==(Object other) =>
      other is ReconcileEntry &&
      other.name == name &&
      other.backupWorkshop == backupWorkshop &&
      other.backupMyProjects == backupMyProjects &&
      other.states[WallpaperLibrary.workshop] ==
          states[WallpaperLibrary.workshop] &&
      other.states[WallpaperLibrary.myProjects] ==
          states[WallpaperLibrary.myProjects];

  @override
  int get hashCode => Object.hash(
    name,
    backupWorkshop,
    backupMyProjects,
    states[WallpaperLibrary.workshop],
    states[WallpaperLibrary.myProjects],
  );

  @override
  String toString() =>
      '$name(${liveWorkshop ? 'LW' : ''}${liveMyProjects ? 'LM' : ''}'
      '${backupWorkshop ? 'BW' : ''}${backupMyProjects ? 'BM' : ''})';
}

/// What the backup holds for one wallpaper, and which update was waved off.
///
/// Versions are opaque: Steam's manifest for a Workshop item, a size and mtime
/// digest for a myprojects one. Comparing them needs no idea which is which.
class BackupRecord {
  const BackupRecord({this.backedUpVersion, this.dismissedVersion});

  final String? backedUpVersion;
  final String? dismissedVersion;
}

/// A file sitting directly in a wallpaper folder.
class FileStamp {
  const FileStamp({
    required this.name,
    required this.size,
    required this.modified,
  });

  final String name;
  final int size;
  final DateTime modified;
}

/// Version token for a myprojects wallpaper, which has no ACF to ask.
///
/// Only the files directly in the folder count. `project.json` and the scene
/// definition live there, so an edit to the wallpaper shows up; swapping an
/// unpacked asset in a subfolder without touching the scene does not. Listing
/// order varies, so sort before joining. Windows forbids `|` in a filename,
/// which is what keeps the join unambiguous.
String? folderVersion(Iterable<FileStamp> topLevelFiles) {
  final List<FileStamp> files = topLevelFiles.toList()
    ..sort((FileStamp a, FileStamp b) => a.name.compareTo(b.name));
  if (files.isEmpty) return null;
  return files
      .map(
        (FileStamp f) =>
            '${f.name}|${f.size}|${f.modified.millisecondsSinceEpoch}',
      )
      .join(';');
}

typedef BackupDiffResult = ({
  Map<BackupCard, BackupState> cards,
  List<ReconcileEntry> reconcile,
});

/// Every folder name sorted into a grid card or a reconcile entry.
///
/// Three tiers, and the order is the point. Live in neither library is vanished
/// and nothing may demote it, because a Workshop item Steam delisted without
/// saying so is the whole reason for the tab. Otherwise one orphan sends the
/// whole name to reconcile. Everything else is an ordinary card per live
/// library, covered only by its own backup library.
///
/// Coverage was pooled in an earlier design and the reversal is deliberate:
/// see `.claude/backup-restore.md` under States.
BackupDiffResult backupDiff({
  required Set<String> liveWorkshop,
  required Set<String> liveMyProjects,
  required Set<String> backupWorkshop,
  required Set<String> backupMyProjects,
  required Map<String, String> liveWorkshopVersions,
  required Map<String, String> liveMyProjectsVersions,
  required Map<String, BackupRecord> records,
}) {
  final Map<String, String> liveW = _namesByKey(liveWorkshop);
  final Map<String, String> liveM = _namesByKey(liveMyProjects);
  final Map<String, String> backupW = _namesByKey(backupWorkshop);
  final Map<String, String> backupM = _namesByKey(backupMyProjects);

  final Map<String, String> versionsW = _keyed(liveWorkshopVersions);
  final Map<String, String> versionsM = _keyed(liveMyProjectsVersions);
  final Map<String, BackupRecord> byId = _keyed(records);

  final Map<BackupCard, BackupState> cards = <BackupCard, BackupState>{};
  final List<ReconcileEntry> reconcile = <ReconcileEntry>[];

  final Set<String> keys = <String>{
    ...liveW.keys,
    ...liveM.keys,
    ...backupW.keys,
    ...backupM.keys,
  };

  for (final String key in keys) {
    final String? lw = liveW[key];
    final String? lm = liveM[key];
    final String? bw = backupW[key];
    final String? bm = backupM[key];

    if (lw == null && lm == null) {
      if (bw != null) {
        cards[BackupCard(WallpaperLibrary.workshop, bw)] = BackupState.vanished;
      }
      if (bm != null) {
        cards[BackupCard(WallpaperLibrary.myProjects, bm)] =
            BackupState.vanished;
      }
      continue;
    }

    final BackupCard? workshopCard = lw == null
        ? null
        : BackupCard(WallpaperLibrary.workshop, lw);
    final BackupCard? myProjectsCard = lm == null
        ? null
        : BackupCard(WallpaperLibrary.myProjects, lm);

    final Map<WallpaperLibrary, BackupState> states =
        <WallpaperLibrary, BackupState>{
          if (workshopCard != null)
            WallpaperLibrary.workshop: _cardState(
              bw != null,
              versionsW[key],
              byId[workshopCard.id],
            ),
          if (myProjectsCard != null)
            WallpaperLibrary.myProjects: _cardState(
              bm != null,
              versionsM[key],
              byId[myProjectsCard.id],
            ),
        };

    if ((bw != null && lw == null) || (bm != null && lm == null)) {
      // Tier 1 returned already, so one of the two live names is non-null,
      // which is also why the order here does not matter.
      reconcile.add(
        ReconcileEntry(
          name: lw ?? lm!,
          states: states,
          backupWorkshop: bw != null,
          backupMyProjects: bm != null,
        ),
      );
      continue;
    }

    if (workshopCard != null) {
      cards[workshopCard] = states[WallpaperLibrary.workshop]!;
    }
    if (myProjectsCard != null) {
      cards[myProjectsCard] = states[WallpaperLibrary.myProjects]!;
    }
  }

  return (cards: cards, reconcile: reconcile);
}

/// One library's names under a lowercased key, since Windows sees `A` and `a`
/// as one folder.
Map<String, String> _namesByKey(Set<String> names) => <String, String>{
  for (final String name in names) name.toLowerCase(): name,
};

Map<String, V> _keyed<V>(Map<String, V> byName) => <String, V>{
  for (final MapEntry<String, V> entry in byName.entries)
    entry.key.toLowerCase(): entry.value,
};

/// State of one grid card.
///
/// Either version missing means nothing can be compared, so the wallpaper is
/// left alone. The two cases are not the same, though: no recorded version is a
/// folder copied into the backup by hand, while no live version means the ACF
/// could not be read. The caller warns about that one rather than letting a
/// whole library quietly read as current. Back up stays available on a synced
/// card, which is how one with no record acquires a baseline.
BackupState _cardState(
  bool covered,
  String? liveVersion,
  BackupRecord? record,
) {
  if (!covered) return BackupState.notBackedUp;
  final String? backedUp = record?.backedUpVersion;
  if (liveVersion == null || backedUp == null) return BackupState.synced;
  if (liveVersion == backedUp) return BackupState.synced;
  if (liveVersion == record?.dismissedVersion) {
    return BackupState.updateDismissed;
  }
  return BackupState.updateAvailable;
}
