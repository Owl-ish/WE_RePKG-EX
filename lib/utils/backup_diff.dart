import 'package:flutter/foundation.dart';

// Stored in backup records. Keep these keys lowercase and stable for compatibility.
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

enum BackupState {
  synced,
  notBackedUp,
  vanished,
  updateAvailable,
  updateDismissed,
  emptyBackup,
}

// Each normal pill exposes at most one safe action.
enum BackupAction { backUp, update, restore, recycleJunk, showUpdateAgain }

// Update refreshes content. Sync fixes which backup library owns the copy.
enum BackupUpdateKind { update, sync }

enum BackupSyncKind { relocate, removeDuplicate }

/// Structural correction for a protected backup that is misplaced or duplicated.
class BackupSyncPlan {
  const BackupSyncPlan({
    required this.kind,
    required this.from,
    required this.to,
  });

  final BackupSyncKind kind;
  final WallpaperLibrary from;
  final WallpaperLibrary to;

  @override
  bool operator ==(Object other) =>
      other is BackupSyncPlan &&
      other.kind == kind &&
      other.from == from &&
      other.to == to;

  @override
  int get hashCode => Object.hash(kind, from, to);
}

/// Work represented by Update Available: refresh content, normalize placement,
/// or both.
class BackupUpdatePlan {
  const BackupUpdatePlan({this.updateContent = false, this.sync});

  final bool updateContent;
  final BackupSyncPlan? sync;

  bool get needsSync => sync != null;

  @override
  bool operator ==(Object other) =>
      other is BackupUpdatePlan &&
      other.updateContent == updateContent &&
      other.sync == sync;

  @override
  int get hashCode => Object.hash(updateContent, sync);
}

BackupAction? actionForBackupState(BackupState state) => switch (state) {
  BackupState.notBackedUp => BackupAction.backUp,
  BackupState.vanished => BackupAction.restore,
  BackupState.emptyBackup => BackupAction.recycleJunk,
  BackupState.updateAvailable => BackupAction.update,
  BackupState.updateDismissed => BackupAction.showUpdateAgain,
  BackupState.synced => null,
};

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

/// Why a wallpaper cannot be resolved safely without user intent.
enum BackupReconcileReason {
  duplicateLiveCopies,
  conflictingBackupCopies,
  comparisonUnavailable,
}

/// What differs between the two backup copies for one wallpaper.
class BackupCopyDifference {
  const BackupCopyDifference({
    this.differentSize = const <String>[],
    this.onlyWorkshop = const <String>[],
    this.onlyMyProjects = const <String>[],
  });

  final List<String> differentSize;
  final List<String> onlyWorkshop;
  final List<String> onlyMyProjects;

  int get total =>
      differentSize.length + onlyWorkshop.length + onlyMyProjects.length;

  @override
  bool operator ==(Object other) =>
      other is BackupCopyDifference &&
      listEquals(other.differentSize, differentSize) &&
      listEquals(other.onlyWorkshop, onlyWorkshop) &&
      listEquals(other.onlyMyProjects, onlyMyProjects);

  @override
  int get hashCode => Object.hash(
    Object.hashAll(differentSize),
    Object.hashAll(onlyWorkshop),
    Object.hashAll(onlyMyProjects),
  );
}

/// A wallpaper whose copies cannot be mapped safely by the automatic rules.
class ReconcileEntry {
  const ReconcileEntry({
    required this.name,
    required this.reason,
    required this.states,
    required this.backupWorkshop,
    required this.backupMyProjects,
    this.backupDifference,
  });

  final String name;
  final BackupReconcileReason reason;

  /// What each live copy would read as an ordinary card, one entry per live
  /// library. Carried here so a wallpaper waiting to be reconciled still shows
  /// an update rather than going quiet until the user gets to it.
  final Map<WallpaperLibrary, BackupState> states;

  final bool backupWorkshop;
  final bool backupMyProjects;
  final BackupCopyDifference? backupDifference;

  bool get liveWorkshop => states.containsKey(WallpaperLibrary.workshop);
  bool get liveMyProjects => states.containsKey(WallpaperLibrary.myProjects);

  /// Backup libraries that hold this name without a same-library live copy.
  ///
  /// This is diagnostic structure information for Reconcile. It does not imply
  /// that the backup is unprotected, removable, or eligible for an automatic
  /// cleanup action.
  Set<WallpaperLibrary> get orphans => <WallpaperLibrary>{
    if (backupWorkshop && !liveWorkshop) WallpaperLibrary.workshop,
    if (backupMyProjects && !liveMyProjects) WallpaperLibrary.myProjects,
  };

