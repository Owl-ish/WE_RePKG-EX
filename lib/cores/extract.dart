import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:we_repkg/constants/i10n.dart';
import 'package:we_repkg/models/enums.dart';
import 'package:we_repkg/models/error.dart';
import 'package:we_repkg/models/wallpaper.dart';
import 'package:we_repkg/provider/setting.dart';
import 'package:we_repkg/provider/system.dart';
import 'package:we_repkg/provider/wallpaper.dart';
import 'package:we_repkg/utils/info.dart';
import 'package:we_repkg/utils/tool.dart';

import 'base.dart';
import 'toast.dart';

Future<void> extractProject(
  WidgetRef ref,
  List<WallpaperInfo> wallpapers,
) async {
  bool useProjectPath = ref.watch(useProjectPathProvider);
  ExtractType extractType = ref.watch(currentExtractTypeProvider);
  if (useProjectPath || extractType.isProject) {
    if (!await checkProjectPath(ref, true)) return;
  } else {
    if (!await checkExportPath(ref, true)) return;
  }
  // Only scenes (.pkg) need RePKG; skip the check for a batch without any.
  final needsRePKG = wallpapers.any(
    (w) => w.target.toLowerCase().endsWith('pkg'),
  );
  String? rePKGPath = ref.watch(toolPathProvider);
  if (needsRePKG && !await toolExist(rePKGPath)) {
    return showToolNoExistToast();
  }
  List<ErrorInfo> errList = [];
  List<String> skipList = [];
  String outPath = useProjectPath || extractType.isProject
      ? ref.watch(projectPathProvider)!
      : ref.watch(exportPathProvider)!;
  if (!await Directory(outPath).exists()) {
    return projectNoExistToast(outPath);
  }
  changeLoadingText(ref, tr(AppI10n.dialogProcessingWallpaper));
  final cancel = showLoadingView(wallpapers);
  int index = 0;
  final basePath = outPath;
  for (WallpaperInfo wallpaper in wallpapers) {
    ref.read(currentIndexProvider.notifier).update(index);
    if (ref.watch(useTitleNameProvider)) {
      outPath = path.join(basePath, renameFolder(wallpaper.title));
    } else {
      outPath = path.join(basePath, wallpaper.id);
    }
    try {
      await Directory(outPath).create();
    } catch (e) {
      debugPrint('${tr(AppI10n.errorCreatedFolderFailed)} $e');
      errList.add(
        ErrorInfo(
          wallpaper: wallpaper,
          message: '${tr(AppI10n.errorCreatedFolderFailed)} $e',
        ),
      );
      index++;
      continue;
    }
    // Non-scene wallpaper: copy the whole folder (re-importable) instead of RePKG.
    if (!wallpaper.target.toLowerCase().endsWith('pkg')) {
      String? err = await copyWallpaperFolder(ref, wallpaper, outPath);
      if (err != null) {
        errList.add(ErrorInfo(wallpaper: wallpaper, message: err));
      }
      index++;
      continue;
    }
    try {
      String? overwrite = ref.watch(replaceFileProvider) ? '--overwrite' : null;
      final args = [
        'extract',
        '-c',
        ?overwrite,
        '-o',
        outPath,
        wallpaper.target,
      ].cast<String>().toList();
      String fullCommand = '$rePKGPath ${args.join(' ')}';
      debugPrint('${tr(AppI10n.logRunCommand)} $fullCommand');
      // Invoke the exe directly (no shell): Dart quotes args correctly, which is
      // more robust for tool/output paths containing spaces.
      ProcessResult result = await Process.run(rePKGPath!, args);
      int exitCode = result.exitCode;
      String stdout = result.stdout;
      String stderr = result.stderr;
      debugPrint('${tr(AppI10n.logStdout)} $stdout');
      debugPrint('${tr(AppI10n.logStderr)} $stderr');
      if (exitCode != 0) {
        errList.add(
          ErrorInfo(
            wallpaper: wallpaper,
            message: '${tr(AppI10n.errorExtractFailed)} $stderr',
          ),
        );
      }
    } catch (e) {
      debugPrint('${tr(AppI10n.errorExtractFailed)} $e');
      errList.add(
        ErrorInfo(
          wallpaper: wallpaper,
          message: '${tr(AppI10n.errorExtractFailed)} $e',
        ),
      );
    }
    index++;
  }
  cancel.call();
  errList.isNotEmpty ? showErrorView(errList) : showProjectToast(skipList);
}

Future<void> exportCurrentProject(
  WidgetRef ref,
  WallpaperInfo wallpaper,
) async {
  await extractProject(ref, [wallpaper]);
}

