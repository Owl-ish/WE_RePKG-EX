import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:we_repkg/constants/i10n.dart';
import 'package:we_repkg/constants/wallpaper_files.dart';
import 'package:we_repkg/cores/backup.dart';
import 'package:we_repkg/src/rust/api/simple.dart';
import 'package:we_repkg/utils/backup_diff.dart';
import 'package:we_repkg/utils/file_copy.dart';
import 'package:we_repkg/utils/windows_file_transaction.dart';
import 'package:we_repkg/utils/wallpaper_junk.dart';

typedef BackupActionResult = ({bool changed, String? error});
typedef BackupTrash = Future<String?> Function(String folder);

/// Copies a live wallpaper into its matching backup library.
///
/// Detailed Update can preserve selected old files. [mirror] is explicit so
/// ordinary Back up remains non-destructive; Update/Sync enables it. Cleanup
/// happens only after selected copies finish and the source is still stable.
Future<BackupActionResult> backUpWallpaper({
  required BackupCard card,
  required String? backupRoot,
  required String? liveWorkshopPath,
  required String? liveMyProjectsPath,
  required String? acfPath,
  bool mirror = false,
  BackupSelectiveUpdatePlan? selectiveUpdate,
  BackupTrash? trashFolder,
}) async {
  final String? liveRoot = switch (card.library) {
    WallpaperLibrary.workshop => liveWorkshopPath,
    WallpaperLibrary.myProjects => liveMyProjectsPath,
  };
  final String? backupLibrary = switch (card.library) {
    WallpaperLibrary.workshop => backupWorkshopPath(backupRoot),
    WallpaperLibrary.myProjects => backupMyProjectsPath(backupRoot),
  };
  final String? otherLiveRoot = switch (card.library) {
    WallpaperLibrary.workshop => liveMyProjectsPath,
    WallpaperLibrary.myProjects => liveWorkshopPath,
  };
  final String? otherBackupLibrary = switch (card.library) {
    WallpaperLibrary.workshop => backupMyProjectsPath(backupRoot),
    WallpaperLibrary.myProjects => backupWorkshopPath(backupRoot),
  };
  if (backupRoot == null ||
      liveRoot == null ||
      backupLibrary == null ||
      otherBackupLibrary == null) {
    return (changed: false, error: tr(AppI10n.backupActionFolderUnavailable));
  }
  final Directory source = Directory(path.join(liveRoot, card.name));
  final Directory destination = Directory(path.join(backupLibrary, card.name));
  final Directory otherBackup = Directory(
    path.join(otherBackupLibrary, card.name),
  );
  final Directory? otherLive = otherLiveRoot == null
      ? null
      : Directory(path.join(otherLiveRoot, card.name));
  bool changed = false;
  bool filesystemMayHaveChanged = false;
  try {
    if (!await source.exists()) {
      return (changed: false, error: tr(AppI10n.backupActionSourceMissing));
    }
    if (_inside(destination.path, source.path)) {
      return (changed: false, error: tr(AppI10n.backupActionUnsafeDestination));
    }
    final bool destinationExisted = await destination.exists();
    final bool otherBackupExisted = await otherBackup.exists();
    if (otherBackupExisted && otherLive == null) {
      return (changed: false, error: tr(AppI10n.backupActionFolderUnavailable));
    }
    if (otherBackupExisted && await otherLive!.exists()) {
      return (changed: false, error: tr(AppI10n.backupActionStateChanged));
    }
    if (destinationExisted &&
        otherBackupExisted &&
        !await backupFoldersEquivalent(destination, otherBackup)) {
      return (changed: false, error: tr(AppI10n.backupActionStateChanged));
    }

    final BackupSelectiveUpdatePlan? selection = selectiveUpdate;
    if (selection != null) {
      final Directory? comparisonBackup = destinationExisted
          ? destination
          : otherBackupExisted
          ? otherBackup
          : null;
      if (comparisonBackup == null) {
        return (changed: false, error: tr(AppI10n.backupActionStateChanged));
      }
      final BackupFileChanges? current = await compareBackupFileChanges(
        liveFolder: source.path,
        backupFolder: comparisonBackup.path,
      );
      if (current == null ||
          !backupFileChangesEqual(current, selection.expectedChanges)) {
        return (changed: false, error: tr(AppI10n.backupActionStateChanged));
      }
    }

    final String? before = await liveBackupVersion(
      card,
      liveFolder: source.path,
      acfPath: acfPath,
    );
    // A thrown copy can still have published files, so failures after this
    // point refresh instead of claiming the filesystem stayed unchanged.
    filesystemMayHaveChanged = true;

    // A wrong-tree selective update needs the old backup as its starting point
    // so files marked Keep survive the relocation into the canonical tree.
    if (selection?.isPartial == true &&
        !destinationExisted &&
        otherBackupExisted) {
      changed =
          await _copyFolderIncrementally(otherBackup, destination) || changed;
    }
    changed =
        await _copyFolderIncrementally(
          source,
          destination,
          skippedRelativePaths: selection?.skippedCopies ?? const <String>{},
        ) ||
        changed;
    final String? afterCopies = await liveBackupVersion(
      card,
      liveFolder: source.path,
      acfPath: acfPath,
    );
    if (before != afterCopies) {
      return (changed: changed, error: tr(AppI10n.backupActionSourceChanged));
    }

    if (mirror) {
      changed =
          await _removeMirrorResidue(
            source: source,
            destination: destination,
            keptRelativePaths: selection?.keptBackupFiles ?? const <String>{},
          ) ||
          changed;
    }

    final String? version = await liveBackupVersion(
      card,
      liveFolder: source.path,
      acfPath: acfPath,
    );
    if (before != version) {
      return (changed: changed, error: tr(AppI10n.backupActionSourceChanged));
    }
    final Map<String, BackupRecord> records = await readBackupRecords(
      backupRoot,
    );
    final BackupRecord previous = records[card.id] ?? const BackupRecord();
    if (selection?.isPartial != true) {
      final BackupRecord next = BackupRecord(
        backedUpVersion: version ?? previous.backedUpVersion,
      );
      changed =
          changed ||
          next.backedUpVersion != previous.backedUpVersion ||
          next.dismissedVersion != previous.dismissedVersion;
      records[card.id] = next;
    }

    // The matching copy and stable source are established before any
    // opposite-library backup is recycled.
    String? syncError;
    if (otherBackupExisted) {
      syncError = await _recycleSyncedBackup(
        target: otherBackup,
        trashFolder: trashFolder,
      );
      if (syncError == null) {
        changed = true;
        final WallpaperLibrary otherLibrary = switch (card.library) {
          WallpaperLibrary.workshop => WallpaperLibrary.myProjects,
          WallpaperLibrary.myProjects => WallpaperLibrary.workshop,
        };
        records.remove(BackupCard(otherLibrary, card.name).id);
      }
    }
    await writeBackupRecords(backupRoot, records);
    return (changed: changed, error: syncError);
  } catch (error) {
    return (changed: changed || filesystemMayHaveChanged, error: '$error');
  }
}

