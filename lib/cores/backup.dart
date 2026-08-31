import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:we_repkg/constants/i10n.dart';
import 'package:we_repkg/constants/strings.dart';
import 'package:we_repkg/constants/wallpaper_files.dart';
import 'package:we_repkg/models/acf.dart';
import 'package:we_repkg/src/rust/api/simple.dart' as rust;
import 'package:we_repkg/utils/backup_diff.dart';
import 'package:we_repkg/utils/parse_acf.dart';
import 'package:we_repkg/utils/wallpaper_junk.dart';

String? backupWorkshopPath(String? backupRoot) => backupRoot == null
    ? null
    : path.join(backupRoot, AppStrings.backupWorkshopDir);

String? backupMyProjectsPath(String? backupRoot) => backupRoot == null
    ? null
    : path.join(backupRoot, AppStrings.backupProjectDir);

/// A folder the comparison cannot do without.
///
/// Any of the three unset or off disk and the answer is not merely incomplete,
/// it is wrong in the quiet direction: an unreadable live library turns every
/// backup folder into a vanished card, and an unreachable backup root turns the
/// whole live library into "not backed up, nothing vanished". Both read as a
/// confident number rather than as a failure, so the tab names the folder
/// instead of showing counts.
enum BackupFolder { liveWorkshop, liveMyProjects, backupRoot }

/// What the scan is doing, for the tab to say so instead of spinning silently.
///
/// [comparing] is the long one: it checks whether live and backup still mirror
/// each other. [finishing] covers the short tail while the lightweight
/// junk checks finish. [reading] has no useful total. [details] remains for
/// callers that want counted face reads; [preparing] covers the final handoff.
enum BackupScanPhase { reading, comparing, finishing, details, preparing }

typedef BackupScanProgress = ({BackupScanPhase phase, int done, int total});

typedef BackupScan = ({
  Map<BackupCard, BackupState> cards,
  Map<BackupCard, BackupUpdatePlan> updates,
  Set<BackupCard> ignoredUpdates,
  Map<String, ({bool live, bool backup})> presence,
  Map<String, ({bool live, bool backup, WallpaperJunkKind kind})> junk,
  List<ReconcileEntry> reconcile,
  bool acfRead,
  Set<BackupFolder> missing,
});

