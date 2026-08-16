import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:we_repkg/constants/wallpaper_files.dart';
import 'package:we_repkg/utils/backup_diff.dart';

/// Why a wallpaper folder is disposable. Kept explicit so the backup tab can
/// group maintenance work instead of presenting one undifferentiated junk grid.
enum WallpaperJunkKind { empty, shaderCacheOnly, mixed }

Future<WallpaperJunkKind?> classifyLiveWallpaperJunk(Directory folder) async {
  if (!await isLiveWallpaperJunk(folder)) return null;
  return await isEmptyFolderTree(folder)
      ? WallpaperJunkKind.empty
      : WallpaperJunkKind.shaderCacheOnly;
}

Future<WallpaperJunkKind?> classifyBackupWallpaperJunk(Directory folder) async {
  if (!await isBackupWallpaperJunk(folder)) return null;
  return await isEmptyFolderTree(folder)
      ? WallpaperJunkKind.empty
      : WallpaperJunkKind.shaderCacheOnly;
}

/// An empty live folder, or one holding only generated `.dxs` shader files.
Future<bool> isLiveWallpaperJunk(Directory folder) =>
    _containsOnlyFiles(folder, _isDxs);

/// An empty backup, or one containing only disposable shader data.
Future<bool> isBackupWallpaperJunk(Directory folder) => _containsOnlyFiles(
  folder,
  (String relative) => _isDxs(relative) || isRebuiltShaderPath(relative),
);

bool _isDxs(String relative) =>
    path.extension(relative).toLowerCase() ==
    WallpaperFiles.shaderCacheExtension;

/// True when a folder tree contains directories only.
Future<bool> isEmptyFolderTree(Directory folder) =>
    _containsOnlyFiles(folder, (_) => false);

/// Breadth-first so a normal top-level project file rejects a folder before
/// an older, large shader directory is walked.
Future<bool> _containsOnlyFiles(
  Directory folder,
  bool Function(String relativePath) allowed,
) async {
  if (!await folder.exists()) return false;
  try {
    final List<Directory> pending = <Directory>[folder];
    for (int i = 0; i < pending.length; i++) {
      await for (final FileSystemEntity entity in pending[i].list(
        followLinks: false,
      )) {
        if (entity is Link) return false;
        if (entity is Directory) {
          pending.add(entity);
        } else if (entity is File &&
            !allowed(path.relative(entity.path, from: folder.path))) {
          return false;
        }
      }
    }
    return true;
  } on FileSystemException {
    return false;
  }
}

Directory backupShaderCache(Directory wallpaper) => Directory(
  path.join(
    wallpaper.path,
    WallpaperDirectories.shaders,
    WallpaperDirectories.shaderCache,
  ),
);

Future<bool> hasBackupShaderCache(Directory wallpaper) =>
    backupShaderCache(wallpaper).exists();