/// Moves one content-update detection into the shared Ignored view.
///
/// The ignored version is tied to the current live version. A later live
/// change no longer matches the marker, so the update automatically surfaces
/// again.
Future<BackupActionResult> ignoreBackupUpdate({
  required BackupCard card,
  required String? backupRoot,
  required String? liveWorkshopPath,
  required String? liveMyProjectsPath,
  required String? acfPath,
}) async {
  if (backupRoot == null) {
    return (changed: false, error: tr(AppI10n.backupActionFolderUnavailable));
  }
  final String? liveRoot = switch (card.library) {
    WallpaperLibrary.workshop => liveWorkshopPath,
    WallpaperLibrary.myProjects => liveMyProjectsPath,
  };
  if (liveRoot == null) {
    return (changed: false, error: tr(AppI10n.backupActionFolderUnavailable));
  }
  try {
    final String? version = await liveBackupVersion(
      card,
      liveFolder: path.join(liveRoot, card.name),
      acfPath: acfPath,
    );
    if (version == null) {
      return (changed: false, error: tr(AppI10n.backupActionStateChanged));
    }
    final Map<String, BackupRecord> records = await readBackupRecords(
      backupRoot,
    );
    final BackupRecord previous = records[card.id] ?? const BackupRecord();
    if (previous.dismissedVersion == version) {
      return (changed: false, error: null);
    }
    records[card.id] = BackupRecord(
      backedUpVersion: previous.backedUpVersion,
      dismissedVersion: version,
      ignoredReconcileIssues: previous.ignoredReconcileIssues,
    );
    await writeBackupRecords(backupRoot, records);
    return (changed: true, error: null);
  } catch (error) {
    return (changed: false, error: '$error');
  }
}