/// Everything the differ needs, read in one pass, then the comparison.
///
/// Paths rather than a `WidgetRef`, so this runs against a temp directory in a
/// test. A null backup root reads as an empty backup, which is what makes every
/// live wallpaper come back not backed up rather than as an error.
Future<BackupScan> scanBackup({
  required String? backupRoot,
  required String? liveWorkshopPath,
  required String? liveMyProjectsPath,
  required String? acfPath,
  void Function(BackupScanProgress)? onProgress,
}) async {
  onProgress?.call((phase: BackupScanPhase.reading, done: 0, total: 0));
  final Future<Set<String>> liveWorkshopFuture = listFolderNames(
    liveWorkshopPath,
  );
  final Future<({Set<String> names, Map<String, String> versions})>
  myProjectsFuture = _myProjectsInventory(liveMyProjectsPath);
  final Future<Set<String>> backupWorkshopFuture = listFolderNames(
    backupWorkshopPath(backupRoot),
  );
  final Future<Set<String>> backupMyProjectsFuture = listFolderNames(
    backupMyProjectsPath(backupRoot),
  );
  final Future<({Map<String, String> byId, bool acfRead})> acfFuture =
      workshopVersions(acfPath);
  final Future<Map<String, BackupRecord>> recordsFuture = readBackupRecords(
    backupRoot,
  );
  final Future<Set<BackupFolder>> missingFuture = _missingFolders(
    liveWorkshopPath,
    liveMyProjectsPath,
    backupRoot,
  );

  final (
    Set<String> liveWorkshop,
    ({Set<String> names, Map<String, String> versions}) myProjects,
    Set<String> backupWorkshop,
    Set<String> backupMyProjects,
    ({Map<String, String> byId, bool acfRead}) acf,
    Map<String, BackupRecord> records,
    Set<BackupFolder> missing,
  ) = await (
    liveWorkshopFuture,
    myProjectsFuture,
    backupWorkshopFuture,
    backupMyProjectsFuture,
    acfFuture,
    recordsFuture,
    missingFuture,
  ).wait;
  final Set<String> liveMyProjects = myProjects.names;

  // Mirror checks compare every shared folder. Workshop stays shallow because
  // scene.pkg carries most payload, but saved version records cannot answer
  // whether stale files remain only in the backup.
  final Set<String> sharedWorkshop = _shared(liveWorkshop, backupWorkshop);
  final Set<String> sharedMyProjects = _shared(
    liveMyProjects,
    backupMyProjects,
  );
  final Set<String> workshopToCompare = sharedWorkshop;
  final Set<String> duplicateBackupCandidates = _duplicateBackupCandidates(
    liveWorkshop: liveWorkshop,
    liveMyProjects: liveMyProjects,
    backupWorkshop: backupWorkshop,
    backupMyProjects: backupMyProjects,
  );
  final ({Set<String> workshop, Set<String> myProjects}) crossPlaced =
      _crossPlacedCandidates(
        liveWorkshop: liveWorkshop,
        liveMyProjects: liveMyProjects,
        backupWorkshop: backupWorkshop,
        backupMyProjects: backupMyProjects,
      );

  final Map<String, ({bool live, bool backup})> presence = _cardPresence(
    liveWorkshop,
    liveMyProjects,
    backupWorkshop,
    backupMyProjects,
  );
  // Report the work that actually dominates the wait: mirror comparisons.
  // Junk checks run beside it and usually stop at the first ordinary file.
  final int compareTotal =
      workshopToCompare.length +
      sharedMyProjects.length +
      duplicateBackupCandidates.length +
      crossPlaced.workshop.length +
      crossPlaced.myProjects.length;
  int compared = 0;
  void comparedBatch(int folders) {
    compared += folders;
    onProgress?.call((
      phase: compared >= compareTotal
          ? BackupScanPhase.finishing
          : BackupScanPhase.comparing,
      done: compared,
      total: compareTotal,
    ));
  }

  if (compareTotal > 0) {
    onProgress?.call((
      phase: BackupScanPhase.comparing,
      done: 0,
      total: compareTotal,
    ));
  }
  final Future<Map<String, CopyStanding>>
  workshopStandingFuture = copyStandings(
    livePath: liveWorkshopPath,
    backupPath: backupWorkshopPath(backupRoot),
    // Workshop wallpapers are packed, so matching-tree mirror check only needs the
    // top-level payload outside the rebuilt shader cache.
    recursive: false,
    shared: sharedWorkshop,
    compare: workshopToCompare,
    onBatch: comparedBatch,
  );
  final Future<Map<String, CopyStanding>> myProjectsStandingFuture =
      copyStandings(
        livePath: liveMyProjectsPath,
        backupPath: backupMyProjectsPath(backupRoot),
        // MyProjects wallpapers are usually unpacked, so edits can land in
        // subfolders and require recursive mirror comparison.
        recursive: true,
        shared: sharedMyProjects,
        compare: sharedMyProjects,
        onBatch: comparedBatch,
      );
  final Future<_BackupCopyComparisons> backupCopyComparisonsFuture =
      _compareDuplicateBackups(
        workshopPath: backupWorkshopPath(backupRoot),
        myProjectsPath: backupMyProjectsPath(backupRoot),
        workshopNames: backupWorkshop,
        myProjectsNames: backupMyProjects,
        candidates: duplicateBackupCandidates,
        onBatch: comparedBatch,
      );
  final Future<Map<String, CopyStanding>> crossWorkshopStandingFuture =
      copyStandings(
        livePath: liveWorkshopPath,
        backupPath: backupMyProjectsPath(backupRoot),
        recursive: true,
        shared: crossPlaced.workshop,
        compare: crossPlaced.workshop,
        onBatch: comparedBatch,
      );
  final Future<Map<String, CopyStanding>> crossMyProjectsStandingFuture =
      copyStandings(
        livePath: liveMyProjectsPath,
        backupPath: backupWorkshopPath(backupRoot),
        recursive: true,
        shared: crossPlaced.myProjects,
        compare: crossPlaced.myProjects,
        onBatch: comparedBatch,
      );

  final Future<Map<String, WallpaperJunkKind>> junkLiveWorkshopFuture =
      _junkFolders(liveWorkshopPath, liveWorkshop, live: true);
  final Future<Map<String, WallpaperJunkKind>> junkLiveMyProjectsFuture =
      _junkFolders(liveMyProjectsPath, liveMyProjects, live: true);
  final Future<Map<String, WallpaperJunkKind>> junkBackupWorkshopFuture =
      _junkFolders(backupWorkshopPath(backupRoot), backupWorkshop, live: false);
  final Future<Map<String, WallpaperJunkKind>> junkBackupMyProjectsFuture =
      _junkFolders(
        backupMyProjectsPath(backupRoot),
        backupMyProjects,
        live: false,
      );

  final (
    Map<String, CopyStanding> workshopStanding,
    Map<String, CopyStanding> myProjectsStanding,
    _BackupCopyComparisons backupCopyComparisons,
    Map<String, CopyStanding> crossWorkshopStanding,
    Map<String, CopyStanding> crossMyProjectsStanding,
    Map<String, WallpaperJunkKind> junkLiveWorkshop,
    Map<String, WallpaperJunkKind> junkLiveMyProjects,
    Map<String, WallpaperJunkKind> junkBackupWorkshop,
    Map<String, WallpaperJunkKind> junkBackupMyProjects,
  ) = await (
    workshopStandingFuture,
    myProjectsStandingFuture,
    backupCopyComparisonsFuture,
    crossWorkshopStandingFuture,
    crossMyProjectsStandingFuture,
    junkLiveWorkshopFuture,
    junkLiveMyProjectsFuture,
    junkBackupWorkshopFuture,
    junkBackupMyProjectsFuture,
  ).wait;
  onProgress?.call((
    phase: BackupScanPhase.preparing,
    done: compareTotal,
    total: compareTotal,
  ));

  final Set<String> validLiveWorkshop = liveWorkshop.difference(
    junkLiveWorkshop.keys.toSet(),
  );
  final Set<String> validLiveMyProjects = liveMyProjects.difference(
    junkLiveMyProjects.keys.toSet(),
  );
  final Set<String> validBackupWorkshop = backupWorkshop.difference(
    junkBackupWorkshop.keys.toSet(),
  );
  final Set<String> validBackupMyProjects = backupMyProjects.difference(
    junkBackupMyProjects.keys.toSet(),
  );

  final Set<String> unavailableContentComparisons =
      _unavailableContentComparisons(
        liveWorkshop: validLiveWorkshop,
        liveMyProjects: validLiveMyProjects,
        backupWorkshop: validBackupWorkshop,
        backupMyProjects: validBackupMyProjects,
        workshopStanding: workshopStanding,
        myProjectsStanding: myProjectsStanding,
      );

  final BackupDiffResult diff = backupDiff(
    liveWorkshop: validLiveWorkshop,
    liveMyProjects: validLiveMyProjects,
    backupWorkshop: validBackupWorkshop,
    backupMyProjects: validBackupMyProjects,
    liveWorkshopVersions: acf.byId,
    liveMyProjectsVersions: myProjects.versions,
    workshopStanding: workshopStanding,
    myProjectsStanding: myProjectsStanding,
    crossWorkshopStanding: crossWorkshopStanding,
    crossMyProjectsStanding: crossMyProjectsStanding,
    records: records,
    equivalentBackupCopies: backupCopyComparisons.equivalent,
    unavailableBackupComparisons: backupCopyComparisons.unavailable,
    backupCopyDifferences: backupCopyComparisons.differences,
    unavailableContentComparisons: unavailableContentComparisons,
  );
  _addLiveJunkCards(diff, WallpaperLibrary.workshop, junkLiveWorkshop.keys);
  _addLiveJunkCards(diff, WallpaperLibrary.myProjects, junkLiveMyProjects.keys);
  _addBackupJunkCards(diff, WallpaperLibrary.workshop, junkBackupWorkshop.keys);
  _addBackupJunkCards(
    diff,
    WallpaperLibrary.myProjects,
    junkBackupMyProjects.keys,
  );
  final Map<String, ({bool live, bool backup})> junkPresence = _cardPresence(
    junkLiveWorkshop.keys.toSet(),
    junkLiveMyProjects.keys.toSet(),
    junkBackupWorkshop.keys.toSet(),
    junkBackupMyProjects.keys.toSet(),
  );
  final Map<String, WallpaperJunkKind> junkKinds = _junkKinds(
    liveWorkshop: junkLiveWorkshop,
    liveMyProjects: junkLiveMyProjects,
    backupWorkshop: junkBackupWorkshop,
    backupMyProjects: junkBackupMyProjects,
  );
  final Map<String, ({bool live, bool backup, WallpaperJunkKind kind})> junk =
      <String, ({bool live, bool backup, WallpaperJunkKind kind})>{
        for (final MapEntry<String, ({bool live, bool backup})> entry
            in junkPresence.entries)
          entry.key: (
            live: entry.value.live,
            backup: entry.value.backup,
            kind: junkKinds[entry.key] ?? WallpaperJunkKind.empty,
          ),
      };
  return (
    cards: diff.cards,
    updates: diff.updates,
    ignoredUpdates: diff.ignoredUpdates,
    presence: presence,
    junk: junk,
    reconcile: diff.reconcile,
    acfRead: acf.acfRead,
    missing: missing,
  );
}

Map<String, ({bool live, bool backup})> _cardPresence(
  Set<String> liveWorkshop,
  Set<String> liveMyProjects,
  Set<String> backupWorkshop,
  Set<String> backupMyProjects,
) {
  final Map<String, ({bool live, bool backup})> result = {};
  void add(WallpaperLibrary library, String name, {required bool live}) {
    final String id = BackupCard(library, name).id;
    final previous = result[id] ?? (live: false, backup: false);
    result[id] = (
      live: previous.live || live,
      backup: previous.backup || !live,
    );
  }

  for (final String name in liveWorkshop) {
    add(WallpaperLibrary.workshop, name, live: true);
  }
  for (final String name in liveMyProjects) {
    add(WallpaperLibrary.myProjects, name, live: true);
  }
  for (final String name in backupWorkshop) {
    add(WallpaperLibrary.workshop, name, live: false);
  }
  for (final String name in backupMyProjects) {
    add(WallpaperLibrary.myProjects, name, live: false);
  }
  return result;
}

