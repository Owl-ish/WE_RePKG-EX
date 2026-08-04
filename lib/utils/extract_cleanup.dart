import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:we_repkg/constants/i10n.dart';
import 'package:we_repkg/models/extract_settings.dart';
import 'package:we_repkg/src/rust/api/simple.dart';
import 'package:we_repkg/utils/info.dart';
import 'package:we_repkg/utils/tool.dart';

Future<String?> deleteUselessFiles(
  ExtractSettings settings,
  String outPath,
) async {
  final bool onlySaveImage = settings.onlySaveImage;
  final bool excludeTexture = settings.excludeTexture;
  final bool deleteTransparency = settings.deleteTransparency;
  String? err;
  if (onlySaveImage && !excludeTexture) {
    err = await deleteOther(outPath);
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
    err = await deleteTransparentPngs(filePaths);
  }
  return err;
}

Future<String?> deleteOther(String outPath) async {
  try {
    Directory folder = Directory(outPath);
    List<FileSystemEntity> files = await folder.list().toList();
    final List<String?> results = await Future.wait(
      files.where((file) => file is File && !isImage(file.path)).map((
        file,
      ) async {
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
          // Claimed, not renamed straight up: a scene can hold both
          // materials/foo.png and a root foo.png, and rename replaces whatever
          // is already at the destination.
          final String dest = await claimFilePath(
            path.join(outPath, path.basename(file.path)),
          );
          await file.rename(dest);
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

Future<String?> deleteTransparentPngs(List<String> files) async {
  List<String> pngs = files
      .where((file) => file.toLowerCase().endsWith('.png'))
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