/// Saves the current evidence for each ignored Reconcile warning.
Future<BackupActionResult> ignoreReconcileIssues({
  required String name,
  required Map<BackupReconcileReason, String> fingerprints,
  required String? backupRoot,
}) async {
  if (backupRoot == null) {
    return (changed: false, error: tr(AppI10n.backupActionFolderUnavailable));
  }
  final Map<BackupReconcileReason, String> supported =
      <BackupReconcileReason, String>{
        for (final MapEntry<BackupReconcileReason, String> entry
            in fingerprints.entries)
          if (reconcileReasonCanBeIgnored(entry.key)) entry.key: entry.value,
      };
  if (supported.isEmpty) return (changed: false, error: null);
  try {
    final Map<String, BackupRecord> records = await readBackupRecords(
      backupRoot,
    );
    final String id = reconcileIgnoreRecordId(name);
    final BackupRecord previous = records[id] ?? const BackupRecord();
    final Map<BackupReconcileReason, String> ignored =
        <BackupReconcileReason, String>{
          ...previous.ignoredReconcileIssues,
          ...supported,
        };
    if (mapEquals(ignored, previous.ignoredReconcileIssues)) {
      return (changed: false, error: null);
    }
    records[id] = BackupRecord(
      backedUpVersion: previous.backedUpVersion,
      dismissedVersion: previous.dismissedVersion,
      ignoredReconcileIssues: ignored,
    );
    await writeBackupRecords(backupRoot, records);
    return (changed: true, error: null);
  } catch (error) {
    return (changed: false, error: '$error');
  }
}

/// Restores only the requested Reconcile warnings for one wallpaper.
Future<BackupActionResult> showReconcileIssuesAgain({
  required String name,
  required Set<BackupReconcileReason> reasons,
  required String? backupRoot,
}) async {
  if (backupRoot == null) {
    return (changed: false, error: tr(AppI10n.backupActionFolderUnavailable));
  }
  if (reasons.isEmpty) return (changed: false, error: null);
  try {
    final Map<String, BackupRecord> records = await readBackupRecords(
      backupRoot,
    );
    final String id = reconcileIgnoreRecordId(name);
    final BackupRecord? previous = records[id];
    if (previous == null || previous.ignoredReconcileIssues.isEmpty) {
      return (changed: false, error: tr(AppI10n.backupActionStateChanged));
    }
    final Map<BackupReconcileReason, String> ignored =
        <BackupReconcileReason, String>{...previous.ignoredReconcileIssues}
          ..removeWhere(
            (BackupReconcileReason reason, String _) =>
                reasons.contains(reason),
          );
    if (mapEquals(ignored, previous.ignoredReconcileIssues)) {
      return (changed: false, error: tr(AppI10n.backupActionStateChanged));
    }
    if (ignored.isEmpty &&
        previous.backedUpVersion == null &&
        previous.dismissedVersion == null) {
      records.remove(id);
    } else {
      records[id] = BackupRecord(
        backedUpVersion: previous.backedUpVersion,
        dismissedVersion: previous.dismissedVersion,
        ignoredReconcileIssues: ignored,
      );
    }
    await writeBackupRecords(backupRoot, records);
    return (changed: true, error: null);
  } catch (error) {
    return (changed: false, error: '$error');
  }
}

