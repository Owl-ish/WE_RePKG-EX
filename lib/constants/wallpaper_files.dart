/// File names shared by Wallpaper Engine and every feature that reads or
/// writes one of its wallpaper folders.
abstract final class WallpaperFiles {
  static const String project = 'project.json';
  static const String packedScene = 'scene.pkg';
  static const String unpackedScene = 'scene.json';
  static const String webEntry = 'index.html';
  static const String previewStem = 'preview';
  static const String shaderCacheExtension = '.dxs';

  /// Travels with a published rescue until its source reaches the Recycle Bin,
  /// allowing an interrupted repair to resume instead of creating a duplicate.
  static const String rescueMarker = '.werepkg-ex-rescue-source';
  static const String rescueStagePrefix = '.werepkg-ex-rescue-';
  static const String projectStagePrefix = '.werepkg-ex-project-';
  static const String restoreStagePrefix = '.werepkg-ex-restore-';
  static const String emptyBackupStagePrefix = '.werepkg-ex-empty-';

  static bool isLibraryRepairStage(String name) =>
      name.startsWith(rescueStagePrefix) ||
      name.startsWith(restoreStagePrefix) ||
      name.startsWith(emptyBackupStagePrefix);
}

/// Directory names in Wallpaper Engine's on-disk wallpaper format.
abstract final class WallpaperDirectories {
  static const String container = 'directories';
  static const String custom = 'customdirectory';
  static const String shaders = 'shaders';
  static const String shaderCache = 'blobsSM40';
}

/// Keys in Wallpaper Engine's project metadata.
abstract final class WallpaperProjectFields {
  static const String title = 'title';
  static const String type = 'type';
  static const String file = 'file';
  static const String preview = 'preview';
  static const String contentRating = 'contentrating';
  static const String tags = 'tags';
}
