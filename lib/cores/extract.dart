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
import 'package:we_repkg/utils/cancel_token.dart';
import 'package:we_repkg/utils/file_copy.dart';
import 'package:we_repkg/utils/info.dart';
import 'package:we_repkg/utils/tool.dart';
import 'package:we_repkg/utils/work_pool.dart';

import 'base.dart';
import 'toast.dart';

/// Resets batch progress and publishes a fresh cancel token, which the loading
/// overlay's cancel button reaches through activeCancelTokenProvider.
CancelToken startBatch(WidgetRef ref) {
  ref.read(currentIndexProvider.notifier).reset();
  ref.read(processingWallpaperProvider.notifier).update(null);
  final token = CancelToken();
  ref.read(activeCancelTokenProvider.notifier).update(token);
  return token;
}

/// Clears the preview and retires the token once a run finishes.
void endBatch(WidgetRef ref) {
  ref.read(processingWallpaperProvider.notifier).update(null);
  ref.read(activeCancelTokenProvider.notifier).update(null);
}

/// Runs RePKG so a batch can kill it mid-extract.
///
/// Process.run cannot be cancelled: it returns only once the child exits, so a
/// cancelled batch used to sit waiting for a large scene to finish unpacking.
/// Process.start hands back a handle the token can kill.
///
/// stdout and stderr drain concurrently. Reading one to completion before the
/// other deadlocks as soon as the child fills the pipe nobody is reading, which
/// RePKG does on a verbose extract.
Future<({int exitCode, String stdout, String stderr})> runRePKG(
  String rePKGPath,
  List<String> args,
  CancelToken token,
) async {
  // Invoke the exe directly (no shell): Dart quotes args correctly, which is
  // more robust for tool/output paths containing spaces.
  final process = await Process.start(rePKGPath, args);
  token.register(process);
  try {
    // systemEncoding, not utf8: Process.run decoded child output with the
    // system code page, and RePKG emits the console encoding (GBK on a Chinese
    // Windows). Decoding that as UTF-8 throws FormatException on the first
    // non-ASCII byte and failed the extraction.
    final streams = await Future.wait([
      process.stdout.transform(systemEncoding.decoder).join(),
      process.stderr.transform(systemEncoding.decoder).join(),
    ]);
    final exitCode = await process.exitCode;
    debugPrint('${tr(AppI10n.logExitCode)} $exitCode');
    debugPrint('${tr(AppI10n.logStdout)} ${streams[0]}');
    debugPrint('${tr(AppI10n.logStderr)} ${streams[1]}');
    return (exitCode: exitCode, stdout: streams[0], stderr: streams[1]);
  } finally {
    token.unregister(process);
  }
}

/// Copies the wallpaper's preview image into [destDir].
///
/// RePKG does not emit the preview, so an extracted scene had no thumbnail and
/// nothing identifying it but the folder name. Failure here is logged and
/// ignored: a missing preview must not fail an otherwise good extraction.
Future<void> copyPreviewImage(WallpaperInfo wallpaper, String destDir) async {
  final String src = wallpaper.previews;
  if (src.isEmpty) return;
  try {
    final file = File(src);
    if (!await file.exists()) return;
    final dest = await claimFilePath(path.join(destDir, path.basename(src)));
    await file.copy(dest);
  } catch (e) {
    debugPrint('${tr(AppI10n.errorExtractFailed)} (preview) $e');
  }
}

