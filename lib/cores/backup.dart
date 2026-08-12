import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:we_repkg/constants/i10n.dart';
import 'package:we_repkg/constants/strings.dart';
import 'package:we_repkg/models/acf.dart';
import 'package:we_repkg/utils/backup_diff.dart';
import 'package:we_repkg/utils/folder_entries.dart';
import 'package:we_repkg/utils/parse_acf.dart';
import 'package:we_repkg/utils/wallpaper_integrity.dart';

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
/// [comparing] is the long one and the only one that can count: it walks both
/// backup trees, and on a real library that is ten of the scan's twelve
/// seconds. [reading] has no total worth reporting, since it is seven listings
/// running at once.
enum BackupScanPhase { reading, comparing }

typedef BackupScanProgress = ({BackupScanPhase phase, int done, int total});

typedef BackupScan = ({
  Map<BackupCard, BackupState> cards,
  List<ReconcileEntry> reconcile,
  bool acfRead,
  Set<BackupFolder> missing,

  /// Baselines this scan earned. [seedBackupRecords] is what writes them.
  Map<String, String> seeds,
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
    Set<String> liveMyProjects,
    Set<String> backupWorkshop,
    Set<String> backupMyProjects,
    Map<String, String> myProjectsVersions,
    ({Map<String, String> byId, bool acfRead}) acf,
    Map<String, BackupRecord> records,
    Set<BackupFolder> missing,
  ) = await (
    listFolderNames(liveWorkshopPath),
    listFolderNames(liveMyProjectsPath),
    listFolderNames(backupWorkshopPath(backupRoot)),
    listFolderNames(backupMyProjectsPath(backupRoot)),
    folderVersions(liveMyProjectsPath),
    workshopVersions(acfPath),
    readBackupRecords(backupRoot),
    _missingFolders(liveWorkshopPath, liveMyProjectsPath, backupRoot),
  ).wait;

  // Comparing folders is the expensive half, so it runs on as little as
  // possible: only names both sides hold, and for Workshop only cards with no
  // baseline yet, which empties out as records accumulate. An empty backup
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
  final Set<String> unseeded = <String>{
    for (final String name in sharedWorkshop)
      if (byId[BackupCard(WallpaperLibrary.workshop, name).id]
              ?.backedUpVersion ==
          null)
        name,
  };

  // Names live holds and the backup does not, which are the ones that could be
  // a folder Steam emptied. A folder its own backup covers is a wallpaper
  // whatever is left of it live.
  final Set<String> newWorkshop = _liveOnly(liveWorkshop, backupWorkshop);
  final Set<String> newMyProjects = _liveOnly(liveMyProjects, backupMyProjects);

  // One counter across both libraries, since they walk at the same time and the
  // user is watching one line. Every shared folder is opened, whether or not it
  // is compared: the ones with a baseline are still checked for being empty.
  // Counting only the compared ones is what made this read "3314 of 1193", and
  // leaving the husk listings out would stall it on a first run, where they are
  // the only per-folder work there is.
  final int total =
      sharedWorkshop.length +
      sharedMyProjects.length +
      newWorkshop.length +
      newMyProjects.length;
  int done = 0;
  void walked(int folders) {
    done += folders;
    onProgress?.call((
      phase: BackupScanPhase.comparing,
      done: done,
      total: total,
    ));
  }

  // Nothing to compare is a first run against an empty backup folder. Saying
  // "0 of 0" there is worse than staying on the previous line.
  if (total > 0) walked(0);
  final (
    Map<String, CopyStanding> workshopStanding,
    Map<String, CopyStanding> myProjectsStanding,
    Set<String> huskWorkshop,
    Set<String> huskMyProjects,
  ) = await (
    copyStandings(
      livePath: liveWorkshopPath,
      backupPath: backupWorkshopPath(backupRoot),
      onBatch: walked,
      // A Workshop wallpaper is packed, so scene.pkg sits at the top level and
      // moves whenever the author republishes. Measured on a real library, not
      // one of 2192 folders held a file below the top level outside the
      // rebuilt shader cache.
      recursive: false,
      shared: sharedWorkshop,
      compare: unseeded,
    ),
    copyStandings(
      livePath: liveMyProjectsPath,
      backupPath: backupMyProjectsPath(backupRoot),
      onBatch: walked,
      // A myprojects wallpaper is usually unpacked and its edits land in
      // subfolders: the top level alone found 3 of 46 stale backups.
      recursive: true,
      shared: sharedMyProjects,
      compare: sharedMyProjects,
    ),
    _shaderHusks(liveWorkshopPath, newWorkshop, onBatch: walked),
    _shaderHusks(liveMyProjectsPath, newMyProjects, onBatch: walked),
  ).wait;

  final BackupDiffResult diff = backupDiff(
    liveWorkshop: liveWorkshop.difference(huskWorkshop),
    liveMyProjects: liveMyProjects.difference(huskMyProjects),
    backupWorkshop: backupWorkshop,
    backupMyProjects: backupMyProjects,
    liveWorkshopVersions: acf.byId,
    liveMyProjectsVersions: myProjectsVersions,
    workshopStanding: workshopStanding,
    myProjectsStanding: myProjectsStanding,
    records: records,
  );
  return (
    cards: diff.cards,
    reconcile: diff.reconcile,
    acfRead: acf.acfRead,
    missing: missing,
    seeds: diff.seeds,
  );
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
}) async {
  final List<String> liveW = <String>[];
  final List<String> liveM = <String>[];
  final List<String> goneW = <String>[];
  final List<String> goneM = <String>[];
  cards.forEach((BackupCard card, BackupState state) {
    final bool gone = state == BackupState.vanished;
    switch (card.library) {
      case WallpaperLibrary.workshop:
        (gone ? goneW : liveW).add(card.name);
      case WallpaperLibrary.myProjects:
        (gone ? goneM : liveM).add(card.name);
    }
  });

  final (
    Map<String, CardFace> facesLiveW,
    Map<String, CardFace> facesLiveM,
    Map<String, CardFace> facesGoneW,
    Map<String, CardFace> facesGoneM,
  ) = await (
    _faces(liveWorkshopPath, liveW),
    _faces(liveMyProjectsPath, liveM),
    _faces(backupWorkshopPath(backupRoot), goneW),
    _faces(backupMyProjectsPath(backupRoot), goneM),
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

Future<Map<String, CardFace>> _faces(String? root, List<String> names) async {
  if (root == null || names.isEmpty) return <String, CardFace>{};
  return _perFolder<CardFace>(root, names, _face);
}

Future<CardFace?> _face(Directory folder) async {
  final File file = File(path.join(folder.path, 'project.json'));
  if (!await file.exists()) return null;
  try {
    final Map<String, dynamic> parsed =
        json.decode(await file.readAsString()) as Map<String, dynamic>;
    final String? preview = parsed['preview'] as String?;
    // The same field the extract grid dates a wallpaper by, so both grids mean
    // the same thing by their date order.
    final FileStat stat = await file.stat();
    // myprojects wallpapers often have no title. A hand-made one can also put a
    // number where the string belongs, which the cast throws on and the catch
    // below turns into no face at all, matching what the extract grid does with
    // the same folder.
    return (
      title: parsed['title'] as String? ?? path.basename(folder.path),
      preview: preview == null ? '' : path.join(folder.path, preview),
      type: (parsed['type'] as String? ?? '').toLowerCase(),
      rating: (parsed['contentrating'] as String? ?? '').toLowerCase(),
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

/// Live names the backup does not hold, in their own case so a path can be
/// joined from them, unlike [_shared] which lowercases.
Set<String> _liveOnly(Set<String> live, Set<String> backup) {
  final Set<String> backupKeys = _lowered(backup);
  return <String>{
    for (final String name in live)
      if (!backupKeys.contains(name.toLowerCase())) name,
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
Future<Set<String>> _shaderHusks(
  String? root,
  Set<String> names, {
  void Function(int folders)? onBatch,
}) async {
  if (root == null || names.isEmpty) return const <String>{};
  return (await _perFolder<bool>(root, names, onBatch: onBatch, (
    Directory folder,
  ) async {
    final List<FolderEntry>? entries = await listFolderEntries(folder);
    return entries != null && holdsOnlyRebuiltShaders(entries) ? true : null;
  })).keys.toSet();
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
    if (entity is Directory) names.add(path.basename(entity.path));
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

/// Records the baselines a scan earned, keeping any dismissal already filed.
///
/// The only write this feature makes into the user's backup. Existing keys are
/// folded to lowercase on the way through, so a file hand-edited with a
/// different spelling converges rather than growing a second entry for one
/// wallpaper.
Future<void> seedBackupRecords(
  String? backupRoot,
  Map<String, String> seeds,
) async {
  if (backupRoot == null || seeds.isEmpty) return;
  final Map<String, BackupRecord> existing = await readBackupRecords(
    backupRoot,
  );
  final Map<String, BackupRecord> merged = <String, BackupRecord>{
    for (final MapEntry<String, BackupRecord> entry in existing.entries)
      entry.key.toLowerCase(): entry.value,
  };
  seeds.forEach((String id, String version) {
    merged[id] = BackupRecord(
      backedUpVersion: version,
      dismissedVersion: merged[id]?.dismissedVersion,
    );
  });
  await writeBackupRecords(backupRoot, merged);
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
}) async {
  final Map<String, T> found = <String, T>{};
  final List<String> wanted = names.toList();
  const int batchSize = 24;
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
  return _perFolder<CopyStanding>(backupPath, shared, onBatch: onBatch, (
    Directory backupFolder,
  ) async {
    final String name = path.basename(backupFolder.path);
    final List<FileEntry>? backup = await _files(
      backupFolder,
      recursive: recursive,
    );
    if (backup == null) return null;
    if (!compare.contains(name)) {
      // Not worth a full comparison, so the only question left is whether
      // anything is in there at all.
      return compareCopy(live: const <FileEntry>[], backup: backup) ==
              CopyStanding.empty
          ? CopyStanding.empty
          : null;
    }
    final List<FileEntry>? live = await _files(
      Directory(path.join(livePath, name)),
      recursive: recursive,
    );
    if (live == null) return null;
    return compareCopy(live: live, backup: backup);
  });
}

Future<void> writeBackupRecords(
  String? backupRoot,
  Map<String, BackupRecord> records,
) async {
  if (backupRoot == null) return;
  final Map<String, Map<String, String>> encoded =
      <String, Map<String, String>>{};
  // Sorted, and indented below, because this file sits in the user's backup
  // where they read it by hand. It is also rewritten on every scan, so a stable
  // order keeps one changed wallpaper from rewriting the whole thing.
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
  // discarding every baseline and every dismissal. This file is rewritten on
  // every scan, so that window would be open constantly.
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
  if (folderPath == null) return <String, String>{};
  return _perFolder<String>(
    folderPath,
    await listFolderNames(folderPath),
    _folderToken,
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
