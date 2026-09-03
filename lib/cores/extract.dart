import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:we_repkg/constants/i10n.dart';
import 'package:we_repkg/constants/wallpaper_files.dart';
import 'package:we_repkg/models/extract_settings.dart';
import 'package:we_repkg/models/wallpaper.dart';
import 'package:we_repkg/utils/cancel_token.dart';
import 'package:we_repkg/utils/extract_cleanup.dart';
import 'package:we_repkg/utils/file_copy.dart';
import 'package:we_repkg/utils/repkg_output.dart';
import 'package:we_repkg/utils/tool.dart';

/// Where a worker writes its progress line. Captured from the provider before
/// the first await, so the workers never touch `ref` and can be called from a
/// test without pumping a frame.
typedef StatusSink = void Function(String text);

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

/// Keeps the ID in title-based names so equal titles cannot merge across runs,
/// even when the wallpapers are selected separately or in a different order.
String wallpaperExportFolder(
  WallpaperInfo wallpaper,
  String basePath, {
  required bool useTitleName,
}) {
  final String name = useTitleName
      ? '${renameFolder(wallpaper.title)} (${wallpaper.id})'
      : wallpaper.id;
  // A later shared-folder export must not mistake this output for scratch data.
  final String safeName = name.toLowerCase().startsWith(_sceneTempSweepPrefix)
      ? '_$name'
      : name;
  return path.join(basePath, safeName);
}

/// Extracts one wallpaper into [outPath]. Returns the failure, or null on
/// success, so a bad item never aborts the batch.
Future<String?> extractProjectTo({
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
    return '${tr(AppI10n.errorCreatedFolderFailed)} $e';
  }

  // Non-scene wallpaper: copy the whole folder (re-importable) instead of RePKG.
  if (!wallpaper.target.toLowerCase().endsWith('pkg')) {
    return copyWallpaperFolderTo(wallpaper, outPath, overwrite: overwrite);
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
      return _formatRePKGFailure(
        wallpaper,
        outPath,
        exitCode: result.exitCode,
        summary: summarizeRePKGOutput(result.stdout, result.stderr),
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

/// How many batches are running in each export folder. A count, not a flag:
/// with three runs in flight the first to finish would otherwise free the
/// folder while the second is still writing into it.
final Map<String, int> _exporting = <String, int>{};

/// Runs [work] as one export batch, clearing what an earlier run left behind
/// only when nothing else is exporting into [outPath].
///
/// The sweep cannot tell a leftover from a scene folder or a part file another
/// run is writing this second, and two runs overlapping is ordinary: picking an
/// export folder returns while the first run is still going, and the second
/// click starts before it finishes. The second sweep then deleted the first
/// run's `.werepkg-ex-` folder out from under RePKG, which surfaced as a file
/// that was not found.
Future<T> withExportSweep<T>(String outPath, Future<T> Function() work) async {
  final String key = path.normalize(outPath).toLowerCase();
  final bool alone = (_exporting[key] ?? 0) == 0;
  _exporting[key] = (_exporting[key] ?? 0) + 1;
  try {
    if (alone) await sweepStaleOutput(outPath);
    return await work();
  } finally {
    final int left = (_exporting[key] ?? 1) - 1;
    left > 0 ? _exporting[key] = left : _exporting.remove(key);
  }
}

/// [detailedProgress] turns on the per-file byte counter. Off for batches, where
/// several workers writing one progress line just makes it flicker.
/// [destinationIsWallpaperFolder] prevents another nesting level for web and
/// application wallpapers when [outPath] already belongs to this wallpaper.
Future<String?> extractBranch(
  StatusSink onStatus,
  ExtractSettings settings,
  WallpaperInfo wallpaper,
  String outPath,
  FileNameClaims claims,
  CancelToken token, {
  bool detailedProgress = false,
  VoidCallback? onNothingWritten,
  bool destinationIsWallpaperFolder = false,
}) async {
  final target = wallpaper.target;
  // Match the file type case-insensitively (e.g. ".MP4" should still count).
  final targetLower = target.toLowerCase();
  if (targetLower.endsWith('pkg')) {
    return extractSceneToShared(
      onStatus,
      settings,
      wallpaper,
      outPath,
      claims,
      token,
      detailedProgress: detailedProgress,
      onNothingWritten: onNothingWritten,
    );
  } else if (targetLower.endsWith('.mp4')) {
    return extractVideo(
      onStatus,
      wallpaper,
      outPath,
      claims,
      token,
      detailedProgress: detailedProgress,
    );
  } else if (targetLower.endsWith(WallpaperDirectories.custom)) {
    // A wallpaper whose folder holds nothing to copy is the same silence a
    // scene that extracted nothing leaves.
    if (await isEmptyOfFiles(Directory(target))) onNothingWritten?.call();
    return extractImages(
      onStatus,
      target,
      outPath,
      claims,
      detailedProgress: detailedProgress,
    );
  }
  // Anything RePKG does not handle: copy the folder into a subfolder of its own.
  final name = settings.useTitleName
      ? renameFolder(wallpaper.title)
      : wallpaper.id;
  final String dest = destinationIsWallpaperFolder
      ? outPath
      : path.join(outPath, name);
  final String? copied = await copyWallpaperFolderTo(
    wallpaper,
    dest,
    overwrite: settings.overwrite,
  );
  // Nothing copied and nothing there: every file already existed with overwrite
  // off, or the folder was empty to begin with.
  if (copied == null && await isEmptyOfFiles(Directory(dest))) {
    onNothingWritten?.call();
  }
  return copied;
}

/// Copies the whole wallpaper folder into [destDir], so the output stays a
/// re-importable Wallpaper Engine wallpaper. For web, application, and anything
/// else RePKG does not unpack.
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
        if (!overwrite && await File(dest).exists()) continue;
        final parent = path.dirname(dest);
        // list() can hand back a child before its parent.
        if (createdDirs.add(parent)) {
          await Directory(parent).create(recursive: true);
        }
        // Replacing goes through a part file: copying straight over would leave
        // a truncated file where the last export was if it failed partway.
        if (overwrite) {
          await copyFileReplacing(entity, File(dest));
        } else {
          await entity.copy(dest);
        }
      }
    }
  } catch (e) {
    debugPrint('${tr(AppI10n.errorExtractFailed)} $e');
    return '${tr(AppI10n.errorExtractFailed)} $e';
  }
  return null;
}