/// Reads the face of every card, from whichever folder still exists.
///
/// A vanished card has no live folder left, so its picture can only come from
/// the backup copy. A folder whose `project.json` is missing or unreadable
/// comes back absent rather than dropping the card: that folder is exactly what
/// the integrity check exists to point at, and hiding it here would make the
/// card list disagree with the filesystem scan.
Future<Map<BackupCard, CardFace>> readCardFaces({
  required String? backupRoot,
  required String? liveWorkshopPath,
  required String? liveMyProjectsPath,
  required Map<BackupCard, BackupState> cards,
  Map<String, ({bool live, bool backup})> presence = const {},
  void Function(BackupScanProgress)? onProgress,
}) async {
  final List<String> liveW = <String>[];
  final List<String> liveM = <String>[];
  final List<String> goneW = <String>[];
  final List<String> goneM = <String>[];
  cards.forEach((BackupCard card, BackupState state) {
    final bool gone =
        !(presence[card.id]?.live ?? state != BackupState.vanished);
    switch (card.library) {
      case WallpaperLibrary.workshop:
        (gone ? goneW : liveW).add(card.name);
      case WallpaperLibrary.myProjects:
        (gone ? goneM : liveM).add(card.name);
    }
  });

  // One counter over all four, since they read at the same time and the user is
  // watching one line.
  int done = 0;
  void read(int folders) {
    done += folders;
    onProgress?.call((
      // The last disk read is not the end of the wait: the provider still has
      // to assemble the card list and Flutter has to replace this progress UI.
      phase: done >= cards.length
          ? BackupScanPhase.preparing
          : BackupScanPhase.details,
      done: done,
      total: cards.length,
    ));
  }

  if (cards.isNotEmpty) read(0);
  final Future<Map<String, CardFace>> facesLiveWFuture = _faces(
    liveWorkshopPath,
    liveW,
    onBatch: read,
  );
  final Future<Map<String, CardFace>> facesLiveMFuture = _faces(
    liveMyProjectsPath,
    liveM,
    onBatch: read,
  );
  final Future<Map<String, CardFace>> facesGoneWFuture = _faces(
    backupWorkshopPath(backupRoot),
    goneW,
    onBatch: read,
  );
  final Future<Map<String, CardFace>> facesGoneMFuture = _faces(
    backupMyProjectsPath(backupRoot),
    goneM,
    onBatch: read,
  );

  final (
    Map<String, CardFace> facesLiveW,
    Map<String, CardFace> facesLiveM,
    Map<String, CardFace> facesGoneW,
    Map<String, CardFace> facesGoneM,
  ) = await (
    facesLiveWFuture,
    facesLiveMFuture,
    facesGoneWFuture,
    facesGoneMFuture,
  ).wait;

  return <BackupCard, CardFace>{
    for (final MapEntry<String, CardFace> e in facesLiveW.entries)
      BackupCard(WallpaperLibrary.workshop, e.key): e.value,
    for (final MapEntry<String, CardFace> e in facesGoneW.entries)
      BackupCard(WallpaperLibrary.workshop, e.key): e.value,
    for (final MapEntry<String, CardFace> e in facesLiveM.entries)
      BackupCard(WallpaperLibrary.myProjects, e.key): e.value,
    for (final MapEntry<String, CardFace> e in facesGoneM.entries)
      BackupCard(WallpaperLibrary.myProjects, e.key): e.value,
  };
}

Future<Map<String, CardFace>> _faces(
  String? root,
  List<String> names, {
  void Function(int folders)? onBatch,
}) async {
  if (root == null || names.isEmpty) return <String, CardFace>{};

  try {
    final Map<String, rust.WallpaperProjectRead> projects = await rust
        .readWallpaperProjectsRust(root: root, folderNames: names, workers: 24);
    return _perFolder<CardFace>(root, names, (Directory folder) {
      final rust.WallpaperProjectRead? project =
          projects[path.basename(folder.path)];
      return _faceFromJson(
        folder,
        project?.json,
        changedMicros: project?.changedMicros,
      );
    }, onBatch: onBatch);
  } catch (_) {
    // Keep the existing Dart reader as a safety net if the native bridge is
    // unavailable or a future platform cannot service the batch call.
    return _perFolder<CardFace>(
      root,
      names,
      (Directory folder) => _face(folder),
      onBatch: onBatch,
    );
  }
}

Future<CardFace?> _faceFromJson(
  Directory folder,
  String? jsonString, {
  double? changedMicros,
}) async {
  if (jsonString == null) return null;
  final File file = File(path.join(folder.path, WallpaperFiles.project));
  try {
    final Map<String, dynamic> parsed =
        json.decode(jsonString) as Map<String, dynamic>;

    final DateTime modified;
    if (changedMicros != null) {
      modified = DateTime.fromMicrosecondsSinceEpoch(changedMicros.round());
    } else {
      modified = (await file.stat()).changed;
    }

    final String? preview = parsed[WallpaperProjectFields.preview] as String?;
    return (
      title:
          parsed[WallpaperProjectFields.title] as String? ??
          path.basename(folder.path),
      preview: preview == null ? '' : path.join(folder.path, preview),
      type: (parsed[WallpaperProjectFields.type] as String? ?? '')
          .toLowerCase(),
      rating: (parsed[WallpaperProjectFields.contentRating] as String? ?? '')
          .toLowerCase(),
      modified: modified,
    );
  } catch (e) {
    debugPrint('${tr(AppI10n.logParseWallpaperSkipped)} ${folder.path} $e');
    return null;
  }
}

Future<CardFace?> _face(Directory folder) async {
  final File file = File(path.join(folder.path, WallpaperFiles.project));
  final bool exists = await file.exists();
  if (!exists) return null;
  try {
    final Map<String, dynamic> parsed =
        json.decode(await file.readAsString()) as Map<String, dynamic>;
    // The same field the extract grid dates a wallpaper by, so both grids
    // mean the same thing by their date order.
    final DateTime modified = (await file.stat()).changed;

    final String? preview = parsed[WallpaperProjectFields.preview] as String?;
    // myprojects wallpapers often have no title. A hand-made one can also put a
    // number where the string belongs, which the cast throws on and the catch
    // below turns into no face at all, matching what the extract grid does with
    // the same folder.
    return (
      title:
          parsed[WallpaperProjectFields.title] as String? ??
          path.basename(folder.path),
      preview: preview == null ? '' : path.join(folder.path, preview),
      type: (parsed[WallpaperProjectFields.type] as String? ?? '')
          .toLowerCase(),
      rating: (parsed[WallpaperProjectFields.contentRating] as String? ?? '')
          .toLowerCase(),
      modified: modified,
    );
  } catch (e) {
    debugPrint('${tr(AppI10n.logParseWallpaperSkipped)} ${folder.path} $e');
    return null;
  }
}

/// Faces for the names waiting to be reconciled, one per name.
///
/// A live folder before a backup copy, and myprojects before Workshop: the
/// picture should be the one Wallpaper Engine is showing.
Future<Map<String, CardFace>> readReconcileFaces({
  required String? backupRoot,
  required String? liveWorkshopPath,
  required String? liveMyProjectsPath,
  required List<ReconcileEntry> entries,
}) async {
  final (
    Map<String, CardFace> liveM,
    Map<String, CardFace> liveW,
    Map<String, CardFace> backupM,
    Map<String, CardFace> backupW,
  ) = await (
    _faces(liveMyProjectsPath, <String>[
      for (final ReconcileEntry e in entries)
        if (e.liveMyProjects) e.name,
    ]),
    _faces(liveWorkshopPath, <String>[
      for (final ReconcileEntry e in entries)
        if (e.liveWorkshop) e.name,
    ]),
    _faces(backupMyProjectsPath(backupRoot), <String>[
      for (final ReconcileEntry e in entries)
        if (e.backupMyProjects) e.name,
    ]),
    _faces(backupWorkshopPath(backupRoot), <String>[
      for (final ReconcileEntry e in entries)
        if (e.backupWorkshop) e.name,
    ]),
  ).wait;

  return <String, CardFace>{
    for (final ReconcileEntry entry in entries)
      if (liveM[entry.name] ??
              liveW[entry.name] ??
              backupM[entry.name] ??
              backupW[entry.name]
          case final CardFace face)
        entry.name: face,
  };
}

