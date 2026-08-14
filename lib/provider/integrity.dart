import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:we_repkg/cores/integrity_scan.dart';
import 'package:we_repkg/provider/system.dart';
import 'package:we_repkg/cores/integrity_rules.dart';

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

/// Which concern the list is showing, or null for the worst one the check
/// found.
@Riverpod(keepAlive: true)
class IntegrityShown extends _$IntegrityShown {
  @override
  IntegrityVerdict? build() {
    // Forgotten on a recheck, so fixing every folder of one concern lands back
    // on the worst one left rather than on an empty list, and a later recheck
    // cannot yank the list back to a pick from two checks ago.
    ref.watch(integrityScanProvider);
    return null;
  }

  void show(IntegrityVerdict verdict) => state = verdict;
}
