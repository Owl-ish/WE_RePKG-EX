import 'dart:convert';
import 'dart:io';
import 'dart:math';

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
import 'package:we_repkg/utils/repkg_output.dart';
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

/// Runs RePKG through Process.start so a cancelled batch can kill it, rather
/// than waiting for a large scene to finish unpacking.
Future<({int exitCode, String stdout, String stderr})> runRePKG(
  String rePKGPath,
  List<String> args,
  CancelToken token, {
  void Function(String line)? onStdoutLine,
}) async {
  // No shell: Dart quotes args correctly for paths containing spaces.
  final process = await Process.start(rePKGPath, args);
  token.register(process);
  try {
    // systemEncoding, not utf8. RePKG emits the console code page, GBK on a
    // Chinese Windows, and decoding that as UTF-8 throws on the first
    // non-ASCII byte. Both streams drain at once or a full pipe deadlocks.
    final StringBuffer out = StringBuffer();
    final Future<void> stdoutDone = process.stdout
        .transform(systemEncoding.decoder)
        .transform(const LineSplitter())
        .forEach((line) {
          out.writeln(line);
          onStdoutLine?.call(line);
        });
    final Future<String> stderrDone = process.stderr
        .transform(systemEncoding.decoder)
        .join();
    // Both awaited even if stdout throws, or stderr's error goes unhandled.
    final List<String> streams = await Future.wait(<Future<String>>[
      stdoutDone.then((_) => out.toString()),
      stderrDone,
    ]);
    final String stdout = streams[0];
    final String stderr = streams[1];
    final exitCode = await process.exitCode;
    debugPrint('${tr(AppI10n.logExitCode)} $exitCode');
    debugPrint('${tr(AppI10n.logStdout)} $stdout');
    debugPrint('${tr(AppI10n.logStderr)} $stderr');
    return (exitCode: exitCode, stdout: stdout, stderr: stderr);
  } finally {
    token.unregister(process);
  }
}

/// Guarded because this runs before the loading overlay, so a throw here took
/// the extraction down with nothing on screen.
Future<bool> ensureOutputDir(String outPath) async {
  try {
    await Directory(outPath).create(recursive: true);
    return true;
  } catch (e) {
    debugPrint('${tr(AppI10n.errorCreatedFolderFailed)} $e');
    showErrorToast('${tr(AppI10n.errorCreatedFolderFailed)} $outPath');
    return false;
  }
}