/// The pair of folders a reconcile tile opens.
///
/// A name here has copies in more than one place, so it picks one of each: the
/// myprojects copy, being the one the author edits, before the Workshop one.
/// The rest is in the presence matrix on the tile, and the per-folder actions
/// arrive with the reconcile operations.
({String? live, String? backup}) reconcileFolders({
  required ReconcileEntry entry,
  required String? backupRoot,
  required String? liveWorkshopPath,
  required String? liveMyProjectsPath,
}) {
  final ({String? backup, String? live}) myProjects = cardFolders(
    library: WallpaperLibrary.myProjects,
    name: entry.name,
    liveExists: entry.liveMyProjects,
    backupExists: entry.backupMyProjects,
    backupRoot: backupRoot,
    liveWorkshopPath: liveWorkshopPath,
    liveMyProjectsPath: liveMyProjectsPath,
  );
  final ({String? backup, String? live}) workshop = cardFolders(
    library: WallpaperLibrary.workshop,
    name: entry.name,
    liveExists: entry.liveWorkshop,
    backupExists: entry.backupWorkshop,
    backupRoot: backupRoot,
    liveWorkshopPath: liveWorkshopPath,
    liveMyProjectsPath: liveMyProjectsPath,
  );
  return (
    live: myProjects.live ?? workshop.live,
    backup: myProjects.backup ?? workshop.backup,
  );
}

/// The two folders a card stands for. Null where the folder is not there: a
/// vanished card has no live copy left, and one never backed up has no backup.
({String? live, String? backup}) cardFolders({
  required WallpaperLibrary library,
  required String name,
  required bool liveExists,
  required bool backupExists,
  required String? backupRoot,
  required String? liveWorkshopPath,
  required String? liveMyProjectsPath,
}) {
  final String? livePath = switch (library) {
    WallpaperLibrary.workshop => liveWorkshopPath,
    WallpaperLibrary.myProjects => liveMyProjectsPath,
  };
  final String? backupPath = switch (library) {
    WallpaperLibrary.workshop => backupWorkshopPath(backupRoot),
    WallpaperLibrary.myProjects => backupMyProjectsPath(backupRoot),
  };
  return (
    live: liveExists && livePath != null ? path.join(livePath, name) : null,
    backup: backupExists && backupPath != null
        ? path.join(backupPath, name)
        : null,
  );
}

/// Names held by both sides, which are the only ones worth comparing: a folder
/// with no counterpart has nothing to compare against.
///
/// Lowercased to match [BackupCard.id] and to keep the two sets that come out
/// of here spelling a name the same way. It is not what makes a re-cased folder
/// compare: the paths are joined rather than listed, and Windows resolves the
/// case itself.
Set<String> _shared(Set<String> live, Set<String> backup) {
  final Set<String> backupKeys = _lowered(backup);
  return <String>{
    for (final String name in live)
      if (backupKeys.contains(name.toLowerCase())) name.toLowerCase(),
  };
}

Set<String> _lowered(Set<String> names) => <String>{
  for (final String name in names) name.toLowerCase(),
};

Set<String> _duplicateBackupCandidates({
  required Set<String> liveWorkshop,
  required Set<String> liveMyProjects,
  required Set<String> backupWorkshop,
  required Set<String> backupMyProjects,
}) {
  final Set<String> liveW = _lowered(liveWorkshop);
  final Set<String> liveM = _lowered(liveMyProjects);
  final Set<String> backupW = _lowered(backupWorkshop);
  final Set<String> backupM = _lowered(backupMyProjects);
  return <String>{
    for (final String name in backupW.intersection(backupM))
      if (liveW.contains(name) != liveM.contains(name)) name,
  };
}

({Set<String> workshop, Set<String> myProjects}) _crossPlacedCandidates({
  required Set<String> liveWorkshop,
  required Set<String> liveMyProjects,
  required Set<String> backupWorkshop,
  required Set<String> backupMyProjects,
}) {
  final Set<String> liveW = _lowered(liveWorkshop);
  final Set<String> liveM = _lowered(liveMyProjects);
  final Set<String> backupW = _lowered(backupWorkshop);
  final Set<String> backupM = _lowered(backupMyProjects);
  return (
    workshop: <String>{
      for (final String name in liveW)
        if (!liveM.contains(name) &&
            !backupW.contains(name) &&
            backupM.contains(name))
          name,
    },
    myProjects: <String>{
      for (final String name in liveM)
        if (!liveW.contains(name) &&
            !backupM.contains(name) &&
            backupW.contains(name))
          name,
    },
  );
}

Set<String> _unavailableContentComparisons({
  required Set<String> liveWorkshop,
  required Set<String> liveMyProjects,
  required Set<String> backupWorkshop,
  required Set<String> backupMyProjects,
  required Map<String, CopyStanding> workshopStanding,
  required Map<String, CopyStanding> myProjectsStanding,
}) {
  final Set<String> sharedWorkshop = _shared(liveWorkshop, backupWorkshop);
  final Set<String> sharedMyProjects = _shared(
    liveMyProjects,
    backupMyProjects,
  );
  final Set<String> workshopCompared = <String>{
    for (final String name in workshopStanding.keys) name.toLowerCase(),
  };
  final Set<String> myProjectsCompared = <String>{
    for (final String name in myProjectsStanding.keys) name.toLowerCase(),
  };

  return <String>{
    for (final String name in sharedWorkshop)
      if (!workshopCompared.contains(name)) 'workshop/$name',
    for (final String name in sharedMyProjects)
      if (!myProjectsCompared.contains(name)) 'myprojects/$name',
  };
}

typedef _BackupCopyComparisons = ({
  Set<String> equivalent,
  Set<String> unavailable,
  Map<String, BackupCopyDifference> differences,
});

enum _BackupCopyComparison { equivalent, different, unavailable }

typedef _FolderDifference = ({
  List<String> differentSize,
  List<String> onlyFirst,
  List<String> onlySecond,
  String evidenceFingerprint,
});

typedef _FolderComparison = ({
  _BackupCopyComparison result,
  _FolderDifference? difference,
});

/// Exact file-level differences between two wallpaper folders.
///
/// The normal library scan only needs names and sizes. Detail views pay for
/// content reads so same-size modified files are still detected.
typedef FolderFileChanges = ({
  List<String> modified,
  List<String> onlyFirst,
  List<String> onlySecond,
});

/// Exact comparison result for detail views that also need proof of equality.
///
/// [matching] contains relative paths that existed on both sides and whose
/// contents were confirmed equal. The ordinary Update flow only consumes
/// [changes], so retaining this evidence does not change its public contract.
typedef FolderFileComparison = ({
  FolderFileChanges changes,
  List<String> matching,
});

/// Update-facing names for the same exact comparison semantics.
typedef BackupFileChanges = ({
  List<String> modified,
  List<String> onlyLive,
  List<String> onlyBackup,
});

/// Optional per-file overrides for a detailed Update.
///
/// The default plan is the same full mirror used by bulk Update. Exceptions
/// preserve selected old backup files or skip selected live replacements.
class BackupSelectiveUpdatePlan {
  const BackupSelectiveUpdatePlan({
    required this.expectedChanges,
    this.skippedCopies = const <String>{},
    this.keptBackupFiles = const <String>{},
  });

