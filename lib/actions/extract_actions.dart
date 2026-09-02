import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:we_repkg/constants/i10n.dart';
import 'package:we_repkg/cores/extract.dart';
import 'package:we_repkg/cores/toast.dart';
import 'package:we_repkg/models/enums.dart';
import 'package:we_repkg/models/error.dart';
import 'package:we_repkg/models/extract_settings.dart';
import 'package:we_repkg/models/wallpaper.dart';
import 'package:we_repkg/provider/setting.dart';
import 'package:we_repkg/provider/system.dart';
import 'package:we_repkg/provider/wallpaper.dart';
import 'package:we_repkg/utils/cancel_token.dart';
import 'package:we_repkg/utils/info.dart';
import 'package:we_repkg/utils/tool.dart';
import 'package:we_repkg/utils/work_pool.dart';

import 'path_actions.dart';

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

/// Only scenes (.pkg) need RePKG, so a batch without any skips the check.
/// Returns false having already told the user.
Future<bool> _rePKGAvailable(
  WidgetRef ref,
  List<WallpaperInfo> wallpapers,
) async {
  if (!wallpapers.any((w) => w.target.toLowerCase().endsWith('pkg'))) {
    return true;
  }
  if (await toolExist(ref.read(toolPathProvider))) return true;
  showToolNoExistToast();
  return false;
}

/// Runs [work] over [wallpapers] behind the loading overlay and reports how it
/// went. Both extraction modes share this; only the setup before it differs.
///
/// Returns whether it ran to the end, so a caller with something else to say
/// stays quiet after a cancel.
Future<bool> _runBatch(
  WidgetRef ref,
  List<WallpaperInfo> wallpapers,
  int concurrency,
  Future<String?> Function(WallpaperInfo wallpaper, CancelToken token) work,
) async {
  // Every notifier taken before the first await: the widget owning `ref` can be
  // gone by the time a worker reports or the batch retires, and reading through
  // it then throws.
  final processing = ref.read(processingWallpaperProvider.notifier);
  final index = ref.read(currentIndexProvider.notifier);
  final activeToken = ref.read(activeCancelTokenProvider.notifier);
  ref
      .read(loadingTextProvider.notifier)
      .update(tr(AppI10n.dialogProcessingWallpaper));

  final cancel = showExtractionProgress(wallpapers);
  index.reset();
  processing.update(null);
  // Published so the loading overlay's cancel button can reach it.
  final token = CancelToken();
  activeToken.update(token);

  final List<ErrorInfo> errList = [];
  List<String?> results = const <String?>[];
  try {
    results = await runBounded<WallpaperInfo, String?>(
      wallpapers,
      (wallpaper) => work(wallpaper, token),
      concurrency: concurrency,
      cancelToken: token,
      onStart: processing.update,
      onComplete: (_) => index.increment(),
    );
  } catch (e) {
    errList.add(ErrorInfo(wallpaper: null, message: e.toString()));
  } finally {
    // The pool rethrows a worker's error, so without this the loading overlay
    // and its barrier stay up for good and the token is never retired.
    processing.update(null);
    activeToken.update(null);
    cancel.call();
  }

  for (int i = 0; i < results.length; i++) {
    final String? message = results[i];
    if (message != null) {
      errList.add(ErrorInfo(wallpaper: wallpapers[i], message: message));
    }
  }

  if (token.isCancelled) {
    showCancelledToast();
    return false;
  }
  errList.isNotEmpty ? showErrorView(errList) : showExtractSuccessToast();
  return true;
}

Future<void> extractProject(
  WidgetRef ref,
  List<WallpaperInfo> wallpapers,
) async {
  final bool toProjectFolder =
      ref.read(useProjectPathProvider) ||
      ref.read(currentExtractTypeProvider).isProject;
  final bool pathOk = toProjectFolder
      ? await checkProjectPath(ref, true)
      : await checkExportPath(ref, true);
  if (!pathOk) return;
  if (!await _rePKGAvailable(ref, wallpapers)) return;

  final String outPath = (toProjectFolder
      ? ref.read(projectPathProvider)
      : ref.read(exportPathProvider))!;
  if (!await ensureOutputDir(outPath)) return;

  // Read once rather than per wallpaper; neither changes mid-batch.
  final String? rePKGPath = ref.read(toolPathProvider);
  final bool overwrite = ref.read(replaceFileProvider);
  // Assigned before any worker starts, so the folder choice cannot race.
  final Map<String, String> outDirs = resolveProjectFolders(
    wallpapers,
    outPath,
    useTitleName: ref.read(useTitleNameProvider),
  );

  // Parallel is safe here: every wallpaper owns a distinct subfolder.
  await _runBatch(
    ref,
    wallpapers,
    planFor(ref, wallpapers.length).concurrency,
    (wallpaper, token) => extractProjectTo(
      wallpaper: wallpaper,
      outPath: outDirs[wallpaper.id]!,
      rePKGPath: rePKGPath,
      overwrite: overwrite,
      token: token,
    ),
  );
}

