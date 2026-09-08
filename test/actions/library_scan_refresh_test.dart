import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:we_repkg/actions/library_scan_refresh.dart';
import 'package:we_repkg/cores/backup.dart';
import 'package:we_repkg/cores/integrity_scan.dart';
import 'package:we_repkg/provider/backup.dart';
import 'package:we_repkg/provider/integrity.dart';
import 'package:we_repkg/provider/system.dart';

void main() {
  final root = path.absolute('test-library-roots');
  final workshop = path.join(root, 'workshop');
  final projects = path.join(root, 'projects');
  final backup = path.join(root, 'backup');
  for (final scenario in <({String name, String? output, bool refresh})>[
    (name: 'known mutation', output: null, refresh: true),
    (name: 'Workshop root', output: workshop, refresh: true),
    (
      name: 'nested MyProjects folder',
      output: path.join(projects, 'wallpaper'),
      refresh: true,
    ),
    (
      name: 'backup output',
      output: path.join(backup, 'workshop'),
      refresh: true,
    ),
    (name: 'parent output', output: root, refresh: true),
    (name: 'similar sibling name', output: '$projects-export', refresh: false),
    (
      name: 'normalized unrelated path',
      output: path.join(projects, '..', 'export'),
      refresh: false,
    ),
    if (path.style == path.Style.windows)
      (
        name: 'Windows case variation',
        output: projects.toUpperCase(),
        refresh: true,
      ),
  ]) {
    for (final outcome in ['success', 'reported failure', 'thrown failure']) {
      test('${scenario.name}: scan refresh after $outcome', () async {
        var changed = false;
        Future<BackupScan> scanBackup(Ref ref) async {
          final BackupScan result = (
            cards: {},
            updates: {},
            ignoredUpdates: {},
            presence: {},
            junk: {},
            reconcile: [],
            acfRead: changed,
            missing: {},
          );
          return result;
        }

        Future<IntegrityReport> scanIntegrity(Ref ref) async {
          final IntegrityReport result = (
            findings: [],
            scanned: {},
            missing: changed ? <IntegrityRoot>{} : {IntegrityRoot.liveWorkshop},
          );
          return result;
        }

        final container = ProviderContainer(
          overrides: [
            wallpaperPathProvider.overrideWithValue(workshop),
            myProjectsLibraryProvider.overrideWithValue(projects),
            backupRootProvider.overrideWithValue(backup),
            backupScanProvider.overrideWith(scanBackup),
            integrityScanProvider.overrideWith(scanIntegrity),
          ],
        );
        addTearDown(container.dispose);
        expect(
          (await container.read(backupScanProvider.future)).acfRead,
          isFalse,
        );
        expect(
          (await container.read(integrityScanProvider.future)).missing,
          isNotEmpty,
        );

        final result = withLibraryScanRefresh<String?>(container, () async {
          changed = true;
          if (outcome == 'thrown failure') throw StateError('partial deletion');
          return outcome == 'reported failure' ? 'partial deletion' : null;
        }, outputFolder: scenario.output);
        if (outcome == 'thrown failure') {
          await expectLater(result, throwsStateError);
        } else {
          expect(
            await result,
            outcome == 'reported failure' ? 'partial deletion' : null,
          );
        }

        expect(
          (await container.read(backupScanProvider.future)).acfRead,
          scenario.refresh,
        );
        expect(
          (await container.read(integrityScanProvider.future)).missing,
          scenario.refresh ? isEmpty : isNotEmpty,
        );
      });
    }
  }
}
