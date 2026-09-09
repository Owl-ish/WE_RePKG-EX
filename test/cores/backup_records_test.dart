import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:we_repkg/cores/backup_records.dart';
import 'package:we_repkg/utils/backup_diff.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('we_repkg_backup_records');
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  group('with no backup root', () {
    test('the records read as none', () async {
      expect(await readBackupRecords(null), isEmpty);
    });

    test('writing records is a no-op rather than a crash', () async {
      await writeBackupRecords(null, <String, BackupRecord>{
        'workshop/793602574': const BackupRecord(backedUpVersion: 'manifest-1'),
      });
    });
  });

  group('backup records', () {
    test('round-trips through the backup root', () async {
      await writeBackupRecords(tmp.path, <String, BackupRecord>{
        'workshop/793602574': const BackupRecord(
          backedUpVersion: 'manifest-1',
          dismissedVersion: 'manifest-2',
        ),
        'myprojects/793602574': const BackupRecord(
          backedUpVersion: 'alpha|1|2',
        ),
      });

      final Map<String, BackupRecord> read = await readBackupRecords(tmp.path);

      expect(read.keys, <String>{'workshop/793602574', 'myprojects/793602574'});
      expect(read['workshop/793602574']!.backedUpVersion, 'manifest-1');
      expect(read['workshop/793602574']!.dismissedVersion, 'manifest-2');
      expect(read['myprojects/793602574']!.backedUpVersion, 'alpha|1|2');
      expect(read['myprojects/793602574']!.dismissedVersion, isNull);
    });

    test('is written indented and in a stable order', () async {
      await writeBackupRecords(tmp.path, <String, BackupRecord>{
        'workshop/zzz': const BackupRecord(backedUpVersion: 'later'),
        'workshop/aaa': const BackupRecord(backedUpVersion: 'earlier'),
      });

      final String body = File(
        p.join(tmp.path, backupRecordsName),
      ).readAsStringSync();

      expect(body, contains('\n'), reason: 'one long line is unreadable');
      expect(
        body.indexOf('workshop/aaa'),
        lessThan(body.indexOf('workshop/zzz')),
      );
    });

    test('reads an absent file as no records', () async {
      expect(await readBackupRecords(tmp.path), isEmpty);
    });

    test('reads a corrupt file as no records', () async {
      File(p.join(tmp.path, backupRecordsName)).writeAsStringSync('{ not json');

      expect(await readBackupRecords(tmp.path), isEmpty);
    });

    test('leaves out wallpapers with nothing recorded', () async {
      await writeBackupRecords(tmp.path, <String, BackupRecord>{
        '793602574': const BackupRecord(),
      });

      expect(
        File(p.join(tmp.path, backupRecordsName)).readAsStringSync(),
        isNot(contains('793602574')),
      );
    });
  });
}