/// Restores every ignored content update and Reconcile warning in one write.
Future<BackupActionResult> showAllIgnoredIssues({
  required String? backupRoot,
  required Iterable<BackupCard> ignoredUpdates,
  required Iterable<ReconcileEntry> reconcileEntries,
}) async {
  if (backupRoot == null) {
    return (changed: false, error: tr(AppI10n.backupActionFolderUnavailable));
  }
  try {
    final Map<String, BackupRecord> records = await readBackupRecords(
      backupRoot,
    );
    bool changed = false;
    for (final BackupCard card in ignoredUpdates) {
      final BackupRecord? previous = records[card.id];
      if (previous == null || previous.dismissedVersion == null) continue;
      records[card.id] = BackupRecord(
        backedUpVersion: previous.backedUpVersion,
        ignoredReconcileIssues: previous.ignoredReconcileIssues,
      );
      changed = true;
    }
    for (final ReconcileEntry entry in reconcileEntries) {
      if (entry.ignoredReasons.isEmpty) continue;
      final String id = reconcileIgnoreRecordId(entry.name);
      final BackupRecord? previous = records[id];
      if (previous == null || previous.ignoredReconcileIssues.isEmpty) continue;
      if (previous.backedUpVersion == null &&
          previous.dismissedVersion == null) {
        records.remove(id);
      } else {
        records[id] = BackupRecord(
          backedUpVersion: previous.backedUpVersion,
          dismissedVersion: previous.dismissedVersion,
        );
      }
      changed = true;
    }
    if (!changed) {
      return (changed: false, error: tr(AppI10n.backupActionStateChanged));
    }
    await writeBackupRecords(backupRoot, records);
    return (changed: true, error: null);
  } catch (error) {
    return (changed: false, error: '$error');
  }
}

/// Clears only the dismissed update marker, preserving the backup baseline.
Future<BackupActionResult> showBackupUpdateAgain({
  required BackupCard card,
  required String? backupRoot,
}) async {
  if (backupRoot == null) {
    return (changed: false, error: tr(AppI10n.backupActionFolderUnavailable));
  }
  try {
    final Map<String, BackupRecord> records = await readBackupRecords(
      backupRoot,
    );
    final BackupRecord? previous = records[card.id];
    if (previous == null || previous.dismissedVersion == null) {
      return (changed: false, error: tr(AppI10n.backupActionStateChanged));
    }
    records[card.id] = BackupRecord(
      backedUpVersion: previous.backedUpVersion,
      ignoredReconcileIssues: previous.ignoredReconcileIssues,
    );
    await writeBackupRecords(backupRoot, records);
    return (changed: true, error: null);
  } catch (error) {
    return (changed: false, error: '$error');
  }
}

