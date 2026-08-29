import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:we_repkg/cores/backup.dart';

void main() {
  test(
    'file inspection detects content and path differences exactly',
    () async {
      final Directory root = Directory.systemTemp.createTempSync(
        'we_repkg_file_changes',
      );
      addTearDown(() {
        if (root.existsSync()) root.deleteSync(recursive: true);
      });
      final Directory live = Directory(
        '${root.path}${Platform.pathSeparator}live',
      )..createSync();
      final Directory backup = Directory(
        '${root.path}${Platform.pathSeparator}backup',
      )..createSync();

      File(
        '${live.path}${Platform.pathSeparator}same-size.txt',
      ).writeAsStringSync('new');
      File(
        '${backup.path}${Platform.pathSeparator}same-size.txt',
      ).writeAsStringSync('old');
      File(
        '${live.path}${Platform.pathSeparator}added.txt',
      ).writeAsStringSync('live');
      File(
        '${backup.path}${Platform.pathSeparator}removed.txt',
      ).writeAsStringSync('backup');

      final BackupFileChanges? changes = await compareBackupFileChanges(
        liveFolder: live.path,
        backupFolder: backup.path,
      );

      expect(changes, isNotNull);
      expect(changes!.modified, <String>['same-size.txt']);
      expect(changes.onlyLive, <String>['added.txt']);
      expect(changes.onlyBackup, <String>['removed.txt']);
    },
  );

  test(
    'file inspection reports unavailable folders without throwing',
    () async {
      final BackupFileChanges? changes = await compareBackupFileChanges(
        liveFolder: 'missing-live-folder',
        backupFolder: 'missing-backup-folder',
      );

      expect(changes, isNull);
    },
  );
}
