import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:we_repkg/constants/i10n.dart';
import 'package:we_repkg/cores/backup.dart';
import 'package:we_repkg/provider/system.dart';

part 'backup.g.dart';

/// How far the running scan has got, for the tab to show while it waits.
///
/// A notifier rather than provider state: the count moves every few folders,
/// and rebuilding the tab that often to redraw one line of text would be worse
/// than the silence it replaces. Only the line itself listens.
@Riverpod(keepAlive: true)
ValueNotifier<BackupScanProgress?> backupScanProgress(Ref ref) {
  final ValueNotifier<BackupScanProgress?> progress =
      ValueNotifier<BackupScanProgress?>(null);
  ref.onDispose(progress.dispose);
  return progress;
}

/// The whole comparison, run when the backup tab first asks for it.
///
/// Kept alive because leaving the tab unmounts the view and rescanning both
/// libraries is seconds of disk work. Watching the four paths is what refreshes
/// it when one of them changes; anything that writes to the backup invalidates
/// it by hand.
@Riverpod(keepAlive: true)
Future<BackupScan> backupScan(Ref ref) async {
  final String? backupRoot = ref.watch(backupRootProvider);
  final ValueNotifier<BackupScanProgress?> progress = ref.watch(
    backupScanProgressProvider,
  );
  final BackupScan scan = await scanBackup(
    backupRoot: backupRoot,
    liveWorkshopPath: ref.watch(wallpaperPathProvider),
    liveMyProjectsPath: ref.watch(myProjectsLibraryProvider),
    acfPath: ref.watch(acfPathProvider),
    onProgress: (BackupScanProgress value) => progress.value = value,
  );
  progress.value = null;
  // A Workshop card whose backup already matches live earns its baseline here.
  // Failing to write it must never cost the user the scan: a read-only backup
  // drive would otherwise replace the vanished list with an error string, and
  // nothing in this feature is allowed to weaken that tier. A lost baseline is
  // earned again on the next scan.
  try {
    await seedBackupRecords(backupRoot, scan.seeds);
  } catch (e) {
    debugPrint('${tr(AppI10n.errorSeedBackupRecordsFailed)} $e');
  }
  return scan;
}