Future<void> extractProject(
  WidgetRef ref,
  List<WallpaperInfo> wallpapers,
) async {
  bool useProjectPath = ref.read(useProjectPathProvider);
  ExtractType extractType = ref.read(currentExtractTypeProvider);
  if (useProjectPath || extractType.isProject) {
    if (!await checkProjectPath(ref, true)) return;
  } else {
    if (!await checkExportPath(ref, true)) return;
  }
  // Only scenes (.pkg) need RePKG; skip the check for a batch without any.
  final needsRePKG = wallpapers.any(
    (w) => w.target.toLowerCase().endsWith('pkg'),
  );
  String? rePKGPath = ref.read(toolPathProvider);
  if (needsRePKG && !await toolExist(rePKGPath)) {
    return showToolNoExistToast();
  }
  List<ErrorInfo> errList = [];
  List<String> skipList = [];
  String outPath = useProjectPath || extractType.isProject
      ? ref.read(projectPathProvider)!
      : ref.read(exportPathProvider)!;
  if (!await Directory(outPath).exists()) {
    return projectNoExistToast(outPath);
  }
  changeLoadingText(ref, tr(AppI10n.dialogProcessingWallpaper));
  final cancel = showLoadingView(wallpapers);
  final basePath = outPath;
  // Hoisted out of the worker: these never change mid-batch, and reading a
  // provider once beats reading it per wallpaper.
  final bool useTitleName = ref.read(useTitleNameProvider);
  final bool overwrite = ref.read(replaceFileProvider);
  // Resolved before any worker starts, so the folder assignment is decided
  // single-threaded and cannot race.
  final Map<String, String> outDirs = resolveProjectFolders(
    wallpapers,
    basePath,
    useTitleName: useTitleName,
  );
  final token = startBatch(ref);

  // Safe to run in parallel: resolveProjectFolders guarantees every wallpaper
  // owns a distinct subfolder, so workers share no output directory.
  final results = await runBounded<WallpaperInfo, ErrorInfo?>(
    wallpapers,
    (wallpaper) => _extractProjectOne(
      wallpaper: wallpaper,
      outPath: outDirs[wallpaper.id]!,
      rePKGPath: rePKGPath,
      overwrite: overwrite,
      token: token,
    ),
    concurrency: ref.read(extractConcurrencyProvider),
    cancelToken: token,
    onStart: (w) => ref.read(processingWallpaperProvider.notifier).update(w),
    onComplete: (_) => ref.read(currentIndexProvider.notifier).increment(),
  );
  errList.addAll(results.whereType<ErrorInfo>());
  final bool cancelled = token.isCancelled;

  endBatch(ref);
  cancel.call();
  if (cancelled) return showCancelledToast();
  errList.isNotEmpty ? showErrorView(errList) : showProjectToast(skipList);
}

/// Assigns each wallpaper a distinct output folder under [basePath].
///
/// Two wallpapers can share a title, and sanitising illegal characters can make
/// two different titles collide as well. Serially that merged both into one
/// folder; in parallel it would have two workers writing into the same directory
/// at once. Suffixing duplicates here, before the pool starts, keeps the
/// decision deterministic and off the filesystem.
Map<String, String> resolveProjectFolders(
  List<WallpaperInfo> wallpapers,
  String basePath, {
  required bool useTitleName,
}) {
  final Map<String, String> assigned = {};
  final Set<String> taken = {};
  for (final wallpaper in wallpapers) {
    final String base = useTitleName
        ? renameFolder(wallpaper.title)
        : wallpaper.id;
    String name = base;
    int suffix = 1;
    while (!taken.add(name.toLowerCase())) {
      // Windows paths are case-insensitive, so compare that way too.
      name = '$base-$suffix';
      suffix++;
    }
    assigned[wallpaper.id] = path.join(basePath, name);
  }
  return assigned;
}