/// Recycles disposable live or backup remnants after rechecking each target.
Future<BackupActionResult> recycleBackupJunk({
  required BackupCard card,
  required String? backupRoot,
  required String? liveWorkshopPath,
  required String? liveMyProjectsPath,
  BackupTrash? trashFolder,
}) async {
  final String? liveLibrary = switch (card.library) {
    WallpaperLibrary.workshop => liveWorkshopPath,
    WallpaperLibrary.myProjects => liveMyProjectsPath,
  };
  final String? backupLibrary = switch (card.library) {
    WallpaperLibrary.workshop => backupWorkshopPath(backupRoot),
    WallpaperLibrary.myProjects => backupMyProjectsPath(backupRoot),
  };
  if (liveLibrary == null || backupLibrary == null) {
    return (changed: false, error: tr(AppI10n.backupActionFolderUnavailable));
  }
  final Directory live = Directory(path.join(liveLibrary, card.name));
  final Directory backup = Directory(path.join(backupLibrary, card.name));
  final List<({Directory folder, String library, _JunkCheck check})> targets =
      [];
  if (await isLiveWallpaperJunk(live)) {
    targets.add((
      folder: live,
      library: liveLibrary,
      check: isLiveWallpaperJunk,
    ));
  }
  if (await isEmptyFolderTree(backup)) {
    targets.add((
      folder: backup,
      library: backupLibrary,
      check: isEmptyFolderTree,
    ));
  } else if (await isBackupWallpaperJunk(backup)) {
    final bool hasCache = await hasBackupShaderCache(backup);
    targets.add((
      folder: hasCache ? backupShaderCache(backup) : backup,
      library: backupLibrary,
      check: hasCache ? _isShaderCacheFolder : isBackupWallpaperJunk,
    ));
  }
  if (targets.isEmpty) {
    return (changed: false, error: tr(AppI10n.backupActionStateChanged));
  }

  bool changed = false;
  final List<String> errors = [];
  for (final target in targets) {
    final BackupActionResult result = await _recycleCheckedFolder(
      target: target.folder,
      library: target.library,
      check: target.check,
      trashFolder: trashFolder,
    );
    changed = changed || result.changed;
    if (result.error != null) errors.add(result.error!);
  }
  // Removing cache can leave an empty or `.dxs`-only wrapper behind.
  if (changed && await isBackupWallpaperJunk(backup)) {
    final BackupActionResult result = await _recycleCheckedFolder(
      target: backup,
      library: backupLibrary,
      check: isBackupWallpaperJunk,
      trashFolder: trashFolder,
    );
    changed = changed || result.changed;
    if (result.error != null) errors.add(result.error!);
  }
  return (changed: changed, error: errors.isEmpty ? null : errors.join('\n'));
}

/// Claims a redundant backup before sending it to the Recycle Bin.
///
/// If trash cannot be confirmed, the claim is restored so Sync does not leave
/// the filesystem in a half-cleaned state.
Future<String?> _recycleSyncedBackup({
  required Directory target,
  BackupTrash? trashFolder,
}) async {
  if (!await target.exists()) return null;
  final Directory wrapper = await target.parent.createTemp(
    WallpaperFiles.emptyBackupStagePrefix,
  );
  final Directory claimed = Directory(
    path.join(wrapper.path, path.basename(target.path)),
  );
  try {
    publishWithoutReplacing(target, claimed.path);
    final BackupTrash trash =
        trashFolder ?? (String folder) => deleteToTrash(filePath: folder);
    final String? error = await trash(claimed.path);
    if (await claimed.exists()) {
      await _restoreClaim(claimed, target.path);
      return error ?? tr(AppI10n.backupActionTrashUnconfirmed);
    }
    return error;
  } catch (error) {
    if (await claimed.exists()) await _restoreClaim(claimed, target.path);
    return '$error';
  } finally {
    await _deleteEmptyDirectory(wrapper);
  }
}

typedef _JunkCheck = Future<bool> Function(Directory folder);

/// Rechecks junk before and after claiming it so concurrent changes fail safe.
Future<BackupActionResult> _recycleCheckedFolder({
  required Directory target,
  required String library,
  required _JunkCheck check,
  BackupTrash? trashFolder,
}) async {
  final Directory wrapper = await Directory(
    library,
  ).createTemp(WallpaperFiles.emptyBackupStagePrefix);
  final Directory claimed = Directory(
    path.join(wrapper.path, path.basename(target.path)),
  );
  try {
    if (!await check(target)) {
      return (changed: false, error: tr(AppI10n.backupActionStateChanged));
    }
    publishWithoutReplacing(target, claimed.path);
    if (!await check(claimed)) {
      await _restoreClaim(claimed, target.path);
      return (changed: false, error: tr(AppI10n.backupActionStateChanged));
    }
    final BackupTrash trash =
        trashFolder ?? (String folder) => deleteToTrash(filePath: folder);
    final String? error = await trash(claimed.path);
    if (await claimed.exists()) {
      await _restoreClaim(claimed, target.path);
      return (
        changed: false,
        error: error ?? tr(AppI10n.backupActionTrashUnconfirmed),
      );
    }
    return (changed: true, error: error);
  } catch (error) {
    if (await claimed.exists()) await _restoreClaim(claimed, target.path);
    return (changed: false, error: '$error');
  } finally {
    await _deleteEmptyDirectory(wrapper);
  }
}

