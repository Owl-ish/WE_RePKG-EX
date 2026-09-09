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
import 'library_scan_refresh.dart';

/// Creates the output folder; shows an error and returns false on failure.
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

/// Checks RePKG only for scene batches. Reports a missing tool before returning false.
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

/// Runs a batch with progress and error reporting. Returns false on cancellation,
/// not on worker errors, which are reported separately.
Future<bool> _runBatch(
  WidgetRef ref,
  List<WallpaperInfo> wallpapers,
  int concurrency,
  Future<String?> Function(WallpaperInfo wallpaper, CancelToken token) work, {
  required String outputFolder,
}) async {
  final container = ProviderScope.containerOf(ref.context, listen: false);
  // Capture notifiers before awaiting; the widget may unmount during extraction.
  final processing = ref.read(processingWallpaperProvider.notifier);
  final index = ref.read(currentIndexProvider.notifier);
  final activeToken = ref.read(activeCancelTokenProvider.notifier);
  ref
      .read(loadingTextProvider.notifier)
      .update(tr(AppI10n.dialogProcessingWallpaper));

  final cancel = showExtractionProgress(wallpapers);
  index.reset();
  processing.update(null);
  // Expose the token to the loading overlay's cancel button.
  final token = CancelToken();
  activeToken.update(token);

  final List<ErrorInfo> errList = [];
  List<String?> results = const <String?>[];
  try {
    results = await withLibraryScanRefresh(
      container,
      () => runBounded<WallpaperInfo, String?>(
        wallpapers,
        (wallpaper) => work(wallpaper, token),
        concurrency: concurrency,
        cancelToken: token,
        onStart: processing.update,
        onComplete: (_) => index.increment(),
      ),
      outputFolder: outputFolder,
    );
  } catch (e) {
    errList.add(ErrorInfo(wallpaper: null, message: e.toString()));
  } finally {
    // Release the overlay and token even if a worker throws.
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
  if (wallpapers.isEmpty) return;
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

  // Use one settings snapshot for the batch.
  final String? rePKGPath = ref.read(toolPathProvider);
  final bool overwrite = ref.read(replaceFileProvider);
  // Allocate distinct folders before starting workers.
  final Map<String, String> outDirs = resolveProjectFolders(
    wallpapers,
    outPath,
    useTitleName: ref.read(useTitleNameProvider),
  );

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
    outputFolder: outPath,
  );
}

// 新增的通用提取方法
//
// Clean each scene in its temporary directory, not among the user's exported files.
Future<void> extractWallpapers(
  WidgetRef ref,
  List<WallpaperInfo> wallpapers,
) async {
  if (wallpapers.isEmpty) return;
  if (!await checkExportPath(ref, true)) return;
  if (!await _rePKGAvailable(ref, wallpapers)) return;

  final String outPath = ref.read(exportPathProvider)!;
  if (!await ensureOutputDir(outPath)) return;

  final ExtractSettings settings = await readExtractSettings(
    ref,
    wallpapers.length,
  );
  // Overwrite may replace earlier exports, but workers must not share a filename.
  final claims = FileNameClaims(overwrite: settings.overwrite);
  final bool separateFolders = ref.read(separateWallpaperFoldersProvider);

  final StatusSink onStatus = ref.read(loadingTextProvider.notifier).update;

  // Report empty output separately; settings may intentionally skip every file.
  final List<String> emptyHanded = <String>[];
  bool finished = false;

  await withExportSweep(outPath, () async {
    finished = await _runBatch(ref, wallpapers, settings.plan.concurrency, (
      wallpaper,
      token,
    ) async {
      final String destination = separateFolders
          ? wallpaperExportFolder(
              wallpaper,
              outPath,
              useTitleName: settings.useTitleName,
            )
          : outPath;
      Future<String?> extract() => extractBranch(
        onStatus,
        settings,
        wallpaper,
        destination,
        claims,
        token,
        // Avoid competing per-file progress updates in a batch.
        detailedProgress: wallpapers.length == 1,
        onNothingWritten: () => emptyHanded.add(wallpaper.title),
        destinationIsWallpaperFolder: separateFolders,
      );
      if (!separateFolders) return extract();
      if (!await ensureOutputDir(destination)) {
        return '${tr(AppI10n.errorCreatedFolderFailed)} $destination';
      }
      return withExportSweep(destination, extract);
    }, outputFolder: outPath);
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