// 新增的通用提取方法
Future<void> extractWallpapers(
  WidgetRef ref,
  List<WallpaperInfo> wallpapers,
) async {
  if (!await checkExportPath(ref, true)) return;
  // Only scenes (.pkg) need RePKG; skip the check for a batch without any.
  final needsRePKG = wallpapers.any(
    (w) => w.target.toLowerCase().endsWith('pkg'),
  );
  String? rePKGPath = ref.watch(toolPathProvider);
  if (needsRePKG && !await toolExist(rePKGPath)) {
    return showToolNoExistToast();
  }
  List<ErrorInfo> errList = [];
  String outPath = ref.watch(exportPathProvider)!;
  Directory outDir = Directory(outPath);
  if (!await outDir.exists()) await outDir.create();
  List<FileSystemEntity> oldFiles = await outDir.list().toList();
  int index = 0;
  changeLoadingText(ref, tr(AppI10n.dialogProcessingWallpaper));
  final cancel = showLoadingView(wallpapers);
  bool needClear = false;
  for (WallpaperInfo wallpaper in wallpapers) {
    ref.read(currentIndexProvider.notifier).update(index);
    (String?, bool) res = await extractBranch(ref, wallpaper, outPath);
    String? err = res.$1;
    needClear = res.$2;
    if (err != null) errList.add(ErrorInfo(wallpaper: wallpaper, message: err));
    index++;
  }

  if (needClear) {
    changeLoadingText(ref, tr(AppI10n.dialogProcessingDelete));
    String? err2 = await deleteUselessFiles(ref, outPath, oldFiles);
    if (err2 != null) errList.add(ErrorInfo(wallpaper: null, message: err2));
  }
  cancel.call();
  errList.isNotEmpty ? showErrorView(errList) : showExtractSuccessToast();
}

Future<void> extractCurrent(WidgetRef ref, WallpaperInfo wallpaper) async {
  await extractWallpapers(ref, [wallpaper]);
}

Future<void> extractChecked(WidgetRef ref) async {
  List<WallpaperInfo> wallpapers = ref.watch(checkedWallpaperListProvider);
  ExtractType extractType = ref.watch(currentExtractTypeProvider);
  if (extractType.isWallpaper) {
    await extractWallpapers(ref, wallpapers);
  } else {
    await extractProject(ref, wallpapers);
  }
}

Future<void> extractAll(WidgetRef ref) async {
  List<WallpaperInfo> wallpapers = ref.watch(filterWallpaperListProvider);
  ExtractType extractType = ref.watch(currentExtractTypeProvider);
  if (extractType.isWallpaper) {
    await extractWallpapers(ref, wallpapers);
  } else {
    await extractProject(ref, wallpapers);
  }
}

Future<(String?, bool)> extractBranch(
  WidgetRef ref,
  WallpaperInfo wallpaper,
  String outPath,
) async {
  final target = wallpaper.target;
  // Match the file type case-insensitively (e.g. ".MP4" should still count).
  final targetLower = target.toLowerCase();
  if (targetLower.endsWith('pkg')) {
    return (await extractPKG(ref, target, outPath), true);
  } else if (targetLower.endsWith('.mp4')) {
    return (await extractVideo(ref, wallpaper, outPath), false);
  } else if (targetLower.endsWith('customdirectory')) {
    return (await extractImages(ref, target, outPath), false);
  }
  // web / application / any other type RePKG does not handle: copy the whole
  // folder into a per-wallpaper subfolder so it stays re-importable.
  final name = ref.watch(useTitleNameProvider)
      ? renameFolder(wallpaper.title)
      : wallpaper.id;
  final err = await copyWallpaperFolder(
    ref,
    wallpaper,
    path.join(outPath, name),
  );
  return (err, false);
}

/// Copies the entire wallpaper folder into [destDir] (every file, so the output
/// stays a valid, re-importable Wallpaper Engine wallpaper). Used for web,
/// application, and any type RePKG does not unpack.
Future<String?> copyWallpaperFolder(
  WidgetRef ref,
  WallpaperInfo wallpaper,
  String destDir,
) async {
  final bool overwrite = ref.watch(replaceFileProvider);
  changeLoadingText(ref, tr(AppI10n.dialogProcessingWallpaper));
  try {
    final src = Directory(wallpaper.folder);
    await Directory(destDir).create(recursive: true);
    await for (final entity in src.list(recursive: true, followLinks: false)) {
      final dest = path.join(
        destDir,
        path.relative(entity.path, from: src.path),
      );
      if (entity is Directory) {
        await Directory(dest).create(recursive: true);
      } else if (entity is File) {
        // Respect the "replace existing" toggle: skip files already present.
        if (!overwrite && await File(dest).exists()) continue;
        await Directory(path.dirname(dest)).create(recursive: true);
        await entity.copy(dest);
      }
    }
  } catch (e) {
    debugPrint('${tr(AppI10n.errorExtractFailed)} $e');
    return '${tr(AppI10n.errorExtractFailed)} $e';
  }
  return null;
}

