import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:we_repkg/cores/backup.dart';
import 'package:we_repkg/provider/system.dart';

part 'backup.g.dart';

/// The whole comparison, run when the backup tab first asks for it.
///
/// Kept alive because leaving the tab unmounts the view and rescanning both
/// libraries is seconds of disk work. Watching the four paths is what refreshes
/// it when one of them changes; anything that writes to the backup invalidates
/// it by hand.
@Riverpod(keepAlive: true)
Future<BackupScan> backupScan(Ref ref) => scanBackup(
  backupRoot: ref.watch(backupRootProvider),
  liveWorkshopPath: ref.watch(wallpaperPathProvider),
  liveMyProjectsPath: ref.watch(myProjectsLibraryProvider),
  acfPath: ref.watch(acfPathProvider),
);
