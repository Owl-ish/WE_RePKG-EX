import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:we_repkg/cores/backup.dart';

void main() {
  test('detailed comparison retains files proven identical', () async {
    final Directory root = Directory.systemTemp.createTempSync(
      'we_repkg_detailed_file_changes',
    );
    addTearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });
    final Directory first = Directory(
      '${root.path}${Platform.pathSeparator}first',
    )..createSync();
    final Directory second = Directory(
      '${root.path}${Platform.pathSeparator}second',
    )..createSync();

    File(
      '${first.path}${Platform.pathSeparator}project.json',
    ).writeAsStringSync('same project');
    File(
      '${second.path}${Platform.pathSeparator}project.json',
    ).writeAsStringSync('same project');
    File(
      '${first.path}${Platform.pathSeparator}same-size.txt',
    ).writeAsStringSync('left');
    File(
      '${second.path}${Platform.pathSeparator}same-size.txt',
    ).writeAsStringSync('rift');

    final FolderFileComparison? comparison = await compareFolderFilesDetailed(
      firstFolder: first.path,
      secondFolder: second.path,
    );

    expect(comparison, isNotNull);
    expect(comparison!.matching, <String>['project.json']);
    expect(comparison.changes.modified, <String>['same-size.txt']);
  });

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