Future<String?> extractPKG(WidgetRef ref, String file, String outPath) async {
  changeLoadingText(ref, tr(AppI10n.dialogProcessingWallpaper));
  String rePKGPath = ref.watch(toolPathProvider)!;
  bool excludeTexture = ref.watch(excludeTextureProvider);
  try {
    String? overwrite = ref.watch(replaceFileProvider) ? '--overwrite' : null;
    List<String> args = [
      'extract',
      '-e',
      'tex',
      '-s',
      ?overwrite,
      '-o',
      outPath,
      file,
    ].cast<String>().toList();
    // 提取项目，移动materials一级目录的文件到外面
    if (excludeTexture) args = ['extract', '-o', outPath, file];
    String fullCommand = '$rePKGPath ${args.join(' ')}';
    debugPrint('${tr(AppI10n.logRunCommand)} $fullCommand');
    // Invoke the exe directly (no shell) for space-safe argument handling.
    ProcessResult result = await Process.run(rePKGPath, args);
    int exitCode = result.exitCode; // 退出码
    String stdout = result.stdout; // 标准输出
    String stderr = result.stderr;
    debugPrint('${tr(AppI10n.logExitCode)} $exitCode');
    debugPrint('${tr(AppI10n.logStdout)} $stdout');
    debugPrint('${tr(AppI10n.logStderr)} $stderr');
    if (exitCode != 0) {
      return '${tr(AppI10n.errorExtractFailed)} (Exit code: $exitCode)\n$stderr';
    }
  } catch (e) {
    debugPrint('${tr(AppI10n.errorExtractFailed)} $e');
    return '${tr(AppI10n.errorExtractFailed)} $e';
  }
  return null;
}

Future<String?> extractVideo(
  WidgetRef ref,
  WallpaperInfo wallpaper,
  String outPath,
) async {
  Stopwatch stopwatch = Stopwatch();
  stopwatch.start();
  try {
    final filePath = wallpaper.target;
    // Name the exported video after the wallpaper title (sanitized), keeping the
    // source extension, instead of the cryptic source filename. Falls back to the
    // source base name when the title is empty.
    final extension = path.extension(filePath);
    final title = renameFolder(wallpaper.title).trim();
    final baseName = title.isEmpty
        ? path.basenameWithoutExtension(filePath)
        : title;
    final fileName = '$baseName$extension';
    final targetPath = renameFile(path.join(outPath, fileName));
    final sourceFile = File(filePath);
    final destinationFile = File(targetPath);
    final totalSize = await sourceFile.length();
    await destinationFile.parent.create(recursive: true);
    // 使用流方式复制文件并显示进度
    // final int chunkSize = 1024 * 1024; // 1MB chunks
    int copiedSize = 0;
    final readStream = sourceFile.openRead();
    final writeStream = destinationFile.openWrite();
    try {
      await readStream
          .listen(
            (List<int> data) async {
              writeStream.add(data);
              copiedSize += data.length;
              String loadingText = tr(
                AppI10n.dialogExtractVideoInfo,
                namedArgs: {
                  "copied": formatSize(copiedSize),
                  "total": formatSize(totalSize),
                },
              );
              changeLoadingText(ref, loadingText);
            },
            onError: (error) {
              throw Exception('读取文件时出错: $error');
            },
            onDone: () async {
              await writeStream.close();
            },
            cancelOnError: true,
          )
          .asFuture<void>();
    } finally {
      await writeStream.close();
    }
    await writeStream.done;
  } catch (e) {
    debugPrint('${tr(AppI10n.errorExportVideoFailed)} $e');
    return '${tr(AppI10n.errorExportVideoFailed)} $e';
  } finally {
    stopwatch.stop();
    double seconds = stopwatch.elapsedMilliseconds / 1000;
    debugPrint('${tr(AppI10n.logExtractVideoTime)} $seconds');
  }
  return null;
}

Future<String?> extractImages(
  WidgetRef ref,
  String filePath,
  String outPath,
) async {
  Stopwatch stopwatch = Stopwatch();
  stopwatch.start();
  try {
    Directory folder = Directory(filePath);
    List<FileSystemEntity> files = await folder.list().toList();
    String loadingText = '';
    int count = files.length;
    // Track the index directly instead of files.indexOf(file), which is O(n^2)
    // inside this loop.
    int index = 0;
    for (var file in files) {
      if (file is File) {
        loadingText = tr(
          AppI10n.dialogExtractImageInfo,
          namedArgs: {'index': '$index', 'count': '$count'},
        );
        changeLoadingText(ref, loadingText);
        String fileName = path.basename(file.path);
        String targetPath = renameFile(path.join(outPath, fileName));
        await file.copy(targetPath);
      }
      index++;
    }
  } catch (e) {
    debugPrint('${tr(AppI10n.errorExportImageFailed)} $e');
    return '${tr(AppI10n.errorExportImageFailed)} $e';
  }
  stopwatch.stop();
  double seconds = stopwatch.elapsedMilliseconds / 1000;
  debugPrint('${tr(AppI10n.logExtractImageTime)} $seconds');
  return null;
}

void changeLoadingText(WidgetRef ref, String text) {
  ref.read(loadingTextProvider.notifier).update(text);
}