  final BackupFileChanges expectedChanges;
  final Set<String> skippedCopies;
  final Set<String> keptBackupFiles;

  bool get isPartial => skippedCopies.isNotEmpty || keptBackupFiles.isNotEmpty;
}

bool backupFileChangesEqual(BackupFileChanges a, BackupFileChanges b) =>
    listEquals(a.modified, b.modified) &&
    listEquals(a.onlyLive, b.onlyLive) &&
    listEquals(a.onlyBackup, b.onlyBackup);

Future<_BackupCopyComparisons> _compareDuplicateBackups({
  required String? workshopPath,
  required String? myProjectsPath,
  required Set<String> workshopNames,
  required Set<String> myProjectsNames,
  required Set<String> candidates,
  void Function(int folders)? onBatch,
}) async {
  if (workshopPath == null || myProjectsPath == null || candidates.isEmpty) {
    return (
      equivalent: <String>{},
      unavailable: <String>{},
      differences: <String, BackupCopyDifference>{},
    );
  }
  final Map<String, String> workshopByKey = <String, String>{
    for (final String name in workshopNames) name.toLowerCase(): name,
  };
  final Map<String, String> myProjectsByKey = <String, String>{
    for (final String name in myProjectsNames) name.toLowerCase(): name,
  };
  final List<String> wanted = candidates.toList();
  final Set<String> equivalent = <String>{};
  final Set<String> unavailable = <String>{};
  final Map<String, BackupCopyDifference> differences =
      <String, BackupCopyDifference>{};
  const int batchSize = 8;
  for (int i = 0; i < wanted.length; i += batchSize) {
    final List<String> batch = wanted.skip(i).take(batchSize).toList();
    final List<_FolderComparison> matches = await Future.wait(
      batch.map((String key) async {
        final String? workshopName = workshopByKey[key];
        final String? myProjectsName = myProjectsByKey[key];
        if (workshopName == null || myProjectsName == null) {
          return (result: _BackupCopyComparison.unavailable, difference: null);
        }
        return _compareBackupFolders(
          Directory(path.join(workshopPath, workshopName)),
          Directory(path.join(myProjectsPath, myProjectsName)),
        );
      }),
    );
    for (int j = 0; j < batch.length; j++) {
      final _FolderComparison match = matches[j];
      switch (match.result) {
        case _BackupCopyComparison.equivalent:
          equivalent.add(batch[j]);
          break;
        case _BackupCopyComparison.unavailable:
          unavailable.add(batch[j]);
          break;
        case _BackupCopyComparison.different:
          final _FolderDifference difference = match.difference!;
          differences[batch[j]] = BackupCopyDifference(
            differentSize: difference.differentSize,
            onlyWorkshop: difference.onlyFirst,
            onlyMyProjects: difference.onlySecond,
            evidenceFingerprint: difference.evidenceFingerprint,
          );
          break;
      }
    }
    onBatch?.call(batch.length);
  }
  return (
    equivalent: equivalent,
    unavailable: unavailable,
    differences: differences,
  );
}

Future<Set<BackupFolder>> _missingFolders(
  String? liveWorkshopPath,
  String? liveMyProjectsPath,
  String? backupRoot,
) async {
  final List<bool> found = await Future.wait(<Future<bool>>[
    _folderPresent(liveWorkshopPath),
    _folderPresent(liveMyProjectsPath),
    _folderPresent(backupRoot),
  ]);
  return <BackupFolder>{
    if (!found[0]) BackupFolder.liveWorkshop,
    if (!found[1]) BackupFolder.liveMyProjects,
    if (!found[2]) BackupFolder.backupRoot,
  };
}

Future<bool> _folderPresent(String? folderPath) async =>
    folderPath != null && await Directory(folderPath).exists();

/// Which of [names] are folders Steam emptied, so the tab can leave them out.
///
/// Narrow on purpose: only a folder holding nothing but the rebuilt shader cache
/// counts. Anything else with content in it, however unloadable, keeps its card,
/// or a wallpaper the user could still back up would quietly stop existing.
Future<Map<String, WallpaperJunkKind>> _junkFolders(
  String? root,
  Set<String> names, {
  required bool live,
}) async {
  if (root == null || names.isEmpty) {
    return const <String, WallpaperJunkKind>{};
  }
  try {
    final List<String> junk = await rust.findJunkFoldersRust(
      root: root,
      folderNames: names.toList(),
      backup: !live,
      workers: 4,
    );
    return _classifyKnownJunk(root, junk);
  } catch (_) {
    // Keep the Dart scan as a safety net when the native bridge is unavailable,
    // including unit tests that do not initialise the desktop Rust library.
  }
  return _perFolder<WallpaperJunkKind>(
    root,
    names,
    (Directory folder) => live
        ? classifyLiveWallpaperJunk(folder)
        : classifyBackupWallpaperJunk(folder),
  );
}

Future<Map<String, WallpaperJunkKind>> _classifyKnownJunk(
  String root,
  Iterable<String> names,
) => _perFolder<WallpaperJunkKind>(root, names, (Directory folder) async {
  if (!await folder.exists()) return null;
  return await isEmptyFolderTree(folder)
      ? WallpaperJunkKind.empty
      : WallpaperJunkKind.shaderCacheOnly;
});

Map<String, WallpaperJunkKind> _junkKinds({
  required Map<String, WallpaperJunkKind> liveWorkshop,
  required Map<String, WallpaperJunkKind> liveMyProjects,
  required Map<String, WallpaperJunkKind> backupWorkshop,
  required Map<String, WallpaperJunkKind> backupMyProjects,
}) {
  final Map<String, WallpaperJunkKind> result = <String, WallpaperJunkKind>{};
  void add(WallpaperLibrary library, Map<String, WallpaperJunkKind> found) {
    for (final MapEntry<String, WallpaperJunkKind> entry in found.entries) {
      final String id = BackupCard(library, entry.key).id;
      final WallpaperJunkKind? previous = result[id];
      result[id] = previous == null || previous == entry.value
          ? entry.value
          : WallpaperJunkKind.mixed;
    }
  }

  add(WallpaperLibrary.workshop, liveWorkshop);
  add(WallpaperLibrary.myProjects, liveMyProjects);
  add(WallpaperLibrary.workshop, backupWorkshop);
  add(WallpaperLibrary.myProjects, backupMyProjects);
  return result;
}

void _addLiveJunkCards(
  BackupDiffResult diff,
  WallpaperLibrary library,
  Iterable<String> names,
) {
  for (final String name in names) {
    final BackupCard card = BackupCard(library, name);
    final BackupCard? existing = _cardWithId(diff.cards, card.id);
    if (existing != null) {
      diff.cards.remove(existing);
      diff.updates.remove(existing);
    }
    diff.cards[card] = BackupState.emptyBackup;
  }
}

void _addBackupJunkCards(
  BackupDiffResult diff,
  WallpaperLibrary library,
  Iterable<String> names,
) {
  final Set<String> reconciling = <String>{
    for (final ReconcileEntry entry in diff.reconcile) entry.name.toLowerCase(),
  };
  for (final String name in names) {
    if (reconciling.contains(name.toLowerCase())) continue;
    final BackupCard card = BackupCard(library, name);
    if (_cardWithId(diff.cards, card.id) != null) continue;
    diff.cards[card] = BackupState.emptyBackup;
  }
}

BackupCard? _cardWithId(Map<BackupCard, BackupState> cards, String id) {
  for (final BackupCard card in cards.keys) {
    if (card.id == id) return card;
  }
  return null;
}

