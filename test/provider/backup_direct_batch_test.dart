import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:we_repkg/cores/backup.dart';
import 'package:we_repkg/cores/scene_pkg_inspection.dart';
import 'package:we_repkg/provider/backup.dart';
import 'package:we_repkg/utils/backup_diff.dart';
import 'package:we_repkg/utils/cancel_token.dart';

import '../support/backup_test_harness.dart';

void main() {
  ReconcileEntry entry(String name) => ReconcileEntry(
    name: name,
    reason: BackupReconcileReason.conflictingBackupCopies,
    states: const {},
    backupWorkshop: true,
    backupMyProjects: true,
    backupDifference: const BackupCopyDifference(
      workshopFormat: BackupCopyFormat.packed,
      myProjectsFormat: BackupCopyFormat.unpacked,
      verificationSignature: 'scan-signature',
    ),
  );

  DirectBackupProbe result(DirectBackupProbeStatus status) => (
    status: status,
    changes: (
      modified: <String>[],
      onlyPacked: <String>[],
      onlyUnpacked: <String>[],
    ),
    reasons: <DirectBackupProbeReason>{},
  );

  test(
    'explicit batch bounds work, reports progress, and cancels remaining jobs',
    () async {
      final Map<String, Completer<DirectBackupProbe>> pending = {};
      final BackupDirectBatch batch = BackupDirectBatch(
        probe:
            ({
              required Directory packedFolder,
              required Directory unpackedFolder,
              String? expectedSignature,
              CancelToken? cancelToken,
            }) {
              expect(expectedSignature, 'scan-signature');
              final String name = path.basename(packedFolder.path);
              final Completer<DirectBackupProbe> completer =
                  Completer<DirectBackupProbe>();
              pending[name] = completer;
              return completer.future;
            },
      );
      addTearDown(batch.dispose);
      final List<ReconcileEntry> entries = <ReconcileEntry>[
        entry('first'),
        entry('second'),
        entry('third'),
        entry('fourth'),
        entry('fifth'),
      ];
      final BackupScan scan = scanOf(reconcile: entries);

      final Future<void> running = batch.start(
        scan: scan,
        backupRoot: r'C:\fixture',
        entries: entries,
      );
      expect(
        pending.keys,
        containsAll(<String>['first', 'second', 'third', 'fourth']),
      );
      expect(pending, hasLength(4));
      await batch.start(
        scan: scan,
        backupRoot: r'C:\fixture',
        entries: entries,
      );
      expect(pending, hasLength(4));

      pending['first']!.complete(
        result(DirectBackupProbeStatus.candidateMatch),
      );
      await Future<void>.delayed(Duration.zero);
      expect(batch.value.done, 1);
      expect(
        batch.value.results['first']?.status,
        DirectBackupProbeStatus.candidateMatch,
      );
      expect(pending, hasLength(5));

      batch.cancel();
      pending['second']!.complete(result(DirectBackupProbeStatus.different));
      pending['third']!.complete(result(DirectBackupProbeStatus.different));
      pending['fourth']!.complete(result(DirectBackupProbeStatus.different));
      pending['fifth']!.complete(result(DirectBackupProbeStatus.different));
      await running;
      expect(batch.value.cancelled, isTrue);
      expect(batch.value.running, isFalse);
      expect(batch.value.done, 1);
      expect(batch.forScan(scanOf(), r'C:\fixture').results, isEmpty);

      pending.clear();
      final Future<void> resumed = batch.start(
        scan: scan,
        backupRoot: r'C:\fixture',
        entries: entries,
      );
      expect(
        pending.keys,
        containsAll(<String>['second', 'third', 'fourth', 'fifth']),
      );
      expect(pending, hasLength(4));
      expect(batch.value.done, 1);
      expect(
        batch.value.results['first']?.status,
        DirectBackupProbeStatus.candidateMatch,
      );
      pending['second']!.complete(result(DirectBackupProbeStatus.different));
      pending['third']!.complete(
        result(DirectBackupProbeStatus.candidateMatch),
      );
      pending['fourth']!.complete(result(DirectBackupProbeStatus.different));
      pending['fifth']!.complete(result(DirectBackupProbeStatus.different));
      await resumed;
      expect(batch.value.done, 5);
      expect(batch.value.cancelled, isFalse);

      pending.clear();
      final Future<void> fresh = batch.start(
        scan: scan,
        backupRoot: r'C:\fixture',
        entries: entries,
      );
      expect(
        pending.keys,
        containsAll(<String>['first', 'second', 'third', 'fourth']),
      );
      expect(batch.value.done, 0);
      pending['first']!.complete(result(DirectBackupProbeStatus.different));
      await Future<void>.delayed(Duration.zero);
      pending['second']!.complete(result(DirectBackupProbeStatus.different));
      pending['third']!.complete(result(DirectBackupProbeStatus.different));
      pending['fourth']!.complete(result(DirectBackupProbeStatus.different));
      pending['fifth']!.complete(result(DirectBackupProbeStatus.different));
      await fresh;
      expect(batch.value.done, 5);
    },
  );
}