Future<bool> _isShaderCacheFolder(Directory folder) async =>
    path.basename(folder.path).toLowerCase() ==
        WallpaperDirectories.shaderCache.toLowerCase() &&
    await folder.exists();

/// Restores one vanished wallpaper into MyProjects through a staging folder.
///
/// Same-name cards share one restore target. Source choice prefers an unpacked
/// MyProjects backup, then Workshop, then any remaining MyProjects copy.
Future<BackupActionResult> restoreVanishedWallpaper({
  required List<BackupCard> cards,
  required String? backupRoot,
  required String? liveMyProjectsPath,
}) async {
  if (cards.isEmpty) return (changed: false, error: null);
  if (backupRoot == null || liveMyProjectsPath == null) {
    return (changed: false, error: tr(AppI10n.backupActionFolderUnavailable));
  }
  final String name = cards.first.name;
  final Directory destination = Directory(path.join(liveMyProjectsPath, name));
  final List<({BackupCard card, Directory folder})> sources = [];
  for (final BackupCard card in cards) {
    final String? root = switch (card.library) {
      WallpaperLibrary.workshop => backupWorkshopPath(backupRoot),
      WallpaperLibrary.myProjects => backupMyProjectsPath(backupRoot),
    };
    final Directory candidate = Directory(path.join(root!, card.name));
    if (await candidate.exists()) sources.add((card: card, folder: candidate));
  }
  final Directory? source = await _preferredRestoreSource(sources);
  if (source == null) {
    return (changed: false, error: tr(AppI10n.backupActionSourceMissing));
  }
  if (await destination.exists()) {
    return (changed: false, error: tr(AppI10n.backupActionTargetExists));
  }
  if (_inside(liveMyProjectsPath, source.path)) {
    return (changed: false, error: tr(AppI10n.backupActionUnsafeDestination));
  }
  final Directory stage = await Directory(
    liveMyProjectsPath,
  ).createTemp(WallpaperFiles.restoreStagePrefix);
  try {
    await _copyFolderIncrementally(source, stage);
    publishWithoutReplacing(stage, destination.path);
    return (changed: true, error: null);
  } catch (error) {
    return (changed: false, error: '$error');
  } finally {
    if (await stage.exists()) await stage.delete(recursive: true);
  }
}

/// Chooses the restore copy most likely to preserve editable project data.
Future<Directory?> _preferredRestoreSource(
  List<({BackupCard card, Directory folder})> sources,
) async {
  for (final source in sources) {
    if (source.card.library == WallpaperLibrary.myProjects &&
        await File(
          path.join(source.folder.path, WallpaperFiles.unpackedScene),
        ).exists() &&
        await File(
          path.join(source.folder.path, WallpaperFiles.project),
        ).exists()) {
      return source.folder;
    }
  }
  for (final source in sources) {
    if (source.card.library == WallpaperLibrary.workshop) return source.folder;
  }
  return sources.isEmpty ? null : sources.first.folder;
}

/// Copies selected meaningful files without touching destination-only files.
///
/// Cleanup is a separate phase so a failed copy cannot delete the old backup
/// first. Copied files keep source modification time for cheap reruns.
Future<bool> _copyFolderIncrementally(
  Directory source,
  Directory destination, {
  Set<String> skippedRelativePaths = const <String>{},
}) async {
  await destination.create(recursive: true);
  final Set<String> skipped = _normalisedPaths(skippedRelativePaths);
  bool changed = false;
  await for (final FileSystemEntity entity in source.list(
    recursive: true,
    followLinks: false,
  )) {
    final String relative = path.relative(entity.path, from: source.path);
    if (isRebuiltShaderPath(relative) || skipped.contains(_pathKey(relative))) {
      continue;
    }
    if (entity is Link) {
      throw FileSystemException(tr(AppI10n.backupActionLinkFound), entity.path);
    }
    if (entity is! File) continue;
    final File target = File(path.join(destination.path, relative));
    if (await _sameFile(entity, target)) continue;
    final DateTime modified = (await entity.stat()).modified;
    await copyFileReplacing(entity, target);
    await target.setLastModified(modified);
    changed = true;
  }
  return changed;
}