/// Folder names in a wallpaper library, for the backup diff.
///
/// Names only, with no `project.json` parsing: the diff compares thousands of
/// folders and does not need their contents, and a folder dropped in by hand
/// without a `project.json` still occupies the backup.
Future<Set<String>> listFolderNames(String? folderPath) async {
  final Set<String> names = <String>{};
  if (folderPath == null) return names;
  final Directory dir = Directory(folderPath);
  if (!await dir.exists()) return names;
  await for (final FileSystemEntity entity in dir.list()) {
    if (entity is! Directory) continue;
    final String name = path.basename(entity.path);
    if (!WallpaperFiles.isLibraryRepairStage(name)) names.add(name);
  }
  return names;
}

/// The only persisted state in the feature. It sits at the backup root so it
/// travels with the drive, and triage survives moving to another machine.
const String backupRecordsName = 'werepkg-ex-backup.json';

/// Where the records file is built before it is renamed into place.
const String backupRecordsPartSuffix = '.werepkg-ex-part';

/// Indented, because this file lives in the user's backup and they open it.
const JsonEncoder _records = JsonEncoder.withIndent('  ');

/// What the backup holds, and which updates were waved off.
///
/// Every other fact the tab shows comes off the filesystem. A missing or
/// corrupt file reads as no records, which re-offers some dismissed updates
/// rather than taking the tab down.
Future<Map<String, BackupRecord>> readBackupRecords(String? backupRoot) async {
  if (backupRoot == null) return <String, BackupRecord>{};
  final File file = File(path.join(backupRoot, backupRecordsName));
  if (!await file.exists()) return <String, BackupRecord>{};
  try {
    final Map<String, dynamic> parsed =
        json.decode(await file.readAsString()) as Map<String, dynamic>;
    return <String, BackupRecord>{
      for (final MapEntry<String, dynamic> entry in parsed.entries)
        if (entry.value is Map<String, dynamic>)
          entry.key: BackupRecord(
            backedUpVersion: entry.value['backedUpVersion'] as String?,
            dismissedVersion: entry.value['dismissedVersion'] as String?,
            ignoredReconcileIssues:
                entry.value['ignoredReconcileIssues'] is Map<String, dynamic>
                ? <BackupReconcileReason, String>{
                    for (final MapEntry<String, dynamic> issue
                        in (entry.value['ignoredReconcileIssues']
                                as Map<String, dynamic>)
                            .entries)
                      for (final BackupReconcileReason reason
                          in BackupReconcileReason.values)
                        if (reason.name == issue.key && issue.value is String)
                          reason: issue.value as String,
                  }
                : const <BackupReconcileReason, String>{},
          ),
    };
  } catch (e) {
    debugPrint('${tr(AppI10n.errorReadBackupRecordsFailed)} $e');
    return <String, BackupRecord>{};
  }
}

/// Runs [work] over [names] under [root], keeping whatever comes back non-null.
///
/// Batched, or a large library opens too many file handles at once. Paths are
/// joined rather than listed: every caller already knows the names it wants, so
/// enumerating the directory again would walk each library twice per scan.
Future<Map<String, T>> _perFolder<T extends Object>(
  String root,
  Iterable<String> names,
  Future<T?> Function(Directory folder) work, {
  void Function(int folders)? onBatch,
  int batchSize = 24,
}) async {
  final Map<String, T> found = <String, T>{};
  final List<String> wanted = names.toList();
  for (int i = 0; i < wanted.length; i += batchSize) {
    final List<String> batch = wanted.skip(i).take(batchSize).toList();
    final List<T?> done = await Future.wait(
      batch.map((String name) => work(Directory(path.join(root, name)))),
    );
    for (int j = 0; j < batch.length; j++) {
      final T? result = done[j];
      if (result != null) found[batch[j]] = result;
    }
    onBatch?.call(batch.length);
  }
  return found;
}

/// Whether the backup mirrors every meaningful live file and has no residue.
Future<CopyStanding?> _copyStanding({
  required Directory liveFolder,
  required Directory backupFolder,
  required bool recursive,
}) async {
  final (
    Map<String, ({String display, int size})>? liveFiles,
    Map<String, ({String display, int size})>? backupFiles,
  ) = await (
    _backupFileManifest(liveFolder, recursive: recursive),
    _backupFileManifest(backupFolder, recursive: recursive),
  ).wait;
  if (liveFiles == null || backupFiles == null) return null;
  if (backupFiles.isEmpty) return CopyStanding.empty;
  if (liveFiles.length != backupFiles.length) return CopyStanding.behind;
  for (final MapEntry<String, ({String display, int size})> file
      in liveFiles.entries) {
    if (backupFiles[file.key]?.size != file.value.size) {
      return CopyStanding.behind;
    }
  }
  return CopyStanding.covers;
}

/// Whether two backup folders hold the same meaningful files.
Future<_FolderComparison> _compareBackupFolders(
  Directory first,
  Directory second,
) async {
  final (
    Map<String, ({String display, int size})>? firstFiles,
    Map<String, ({String display, int size})>? secondFiles,
  ) = await (
    _backupFileManifest(first),
    _backupFileManifest(second),
  ).wait;
  if (firstFiles == null || secondFiles == null) {
    return (result: _BackupCopyComparison.unavailable, difference: null);
  }

  final List<String> differentSize = <String>[];
  final List<String> onlyFirst = <String>[];
  final List<String> onlySecond = <String>[];
  final Set<String> keys = <String>{...firstFiles.keys, ...secondFiles.keys};
  for (final String key in keys) {
    final firstFile = firstFiles[key];
    final secondFile = secondFiles[key];
    if (firstFile == null) {
      onlySecond.add(secondFile!.display);
    } else if (secondFile == null) {
      onlyFirst.add(firstFile.display);
    } else if (firstFile.size != secondFile.size) {
      differentSize.add(firstFile.display);
    }
  }
  void sortPaths(List<String> paths) => paths.sort(
    (String a, String b) => a.toLowerCase().compareTo(b.toLowerCase()),
  );
  sortPaths(differentSize);
  sortPaths(onlyFirst);
  sortPaths(onlySecond);

  final List<String> evidence = keys.toList()..sort();
  final String evidenceFingerprint = evidence
      .map((String key) {
        final firstFile = firstFiles[key];
        final secondFile = secondFiles[key];
        return '$key:${firstFile?.size ?? -1}:${secondFile?.size ?? -1}';
      })
      .join('|');
  final _FolderDifference difference = (
    differentSize: differentSize,
    onlyFirst: onlyFirst,
    onlySecond: onlySecond,
    evidenceFingerprint: 'conflicting-backups:$evidenceFingerprint',
  );
  final bool same =
      differentSize.isEmpty && onlyFirst.isEmpty && onlySecond.isEmpty;
  return (
    result: same
        ? _BackupCopyComparison.equivalent
        : _BackupCopyComparison.different,
    difference: same ? null : difference,
  );
}