/// Copies a project's preview image into [destDir]. RePKG does not emit one, so
/// without this an extracted scene has nothing identifying it but its folder
/// name. Failure is logged and ignored.
Future<void> copyProjectPreviewImage(
  WallpaperInfo wallpaper,
  String destDir,
) async {
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
  String outPath = useProjectPath || extractType.isProject
      ? ref.read(projectPathProvider)!
      : ref.read(exportPathProvider)!;
  if (!await ensureOutputDir(outPath)) return;
  changeLoadingText(ref, tr(AppI10n.dialogProcessingWallpaper));
  final cancel = showLoadingView(wallpapers);
  final basePath = outPath;
  // Read once rather than per wallpaper; neither changes mid-batch.
  final bool useTitleName = ref.read(useTitleNameProvider);
  final bool overwrite = ref.read(replaceFileProvider);
  // Assigned before any worker starts, so the folder choice cannot race.
  final Map<String, String> outDirs = resolveProjectFolders(
    wallpapers,
    basePath,
    useTitleName: useTitleName,
  );
  final token = startBatch(ref);

  List<ErrorInfo?> results = const <ErrorInfo?>[];
  try {
    // Parallel is safe here: every wallpaper owns a distinct subfolder.
    results = await runBounded<WallpaperInfo, ErrorInfo?>(
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
  } catch (e) {
    errList.add(ErrorInfo(wallpaper: null, message: e.toString()));
  } finally {
    // The pool rethrows a worker's error, so without this the loading overlay
    // and its barrier stay up for good and the token is never retired.
    endBatch(ref);
    cancel.call();
  }
  errList.addAll(results.whereType<ErrorInfo>());
  if (token.isCancelled) return showCancelledToast();
  errList.isNotEmpty ? showErrorView(errList) : showExtractSuccessToast();
}

/// Assigns each wallpaper a distinct output folder under [basePath].
///
/// Two wallpapers can share a title, and sanitising illegal characters can make
/// two more collide, which would put two workers in one directory. Suffixed
/// here, before the pool starts, so the decision is deterministic.
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
    // Recursive and existing-tolerant: two workers may be creating siblings
    // under the same parent.
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
    // Before the exit code is judged. A non-zero exit usually means RePKG
    // skipped some entries and carried on, so the folder still wants a preview.
    await copyProjectPreviewImage(wallpaper, outPath);
    if (result.exitCode != 0) {
      return ErrorInfo(
        wallpaper: wallpaper,
        message: _formatRePKGFailure(
          wallpaper,
          outPath,
          exitCode: result.exitCode,
          summary: summarizeRePKGOutput(result.stdout, result.stderr),
        ),
      );
    }
  } catch (e) {
    debugPrint('${tr(AppI10n.errorExtractFailed)} $e');
    return ErrorInfo(
      wallpaper: wallpaper,
      message: _formatRePKGFailure(
        wallpaper,
        outPath,
        exitCode: null,
        details: e.toString(),
      ),
    );
  }
  return null;
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
  if (!await ensureOutputDir(outPath)) return;
  await sweepStaleSceneDirs(outPath);
  changeLoadingText(ref, tr(AppI10n.dialogProcessingWallpaper));
  final cancel = showLoadingView(wallpapers);
  final token = startBatch(ref);
  // One set for the whole batch: with overwrite on, a name may replace an
  // earlier run's file but must not be handed to two wallpapers here.
  final claims = FileNameClaims(overwrite: ref.read(replaceFileProvider));

  List<String?> results = const <String?>[];
  try {
    results = await runBounded<WallpaperInfo, String?>(
      wallpapers,
      (wallpaper) => extractBranch(
        ref,
        wallpaper,
        outPath,
        claims,
        // Only a single-wallpaper run can own the progress line.
        detailedProgress: wallpapers.length == 1,
      ),
      concurrency: ref.read(extractConcurrencyProvider),
      cancelToken: token,
      onStart: (w) => ref.read(processingWallpaperProvider.notifier).update(w),
      onComplete: (_) => ref.read(currentIndexProvider.notifier).increment(),
    );
  } catch (e) {
    errList.add(ErrorInfo(wallpaper: null, message: e.toString()));
  } finally {
    // The pool rethrows a worker's error, so without this the loading overlay
    // and its barrier stay up for good and the token is never retired.
    endBatch(ref);
    cancel.call();
  }

  // Each scene cleans up inside its own private directory before publishing, so
  // there is no sweep out here: it could not tell this run's output from the
  // user's own files.
  for (int i = 0; i < results.length; i++) {
    final err = results[i];
    if (err != null) {
      errList.add(ErrorInfo(wallpaper: wallpapers[i], message: err));
    }
  }

  if (token.isCancelled) return showCancelledToast();
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

/// [detailedProgress] turns on the per-file byte counter. Off for batches, where
/// several workers writing one progress line just makes it flicker.
Future<String?> extractBranch(
  WidgetRef ref,
  WallpaperInfo wallpaper,
  String outPath,
  FileNameClaims claims, {
  bool detailedProgress = false,
}) async {
  final target = wallpaper.target;
  // Match the file type case-insensitively (e.g. ".MP4" should still count).
  final targetLower = target.toLowerCase();
  if (targetLower.endsWith('pkg')) {
    return extractSceneToShared(
      ref,
      wallpaper,
      outPath,
      claims,
      detailedProgress: detailedProgress,
    );
  } else if (targetLower.endsWith('.mp4')) {
    return extractVideo(
      ref,
      wallpaper,
      outPath,
      claims,
      detailedProgress: detailedProgress,
    );
  } else if (targetLower.endsWith('customdirectory')) {
    return extractImages(
      ref,
      target,
      outPath,
      claims,
      detailedProgress: detailedProgress,
    );
  }
  // Anything RePKG does not handle: copy the folder into a subfolder of its own.
  final name = ref.read(useTitleNameProvider)
      ? renameFolder(wallpaper.title)
      : wallpaper.id;
  return copyWallpaperFolderTo(
    wallpaper,
    path.join(outPath, name),
    overwrite: ref.read(replaceFileProvider),
  );
}

