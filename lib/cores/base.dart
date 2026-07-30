import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:url_launcher/url_launcher.dart';
import 'package:we_repkg/constants/i10n.dart';
import 'package:we_repkg/constants/keys.dart';
import 'package:we_repkg/models/wallpaper.dart';
import 'package:we_repkg/provider/navigation.dart';
import 'package:we_repkg/provider/setting.dart';
import 'package:we_repkg/provider/system.dart';
import 'package:we_repkg/provider/wallpaper.dart';
import 'package:we_repkg/src/rust/api/simple.dart';
import 'package:we_repkg/utils/info.dart';
import 'package:we_repkg/utils/storage.dart';
import 'package:we_repkg/widgets/confirm_dialog.dart';

import 'toast.dart';
import 'wallpaper.dart';

Future<bool> setExportPath(WidgetRef ref, [bool show = false]) async {
  if (show) showSelectFolderToast(tr(AppI10n.extractFolderToast));
  final String? exportPath = await getDirectoryPath();
  if (exportPath != null) {
    ref.read(exportPathProvider.notifier).update(exportPath);
    return true;
  }
  return false;
}

Future<void> setToolPath(WidgetRef ref) async {
  final xType = XTypeGroup(label: 'RePKG', extensions: ['exe']);
  final XFile? file = await openFile(acceptedTypeGroups: [xType]);
  if (file != null) {
    ref.read(toolPathProvider.notifier).update(file.path);
    final String? version = await ref.read(toolVersionProvider.future);
    if (version != null) {
      debugPrint('${tr(AppI10n.logVersion)} $version');
    }
  }
}

Future<void> refreshToolPath(WidgetRef ref) async {
  await StorageUtil.remove(AppKeys.toolPath);
  ref.read(toolPathProvider.notifier).update(getToolPath());
}

Future<bool> setProjectPath(WidgetRef ref, [bool show = false]) async {
  if (show) showSelectFolderToast(tr(AppI10n.projectFolderToast));
  String? projectPath = await getDirectoryPath();
  if (projectPath != null) {
    ref.read(projectPathProvider.notifier).update(projectPath);
    return true;
  }
  return false;
}

void refreshProjectPath(WidgetRef ref) {
  String? wallpaperPath = StorageUtil.getString(AppKeys.wallpaperPath);
  if (wallpaperPath != null) {
    String projectPath = projectDefaultPath(wallpaperPath);
    ref.read(projectPathProvider.notifier).update(projectPath);
  }
}

Future<void> setWallpaperPath(WidgetRef ref) async {
  final String? previousPath = ref.read(wallpaperPathProvider);
  final String? wallpaperPath = await getDirectoryPath();
  if (wallpaperPath != null) {
    if (wallpaperPath != previousPath) {
      ref.read(currentSectionProvider.notifier).requestExtractEntrance();
    }
    ref.read(selectedWallpaperProvider.notifier).update(null);
    ref.read(wallpaperPathProvider.notifier).update(wallpaperPath);
    updateOtherFolder(ref, wallpaperPath);
    await refreshWallpaper(ref);
  }
}

Future<void> refreshWallpaperPath(WidgetRef ref) async {
  // String? before = StorageUtil.getString(AppKeys.wallpaperPathBefore);
  // await StorageUtil.remove(AppKeys.acfPath);
  final String? previousPath = ref.read(wallpaperPathProvider);
  String? wallpaperPath = await getWallpaperPath();
  if (wallpaperPath != null) {
    if (wallpaperPath != previousPath) {
      ref.read(currentSectionProvider.notifier).requestExtractEntrance();
    }
    ref.read(wallpaperPathProvider.notifier).update(wallpaperPath);
    updateOtherFolder(ref, wallpaperPath);
  }
  await refreshWallpaper(ref);
}