Future<Map<String, ({String display, int size})>?> _backupFileManifest(
  Directory folder, {
  bool recursive = true,
}) async {
  try {
    if (!await folder.exists()) return null;
    final Map<String, ({String display, int size})> files =
        <String, ({String display, int size})>{};
    await for (final FileSystemEntity entity in folder.list(
      recursive: recursive,
      followLinks: false,
    )) {
      if (entity is! File) continue;
      final String relative = path.relative(entity.path, from: folder.path);
      if (isRebuiltShaderPath(relative)) continue;
      final FileStat stat = await entity.stat();
      if (stat.type != FileSystemEntityType.file) return null;
      final String key = relative.toLowerCase().replaceAll('/', r'\');
      files[key] = (display: relative, size: stat.size);
    }
    return files;
  } on FileSystemException {
    return null;
  }
}

/// Compares two complete wallpaper folders exactly and retains equality proof.
///
/// This is deliberately more exact than the normal scan: same-size matching
/// files are compared in chunks without loading whole wallpaper files into
/// memory. Returns null when either tree cannot be read.
Future<FolderFileComparison?> compareFolderFilesDetailed({
  required String firstFolder,
  required String secondFolder,
}) async {
  final Directory first = Directory(firstFolder);
  final Directory second = Directory(secondFolder);
  final (
    Map<String, ({String display, int size})>? firstFiles,
    Map<String, ({String display, int size})>? secondFiles,
  ) = await (
    _backupFileManifest(first),
    _backupFileManifest(second),
  ).wait;
  if (firstFiles == null || secondFiles == null) return null;

  final List<String> modified = <String>[];
  final List<String> onlyFirst = <String>[];
  final List<String> onlySecond = <String>[];
  final List<String> matching = <String>[];
  final Set<String> keys = <String>{...firstFiles.keys, ...secondFiles.keys};
  for (final String key in keys) {
    final firstFile = firstFiles[key];
    final secondFile = secondFiles[key];
    if (firstFile == null) {
      onlySecond.add(secondFile!.display);
      continue;
    }
    if (secondFile == null) {
      onlyFirst.add(firstFile.display);
      continue;
    }
    if (firstFile.size != secondFile.size) {
      modified.add(firstFile.display);
      continue;
    }
    final bool? same = await filesHaveSameContents(
      File(path.join(first.path, firstFile.display)),
      File(path.join(second.path, secondFile.display)),
    );
    if (same == null) return null;
    if (same) {
      matching.add(firstFile.display);
    } else {
      modified.add(firstFile.display);
    }
  }

  void sortPaths(List<String> paths) => paths.sort(
    (String a, String b) => a.toLowerCase().compareTo(b.toLowerCase()),
  );
  sortPaths(modified);
  sortPaths(onlyFirst);
  sortPaths(onlySecond);
  sortPaths(matching);
  return (
    changes: (modified: modified, onlyFirst: onlyFirst, onlySecond: onlySecond),
    matching: matching,
  );
}

/// Difference-only wrapper retained for Update and existing callers.
Future<FolderFileChanges?> compareFolderFileChanges({
  required String firstFolder,
  required String secondFolder,
}) async {
  final FolderFileComparison? comparison = await compareFolderFilesDetailed(
    firstFolder: firstFolder,
    secondFolder: secondFolder,
  );
  return comparison?.changes;
}

/// Update-facing wrapper for the shared exact folder comparison.
Future<BackupFileChanges?> compareBackupFileChanges({
  required String liveFolder,
  required String backupFolder,
}) async {
  final FolderFileChanges? changes = await compareFolderFileChanges(
    firstFolder: liveFolder,
    secondFolder: backupFolder,
  );
  if (changes == null) return null;
  return (
    modified: changes.modified,
    onlyLive: changes.onlyFirst,
    onlyBackup: changes.onlySecond,
  );
}

/// One leaf-level semantic change inside a JSON file.
///
/// Presence is kept separately from the value because JSON `null` is a real
/// value and must not be confused with a field or list item that was added or
/// removed.
typedef BackupJsonFieldChange = ({
  String field,
  Object? before,
  Object? after,
  bool beforePresent,
  bool afterPresent,
});

/// Compares any two JSON files structurally by relative path.
///
/// File-byte comparison decides whether a JSON file changed. This slower parse
/// is intentionally on-demand for detail views that need field-level meaning.
Future<List<BackupJsonFieldChange>?> compareBackupJsonChanges({
  required String beforeFolder,
  required String afterFolder,
  required String relativePath,
}) async {
  final File beforeFile = File(path.join(beforeFolder, relativePath));
  final File afterFile = File(path.join(afterFolder, relativePath));
  try {
    if (!await beforeFile.exists() || !await afterFile.exists()) return null;
    final Object? beforeJson = jsonDecode(await beforeFile.readAsString());
    final Object? afterJson = jsonDecode(await afterFile.readAsString());
    final List<BackupJsonFieldChange> changes = <BackupJsonFieldChange>[];
    _collectJsonChanges(
      beforeJson,
      afterJson,
      field: '',
      beforePresent: true,
      afterPresent: true,
      changes: changes,
    );
    changes.sort(
      (BackupJsonFieldChange a, BackupJsonFieldChange b) =>
          a.field.toLowerCase().compareTo(b.field.toLowerCase()),
    );
    return changes;
  } on FileSystemException {
    return null;
  } on FormatException {
    return null;
  }
}

/// Compatibility helper for callers that still ask specifically for project.json.
Future<List<BackupJsonFieldChange>?> compareBackupProjectJsonChanges({
  required String liveFolder,
  required String backupFolder,
}) => compareBackupJsonChanges(
  beforeFolder: backupFolder,
  afterFolder: liveFolder,
  relativePath: WallpaperFiles.project,
);

void _collectJsonChanges(
  Object? before,
  Object? after, {
  required String field,
  required bool beforePresent,
  required bool afterPresent,
  required List<BackupJsonFieldChange> changes,
}) {
  if (beforePresent && afterPresent && before is Map && after is Map) {
    final Set<String> keys = <String>{
      ...before.keys.map((Object? key) => '$key'),
      ...after.keys.map((Object? key) => '$key'),
    };
    final List<String> ordered = keys.toList()
      ..sort(
        (String a, String b) => a.toLowerCase().compareTo(b.toLowerCase()),
      );
    for (final String key in ordered) {
      final bool hasBefore = before.containsKey(key);
      final bool hasAfter = after.containsKey(key);
      _collectJsonChanges(
        hasBefore ? before[key] : null,
        hasAfter ? after[key] : null,
        field: field.isEmpty ? key : '$field.$key',
        beforePresent: hasBefore,
        afterPresent: hasAfter,
        changes: changes,
      );
    }
    return;
  }

  if (beforePresent && afterPresent && before is List && after is List) {
    final int length = max(before.length, after.length);
    for (int index = 0; index < length; index++) {
      final bool hasBefore = index < before.length;
      final bool hasAfter = index < after.length;
      _collectJsonChanges(
        hasBefore ? before[index] : null,
        hasAfter ? after[index] : null,
        field: '$field[$index]',
        beforePresent: hasBefore,
        afterPresent: hasAfter,
        changes: changes,
      );
    }
    return;
  }

  if (beforePresent == afterPresent && before == after) return;
  changes.add((
    field: field.isEmpty ? r'$' : field,
    before: before,
    after: after,
    beforePresent: beforePresent,
    afterPresent: afterPresent,
  ));
}

/// Compares two files in fixed-size chunks without buffering whole payloads.
Future<bool?> filesHaveSameContents(File first, File second) async {
  RandomAccessFile? firstHandle;
  RandomAccessFile? secondHandle;
  try {
    firstHandle = await first.open();
    secondHandle = await second.open();
    const int chunkSize = 64 * 1024;
    while (true) {
      final List<int> firstBytes = await firstHandle.read(chunkSize);
      final List<int> secondBytes = await secondHandle.read(chunkSize);
      if (firstBytes.length != secondBytes.length) return false;
      if (firstBytes.isEmpty) return true;
      for (int index = 0; index < firstBytes.length; index++) {
        if (firstBytes[index] != secondBytes[index]) return false;
      }
    }
  } on FileSystemException {
    return null;
  } finally {
    if (firstHandle != null) await firstHandle.close();
    if (secondHandle != null) await secondHandle.close();
  }
}

/// Whether two backup folders hold exactly the same meaningful files.
///
/// This guard is used immediately before destructive reconciliation. The normal
/// library scan intentionally compares only names and sizes for speed, but a
/// destructive decision must also verify same-size file contents byte-for-byte.
Future<bool> backupFoldersEquivalent(Directory first, Directory second) async {
  final FolderFileChanges? changes = await compareFolderFileChanges(
    firstFolder: first.path,
    secondFolder: second.path,
  );
  return changes != null &&
      changes.modified.isEmpty &&
      changes.onlyFirst.isEmpty &&
      changes.onlySecond.isEmpty;
}

/// Where each backup folder stands against its live counterpart.
///
/// Only [compare] is opened. Empty/junk detection belongs to the dedicated junk
/// pass; this comparison answers whether the meaningful file sets mirror.
Future<Map<String, CopyStanding>> copyStandings({
  required String? livePath,
  required String? backupPath,
  required bool recursive,
  required Set<String> shared,
  required Set<String> compare,
  void Function(int folders)? onBatch,
}) async {
  if (livePath == null || backupPath == null || compare.isEmpty) {
    return <String, CopyStanding>{};
  }
  final Set<String> wanted = <String>{
    for (final String name in shared)
      if (compare.contains(name)) name,
  };
  if (wanted.isEmpty) return <String, CopyStanding>{};

  if (recursive) {
    try {
      final Map<String, bool> native = await rust.compareBackupFoldersRust(
        liveRoot: livePath,
        backupRoot: backupPath,
        folderNames: wanted.toList(),
        workers: 12,
      );
      onBatch?.call(wanted.length);
      return <String, CopyStanding>{
        for (final MapEntry<String, bool> entry in native.entries)
          entry.key: entry.value ? CopyStanding.covers : CopyStanding.behind,
      };
    } catch (_) {
      // Keep the existing Dart path as a safety net if the native bridge is
      // unavailable or the native scan itself cannot start.
    }
  }

  return _perFolder<CopyStanding>(
    backupPath,
    wanted,
    onBatch: onBatch,
    batchSize: recursive ? 8 : 24,
    (Directory backupFolder) => _copyStanding(
      liveFolder: Directory(
        path.join(livePath, path.basename(backupFolder.path)),
      ),
      backupFolder: backupFolder,
      recursive: recursive,
    ),
  );
}

Future<void> writeBackupRecords(
  String? backupRoot,
  Map<String, BackupRecord> records,
) async {
  if (backupRoot == null) return;
  final Map<String, Map<String, dynamic>> encoded =
      <String, Map<String, dynamic>>{};
  // Sorted, and indented below, because this file sits in the user's backup
  // where they read it by hand. A stable order also keeps one changed wallpaper
  // from rewriting the whole thing.
  final List<String> ids = records.keys.toList()..sort();
  for (final String id in ids) {
    final BackupRecord record = records[id]!;
    final Map<String, dynamic> fields = <String, dynamic>{
      if (record.backedUpVersion != null)
        'backedUpVersion': record.backedUpVersion!,
      if (record.dismissedVersion != null)
        'dismissedVersion': record.dismissedVersion!,
      if (record.ignoredReconcileIssues.isNotEmpty)
        'ignoredReconcileIssues': <String, String>{
          for (final MapEntry<BackupReconcileReason, String> issue
              in (record.ignoredReconcileIssues.entries.toList()..sort(
                (
                  MapEntry<BackupReconcileReason, String> a,
                  MapEntry<BackupReconcileReason, String> b,
                ) => a.key.index.compareTo(b.key.index),
              )))
            issue.key.name: issue.value,
        },
    };
    if (fields.isNotEmpty) encoded[id] = fields;
  }
  // Write beside the live file and rename into place. A direct write truncates
  // first, so process failure could discard every baseline and dismissal.
  final File file = File(path.join(backupRoot, backupRecordsName));
  final File part = File('${file.path}$backupRecordsPartSuffix');
  await part.writeAsString(_records.convert(encoded), flush: true);
  await part.rename(file.path);
}

/// Workshop version tokens by wallpaper id, and whether the ACF was readable.
///
/// Deliberately not `getAcfInfo`, which honours the `useAcfInfo` setting. That
/// setting picks what the grid sorts on; letting it switch off update detection
/// would report every backed-up Workshop wallpaper as current. A false
/// `acfRead` puts the warning above the counts, since an unreadable ACF and a
/// library with nothing to update look identical otherwise.
Future<({Map<String, String> byId, bool acfRead})> workshopVersions(
  String? acfPath,
) async {
  if (acfPath == null || !await File(acfPath).exists()) {
    return (byId: <String, String>{}, acfRead: false);
  }
  try {
    final Map<String, dynamic> parsed = await parseAcf(acfPath);
    if (!isWorkshopAcf(parsed)) {
      return (byId: <String, String>{}, acfRead: false);
    }
    final List<AcfInfo> items = convertToAcfInfoList(parsed);
    return (
      byId: <String, String>{
        for (final AcfInfo item in items)
          if (item.manifest != null) item.id: item.manifest!,
      },
      acfRead: true,
    );
  } catch (e) {
    debugPrint('${tr(AppI10n.errorParseAcfFailed)} $e');
    return (byId: <String, String>{}, acfRead: false);
  }
}

/// Version token per wallpaper folder, for a library with no ACF to ask.
///
/// Folders with no top-level files are left out, so the differ sees them as
/// uncomparable rather than as changed.
Future<Map<String, String>> folderVersions(String? folderPath) async {
  return (await _myProjectsInventory(folderPath)).versions;
}

/// Current version recorded after backing up one live wallpaper.
Future<String?> liveBackupVersion(
  BackupCard card, {
  required String liveFolder,
  required String? acfPath,
}) async => switch (card.library) {
  WallpaperLibrary.workshop => (await workshopVersions(
    acfPath,
  )).byId[card.name],
  WallpaperLibrary.myProjects => _folderToken(Directory(liveFolder)),
};

Future<({Set<String> names, Map<String, String> versions})>
_myProjectsInventory(String? folderPath) async {
  if (folderPath == null) {
    return (names: <String>{}, versions: <String, String>{});
  }

  try {
    final Map<String, String?> native = await rust.myProjectsInventoryRust(
      root: folderPath,
      ignoredPrefixes: const <String>[
        WallpaperFiles.rescueStagePrefix,
        WallpaperFiles.restoreStagePrefix,
        WallpaperFiles.emptyBackupStagePrefix,
      ],
      workers: 12,
    );
    return (
      names: native.keys.toSet(),
      versions: <String, String>{
        for (final MapEntry<String, String?> entry in native.entries)
          if (entry.value != null) entry.key: entry.value!,
      },
    );
  } catch (_) {
    final Set<String> names = await listFolderNames(folderPath);
    return (
      names: names,
      versions: await _perFolder<String>(folderPath, names, _folderToken),
    );
  }
}

Future<String?> _folderToken(Directory folder) async {
  final List<FileStamp> stamps = <FileStamp>[];
  try {
    await for (final FileSystemEntity entity in folder.list()) {
      if (entity is! File) continue;
      final FileStat stat = await entity.stat();
      stamps.add(
        FileStamp(
          name: path.basename(entity.path),
          size: stat.size,
          modified: stat.modified,
        ),
      );
    }
  } on FileSystemException {
    return null; // A folder that moved mid-scan skips, it does not abort.
  }
  return folderVersion(stamps);
}
