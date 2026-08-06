import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:we_repkg/constants/i10n.dart';
import 'package:we_repkg/constants/strings.dart';
import 'package:we_repkg/models/acf.dart';
import 'package:we_repkg/utils/backup_diff.dart';
import 'package:we_repkg/utils/parse_acf.dart';

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

typedef BackupScan = ({
  Map<BackupCard, BackupState> cards,
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
}) async {
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

  final BackupDiffResult diff = backupDiff(
    liveWorkshop: liveWorkshop,
    liveMyProjects: liveMyProjects,
    backupWorkshop: backupWorkshop,
    backupMyProjects: backupMyProjects,
    liveWorkshopVersions: acf.byId,
    liveMyProjectsVersions: myProjectsVersions,
    records: records,
  );
  return (
    cards: diff.cards,
    reconcile: diff.reconcile,
    acfRead: acf.acfRead,
    missing: missing,
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

Future<void> writeBackupRecords(
  String? backupRoot,
  Map<String, BackupRecord> records,
) async {
  if (backupRoot == null) return;
  final Map<String, Map<String, String>> encoded =
      <String, Map<String, String>>{};
  records.forEach((String id, BackupRecord record) {
    final Map<String, String> fields = <String, String>{
      if (record.backedUpVersion != null)
        'backedUpVersion': record.backedUpVersion!,
      if (record.dismissedVersion != null)
        'dismissedVersion': record.dismissedVersion!,
    };
    if (fields.isNotEmpty) encoded[id] = fields;
  });
  await File(
    path.join(backupRoot, backupRecordsName),
  ).writeAsString(json.encode(encoded));
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
  final Map<String, String> versions = <String, String>{};
  if (folderPath == null) return versions;
  final Directory dir = Directory(folderPath);
  if (!await dir.exists()) return versions;

  final List<Directory> folders = <Directory>[];
  await for (final FileSystemEntity entity in dir.list()) {
    if (entity is Directory) folders.add(entity);
  }
  // Batched, or a large library opens too many file handles at once.
  const int batchSize = 24;
  for (int i = 0; i < folders.length; i += batchSize) {
    final List<(String, String)?> batch = await Future.wait(
      folders.skip(i).take(batchSize).map(_folderToken),
    );
    for (final (String, String)? entry in batch) {
      if (entry != null) versions[entry.$1] = entry.$2;
    }
  }
  return versions;
}

Future<(String, String)?> _folderToken(Directory folder) async {
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
  final String? token = folderVersion(stamps);
  return token == null ? null : (path.basename(folder.path), token);
}