/// Extracts one wallpaper into [outPath]. Returns the failure, or null on
/// success, so a bad item never aborts the batch.
Future<ErrorInfo?> _extractProjectOne({
  required WallpaperInfo wallpaper,
  required String outPath,
  required String? rePKGPath,
  required bool overwrite,
  required CancelToken token,
}) async {
  try {
    // recursive+existing-tolerant: two workers can be creating sibling folders
    // under the same parent at the same time.
    await Directory(outPath).create(recursive: true);
  } catch (e) {
    debugPrint('${tr(AppI10n.errorCreatedFolderFailed)} $e');
    return ErrorInfo(
      wallpaper: wallpaper,
      message: '${tr(AppI10n.errorCreatedFolderFailed)} $e',
    );
  }

  // Non-scene wallpaper: copy the whole folder (re-importable) instead of RePKG.
  if (!wallpaper.target.toLowerCase().endsWith('pkg')) {
    final String? err = await copyWallpaperFolderTo(
      wallpaper,
      outPath,
      overwrite: overwrite,
    );
    return err == null ? null : ErrorInfo(wallpaper: wallpaper, message: err);
  }

  try {
    final args = [
      'extract',
      '-c',
      ?(overwrite ? '--overwrite' : null),
      '-o',
      outPath,
      wallpaper.target,
    ].cast<String>().toList();
    debugPrint('${tr(AppI10n.logRunCommand)} $rePKGPath ${args.join(' ')}');
    final result = await runRePKG(rePKGPath!, args, token);
    if (token.isCancelled) return null;
    // Before the exit code is judged: a non-zero exit now means RePKG skipped
    // some entries and carried on, not that it produced nothing. Reporting the
    // failure is right, but denying an otherwise complete folder its preview
    // image on top of that is not.
    await copyPreviewImage(wallpaper, outPath);
    if (result.exitCode != 0) {
      return ErrorInfo(
        wallpaper: wallpaper,
        message: '${tr(AppI10n.errorExtractFailed)} ${result.stderr}',
      );
    }
  } catch (e) {
    debugPrint('${tr(AppI10n.errorExtractFailed)} $e');
    return ErrorInfo(
      wallpaper: wallpaper,
      message: '${tr(AppI10n.errorExtractFailed)} $e',
    );
  }
  return null;
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
  String? rePKGPath = ref.read(toolPathProvider);
  if (needsRePKG && !await toolExist(rePKGPath)) {
    return showToolNoExistToast();
  }
  List<ErrorInfo> errList = [];
  String outPath = ref.read(exportPathProvider)!;
  Directory outDir = Directory(outPath);
  if (!await outDir.exists()) await outDir.create();
  List<FileSystemEntity> oldFiles = await outDir.list().toList();
  changeLoadingText(ref, tr(AppI10n.dialogProcessingWallpaper));
  final cancel = showLoadingView(wallpapers);
  final token = startBatch(ref);

  // Every wallpaper here writes into the SAME export folder, unlike
  // extractProject. That is safe only because claimFilePath reserves output
  // names atomically; without it two workers could be handed the same filename.
  final results = await runBounded<WallpaperInfo, (String?, bool)>(
    wallpapers,
    (wallpaper) => extractBranch(
      ref,
      wallpaper,
      outPath,
      // Only a single-wallpaper run can own the progress line.
      detailedProgress: wallpapers.length == 1,
    ),
    concurrency: ref.read(extractConcurrencyProvider),
    cancelToken: token,
    onStart: (w) => ref.read(processingWallpaperProvider.notifier).update(w),
    onComplete: (_) => ref.read(currentIndexProvider.notifier).increment(),
  );

  // OR, not assignment: the previous version kept only the last item's flag, so
  // a batch ending in a video skipped the cleanup a .pkg earlier had asked for.
  bool needClear = false;
  for (int i = 0; i < results.length; i++) {
    final result = results[i];
    if (result == null) continue; // never started: the batch was cancelled
    final (err, wantsClear) = result;
    needClear = needClear || wantsClear;
    if (err != null) {
      errList.add(ErrorInfo(wallpaper: wallpapers[i], message: err));
    }
  }

  if (needClear && !token.isCancelled) {
    changeLoadingText(ref, tr(AppI10n.dialogProcessingDelete));
    String? err2 = await deleteUselessFiles(ref, outPath, oldFiles);
    if (err2 != null) errList.add(ErrorInfo(wallpaper: null, message: err2));
  }
  final bool wasCancelled = token.isCancelled;
  endBatch(ref);
  cancel.call();
  if (wasCancelled) return showCancelledToast();
  errList.isNotEmpty ? showErrorView(errList) : showExtractSuccessToast();
}

Future<void> extractCurrent(WidgetRef ref, WallpaperInfo wallpaper) async {
  await extractWallpapers(ref, [wallpaper]);
}

Future<void> extractChecked(WidgetRef ref) async {
  List<WallpaperInfo> wallpapers = ref.read(checkedWallpaperListProvider);
  ExtractType extractType = ref.read(currentExtractTypeProvider);
  if (extractType.isWallpaper) {
    await extractWallpapers(ref, wallpapers);
  } else {
    await extractProject(ref, wallpapers);
  }
}

Future<void> extractAll(WidgetRef ref) async {
  List<WallpaperInfo> wallpapers = ref.read(filterWallpaperListProvider);
  ExtractType extractType = ref.read(currentExtractTypeProvider);
  if (extractType.isWallpaper) {
    await extractWallpapers(ref, wallpapers);
  } else {
    await extractProject(ref, wallpapers);
  }
}

