import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:we_repkg/constants/i10n.dart';
import 'package:we_repkg/constants/strings.dart';
import 'package:we_repkg/constants/wallpaper_files.dart';
import 'package:we_repkg/models/acf.dart';
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
/// [comparing] is the long one: it walks both backup trees, and on a real
/// library that is ten of the scan's twelve seconds. [reading] has no total
/// worth reporting, since it is seven listings running at once. [details] is
/// the counted title and preview read; [preparing] covers the short handoff
/// while those results become the visible grid.
enum BackupScanPhase { reading, comparing, details, preparing }

typedef BackupScanProgress = ({BackupScanPhase phase, int done, int total});

typedef BackupScan = ({
  Map<BackupCard, BackupState> cards,
  Map<String, ({bool live, bool backup})> presence,
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
  final (
    Set<String> liveWorkshop,
    ({Set<String> names, Map<String, String> versions}) myProjects,
    Set<String> backupWorkshop,
    Set<String> backupMyProjects,
    ({Map<String, String> byId, bool acfRead}) acf,
    Map<String, BackupRecord> records,
    Set<BackupFolder> missing,
  ) = await (
    listFolderNames(liveWorkshopPath),
    _myProjectsInventory(liveMyProjectsPath),
    listFolderNames(backupWorkshopPath(backupRoot)),
    listFolderNames(backupMyProjectsPath(backupRoot)),
    workshopVersions(acfPath),
    readBackupRecords(backupRoot),
    _missingFolders(liveWorkshopPath, liveMyProjectsPath, backupRoot),
  ).wait;
  final Set<String> liveMyProjects = myProjects.names;

  // Comparing folders is the expensive half, so it runs on as little as
  // possible: only names both sides hold, and for Workshop only cards with no
  // saved backup version yet. An empty backup
  // folder is judged without any of that, so it is caught even on a card whose
  // record would otherwise answer for it.
  final Map<String, BackupRecord> byId = <String, BackupRecord>{
    for (final MapEntry<String, BackupRecord> entry in records.entries)
      entry.key.toLowerCase(): entry.value,
  };
  final Set<String> sharedWorkshop = _shared(liveWorkshop, backupWorkshop);
  final Set<String> sharedMyProjects = _shared(
    liveMyProjects,
    backupMyProjects,
  );
  final Set<String> workshopToCompare = <String>{
    for (final String name in sharedWorkshop)
      if (byId[BackupCard(WallpaperLibrary.workshop, name).id]
              ?.backedUpVersion ==
          null)
        name,
  };

  final Map<String, ({bool live, bool backup})> presence = _cardPresence(
    liveWorkshop,
    liveMyProjects,
    backupWorkshop,
    backupMyProjects,
  );
  // Count wallpapers, not the internal live/backup checks. The previous total
  // counted a shared wallpaper three times and made 3,400 items read as 10,000.
  final int total = presence.length;
  final Set<String> walkedCards = <String>{};
  void walked(WallpaperLibrary library, Iterable<String> names) {
    final int before = walkedCards.length;
    for (final String name in names) {
      walkedCards.add(BackupCard(library, name).id);
    }
    if (walkedCards.length == before) return;
    // The directory checks are only one arm of the comparison. Leave one step
    // open until every parallel arm has returned, rather than showing 100% while
    // file comparison is still working.
    final int reported = walkedCards.length >= total
        ? total - 1
        : walkedCards.length;
    onProgress?.call((
      phase: BackupScanPhase.comparing,
      done: reported,
      total: total,
    ));
  }

  // Nothing to compare is a first run against an empty backup folder. Saying
  // "0 of 0" there is worse than staying on the previous line.
  if (total > 0) {
    onProgress?.call((phase: BackupScanPhase.comparing, done: 0, total: total));
  }
  final (
    Map<String, CopyStanding> workshopStanding,
    Map<String, CopyStanding> myProjectsStanding,
    Set<String> junkLiveWorkshop,
    Set<String> junkLiveMyProjects,
    Set<String> junkBackupWorkshop,
    Set<String> junkBackupMyProjects,
  ) = await (
    copyStandings(
      livePath: liveWorkshopPath,
      backupPath: backupWorkshopPath(backupRoot),
      // A Workshop wallpaper is packed, so scene.pkg sits at the top level and
      // moves whenever the author republishes. Measured on a real library, not
      // one of 2192 folders held a file below the top level outside the
      // rebuilt shader cache.
      recursive: false,
      shared: sharedWorkshop,
      compare: workshopToCompare,
    ),
    copyStandings(
      livePath: liveMyProjectsPath,
      backupPath: backupMyProjectsPath(backupRoot),
      // A myprojects wallpaper is usually unpacked and its edits land in
      // subfolders: the top level alone found 3 of 46 stale backups.
      recursive: true,
      shared: sharedMyProjects,
      compare: sharedMyProjects,
    ),
    _junkFolders(
      liveWorkshopPath,
      liveWorkshop,
      live: true,
      onNames: (names) => walked(WallpaperLibrary.workshop, names),
    ),
    _junkFolders(
      liveMyProjectsPath,
      liveMyProjects,
      live: true,
      onNames: (names) => walked(WallpaperLibrary.myProjects, names),
    ),
    _junkFolders(
      backupWorkshopPath(backupRoot),
      backupWorkshop,
      live: false,
      onNames: (names) => walked(WallpaperLibrary.workshop, names),
    ),
    _junkFolders(
      backupMyProjectsPath(backupRoot),
      backupMyProjects,
      live: false,
      onNames: (names) => walked(WallpaperLibrary.myProjects, names),
    ),
  ).wait;

  onProgress?.call((
    phase: BackupScanPhase.preparing,
    done: total,
    total: total,
  ));

  final BackupDiffResult diff = backupDiff(
    liveWorkshop: liveWorkshop.difference(junkLiveWorkshop),
    liveMyProjects: liveMyProjects.difference(junkLiveMyProjects),
    backupWorkshop: backupWorkshop,
    backupMyProjects: backupMyProjects,
    liveWorkshopVersions: acf.byId,
    liveMyProjectsVersions: myProjects.versions,
    workshopStanding: workshopStanding,
    myProjectsStanding: myProjectsStanding,
    records: records,
  );
  _addLiveJunkCards(diff, WallpaperLibrary.workshop, junkLiveWorkshop);
  _addLiveJunkCards(diff, WallpaperLibrary.myProjects, junkLiveMyProjects);
  _markJunkCards(diff, WallpaperLibrary.workshop, junkBackupWorkshop);
  _markJunkCards(diff, WallpaperLibrary.myProjects, junkBackupMyProjects);
  return (
    cards: diff.cards,
    presence: presence,
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
/// the integrity check exists to point at, and hiding it here would be the one
/// place the tab lies. Measured on a real library at 0.5s warm for 3419
/// folders, against a scan that already takes ten seconds.
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
  final (
    Map<String, CardFace> facesLiveW,
    Map<String, CardFace> facesLiveM,
    Map<String, CardFace> facesGoneW,
    Map<String, CardFace> facesGoneM,
  ) = await (
    _faces(liveWorkshopPath, liveW, onBatch: read),
    _faces(liveMyProjectsPath, liveM, onBatch: read),
    _faces(backupWorkshopPath(backupRoot), goneW, onBatch: read),
    _faces(backupMyProjectsPath(backupRoot), goneM, onBatch: read),
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
  return _perFolder<CardFace>(root, names, _face, onBatch: onBatch);
}

Future<CardFace?> _face(Directory folder) async {
  final File file = File(path.join(folder.path, WallpaperFiles.project));
  if (!await file.exists()) return null;
  try {
    final Map<String, dynamic> parsed =
        json.decode(await file.readAsString()) as Map<String, dynamic>;
    final String? preview = parsed[WallpaperProjectFields.preview] as String?;
    // The same field the extract grid dates a wallpaper by, so both grids mean
    // the same thing by their date order.
    final FileStat stat = await file.stat();
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
      modified: stat.changed,
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
Future<Set<String>> _junkFolders(
  String? root,
  Set<String> names, {
  required bool live,
  void Function(List<String> names)? onNames,
}) async {
  if (root == null || names.isEmpty) return const <String>{};
  return (await _perFolder<bool>(root, names, onNames: onNames, (
    Directory folder,
  ) async {
    final bool junk = live
        ? await isLiveWallpaperJunk(folder)
        : await isBackupWallpaperJunk(folder);
    return junk ? true : null;
  })).keys.toSet();
}

void _addLiveJunkCards(
  BackupDiffResult diff,
  WallpaperLibrary library,
  Iterable<String> names,
) {
  for (final String name in names) {
    final BackupCard card = BackupCard(library, name);
    final BackupCard? existing = _cardWithId(diff.cards, card.id);
    if (existing != null) diff.cards.remove(existing);
    diff.cards[card] = BackupState.emptyBackup;
  }
}

void _markJunkCards(
  BackupDiffResult diff,
  WallpaperLibrary library,
  Iterable<String> names,
) {
  for (final String name in names) {
    final BackupCard card = BackupCard(library, name);
    // Reconciliation owns ambiguous same-name folders until the user decides
    // which copy is which; maintenance must not silently answer that question.
    final BackupCard? existing = _cardWithId(diff.cards, card.id);
    if (existing != null) {
      diff.cards[existing] = BackupState.emptyBackup;
    }
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
  void Function(List<String> names)? onNames,
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
    onNames?.call(batch);
  }
  return found;
}

/// Every file under a wallpaper folder, or null if it could not be read.
///
/// A folder that moved mid-scan skips rather than aborting the library.
Future<List<FileEntry>?> _files(
  Directory folder, {
  required bool recursive,
}) async {
  final List<FileEntry> files = <FileEntry>[];
  try {
    await for (final FileSystemEntity entity in folder.list(
      recursive: recursive,
      followLinks: false,
    )) {
      if (entity is! File) continue;
      files.add((
        path: path.relative(entity.path, from: folder.path),
        size: await entity.length(),
      ));
    }
  } on FileSystemException {
    return null;
  }
  return files;
}

/// Whether a backup folder holds any file that counts as wallpaper content.
/// Stops on the first one and never stats file sizes: an uncompared Workshop
/// backup only needs an empty/not-empty answer.
Future<bool?> _hasComparableFile(
  Directory folder, {
  required bool recursive,
}) async {
  try {
    await for (final FileSystemEntity entity in folder.list(
      recursive: recursive,
      followLinks: false,
    )) {
      if (entity is File &&
          !isRebuiltShaderPath(path.relative(entity.path, from: folder.path))) {
        return true;
      }
    }
    return false;
  } on FileSystemException {
    return null;
  }
}

/// Where each backup folder stands against its live counterpart.
///
/// [shared] is every name both sides hold; [compare] is the subset worth a full
/// comparison. Everything in [shared] is still checked for being empty, because
/// a folder with nothing in it is not a backup whatever a record says, and a
/// Workshop card that already has a baseline is never compared at all.
Future<Map<String, CopyStanding>> copyStandings({
  required String? livePath,
  required String? backupPath,
  required bool recursive,
  required Set<String> shared,
  required Set<String> compare,
  void Function(int folders)? onBatch,
}) async {
  if (livePath == null || backupPath == null || shared.isEmpty) {
    return <String, CopyStanding>{};
  }
  return _perFolder<CopyStanding>(
    backupPath,
    shared,
    onBatch: onBatch,
    // Recursive MyProjects reads contend heavily on OneDrive-backed folders.
    // Eight was the smallest near-fastest value on the real 1,180-folder
    // library; 12 and 16 were no faster, while four was substantially slower.
    batchSize: recursive ? 8 : 24,
    (Directory backupFolder) async {
      final String name = path.basename(backupFolder.path);
      if (!compare.contains(name)) {
        final bool? hasContent = await _hasComparableFile(
          backupFolder,
          recursive: recursive,
        );
        return hasContent == false ? CopyStanding.empty : null;
      }
      final (List<FileEntry>? backup, List<FileEntry>? live) = await (
        _files(backupFolder, recursive: recursive),
        _files(Directory(path.join(livePath, name)), recursive: recursive),
      ).wait;
      if (backup == null || live == null) return null;
      return compareCopy(live: live, backup: backup);
    },
  );
}

Future<void> writeBackupRecords(
  String? backupRoot,
  Map<String, BackupRecord> records,
) async {
  if (backupRoot == null) return;
  final Map<String, Map<String, String>> encoded =
      <String, Map<String, String>>{};
  // Sorted, and indented below, because this file sits in the user's backup
  // where they read it by hand. A stable order also keeps one changed wallpaper
  // from rewriting the whole thing.
  final List<String> ids = records.keys.toList()..sort();
  for (final String id in ids) {
    final BackupRecord record = records[id]!;
    final Map<String, String> fields = <String, String>{
      if (record.backedUpVersion != null)
        'backedUpVersion': record.backedUpVersion!,
      if (record.dismissedVersion != null)
        'dismissedVersion': record.dismissedVersion!,
    };
    if (fields.isNotEmpty) encoded[id] = fields;
  }
  // Written beside itself and renamed over, the way copyFileReplacing does it.
  // A plain write truncates first, so a run killed mid-write would leave a
  // short file that readBackupRecords parses as no records at all, silently
  // discarding every baseline and every dismissal.
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
  final Set<String> names = await listFolderNames(folderPath);
  if (folderPath == null) return (names: names, versions: <String, String>{});
  return (
    names: names,
    versions: await _perFolder<String>(folderPath, names, _folderToken),
  );
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
