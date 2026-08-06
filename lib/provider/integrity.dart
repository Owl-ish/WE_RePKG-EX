import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:we_repkg/cores/integrity.dart';
import 'package:we_repkg/provider/system.dart';

part 'integrity.g.dart';

/// The integrity check over all four roots.
///
/// Kept alive so switching tabs does not re-walk 7000 folders, and watched
/// rather than read once so repointing a library re-checks it.
@Riverpod(keepAlive: true)
Future<IntegrityReport> integrityScan(Ref ref) => scanIntegrity(
  liveWorkshopPath: ref.watch(wallpaperPathProvider),
  liveMyProjectsPath: ref.watch(myProjectsLibraryProvider),
  backupRoot: ref.watch(backupRootProvider),
);