/// [detailedProgress] enables the per-file byte counter. It is off whenever a
/// batch runs more than one wallpaper at a time: with four workers each writing
/// its own progress line into a single provider, the text flickers between
/// unrelated wallpapers instead of reading as progress.
Future<(String?, bool)> extractBranch(
  WidgetRef ref,
  WallpaperInfo wallpaper,
  String outPath, {
  bool detailedProgress = false,
}) async {
  final target = wallpaper.target;
  // Match the file type case-insensitively (e.g. ".MP4" should still count).
  final targetLower = target.toLowerCase();
  if (targetLower.endsWith('pkg')) {
    final err = await extractPKG(ref, target, outPath);
    // Unconditional, like the project-mode path: RePKG reports a non-zero exit
    // for a partial extraction as well as a total one, and the files it did
    // write still deserve their preview.
    await copyPreviewImage(wallpaper, outPath);
    return (err, true);
  } else if (targetLower.endsWith('.mp4')) {
    return (
      await extractVideo(
        ref,
        wallpaper,
        outPath,
        detailedProgress: detailedProgress,
      ),
      false,
    );
  } else if (targetLower.endsWith('customdirectory')) {
    return (
      await extractImages(
        ref,
        target,
        outPath,
        detailedProgress: detailedProgress,
      ),
      false,
    );
  }
  // web / application / any other type RePKG does not handle: copy the whole
  // folder into a per-wallpaper subfolder so it stays re-importable.
  final name = ref.read(useTitleNameProvider)
      ? renameFolder(wallpaper.title)
      : wallpaper.id;
  final err = await copyWallpaperFolderTo(
    wallpaper,
    path.join(outPath, name),
    overwrite: ref.read(replaceFileProvider),
  );
  return (err, false);
}

/// Copies the entire wallpaper folder into [destDir] (every file, so the output
/// stays a valid, re-importable Wallpaper Engine wallpaper). Used for web,
/// application, and any type RePKG does not unpack.
/// Takes [overwrite] directly rather than reading a provider, so it can run
/// inside a worker without touching a WidgetRef.
Future<String?> copyWallpaperFolderTo(
  WallpaperInfo wallpaper,
  String destDir, {
  required bool overwrite,
}) async {
  try {
    final src = Directory(wallpaper.folder);
    await Directory(destDir).create(recursive: true);
    // Directories already created during this copy. The previous version issued
    // a recursive create for every single file's parent, even though the
    // directory walk had just created it, which is one redundant syscall per
    // file across the whole tree.
    final Set<String> createdDirs = {destDir};
    await for (final entity in src.list(recursive: true, followLinks: false)) {
      final dest = path.join(
        destDir,
        path.relative(entity.path, from: src.path),
      );
      if (entity is Directory) {
        if (createdDirs.add(dest)) {
          await Directory(dest).create(recursive: true);
        }
      } else if (entity is File) {
        // Respect the "replace existing" toggle: skip files already present.
        if (!overwrite && await File(dest).exists()) continue;
        final parent = path.dirname(dest);
        // list() does not guarantee a parent arrives before its children, so
        // this still creates on demand, just once per directory.
        if (createdDirs.add(parent)) {
          await Directory(parent).create(recursive: true);
        }
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
  // No text write here: it set the same string the batch already set, and with
  // several workers running it just fought the others for the provider.
  String rePKGPath = ref.read(toolPathProvider)!;
  bool excludeTexture = ref.read(excludeTextureProvider);
  try {
    String? overwrite = ref.read(replaceFileProvider) ? '--overwrite' : null;
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
    final token = ref.read(activeCancelTokenProvider) ?? CancelToken();
    final result = await runRePKG(rePKGPath, args, token);
    if (token.isCancelled) return null;
    if (result.exitCode != 0) {
      return '${tr(AppI10n.errorExtractFailed)} (Exit code: ${result.exitCode})\n${result.stderr}';
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
  String outPath, {
  bool detailedProgress = false,
}) async {
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
    // Atomic claim: several workers may be writing into this same folder.
    final targetPath = await claimFilePath(path.join(outPath, fileName));
    final sourceFile = File(filePath);
    final destinationFile = File(targetPath);
    // 使用流方式复制文件并显示进度，带背压和节流的进度回调
    await copyFileWithProgress(
      sourceFile,
      destinationFile,
      onProgress: (copied, total) {
        if (!detailedProgress) return;
        changeLoadingText(
          ref,
          tr(
            AppI10n.dialogExtractVideoInfo,
            namedArgs: {
              "copied": formatSize(copied),
              "total": formatSize(total),
            },
          ),
        );
      },
    );
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
  String outPath, {
  bool detailedProgress = false,
}) async {
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
        if (detailedProgress) changeLoadingText(ref, loadingText);
        String fileName = path.basename(file.path);
        String targetPath = await claimFilePath(path.join(outPath, fileName));
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
