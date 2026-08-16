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

  /// The backup library holds a folder for this wallpaper and there is nothing
  /// in it. A cancelled copy leaves exactly this, so it is kept apart from
  /// [notBackedUp]: one has never been backed up, the other looks backed up
  /// until you open it.
  emptyBackup,
}

/// What a card draws with, plus the three fields the tab filters and orders on.
///
/// [type] and [rating] are `project.json`'s own, lowercased, so one filter can
/// serve both grids. [modified] is that file's timestamp.
typedef CardFace = ({
  String title,
  String preview,
  String type,
  String rating,
  DateTime? modified,
});

/// Grid order: the states that need attention first, then by folder name.
///
/// The list the marquee and shift-click index into has to hold still across a
/// refresh, and both the differ's map and a directory listing come back in
/// whatever order the filesystem felt like.
List<BackupCard> sortedCards(Map<BackupCard, BackupState> cards) {
  final List<BackupCard> order = cards.keys.toList();
  order.sort((BackupCard a, BackupCard b) {
    final int byState = backupSeverity[cards[a]!]! - backupSeverity[cards[b]!]!;
    if (byState != 0) return byState;
    final int byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
    return byName != 0 ? byName : a.library.key.compareTo(b.library.key);
  });
  return order;
}

/// Worst first, and the one order the tab uses: the grid sorts by it and the
/// counts above the grid are listed in it.
///
/// Vanished leads because the backup is the only copy left. An empty backup
/// folder outranks never having backed one up: both are unprotected, but only
/// one of them looks protected.
const List<BackupState> backupStateOrder = <BackupState>[
  BackupState.vanished,
  BackupState.emptyBackup,
  BackupState.notBackedUp,
  BackupState.updateAvailable,
  BackupState.updateDismissed,
  BackupState.synced,
];

/// Position of each state in [backupStateOrder], for anything sorting by it.
final Map<BackupState, int> backupSeverity = <BackupState, int>{
  for (int i = 0; i < backupStateOrder.length; i++) backupStateOrder[i]: i,
};

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

/// The worst state holding anything, which is where the tab opens.
///
/// Falls back to not backed up, since a library where every count is zero has
/// nothing to open on and that is the one the user came here about.
BackupState worstBackupState(Map<BackupState, int> counts) =>
    backupStateOrder.firstWhere(
      (BackupState state) => (counts[state] ?? 0) > 0,
      orElse: () => BackupState.notBackedUp,
    );

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

/// A file under a wallpaper folder, by its path relative to that folder.
typedef FileEntry = ({String path, int size});

/// Wallpaper Engine rebuilds these for itself, so nothing copies them and
/// nothing may compare them. On a real library 1127 live myprojects folders
/// held one against 214 backup folders, so counting them would call almost
/// every myprojects backup stale. Lowercase, matching what [_relative] folds
/// its paths to.
const String rebuiltShaderDir = r'shaders\blobssm40\';

/// How a backup folder stands against the live wallpaper it mirrors.
enum CopyStanding {
  /// Every live file is in the backup at the same size.
  ///
  /// Files the backup holds *beyond* those do not count against it. Nothing
  /// ever deletes from a backup, so a wallpaper edited to drop a file leaves
  /// residue there for good; counting it would report an update that Back up
  /// can never clear, since backing up copies and never removes.
  covers,

  /// A live file is missing from the backup, or is there at a different size.
  behind,

  /// The backup folder holds nothing worth comparing.
  empty,
}