const String _sceneTempPrefix = '.werepkg-ex-';

int _sceneTempSeq = 0;

/// A private directory for one scene, for one run.
///
/// The counter is what keeps two runs apart. Named by wallpaper id alone, a
/// second run on the same wallpaper deleted the first one's directory on its way
/// in and then emptied it again on its way out, so one run reported a file that
/// was not found and the other moved nothing and called it success. Two runs
/// overlap in ordinary use: the export folder picker returns while the first is
/// still going.
String sceneTempName(String id) => '$_sceneTempPrefix$id-${_sceneTempSeq++}';

/// Every scene temp folder this app has ever made begins with this, the pre-1.7
/// name included, so one check sweeps both spellings.
const String _sceneTempSweepPrefix = '.werepkg-';

/// Clears the scene directories and half-copied files a killed run left at the
/// top of the export folder, which the per-scene cleanup never got to. Both
/// names are namespaced to this app, so nothing of the user's own matches.
///
/// Top level only, so a part file inside a copied wallpaper's own subfolder
/// survives. Walking the whole export folder every run would cost more than
/// clearing that leftover is worth.
Future<void> sweepStaleOutput(String outPath) async {
  try {
    await for (final entity in Directory(outPath).list(followLinks: false)) {
      final String name = path.basename(entity.path);
      if (entity is Directory && name.startsWith(_sceneTempSweepPrefix)) {
        await entity.delete(recursive: true);
      } else if (entity is File &&
          (name.endsWith(partSuffix) || name.endsWith(legacyPartSuffix))) {
        await entity.delete();
      }
    }
  } catch (e) {
    debugPrint('${tr(AppI10n.logDeleteFolderFailed)} $e');
  }
}

/// How many failed files an error message names before summarising the rest.
const int _namedInError = 5;

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
  final String named = failed.take(_namedInError).join(', ');
  final String rest = failed.length > _namedInError
      ? ' (+${failed.length - _namedInError})'
      : '';
  return '${tr(AppI10n.logMoveFileFailed)} $named$rest';
}