/// Removes meaningful destination files that no longer exist in live.
///
/// Copy and source verification happen before this cleanup phase, so a failed
/// copy cannot delete the previous backup first. Empty folders are removed
/// bottom-up without touching the wallpaper root.
Future<bool> _removeMirrorResidue({
  required Directory source,
  required Directory destination,
  Set<String> keptRelativePaths = const <String>{},
}) async {
  if (!await destination.exists()) return false;
  final Set<String> kept = _normalisedPaths(keptRelativePaths);
  final Set<String> liveFiles = <String>{};
  await for (final FileSystemEntity entity in source.list(
    recursive: true,
    followLinks: false,
  )) {
    final String relative = path.relative(entity.path, from: source.path);
    if (isRebuiltShaderPath(relative)) continue;
    if (entity is Link) {
      throw FileSystemException(tr(AppI10n.backupActionLinkFound), entity.path);
    }
    if (entity is File) liveFiles.add(_pathKey(relative));
  }

  final List<Directory> directories = <Directory>[];
  bool changed = false;
  await for (final FileSystemEntity entity in destination.list(
    recursive: true,
    followLinks: false,
  )) {
    final String relative = path.relative(entity.path, from: destination.path);
    if (entity is Directory) {
      directories.add(entity);
      continue;
    }
    if (isRebuiltShaderPath(relative)) continue;
    if (entity is Link) {
      throw FileSystemException(tr(AppI10n.backupActionLinkFound), entity.path);
    }
    if (entity is! File) continue;
    final String key = _pathKey(relative);
    if (liveFiles.contains(key) || kept.contains(key)) continue;
    await entity.delete();
    changed = true;
  }

  directories.sort(
    (Directory a, Directory b) => b.path.length.compareTo(a.path.length),
  );
  for (final Directory directory in directories) {
    try {
      if (await directory.list(followLinks: false).isEmpty) {
        await directory.delete();
        changed = true;
      }
    } on FileSystemException {
      // A non-empty or concurrently changed folder is left for the next scan.
    }
  }
  return changed;
}

Set<String> _normalisedPaths(Iterable<String> paths) => <String>{
  for (final String relative in paths) _pathKey(relative),
};

String _pathKey(String relative) =>
    relative.toLowerCase().replaceAll('/', r'\');

Future<bool> _sameFile(File source, File destination) async {
  if (!await destination.exists()) return false;
  final (FileStat sourceStat, FileStat destinationStat) = await (
    source.stat(),
    destination.stat(),
  ).wait;
  if (sourceStat.size != destinationStat.size ||
      sourceStat.modified != destinationStat.modified) {
    return false;
  }

  // Metadata is only a fast candidate check. Different payloads can share the
  // same size and mtime, so it cannot suppress a required Update copy.
  return await filesHaveSameContents(source, destination) ?? false;
}

/// Restores a claimed folder only while its original destination is still free.
Future<void> _restoreClaim(Directory claimed, String destination) async {
  if (await FileSystemEntity.type(destination, followLinks: false) ==
      FileSystemEntityType.notFound) {
    publishWithoutReplacing(claimed, destination);
  }
}

/// Best-effort staging cleanup; failure must not change the action result.
Future<void> _deleteEmptyDirectory(Directory directory) async {
  try {
    if (await directory.exists()) await directory.delete();
  } catch (_) {}
}

/// Case-insensitive containment check for Windows paths, including equality.
bool _inside(String candidate, String parent) {
  final String child = path.absolute(path.normalize(candidate)).toLowerCase();
  final String root = path.absolute(path.normalize(parent)).toLowerCase();
  return child == root || path.isWithin(root, child);
}