// 新增的通用提取方法
//
// Each scene cleans up inside its own private directory before publishing, so
// nothing sweeps the export folder afterwards: it could not tell this run's
// output from the user's own files.
Future<void> extractWallpapers(
  WidgetRef ref,
  List<WallpaperInfo> wallpapers,
) async {
  if (!await checkExportPath(ref, true)) return;
  if (!await _rePKGAvailable(ref, wallpapers)) return;

  final String outPath = ref.read(exportPathProvider)!;
  if (!await ensureOutputDir(outPath)) return;

  final ExtractSettings settings = await readExtractSettings(
    ref,
    wallpapers.length,
  );
  // One set for the whole batch: with overwrite on, a name may replace an
  // earlier run's file but must not be handed to two wallpapers here.
  final claims = FileNameClaims(overwrite: settings.overwrite);

  final StatusSink onStatus = ref.read(loadingTextProvider.notifier).update;

  // A run that writes nothing is not a failure: skipping every entry is what
  // some settings ask for. It is still worth saying, since the only other
  // signal is a success toast over an unchanged folder.
  final List<String> emptyHanded = <String>[];
  bool finished = false;

  await withExportSweep(outPath, () async {
    finished = await _runBatch(ref, wallpapers, settings.plan.concurrency, (
      wallpaper,
      token,
    ) {
      return extractBranch(
        onStatus,
        settings,
        wallpaper,
        outPath,
        claims,
        token,
        // Only a single-wallpaper run can own the progress line.
        detailedProgress: wallpapers.length == 1,
        onNothingWritten: () => emptyHanded.add(wallpaper.title),
      );
    });
  });

  if (!finished || emptyHanded.isEmpty) return;
  showNoticeToast(
    tr(
      AppI10n.extractNothingWritten,
      namedArgs: <String, String>{
        'names': emptyHanded.take(3).join(', '),
        'count': '${emptyHanded.length}',
        'path': outPath,
      },
    ),
  );
}

Future<void> extractCurrent(WidgetRef ref, WallpaperInfo wallpaper) async {
  await extractWallpapers(ref, [wallpaper]);
}

Future<void> extractChecked(WidgetRef ref) =>
    _extractInCurrentMode(ref, ref.read(checkedWallpaperListProvider));

Future<void> extractAll(WidgetRef ref) =>
    _extractInCurrentMode(ref, ref.read(filterWallpaperListProvider));

Future<void> _extractInCurrentMode(
  WidgetRef ref,
  List<WallpaperInfo> wallpapers,
) async {
  if (ref.read(currentExtractTypeProvider).isWallpaper) {
    await extractWallpapers(ref, wallpapers);
  } else {
    await extractProject(ref, wallpapers);
  }
}

ExtractPlan planFor(WidgetRef ref, int batchSize) => extractPlan(
  requested: ref.read(extractConcurrencyProvider),
  batchSize: batchSize,
  cores: Platform.numberOfProcessors,
  totalMemoryMb: ref.read(extractMemoryLimitProvider),
);

Future<ExtractSettings> readExtractSettings(
  WidgetRef ref,
  int batchSize,
) async {
  // Awaited once here rather than once per wallpaper.
  final String? version = await ref.read(toolVersionProvider.future);
  return ExtractSettings(
    rePKGPath: ref.read(toolPathProvider),
    excludeTexture: ref.read(excludeTextureProvider),
    onlySaveImage: ref.read(onlySaveImageProvider),
    deleteTransparency: ref.read(deleteTransparencyProvider),
    overwrite: ref.read(replaceFileProvider),
    useTitleName: ref.read(useTitleNameProvider),
    newFlags: repkgSupportsExtractFlags(version),
    supportsThreads: repkgSupportsThreads(version),
    plan: planFor(ref, batchSize),
  );
}