/// Copies the whole wallpaper folder into [destDir], so the output stays a
/// re-importable Wallpaper Engine wallpaper. For web, application, and anything
/// else RePKG does not unpack. Takes [overwrite] rather than a provider so it
/// can run inside a worker.
Future<String?> copyWallpaperFolderTo(
  WallpaperInfo wallpaper,
  String destDir, {
  required bool overwrite,
}) async {
  try {
    final src = Directory(wallpaper.folder);
    await Directory(destDir).create(recursive: true);
    // Tracked so each directory is created once, not once per file in it.
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
        // list() can hand back a child before its parent.
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

const String _sceneTempPrefix = '.werepkg-';

/// Clears scene directories left by a run that was killed outright, which the
/// per-scene cleanup never got to.
Future<void> sweepStaleSceneDirs(String outPath) async {
  try {
    await for (final entity in Directory(outPath).list(followLinks: false)) {
      if (entity is! Directory) continue;
      if (!path.basename(entity.path).startsWith(_sceneTempPrefix)) continue;
      await entity.delete(recursive: true);
    }
  } catch (e) {
    debugPrint('${tr(AppI10n.logDeleteFolderFailed)} $e');
  }
}

/// Moves every file under [from] into [to], keeping relative paths and taking a
/// free name when another wallpaper already claimed one.
Future<String?> moveExtractedInto(
  String from,
  String to,
  FileNameClaims claims,
) async {
  // Per file, because the caller deletes the source directory afterwards:
  // stopping at the first failure would throw away everything behind it.
  final List<String> failed = <String>[];
  // Tracked so each directory is created once, not once per file in it.
  final Set<String> createdDirs = <String>{to};
  try {
    await for (final entity in Directory(
      from,
    ).list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final String dest = path.join(to, path.relative(entity.path, from: from));
      try {
        final String parent = path.dirname(dest);
        // list() can hand back a child before its parent.
        if (createdDirs.add(parent)) {
          await Directory(parent).create(recursive: true);
        }
        await entity.rename(await claims.claim(dest));
      } catch (e) {
        debugPrint('${tr(AppI10n.logMoveFileFailed)} ${entity.path} $e');
        failed.add(path.basename(entity.path));
      }
    }
  } catch (e) {
    debugPrint('${tr(AppI10n.logMoveFileFailed)} $e');
    return '${tr(AppI10n.logMoveFileFailed)} $e';
  }

  if (failed.isEmpty) return null;
  final String named = failed.take(5).join(', ');
  final String rest = failed.length > 5 ? ' (+${failed.length - 5})' : '';
  return '${tr(AppI10n.logMoveFileFailed)} $named$rest';
}

/// Extracts one scene into a directory of its own, then moves what survives the
/// cleanup into the shared export folder.
///
/// RePKG writes fixed names like scene.json, so several of them cannot share an
/// output folder. Giving each its own lets the batch run wallpapers at once.
Future<String?> extractSceneToShared(
  WidgetRef ref,
  WallpaperInfo wallpaper,
  String outPath,
  FileNameClaims claims, {
  bool detailedProgress = false,
}) async {
  final Directory temp = Directory(
    path.join(outPath, '$_sceneTempPrefix${wallpaper.id}'),
  );
  try {
    if (await temp.exists()) await temp.delete(recursive: true);
    await temp.create(recursive: true);
  } catch (e) {
    debugPrint('${tr(AppI10n.errorCreatedFolderFailed)} $e');
    return '${tr(AppI10n.errorCreatedFolderFailed)} $e';
  }

  bool keepTemp = false;
  try {
    final String? err = await extractPKG(
      ref,
      wallpaper,
      temp.path,
      detailedProgress: detailedProgress,
    );
    if (err != null) return err;
    // A cancelled RePKG also returns null, and publishing then would mix a
    // fraction of a scene into the export folder under names indistinguishable
    // from real output. The finally below wipes the temp directory instead.
    if (ref.read(activeCancelTokenProvider)?.isCancelled ?? false) return null;
    final String? cleanup = await deleteUselessFiles(
      ref,
      temp.path,
      const <FileSystemEntity>[],
    );
    if (cleanup != null) return cleanup;

    final String? moved = await moveExtractedInto(temp.path, outPath, claims);
    if (moved == null) return null;
    // Whatever could not be moved is still in here. Deleting it would destroy
    // output the error message just named, and re-extracting cannot recover it
    // when the cause is permanent, a path too long being the usual one.
    keepTemp = true;
    return '$moved -> ${await keepUnmovedFiles(temp, outPath, wallpaper.id)}';
  } finally {
    if (!keepTemp) {
      try {
        await temp.delete(recursive: true);
      } catch (e) {
        debugPrint('${tr(AppI10n.logDeleteFolderFailed)} $e');
      }
    }
  }
}

/// Moves the leftovers out of the sweep's way and says where they went, since
/// the next run clears anything still named with the scene prefix.
Future<String> keepUnmovedFiles(
  Directory temp,
  String outPath,
  String id,
) async {
  final String kept = path.join(outPath, '$id-unmoved');
  try {
    await Directory(kept).delete(recursive: true);
  } catch (_) {
    // Nothing there yet, which is the normal case.
  }
  try {
    await temp.rename(kept);
    return kept;
  } catch (e) {
    debugPrint('${tr(AppI10n.logMoveFileFailed)} $e');
    return temp.path;
  }
}

/// Builds RePKG's arguments for wallpaper mode.
///
/// [newFlags] false means an older tool that rejects an unknown option and then
/// exits 0 having written nothing, so every flag added since must hang off it.
/// Ceiling on the textures one RePKG converts at once. Each in-flight
/// conversion costs roughly 100MB, so a 15 texture scene measured 347MB on one
/// thread and 1.9GB on sixteen. Past this the machine runs out of memory long
/// before it runs out of cores.
const int _maxTextureThreads = 8;

/// How many textures one RePKG may convert at once, given how many wallpapers
/// are already running side by side. Dividing keeps the two levels from
/// multiplying, and scales with whatever the machine has: 2 threads each on a
/// four core box, 8 on a sixteen core one.
int textureThreads({required int cores, required int concurrency}) =>
    max(1, cores ~/ max(1, concurrency)).clamp(1, _maxTextureThreads);

List<String> wallpaperExtractArgs({
  required String target,
  required String outPath,
  required bool excludeTexture,
  required bool onlySaveImage,
  required bool overwrite,
  required bool detailedProgress,
  required bool newFlags,
  int? threads,
}) {
  // Either cleanup pass deletes the raw .tex straight after anyway.
  final String? onlyImages = newFlags && (excludeTexture || onlySaveImage)
      ? '-p'
      : null;
  final String? progress = newFlags && detailedProgress
      ? '--progress-json'
      : null;
  // Masks are most of the conversion work and none of the artwork. Wallpaper
  // mode only: a project needs them to still be a project.
  final List<String>? skipMasks = newFlags
      ? const ['--ignore-dirs', 'masks']
      : null;
  final List<String>? threadCount = threads != null
      ? <String>['--threads', '$threads']
      : null;

  return <String>[
    'extract',
    '-e',
    'tex',
    // Keeping the tree lets deleteOtherAndTexture find materials/, where -s would flatten it away.
    if (!excludeTexture) '-s',
    if (!excludeTexture) ?(overwrite ? '--overwrite' : null),
    ?onlyImages,
    ?progress,
    ...?skipMasks,
    ...?threadCount,
    '-o',
    outPath,
    target,
  ];
}

/// Throttled to whole percents: a large scene runs to thousands of entries and
/// each update rebuilds the loading overlay.
void Function(String) _sceneProgressReporter(WidgetRef ref) {
  int lastPercent = -1;
  return (String line) {
    final progress = parseRePKGProgress(line);
    if (progress == null) return;
    final int percent = progress.position * 100 ~/ progress.total;
    if (percent == lastPercent) return;
    lastPercent = percent;
    changeLoadingText(
      ref,
      tr(
        AppI10n.dialogExtractSceneInfo,
        namedArgs: {
          'index': '${progress.position}',
          'count': '${progress.total}',
        },
      ),
    );
  };
}

Future<String?> extractPKG(
  WidgetRef ref,
  WallpaperInfo wallpaper,
  String outPath, {
  bool detailedProgress = false,
}) async {
  // No text write here: it set the same string the batch already set, and with
  // several workers running it just fought the others for the provider.
  String rePKGPath = ref.read(toolPathProvider)!;
  bool excludeTexture = ref.read(excludeTextureProvider);
  bool onlySaveImage = ref.read(onlySaveImageProvider);
  try {
    final String? version = await ref.read(toolVersionProvider.future);
    // Unsupported flags make an older RePKG exit 0 having written nothing.
    final List<String> args = wallpaperExtractArgs(
      target: wallpaper.target,
      outPath: outPath,
      excludeTexture: excludeTexture,
      onlySaveImage: onlySaveImage,
      overwrite: ref.read(replaceFileProvider),
      detailedProgress: detailedProgress,
      newFlags: repkgSupportsExtractFlags(version),
      threads: repkgSupportsThreads(version)
          ? textureThreads(
              cores: Platform.numberOfProcessors,
              concurrency: ref.read(extractConcurrencyProvider),
            )
          : null,
    );
    String fullCommand = '$rePKGPath ${args.join(' ')}';
    debugPrint('${tr(AppI10n.logRunCommand)} $fullCommand');
    final token = ref.read(activeCancelTokenProvider) ?? CancelToken();
    final result = await runRePKG(
      rePKGPath,
      args,
      token,
      onStdoutLine: detailedProgress ? _sceneProgressReporter(ref) : null,
    );
    if (token.isCancelled) return null;
    if (result.exitCode != 0) {
      final summary = summarizeRePKGOutput(result.stdout, result.stderr);
      return _formatRePKGFailure(
        wallpaper,
        outPath,
        exitCode: result.exitCode,
        summary: summary,
      );
    }
  } catch (e) {
    debugPrint('${tr(AppI10n.errorExtractFailed)} $e');
    return _formatRePKGFailure(
      wallpaper,
      outPath,
      exitCode: null,
      details: e.toString(),
    );
  }
  return null;
}

String _formatRePKGFailure(
  WallpaperInfo wallpaper,
  String outPath, {
  required int? exitCode,
  RePKGOutputSummary? summary,
  String? details,
}) {
  final outcome = switch (summary) {
    RePKGOutputSummary(extractedFiles: final count) when count > 0 => tr(
      AppI10n.errorRePKGPartialOutput,
      namedArgs: {'count': '$count'},
    ),
    RePKGOutputSummary(skippedFiles: final count) when count > 0 => tr(
      AppI10n.errorRePKGSkippedOutput,
      namedArgs: {'count': '$count'},
    ),
    _ => tr(AppI10n.errorRePKGUnconfirmedOutput),
  };
  final detailText = (details ?? summary?.details ?? '').trim();
  final lines = <String>[
    tr(AppI10n.errorExtractFailed),
    '${tr(AppI10n.errorWallpaperId)} ${wallpaper.id}',
    '${tr(AppI10n.errorSourcePath)} ${wallpaper.target}',
    '${tr(AppI10n.errorOutputPath)} $outPath',
    '${tr(AppI10n.errorExtractionOutcome)} $outcome',
    if (exitCode != null) '${tr(AppI10n.logExitCode)} $exitCode',
    '${tr(AppI10n.errorRePKGDetails)} '
        '${detailText.isEmpty ? tr(AppI10n.errorRePKGNoDetails) : detailText}',
  ];
  return lines.join('\n');
}

Future<String?> extractVideo(
  WidgetRef ref,
  WallpaperInfo wallpaper,
  String outPath,
  FileNameClaims claims, {
  bool detailedProgress = false,
}) async {
  Stopwatch stopwatch = Stopwatch();
  stopwatch.start();
  // Hoisted so the catch can clear the name claimFilePath already created.
  String? targetPath;
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
    targetPath = await claims.claim(path.join(outPath, fileName));
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
      cancelToken: ref.read(activeCancelTokenProvider),
    );
  } catch (e) {
    // claimFilePath named it after the wallpaper, so a part-written file left
    // here is indistinguishable from a finished export.
    if (targetPath != null) {
      try {
        await File(targetPath).delete();
      } catch (_) {}
    }
    if (e is CopyCancelled) return null;
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
  FileNameClaims claims, {
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
        String targetPath = await claims.claim(path.join(outPath, fileName));
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
