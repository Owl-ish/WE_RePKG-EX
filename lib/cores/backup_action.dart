import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
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
/// [mirror] is explicit so ordinary Back up remains non-destructive while
/// Update can remove files that no longer exist in live. Cleanup happens only
/// after copies finish and the source is still stable.
Future<BackupActionResult> backUpWallpaper({
  required BackupCard card,
  required String? backupRoot,
  required String? liveWorkshopPath,
  required String? liveMyProjectsPath,
  required String? acfPath,
  bool mirror = false,
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
    final String? before = await liveBackupVersion(
      card,
      liveFolder: source.path,
      acfPath: acfPath,
    );
    // A thrown copy can still have published files, so failures after this
    // point refresh instead of claiming the filesystem stayed unchanged.
    filesystemMayHaveChanged = true;
    changed = await _copyFolderIncrementally(source, destination);
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
    records[card.id] = BackupRecord(
      backedUpVersion: version ?? previous.backedUpVersion,
    );

    // The matching copy and stable source are established before any
    // opposite-library backup is recycled.
    String? syncError;
    if (otherBackupExisted) {
      syncError = await _recycleSyncedBackup(
        target: otherBackup,
        trashFolder: trashFolder,
      );
      if (syncError == null) {
        final WallpaperLibrary otherLibrary = switch (card.library) {
          WallpaperLibrary.workshop => WallpaperLibrary.myProjects,
          WallpaperLibrary.myProjects => WallpaperLibrary.workshop,
        };
        records.remove(BackupCard(otherLibrary, card.name).id);
      }
    }
    await writeBackupRecords(backupRoot, records);
    return (changed: true, error: syncError);
  } catch (error) {
    return (changed: changed || filesystemMayHaveChanged, error: '$error');
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
    records[card.id] = BackupRecord(backedUpVersion: previous.backedUpVersion);
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

/// Copies meaningful files without deleting residue already in the destination.
///
/// Rebuilt shaders are skipped, links are rejected, and unchanged files are
/// left in place. Copied files keep the source modification time so reruns can
/// skip them safely.
Future<bool> _copyFolderIncrementally(
  Directory source,
  Directory destination,
) async {
  bool changed = !await destination.exists();
  await destination.create(recursive: true);
  await for (final FileSystemEntity entity in source.list(
    recursive: true,
    followLinks: false,
  )) {
    final String relative = path.relative(entity.path, from: source.path);
    if (isRebuiltShaderPath(relative)) continue;
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
}) async {
  if (!await destination.exists()) return false;
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
    if (entity is! File || liveFiles.contains(_pathKey(relative))) continue;
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
