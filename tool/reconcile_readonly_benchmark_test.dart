// ignore_for_file: avoid_print

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:we_repkg/cores/backup.dart';
import 'package:we_repkg/cores/scene_pkg_inspection.dart';
import 'package:we_repkg/provider/backup.dart';
import 'package:we_repkg/utils/backup_diff.dart';

// Explicit read-only diagnostic of the Reconcile scan and batch controller.
void main() {
  final String? backupRoot = Platform.environment['RECONCILE_BACKUP_ROOT'];
  final String? liveWorkshop = Platform.environment['RECONCILE_LIVE_WORKSHOP'];
  final String? liveMyProjects =
      Platform.environment['RECONCILE_LIVE_MYPROJECTS'];
  final String? acfPath = Platform.environment['RECONCILE_ACF_PATH'];

  test(
    'classifies and checks real conflicting backups without mutation',
    () async {
      final Stopwatch scanTime = Stopwatch()..start();
      final BackupScan scan = await scanBackup(
        backupRoot: backupRoot,
        liveWorkshopPath: liveWorkshop,
        liveMyProjectsPath: liveMyProjects,
        acfPath: acfPath,
      );
      scanTime.stop();
      expect(scan.missing, isEmpty);
      final List<ReconcileEntry> eligible = scan.reconcile
          .where(BackupDirectBatch.eligible)
          .toList();
      print(
        'Backup scan: ${scanTime.elapsed}; '
        'Reconcile cards: ${scan.reconcile.length}; '
        'packed/unpacked checks: ${eligible.length}',
      );

      final BackupDirectBatch batch = BackupDirectBatch();
      addTearDown(batch.dispose);
      int reported = 0;
      final Stopwatch checkTime = Stopwatch()..start();
      batch.addListener(() {
        final int done = batch.value.done;
        if (done > reported &&
            (done - reported >= 25 || done == eligible.length)) {
          reported = done;
          print(
            'Content check: $done/${eligible.length} in ${checkTime.elapsed}',
          );
        }
      });
      await batch.start(scan: scan, backupRoot: backupRoot!, entries: eligible);
      checkTime.stop();
      expect(batch.value.cancelled, isFalse);
      expect(batch.value.done, eligible.length);
      final Map<DirectBackupProbeStatus, int> counts = {
        for (final DirectBackupProbeStatus status
            in DirectBackupProbeStatus.values)
          status: batch.value.results.values
              .where((result) => result.status == status)
              .length,
      };
      print('Content check finished in ${checkTime.elapsed}: $counts');
    },
    skip:
        backupRoot == null ||
        liveWorkshop == null ||
        liveMyProjects == null ||
        acfPath == null,
    timeout: const Timeout(Duration(minutes: 12)),
  );
}