void updateOtherFolder(WidgetRef ref, String wallpaperPath) {
  String? projectPath = StorageUtil.getString(AppKeys.projectPath);
  String? acfPath = StorageUtil.getString(AppKeys.acfPath);
  if (ref.read(updateProjectPathProvider) || projectPath == null) {
    ref
        .read(projectPathProvider.notifier)
        .update(projectDefaultPath(wallpaperPath));
  }
  if (ref.read(updateAcfPathProvider) || acfPath == null) {
    if (acfPath != null) {
      StorageUtil.remove(AppKeys.acfPath);
    }
    ref.read(acfPathProvider.notifier).update(getAcfPath(wallpaperPath));
  }
}

Future<void> setAcfPath(WidgetRef ref) async {
  final xType = XTypeGroup(
    label: 'appworkshop_431960.acf',
    extensions: ['acf'],
  );
  final XFile? file = await openFile(acceptedTypeGroups: [xType]);
  if (file != null) {
    ref.read(acfPathProvider.notifier).update(file.path);
    await refreshWallpaperPath(ref);
  }
}

Future<void> refreshAcfPath(WidgetRef ref) async {
  await StorageUtil.remove(AppKeys.acfPath);
  ref.read(acfPathProvider.notifier).update(getAcfPath());
  await refreshWallpaperPath(ref);
}

Future<void> playVideo(WallpaperInfo wallpaper) async {
  String videoPath = wallpaper.target;
  if (!File(videoPath).existsSync()) {
    return showErrorToast(tr(AppI10n.dialogFileNoExist));
  }
  final Uri fileUri = Uri.file(videoPath);
  if (await canLaunchUrl(fileUri)) {
    await launchUrl(fileUri);
  } else {
    showErrorToast(tr(AppI10n.dialogPlayVideoFailed));
  }
}

Future<bool> checkExportPath(WidgetRef ref, [bool show = false]) async {
  String? exportPath = ref.read(exportPathProvider);
  if (exportPath == null) return await setExportPath(ref, show);
  return true;
}

Future<bool> checkProjectPath(WidgetRef ref, [bool show = false]) async {
  String? projectPath = ref.read(projectPathProvider);
  if (projectPath == null) return await setProjectPath(ref, show);
  return true;
}

/// Ids of the wallpapers whose folder is no longer on disk.
///
/// `trash::delete_all` can fail partway through a batch, leaving some folders
/// deleted and others intact, and its error value says nothing about which is
/// which. Asking the filesystem is the only way to know what to drop from the
/// list. Probes run concurrently; [probe] is injectable for tests.
Future<Set<String>> findDeletedWallpapers(
  List<WallpaperInfo> wallpapers, {
  DirectoryProbe probe = directoryExists,
}) async {
  if (wallpapers.isEmpty) return <String>{};
  final survives = await Future.wait(wallpapers.map((w) => probe(w.folder)));
  return <String>{
    for (int i = 0; i < wallpapers.length; i++)
      if (!survives[i]) wallpapers[i].id,
  };
}

