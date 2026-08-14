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

enum IntegrityResolution {
  restoredFile,
  replacedProject,
  extractedProject,
  createdProject,
  recycled,
}

typedef ResolvedIntegrityIssue = ({
  IntegrityFinding finding,
  IntegrityResolution resolution,
});

typedef IntegrityResolvedState = ({
  List<ResolvedIntegrityIssue> issues,
  bool shown,
});

/// Repairs completed during this app run. Nothing is persisted to disk.
@Riverpod(keepAlive: true)
class IntegrityResolved extends _$IntegrityResolved {
  @override
  IntegrityResolvedState build() =>
      (issues: const <ResolvedIntegrityIssue>[], shown: false);

  void addAll(Iterable<ResolvedIntegrityIssue> issues) {
    final List<ResolvedIntegrityIssue> next = <ResolvedIntegrityIssue>[
      ...state.issues,
    ];
    for (final ResolvedIntegrityIssue issue in issues) {
      final IntegrityFinding finding = issue.finding;
      if (next.any(
        (ResolvedIntegrityIssue existing) =>
            existing.finding.root == finding.root &&
            existing.finding.folder == finding.folder &&
            existing.finding.verdict == finding.verdict,
      )) {
        continue;
      }
      next.add(issue);
    }
    state = (issues: next, shown: state.shown);
  }

  void show(bool value) => state = (issues: state.issues, shown: value);
}