/// Extracts one scene into a directory of its own, then moves what survives the
/// cleanup into the shared export folder.
///
/// RePKG writes fixed names like scene.json, so several of them cannot share an
/// output folder. Giving each its own lets the batch run wallpapers at once.
Future<String?> extractSceneToShared(
  StatusSink onStatus,
  ExtractSettings settings,
  WallpaperInfo wallpaper,
  String outPath,
  FileNameClaims claims,
  CancelToken token, {
  bool detailedProgress = false,
  VoidCallback? onNothingWritten,
}) async {
  final Directory temp = Directory(
    path.join(outPath, sceneTempName(wallpaper.id)),
  );
  try {
    await temp.create(recursive: true);
  } catch (e) {
    debugPrint('${tr(AppI10n.errorCreatedFolderFailed)} $e');
    return '${tr(AppI10n.errorCreatedFolderFailed)} $e';
  }

  bool keepTemp = false;
  try {
    final String? err = await extractPKG(
      onStatus,
      settings,
      wallpaper,
      temp.path,
      token,
      detailedProgress: detailedProgress,
    );
    if (err != null) return err;
    // A cancelled RePKG also returns null, and publishing then would mix a
    // fraction of a scene into the export folder under names indistinguishable
    // from real output. The finally below wipes the temp directory instead.
    if (token.isCancelled) return null;
    final String? cleanup = await deleteUselessFiles(settings, temp.path);
    if (cleanup != null) return cleanup;

    // Counted before the move, which empties it. The tool skipping every entry
    // and the cleanup deleting every file both land here, and neither is a
    // failure to report as one.
    if (await isEmptyOfFiles(temp)) onNothingWritten?.call();

    final String? moved = await moveExtractedInto(temp.path, outPath, claims);
    if (moved == null) return null;
    // Whatever could not be moved is still in here. Deleting it would destroy
    // output the error message just named, and re-extracting cannot recover it
    // when the cause is permanent, a path too long being the usual one.
    keepTemp = true;
    return '$moved -> ${await keepUnmovedFiles(temp, outPath)}';
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

/// Whether [dir] holds no file at any depth. Empty subfolders do not count:
/// RePKG creates the tree before it knows what it will write.
Future<bool> isEmptyOfFiles(Directory dir) async {
  try {
    await for (final FileSystemEntity entity in dir.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is File) return false;
    }
  } on FileSystemException {
    return true;
  }
  return true;
}

/// Moves the leftovers out of the sweep's way and says where they went, since
/// the next run clears anything still named with the scene prefix.
Future<String> keepUnmovedFiles(Directory temp, String outPath) async {
  // Named after this run's own directory, so a second run on the same wallpaper
  // cannot delete the files an error message has just pointed at. The scene
  // prefix comes off, or the next run's sweep would clear it.
  final String kept = path.join(
    outPath,
    '${path.basename(temp.path).replaceFirst(_sceneTempPrefix, '')}-unmoved',
  );
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

List<String> wallpaperExtractArgs({
  required String target,
  required String outPath,
  required bool excludeTexture,
  required bool onlySaveImage,
  required bool overwrite,
  required bool detailedProgress,
  required bool newFlags,
  int? threads,
  int? maxMemoryMb,
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
  final List<String>? memoryCeiling = maxMemoryMb != null
      ? <String>['--max-memory', '$maxMemoryMb']
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
    ...?memoryCeiling,
    '-o',
    outPath,
    target,
  ];
}

/// Throttled to whole percents: a large scene runs to thousands of entries and
/// each update rebuilds the loading overlay.
void Function(String) _sceneProgressReporter(StatusSink onStatus) {
  int lastPercent = -1;
  return (String line) {
    final progress = parseRePKGProgress(line);
    if (progress == null) return;
    final int percent = progress.position * 100 ~/ progress.total;
    if (percent == lastPercent) return;
    lastPercent = percent;
    onStatus(
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
  StatusSink onStatus,
  ExtractSettings settings,
  WallpaperInfo wallpaper,
  String outPath,
  CancelToken token, {
  bool detailedProgress = false,
}) async {
  // No text write here: it set the same string the batch already set, and with
  // several workers running it just fought the others for the provider.
  final String rePKGPath = settings.rePKGPath!;
  try {
    final List<String> args = wallpaperExtractArgs(
      target: wallpaper.target,
      outPath: outPath,
      excludeTexture: settings.excludeTexture,
      onlySaveImage: settings.onlySaveImage,
      overwrite: settings.overwrite,
      detailedProgress: detailedProgress,
      newFlags: settings.newFlags,
      threads: settings.supportsThreads ? settings.plan.threads : null,
      maxMemoryMb: settings.supportsThreads ? settings.plan.memoryMb : null,
    );
    String fullCommand = '$rePKGPath ${args.join(' ')}';
    debugPrint('${tr(AppI10n.logRunCommand)} $fullCommand');
    final result = await runRePKG(
      rePKGPath,
      args,
      token,
      onStdoutLine: detailedProgress ? _sceneProgressReporter(onStatus) : null,
    );
    if (token.isCancelled) return null;
    final summary = summarizeRePKGOutput(result.stdout, result.stderr);
    if (result.exitCode != 0 || summary.claimedSuccessWithoutWriting) {
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
  StatusSink onStatus,
  WallpaperInfo wallpaper,
  String outPath,
  FileNameClaims claims,
  CancelToken token, {
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
    await copyFileReplacing(
      sourceFile,
      destinationFile,
      onProgress: (copied, total) {
        if (!detailedProgress) return;
        onStatus(
          tr(
            AppI10n.dialogExtractVideoInfo,
            namedArgs: {
              "copied": formatSize(copied),
              "total": formatSize(total),
            },
          ),
        );
      },
      cancelToken: token,
    );
  } catch (e) {
    // Only the placeholder claimFilePath created, never a file that was already
    // there: the copy goes through a .part and renames, so an export from an
    // earlier run survives a cancel untouched.
    if (targetPath != null && !claims.overwrite) {
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
  StatusSink onStatus,
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
        if (detailedProgress) onStatus(loadingText);
        String fileName = path.basename(file.path);
        String targetPath = await claims.claim(path.join(outPath, fileName));
        // Through a .part as well: a copy that fails partway would otherwise
        // leave a truncated file where the last run's image was.
        await copyFileReplacing(file, File(targetPath));
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