Future<String?> deleteChecked(WidgetRef ref) async {
  String? err;
  List<WallpaperInfo> wallpapers = ref.read(checkedWallpaperListProvider);
  if (wallpapers.isEmpty) return null;
  // Confirm first: the delete button sits beside the extract buttons and the
  // selection can be large.
  final bool confirmed = await showConfirmDialog(
    title: tr(AppI10n.dialogDeleteConfirmTitle),
    message: wallpapers.length == 1
        ? tr(
            AppI10n.dialogDeleteConfirmOne,
            namedArgs: {'title': wallpapers.first.title},
          )
        : tr(
            AppI10n.dialogDeleteConfirmMany,
            namedArgs: {'count': '${wallpapers.length}'},
          ),
  );
  if (!confirmed) return null;
  List<String> paths = wallpapers.map((e) => e.folder).toList();
  try {
    final String? trashErr = await deleteAllToTrash(filePaths: paths);
    if (trashErr != null) {
      err = '${tr(AppI10n.dialogDeleteFailed)} $trashErr';
    }
    // Remove exactly what actually went away. The previous version dropped
    // every selected wallpaper regardless of the result, so a failed delete
    // showed a success toast and hid folders that were still on disk.
    final Set<String> gone = await findDeletedWallpapers(wallpapers);
    if (gone.isNotEmpty) {
      WallpaperInfo? selectedWallpaper = ref.read(selectedWallpaperProvider);
      if (selectedWallpaper != null && gone.contains(selectedWallpaper.id)) {
        ref.read(selectedWallpaperProvider.notifier).update(null);
      }
      ref.read(wallpaperListProvider.notifier).removeAll(gone);
    }
  } catch (e) {
    debugPrint('${tr(AppI10n.logDeleteCheckedFailed)} $e');
    err = '${tr(AppI10n.dialogDeleteFailed)} $e';
  }
  // The only caller discards this return value, so report the outcome here.
  if (err == null) {
    showDeleteToast();
  } else {
    showErrorToast(err);
  }
  return err;
}

Future<void> browserCurrent(WallpaperInfo wallpaper) async {
  String folder = wallpaper.folder;
  if (!Directory(folder).existsSync()) {
    return showErrorToast(tr(AppI10n.dialogFileNoExist));
  }
  final fixedPath = 'file:///${folder.replaceAll('\\', '/')}';
  final uri = Uri.parse(fixedPath);
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri);
  } else {
    showErrorToast(tr(AppI10n.dialogOpenFolderFailed));
  }
}

Future<void> deleteCurrent(WidgetRef ref, WallpaperInfo wallpaper) async {
  final bool confirmed = await showConfirmDialog(
    title: tr(AppI10n.dialogDeleteConfirmTitle),
    message: tr(
      AppI10n.dialogDeleteConfirmOne,
      namedArgs: {'title': wallpaper.title},
    ),
  );
  if (!confirmed) return;
  try {
    // deleteToTrash reports failure through its return value, not by throwing.
    // Awaiting it and discarding the result dropped the row from the list while
    // the folder was still on disk.
    final String? trashErr = await deleteToTrash(filePath: wallpaper.folder);
    if (trashErr != null) {
      debugPrint('${tr(AppI10n.logDeleteFileFailed)} $trashErr');
      return showErrorToast('${tr(AppI10n.dialogDeleteFailed)} $trashErr');
    }
    ref.read(wallpaperListProvider.notifier).remove(wallpaper);
    ref.read(selectedWallpaperProvider.notifier).update(null);
    showDeleteToast();
  } catch (e) {
    debugPrint('${tr(AppI10n.logDeleteFileFailed)} $e');
    showErrorToast('${tr(AppI10n.dialogDeleteFailed)} $e');
  }
}

Future<String?> deleteUselessFiles(
  WidgetRef ref,
  String outPath,
  List<FileSystemEntity> oldFiles,
) async {
  bool onlySaveImage = ref.read(onlySaveImageProvider);
  bool excludeTexture = ref.read(excludeTextureProvider);
  bool deleteTransparency = ref.read(deleteTransparencyProvider);
  String? err;
  if (onlySaveImage && !excludeTexture) {
    err = await deleteOther(outPath, oldFiles);
  } else if (excludeTexture) {
    err = await deleteOtherAndTexture(outPath);
  }
  // 如果启用了删除透明PNG功能，执行透明PNG删除
  if (deleteTransparency && err == null) {
    Directory folder = Directory(outPath);
    List<FileSystemEntity> files = await folder.list().toList();
    List<String> filePaths = files
        .whereType<File>()
        .map((file) => file.path)
        .toList();
    List<String> oldFilePaths = oldFiles.map((file) => file.path).toList();
    err = await deleteTransparentPngs(filePaths, excludeFiles: oldFilePaths);
  }
  return err;
}

