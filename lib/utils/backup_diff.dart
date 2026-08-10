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
    if (path.startsWith(rebuiltShaderDir)) continue;
    held[path] = file.size;
  }
  // Checked before coverage, so a folder holding only rebuilt shaders reads as
  // empty rather than as covering a live wallpaper it holds nothing of.
  if (held.isEmpty) return CopyStanding.empty;

  for (final FileEntry file in live) {
    final String path = _relative(file);
    if (path.startsWith(rebuiltShaderDir)) continue;
    if (held[path] != file.size) return CopyStanding.behind;
  }
  return CopyStanding.covers;
}

typedef BackupDiffResult = ({
  Map<BackupCard, BackupState> cards,
  List<ReconcileEntry> reconcile,

  /// Baselines the comparison earned, by [BackupCard.id]. Returned rather than
  /// written, so the differ stays pure and one named caller owns the only write
  /// this feature makes into the user's backup.
  Map<String, String> seeds,
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
  final Map<String, String> seeds = <String, String>{};

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
        <WallpaperLibrary, BackupState>{};
    if (workshopCard != null) {
      final _Verdict verdict = _cardState(
        library: WallpaperLibrary.workshop,
        covered: bw != null,
        liveVersion: versionsW[key],
        standing: standingW[key],
        record: byId[workshopCard.id],
      );
      states[WallpaperLibrary.workshop] = verdict.state;
      if (verdict.seed != null) seeds[workshopCard.id] = verdict.seed!;
    }
    if (myProjectsCard != null) {
      final _Verdict verdict = _cardState(
        library: WallpaperLibrary.myProjects,
        covered: bm != null,
        liveVersion: versionsM[key],
        standing: standingM[key],
        record: byId[myProjectsCard.id],
      );
      states[WallpaperLibrary.myProjects] = verdict.state;
      if (verdict.seed != null) seeds[myProjectsCard.id] = verdict.seed!;
    }

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

  return (cards: cards, reconcile: reconcile, seeds: seeds);
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

typedef _Verdict = ({BackupState state, String? seed});

/// State of one grid card. The two libraries answer "is the backup stale?"
/// differently, because only one of them has a version to ask Steam for.
///
/// myprojects compares the two folders directly and keeps no baseline. Its
/// version is already a fingerprint, so a recorded one would add nothing and
/// would go stale the moment anything touched the backup outside this app.
///
/// Workshop keeps a baseline, seeded on first sight. Steam's manifest names
/// the live version only; nothing inside a wallpaper folder says which version
/// it is. So a card with no record compares both folders once. Matching
/// records the live manifest, not the comparison, or every Workshop card
/// would compare a fingerprint against a manifest and read as out of date for
/// good. Not matching reports the update and writes nothing, leaving the card
/// on this path until a backup fixes it.
///
/// A Workshop folder with no manifest was dropped in by hand and will never
/// gain one, so it is left alone rather than nagging forever with no version to
/// dismiss. The caller's banner covers the other reason a manifest is missing,
/// which is an unreadable ACF.
_Verdict _cardState({
  required WallpaperLibrary library,
  required bool covered,
  required String? liveVersion,
  required CopyStanding? standing,
  required BackupRecord? record,
}) {
  if (!covered) return (state: BackupState.notBackedUp, seed: null);
  // Before anything else, including the Workshop baseline: a folder with
  // nothing in it is not a backup, whatever a record says about it.
  if (standing == CopyStanding.empty) {
    return (state: BackupState.emptyBackup, seed: null);
  }

  final String? dismissed = record?.dismissedVersion;
  _Verdict behind() => liveVersion != null && liveVersion == dismissed
      ? (state: BackupState.updateDismissed, seed: null)
      : (state: BackupState.updateAvailable, seed: null);

  if (library == WallpaperLibrary.myProjects) {
    return standing == CopyStanding.behind
        ? behind()
        : (state: BackupState.synced, seed: null);
  }

  if (liveVersion == null) return (state: BackupState.synced, seed: null);

  final String? backedUp = record?.backedUpVersion;
  if (backedUp != null) {
    return liveVersion == backedUp
        ? (state: BackupState.synced, seed: null)
        : behind();
  }
  return switch (standing) {
    CopyStanding.covers => (state: BackupState.synced, seed: liveVersion),
    CopyStanding.behind => behind(),
    // Nothing was compared, so there is nothing to record and nothing to
    // report. Leaving it alone beats guessing in either direction.
    _ => (state: BackupState.synced, seed: null),
  };
}
