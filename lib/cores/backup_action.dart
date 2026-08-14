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

enum BackupAction { backUp, update, restore, recycleJunk, showUpdateAgain }

typedef BackupActionResult = ({bool changed, String? error});
typedef BackupTrash = Future<String?> Function(String folder);

BackupAction? actionForBackupState(BackupState state) => switch (state) {
  BackupState.notBackedUp => BackupAction.backUp,
  BackupState.vanished => BackupAction.restore,
  BackupState.emptyBackup => BackupAction.recycleJunk,
  BackupState.updateAvailable => BackupAction.update,
  BackupState.updateDismissed => BackupAction.showUpdateAgain,
  BackupState.synced => null,
};

Future<BackupActionResult> backUpWallpaper({
  required BackupCard card,
  required String? backupRoot,
  required String? liveWorkshopPath,
  required String? liveMyProjectsPath,
  required String? acfPath,
}) async {
  final String? liveRoot = switch (card.library) {
    WallpaperLibrary.workshop => liveWorkshopPath,
    WallpaperLibrary.myProjects => liveMyProjectsPath,
  };
  final String? backupLibrary = switch (card.library) {
    WallpaperLibrary.workshop => backupWorkshopPath(backupRoot),
    WallpaperLibrary.myProjects => backupMyProjectsPath(backupRoot),
  };
  if (backupRoot == null || liveRoot == null || backupLibrary == null) {
    return (changed: false, error: tr(AppI10n.backupActionFolderUnavailable));
  }
  final Directory source = Directory(path.join(liveRoot, card.name));
  final Directory destination = Directory(path.join(backupLibrary, card.name));
  try {
    if (!await source.exists()) {
      return (changed: false, error: tr(AppI10n.backupActionSourceMissing));
    }
    if (_inside(destination.path, source.path)) {
      return (changed: false, error: tr(AppI10n.backupActionUnsafeDestination));
    }
    final String? before = await liveBackupVersion(
      card,
      liveFolder: source.path,
      acfPath: acfPath,
    );
    await _copyFolderIncrementally(source, destination);
    final String? version = await liveBackupVersion(
      card,
      liveFolder: source.path,
      acfPath: acfPath,
    );
    if (before != version) {
      return (changed: true, error: tr(AppI10n.backupActionSourceChanged));
    }
    final Map<String, BackupRecord> records = await readBackupRecords(
      backupRoot,
    );
    final BackupRecord previous = records[card.id] ?? const BackupRecord();
    records[card.id] = BackupRecord(
      backedUpVersion: version ?? previous.backedUpVersion,
    );
    await writeBackupRecords(backupRoot, records);
    return (changed: true, error: null);
  } catch (error) {
    return (changed: false, error: '$error');
  }
}

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

typedef _JunkCheck = Future<bool> Function(Directory folder);

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

Future<void> _copyFolderIncrementally(
  Directory source,
  Directory destination,
) async {
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
  }
}

Future<bool> _sameFile(File source, File destination) async {
  if (!await destination.exists()) return false;
  final (FileStat sourceStat, FileStat destinationStat) = await (
    source.stat(),
    destination.stat(),
  ).wait;
  return sourceStat.size == destinationStat.size &&
      sourceStat.modified == destinationStat.modified;
}

Future<void> _restoreClaim(Directory claimed, String destination) async {
  if (await FileSystemEntity.type(destination, followLinks: false) ==
      FileSystemEntityType.notFound) {
    publishWithoutReplacing(claimed, destination);
  }
}

Future<void> _deleteEmptyDirectory(Directory directory) async {
  try {
    if (await directory.exists()) await directory.delete();
  } catch (_) {}
}

bool _inside(String candidate, String parent) {
  final String child = path.absolute(path.normalize(candidate)).toLowerCase();
  final String root = path.absolute(path.normalize(parent)).toLowerCase();
  return child == root || path.isWithin(root, child);
}