  /// Live libraries whose Reconcile state is still Not backed up.
  ///
  /// The Reconcile tile uses this only to surface the Not backed up badge;
  /// Reconcile itself remains diagnostic and exposes no automatic backup action.
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
      other.reason == reason &&
      other.backupWorkshop == backupWorkshop &&
      other.backupMyProjects == backupMyProjects &&
      other.backupDifference == backupDifference &&
      other.states[WallpaperLibrary.workshop] ==
          states[WallpaperLibrary.workshop] &&
      other.states[WallpaperLibrary.myProjects] ==
          states[WallpaperLibrary.myProjects];

  @override
  int get hashCode => Object.hash(
    name,
    reason,
    backupWorkshop,
    backupMyProjects,
    backupDifference,
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

/// Wallpaper Engine rebuilds this cache, so backup operations and comparisons
/// ignore it. Lowercase matches the normalized relative paths used below.
const String rebuiltShaderDir = r'shaders\blobssm40\';

/// How a backup folder stands against the live wallpaper it mirrors.
enum CopyStanding {
  /// Live and backup contain the same meaningful files at the same sizes.
  covers,

  /// A meaningful file is missing, extra, or has a different size.
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

/// Whether the backup mirrors the live wallpaper's meaningful files.
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
  final Map<String, int> liveFiles = <String, int>{};
  final Map<String, int> backupFiles = <String, int>{};
  for (final FileEntry file in live) {
    final String relative = _relative(file);
    if (!isRebuiltShaderPath(relative)) liveFiles[relative] = file.size;
  }
  for (final FileEntry file in backup) {
    final String relative = _relative(file);
    if (!isRebuiltShaderPath(relative)) backupFiles[relative] = file.size;
  }
  if (backupFiles.isEmpty) return CopyStanding.empty;
  if (liveFiles.length != backupFiles.length) return CopyStanding.behind;
  for (final MapEntry<String, int> file in liveFiles.entries) {
    if (backupFiles[file.key] != file.value) return CopyStanding.behind;
  }
  return CopyStanding.covers;
}

typedef BackupDiffResult = ({
  Map<BackupCard, BackupState> cards,
  Map<BackupCard, BackupUpdatePlan> updates,
  List<ReconcileEntry> reconcile,
});

enum BackupRuleKind { absent, vanished, ordinary, structureSync, reconcile }

typedef BackupRuleDecision = ({
  BackupRuleKind kind,
  BackupReconcileReason? reconcileReason,
});

/// One source of truth for how folder presence affects a wallpaper.
BackupRuleDecision backupRule({
  required bool liveWorkshop,
  required bool liveMyProjects,
  required bool backupWorkshop,
  required bool backupMyProjects,
  bool backupCopiesEquivalent = false,
  bool backupComparisonUnavailable = false,
  bool contentComparisonUnavailable = false,
}) {
  final int liveCount = (liveWorkshop ? 1 : 0) + (liveMyProjects ? 1 : 0);
  final int backupCount = (backupWorkshop ? 1 : 0) + (backupMyProjects ? 1 : 0);

  // No live or backup copy means there is nothing to show.
  if (liveCount == 0 && backupCount == 0) {
    return (kind: BackupRuleKind.absent, reconcileReason: null);
  }

  //====================
  // Vanished Rules
  //====================
  // No live copy exists in either live library.
  // At least one valid backup exists in either backup library.
  if (liveCount == 0) {
    return (kind: BackupRuleKind.vanished, reconcileReason: null);
  }

  final bool ownBackup = liveWorkshop ? backupWorkshop : backupMyProjects;
  final bool otherBackup = liveWorkshop ? backupMyProjects : backupWorkshop;

  //====================
  // Reconcile Rules
  //====================
  // Two live copies make the authoritative source ambiguous.
  // Different backup copies need a user decision before either is replaced.
  // Failed required comparisons stay unknown instead of being guessed Synced.
  if (liveCount > 1) {
    return (
      kind: BackupRuleKind.reconcile,
      reconcileReason: BackupReconcileReason.duplicateLiveCopies,
    );
  }
  if (ownBackup && otherBackup) {
    if (backupComparisonUnavailable) {
      return (
        kind: BackupRuleKind.reconcile,
        reconcileReason: BackupReconcileReason.comparisonUnavailable,
      );
    }
    if (!backupCopiesEquivalent) {
      return (
        kind: BackupRuleKind.reconcile,
        reconcileReason: BackupReconcileReason.conflictingBackupCopies,
      );
    }
  }
  if (ownBackup && !otherBackup && contentComparisonUnavailable) {
    return (
      kind: BackupRuleKind.reconcile,
      reconcileReason: BackupReconcileReason.comparisonUnavailable,
    );
  }

  //====================
  // Update / Sync Rules
  //====================
  // A usable backup exists, but its top-level library placement is wrong.
  // Equivalent copies in both backup libraries are also safe structure cleanup.
  // Placement problems cannot be hidden by dismissing a content update.
  if (otherBackup) {
    return (kind: BackupRuleKind.structureSync, reconcileReason: null);
  }

  return (kind: BackupRuleKind.ordinary, reconcileReason: null);
}

/// Every folder name sorted into a grid card or a reconcile entry.
///
/// Backup protection is wallpaper-level: either backup tree protects the live
/// wallpaper. A lone opposite-tree backup needs structure sync. Duplicate live
/// copies reconcile. Dual backups reconcile when different or uncomparable;
/// equivalent copies use Update / Sync.
BackupDiffResult backupDiff({
  required Set<String> liveWorkshop,
  required Set<String> liveMyProjects,
  required Set<String> backupWorkshop,
  required Set<String> backupMyProjects,
  required Map<String, String> liveWorkshopVersions,
  required Map<String, String> liveMyProjectsVersions,
  required Map<String, CopyStanding> workshopStanding,
  required Map<String, CopyStanding> myProjectsStanding,
  Map<String, CopyStanding> crossWorkshopStanding =
      const <String, CopyStanding>{},
  Map<String, CopyStanding> crossMyProjectsStanding =
      const <String, CopyStanding>{},
  required Map<String, BackupRecord> records,
  Set<String> equivalentBackupCopies = const <String>{},
  Set<String> unavailableBackupComparisons = const <String>{},
  Map<String, BackupCopyDifference> backupCopyDifferences =
      const <String, BackupCopyDifference>{},
  Set<String> unavailableContentComparisons = const <String>{},
}) {
  final Map<String, String> liveW = _namesByKey(liveWorkshop);
  final Map<String, String> liveM = _namesByKey(liveMyProjects);
  final Map<String, String> backupW = _namesByKey(backupWorkshop);
  final Map<String, String> backupM = _namesByKey(backupMyProjects);

  final Map<String, String> versionsW = _keyed(liveWorkshopVersions);
  final Map<String, String> versionsM = _keyed(liveMyProjectsVersions);
  final Map<String, CopyStanding> standingW = _keyed(workshopStanding);
  final Map<String, CopyStanding> standingM = _keyed(myProjectsStanding);
  final Map<String, CopyStanding> crossStandingW = _keyed(
    crossWorkshopStanding,
  );
  final Map<String, CopyStanding> crossStandingM = _keyed(
    crossMyProjectsStanding,
  );
  final Map<String, BackupRecord> byId = _keyed(records);
  final Set<String> equivalent = <String>{
    for (final String name in equivalentBackupCopies) name.toLowerCase(),
  };
  final Set<String> backupUnavailable = <String>{
    for (final String name in unavailableBackupComparisons) name.toLowerCase(),
  };
  final Map<String, BackupCopyDifference> differences = _keyed(
    backupCopyDifferences,
  );
  final Set<String> contentUnavailable = <String>{
    for (final String id in unavailableContentComparisons) id.toLowerCase(),
  };

  final Map<BackupCard, BackupState> cards = <BackupCard, BackupState>{};
  final Map<BackupCard, BackupUpdatePlan> updates =
      <BackupCard, BackupUpdatePlan>{};
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

    final String? liveId = lw != null
        ? BackupCard(WallpaperLibrary.workshop, lw).id
        : lm != null
        ? BackupCard(WallpaperLibrary.myProjects, lm).id
        : null;
    final BackupRuleDecision decision = backupRule(
      liveWorkshop: lw != null,
      liveMyProjects: lm != null,
      backupWorkshop: bw != null,
      backupMyProjects: bm != null,
      backupCopiesEquivalent: equivalent.contains(key),
      backupComparisonUnavailable: backupUnavailable.contains(key),
      contentComparisonUnavailable:
          liveId != null && contentUnavailable.contains(liveId),
    );
    final BackupRuleKind rule = decision.kind;
    if (rule == BackupRuleKind.absent) continue;
    if (rule == BackupRuleKind.vanished) {
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
      states[WallpaperLibrary.workshop] = _cardState(
        library: WallpaperLibrary.workshop,
        covered: coveredAnywhere,
        liveVersion: versionsW[key],
        standing: bw != null ? standingW[key] : crossStandingW[key],
        record: byId[workshopCard.id],
      );
    }
    if (myProjectsCard != null) {
      states[WallpaperLibrary.myProjects] = _cardState(
        library: WallpaperLibrary.myProjects,
        covered: coveredAnywhere,
        liveVersion: versionsM[key],
        standing: bm != null ? standingM[key] : crossStandingM[key],
        record: byId[myProjectsCard.id],
      );
    }

    if (rule == BackupRuleKind.reconcile) {
      reconcile.add(
        ReconcileEntry(
          name: lw ?? lm!,
          reason: decision.reconcileReason!,
          states: states,
          backupWorkshop: bw != null,
          backupMyProjects: bm != null,
          backupDifference: differences[key],
        ),
      );
      continue;
    }

    final BackupCard liveCard = workshopCard ?? myProjectsCard!;
    final BackupState contentState = states[liveCard.library]!;
    if (rule == BackupRuleKind.structureSync) {
      final WallpaperLibrary other =
          liveCard.library == WallpaperLibrary.workshop
          ? WallpaperLibrary.myProjects
          : WallpaperLibrary.workshop;
      final bool ownBackup = liveCard.library == WallpaperLibrary.workshop
          ? bw != null
          : bm != null;
      updates[liveCard] = BackupUpdatePlan(
        updateContent: contentState == BackupState.updateAvailable,
        sync: BackupSyncPlan(
          kind: ownBackup
              ? BackupSyncKind.removeDuplicate
              : BackupSyncKind.relocate,
          from: other,
          to: liveCard.library,
        ),
      );
      cards[liveCard] = BackupState.updateAvailable;
      continue;
    }

    cards[liveCard] = contentState;
    if (contentState == BackupState.updateAvailable) {
      updates[liveCard] = const BackupUpdatePlan(updateContent: true);
    }
  }

  return (cards: cards, updates: updates, reconcile: reconcile);
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

// Content staleness is calculated only after presence rules have decided the pill.
BackupState _cardState({
  required WallpaperLibrary library,
  required bool covered,
  required String? liveVersion,
  required CopyStanding? standing,
  required BackupRecord? record,
}) {
  //====================
  // Not Backed Up Rules
  //====================
  // A live copy exists.
  // No usable backup exists in either backup library.
  if (!covered) return BackupState.notBackedUp;

  //====================
  // Empty / Junk Rules
  //====================
  // A backup folder exists, but contains nothing worth protecting.
  // Rebuilt shader cache does not count as wallpaper content.
  // This stays separate because the folder can misleadingly look backed up.
  if (standing == CopyStanding.empty) {
    return BackupState.emptyBackup;
  }

  final String? dismissed = record?.dismissedVersion;

  BackupState behind() {
    //====================
    // Update Dismissed Rules
    //====================
    // A real content update exists and matches the version the user dismissed.
    // Only the content update is hidden; placement problems still use Update / Sync.
    if (liveVersion != null && liveVersion == dismissed) {
      return BackupState.updateDismissed;
    }

    // A real content difference uses the Update / Sync pill too.
    return BackupState.updateAvailable;
  }

  //====================
  // Synced Rules
  //====================
  // A direct mirror mismatch always wins over a saved version baseline. This
  // keeps backup-only residue visible even when the Workshop manifest matches.
  if (standing == CopyStanding.behind) return behind();

  // A usable backup exists and mirrors the live wallpaper.
  // No unresolved content update or placement problem remains.
  // Required comparisons are filtered into Reconcile before this point.
  if (library == WallpaperLibrary.myProjects) return BackupState.synced;

  if (liveVersion == null) return BackupState.synced;

  final String? backedUp = record?.backedUpVersion;
  if (backedUp != null) {
    return liveVersion == backedUp ? BackupState.synced : behind();
  }
  return switch (standing) {
    CopyStanding.covers => BackupState.synced,
    CopyStanding.behind => behind(),
    _ => BackupState.synced,
  };
}