Future<String?> deleteOther(
  String outPath,
  List<FileSystemEntity> oldFiles,
) async {
  List<String> allFile = oldFiles.map((e) => e.path).toList();
  try {
    Directory folder = Directory(outPath);
    List<FileSystemEntity> files = await folder.list().toList();
    final List<String?> results = await Future.wait(
      files
          .where((file) {
            if (file is File) {
              String ext = file.path.split('.').last.toLowerCase();
              return !isImage(ext) && !allFile.contains(file.path);
            }
            return false;
          })
          .map((file) async {
            try {
              debugPrint('${tr(AppI10n.logDeletingFile)} ${file.path}');
              await file.delete();
            } catch (e) {
              debugPrint('${tr(AppI10n.logDeleteFileFailed)} ${file.path}: $e');
              return '${file.path} ${tr(AppI10n.dialogDeleteFailed)} $e';
            }
            return null;
          }),
    );
    // 每个文件的失败都要上报: 调用方在返回null时会显示成功提示
    final List<String> failed = results.whereType<String>().toList();
    if (failed.isEmpty) return null;
    final String named = failed.take(5).join('\n');
    return failed.length > 5 ? '$named\n(+${failed.length - 5})' : named;
  } catch (e) {
    String errorMsg = '${tr(AppI10n.dialogDeleteFailed)} $e';
    debugPrint(errorMsg);
    return errorMsg; // 返回错误信息
  }
}

Future<String?> deleteOtherAndTexture(String outPath) async {
  if (await Directory('$outPath/materials').exists()) {
    final files = await Directory('$outPath/materials').list().toList();
    for (var file in files) {
      if (file is File &&
          (isImage(file.path) || file.path.toLowerCase().endsWith('mp4'))) {
        try {
          await file.rename('$outPath/${path.basename(file.path)}');
        } catch (e) {
          debugPrint('${tr(AppI10n.logMoveFileFailed)} $e');
          return e.toString();
        }
      }
    }
  }

  List<String> deleteList = [
    'effects',
    'fonts',
    'materials',
    'models',
    'particles',
    'shaders',
    'sounds',
    'scripts',
  ];

  List<Future<void>> folderDeletionFutures = [];
  for (String folder in deleteList) {
    String tempPath = path.join(outPath, folder);
    if (await Directory(tempPath).exists()) {
      folderDeletionFutures.add(
        Directory(tempPath).delete(recursive: true).catchError((e) {
          debugPrint('${tr(AppI10n.logDeleteFolderFailed)} $e');
          throw '$tempPath ${tr(AppI10n.dialogDeleteFailed)} $e';
        }),
      );
    }
  }
  // Guarded like the folders above: wallpaper mode extracts tex entries only,
  // so scene.json is usually never written in the first place.
  final File sceneJson = File(path.join(outPath, 'scene.json'));
  if (await sceneJson.exists()) {
    folderDeletionFutures.add(
      sceneJson.delete().catchError((e) {
        debugPrint('${tr(AppI10n.logDeleteSceneJsonFailed)} $e');
        throw 'scene.json ${tr(AppI10n.dialogDeleteFailed)} $e';
      }),
    );
  }
  try {
    await Future.wait(folderDeletionFutures);
  } catch (e) {
    return e.toString();
  }
  return null;
}

Future<String?> deleteTransparentPngs(
  List<String> files, {
  List<String> excludeFiles = const [],
}) async {
  // 使用Set提高排除文件查找性能
  Set<String> excludeSet = excludeFiles.toSet();
  List<String> pngs = files
      .where(
        (file) =>
            file.toLowerCase().endsWith('.png') && !excludeSet.contains(file),
      )
      .toList();
  if (pngs.isEmpty) return null;
  // 调用Rust函数进行批量透明度检测和删除
  List<String> errors = await deleteTransparentPngsRust(filePaths: pngs);
  // 如果有错误信息，返回第一个错误
  if (errors.isNotEmpty) {
    return errors.first;
  }
  return null;
}