/// Windows sees one path whatever the case, and the two sides are listed by
/// separate walks that need not agree on it.
String _relative(FileEntry file) =>
    file.path.toLowerCase().replaceAll('/', r'\');

/// Whether a relative file path belongs to Wallpaper Engine's rebuilt cache.
/// Both the full comparison and the fast non-empty check must ignore it.
bool isRebuiltShaderPath(String relativePath) => relativePath
    .toLowerCase()
    .replaceAll('/', r'\')
    .startsWith(rebuiltShaderDir);

/// Whether the backup still holds everything the live wallpaper has.
///
/// Sizes, never timestamps: copying rewrites mtime, so a hand-made backup
/// differs from live on every one of them while being a perfectly good copy.
/// [folderVersion] is the other fingerprint and keeps mtime deliberately,
/// because there it is detecting an author editing their own wallpaper. Two
/// fingerprints, two jobs; do not merge them.
CopyStanding compareCopy({
  required Iterable<FileEntry> live,
  required Iterable<FileEntry> backup,
}) {
  final Map<String, int> held = <String, int>{};
  for (final FileEntry file in backup) {
    final String path = _relative(file);
    if (isRebuiltShaderPath(path)) continue;
    held[path] = file.size;
  }
  // Checked before coverage, so a folder holding only rebuilt shaders reads as
  // empty rather than as covering a live wallpaper it holds nothing of.
  if (held.isEmpty) return CopyStanding.empty;

  for (final FileEntry file in live) {
    final String path = _relative(file);
    if (isRebuiltShaderPath(path)) continue;
    if (held[path] != file.size) return CopyStanding.behind;
  }
  return CopyStanding.covers;
}

typedef BackupDiffResult = ({
  Map<BackupCard, BackupState> cards,
  List<ReconcileEntry> reconcile,
});

/// Every folder name sorted into a grid card or a reconcile entry.
///
/// Three tiers, and the order is the point. Live in neither library is vanished
/// and nothing may demote it, because a Workshop item Steam delisted without
/// saying so is the whole reason for the tab. A name live in both libraries is
/// always a reconcile decision, even with no backup at all. A backup placement
/// mismatch also reconciles. Everything else is an ordinary card.
///
/// Backup protection is wallpaper-level, not library-level: if either backup
/// library holds the name, the live wallpaper is backed up. The library split
/// still matters for update/version reporting and for deciding which folders a
/// reconcile entry offers to keep or remove.
BackupDiffResult backupDiff({
  required Set<String> liveWorkshop,
  required Set<String> liveMyProjects,
  required Set<String> backupWorkshop,
  required Set<String> backupMyProjects,
  required Map<String, String> liveWorkshopVersions,
  required Map<String, String> liveMyProjectsVersions,
  required Map<String, CopyStanding> workshopStanding,
  required Map<String, CopyStanding> myProjectsStanding,
  required Map<String, BackupRecord> records,
}) {
  final Map<String, String> liveW = _namesByKey(liveWorkshop);
  final Map<String, String> liveM = _namesByKey(liveMyProjects);
  final Map<String, String> backupW = _namesByKey(backupWorkshop);
  final Map<String, String> backupM = _namesByKey(backupMyProjects);

  final Map<String, String> versionsW = _keyed(liveWorkshopVersions);
  final Map<String, String> versionsM = _keyed(liveMyProjectsVersions);
  final Map<String, CopyStanding> standingW = _keyed(workshopStanding);
  final Map<String, CopyStanding> standingM = _keyed(myProjectsStanding);
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

    final bool coveredAnywhere = bw != null || bm != null;
    final Map<WallpaperLibrary, BackupState> states =
        <WallpaperLibrary, BackupState>{};
    if (workshopCard != null) {
      states[WallpaperLibrary.workshop] = bw == null && coveredAnywhere
          ? BackupState.synced
          : _cardState(
              library: WallpaperLibrary.workshop,
              covered: coveredAnywhere,
              liveVersion: versionsW[key],
              standing: standingW[key],
              record: byId[workshopCard.id],
            );
    }
    if (myProjectsCard != null) {
      states[WallpaperLibrary.myProjects] = bm == null && coveredAnywhere
          ? BackupState.synced
          : _cardState(
              library: WallpaperLibrary.myProjects,
              covered: coveredAnywhere,
              liveVersion: versionsM[key],
              standing: standingM[key],
              record: byId[myProjectsCard.id],
            );
    }

    final bool duplicateLive = lw != null && lm != null;
    final bool placementMismatch =
        (bw != null && lw == null) || (bm != null && lm == null);
    if (duplicateLive || placementMismatch) {
      // Tier 1 returned already, so one of the two live names is non-null. A
      // duplicate live name is itself the ambiguity: Steam may have restored a
      // Workshop copy beside an edited MyProjects copy without the user seeing
      // it happen.
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

/// State of one grid card. The two libraries answer "is the backup stale?"
/// differently, because only one of them has a version to ask Steam for.
///
/// myprojects compares the two folders directly and keeps no baseline. Its
/// version is already a fingerprint, so a recorded one would add nothing and
/// would go stale the moment anything touched the backup outside this app.
///
/// Workshop uses the version recorded by an explicit backup. Steam's manifest
/// names the live version only; when no record exists, the two folders are
/// compared directly without writing anything during the scan.
///
/// A Workshop folder with no manifest was dropped in by hand and will never
/// gain one, so it is left alone rather than nagging forever with no version to
/// dismiss. The caller's banner covers the other reason a manifest is missing,
/// which is an unreadable ACF.
BackupState _cardState({
  required WallpaperLibrary library,
  required bool covered,
  required String? liveVersion,
  required CopyStanding? standing,
  required BackupRecord? record,
}) {
  if (!covered) return BackupState.notBackedUp;
  // Before anything else, including the Workshop baseline: a folder with
  // nothing in it is not a backup, whatever a record says about it.
  if (standing == CopyStanding.empty) {
    return BackupState.emptyBackup;
  }

  final String? dismissed = record?.dismissedVersion;
  BackupState behind() => liveVersion != null && liveVersion == dismissed
      ? BackupState.updateDismissed
      : BackupState.updateAvailable;

  if (library == WallpaperLibrary.myProjects) {
    return standing == CopyStanding.behind ? behind() : BackupState.synced;
  }

  if (liveVersion == null) return BackupState.synced;

  final String? backedUp = record?.backedUpVersion;
  if (backedUp != null) {
    return liveVersion == backedUp ? BackupState.synced : behind();
  }
  return switch (standing) {
    CopyStanding.covers => BackupState.synced,
    CopyStanding.behind => behind(),
    // Nothing was compared, so there is nothing to record and nothing to
    // report. Leaving it alone beats guessing in either direction.
    _ => BackupState.synced,
  };
}
