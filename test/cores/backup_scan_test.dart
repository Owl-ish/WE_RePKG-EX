import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:we_repkg/constants/keys.dart';
import 'package:we_repkg/cores/backup.dart';
import 'package:we_repkg/utils/backup_diff.dart';
import 'package:we_repkg/utils/storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await StorageUtil.init();
    tmp = Directory.systemTemp.createTempSync('we_repkg_backup');
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  Directory library(String name) =>
      Directory(p.join(tmp.path, name))..createSync(recursive: true);

  Directory wallpaper(Directory lib, String id) =>
      Directory(p.join(lib.path, id))..createSync();

  // AC 2. With no backup root the scan has nothing to look in, so every card
  // falls out of the differ as not backed up rather than as an error.
  group('with no backup root', () {
    test('the library listing is empty', () async {
      expect(await listFolderNames(null), isEmpty);
    });

    test('the version listing is empty', () async {
      expect(await folderVersions(null), isEmpty);
    });

    test('the records read as none', () async {
      expect(await readBackupRecords(null), isEmpty);
    });

    test('writing records is a no-op rather than a crash', () async {
      await writeBackupRecords(null, <String, BackupRecord>{
        'workshop/793602574': const BackupRecord(backedUpVersion: 'manifest-1'),
      });
    });
  });

  group('listFolderNames', () {
    test('returns the folder names and ignores loose files', () async {
      final Directory lib = library('431960');
      wallpaper(lib, '793602574');
      wallpaper(lib, '833227004');
      File(p.join(lib.path, 'readme.txt')).writeAsStringSync('x');

      expect(await listFolderNames(lib.path), <String>{
        '793602574',
        '833227004',
      });
    });
  });

  group('folderVersions', () {
    test('gives each folder a token from its top-level files', () async {
      final Directory lib = library('myprojects');
      File(
        p.join(wallpaper(lib, 'alpha').path, 'project.json'),
      ).writeAsStringSync('{}');
      File(
        p.join(wallpaper(lib, 'beta').path, 'project.json'),
      ).writeAsStringSync('{"title":"beta"}');

      final Map<String, String> versions = await folderVersions(lib.path);

      expect(versions.keys, <String>{'alpha', 'beta'});
      expect(versions['alpha'], isNot(versions['beta']));
    });

    // The accepted blind spot, pinned so it stays a decision. Making this
    // recursive would cost a stat walk over every asset in the library.
    test('an asset changed in a subfolder does not move the token', () async {
      final Directory lib = library('myprojects');
      final Directory folder = wallpaper(lib, 'alpha');
      File(p.join(folder.path, 'project.json')).writeAsStringSync('{}');
      final Directory materials = Directory(p.join(folder.path, 'materials'))
        ..createSync();
      final File asset = File(p.join(materials.path, 'texture.tex'))
        ..writeAsStringSync('before');

      final String? before = (await folderVersions(lib.path))['alpha'];
      asset.writeAsStringSync('after, and a good deal longer');

      expect((await folderVersions(lib.path))['alpha'], before);
    });

    test('a folder with no top-level files is left out', () async {
      final Directory lib = library('myprojects');
      Directory(p.join(wallpaper(lib, 'empty').path, 'materials')).createSync();

      expect(await folderVersions(lib.path), isEmpty);
    });
  });

  group('workshopVersions', () {
    const String acf = '''
"AppWorkshop"
{
  "WorkshopItemsInstalled"
  {
    "793602574"
    {
      "size"  "100"
      "timeupdated"  "1700000000"
      "manifest"  "6791066680065157913"
    }
  }
}
''';

    Future<void> useAcf(String content, {required bool setting}) async {
      final File file = File(p.join(tmp.path, 'appworkshop_431960.acf'))
        ..writeAsStringSync(content);
      SharedPreferences.setMockInitialValues(<String, Object>{
        AppKeys.acfPath: file.path,
        AppKeys.useAcfInfo: setting,
      });
      await StorageUtil.init();
    }

    // useAcfInfo governs the grid's sort column. Letting it switch off update
    // detection would report every backed-up Workshop wallpaper as current.
    test('reads manifests even when the acf display setting is off', () async {
      await useAcf(acf, setting: false);

      final ({Map<String, String> byId, bool acfRead}) result =
          await workshopVersions();

      expect(result.acfRead, isTrue);
      expect(result.byId, <String, String>{'793602574': '6791066680065157913'});
    });

    test('reports the acf unread when no path is set', () async {
      final ({Map<String, String> byId, bool acfRead}) result =
          await workshopVersions();

      expect(result.acfRead, isFalse);
      expect(result.byId, isEmpty);
    });

    // Unread and empty are different answers: one warns, the other does not.
    test('reports the acf unread when it will not parse', () async {
      await useAcf('"AppWorkshop"\n{\n', setting: true);

      expect((await workshopVersions()).acfRead, isFalse);
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

    test('reads an absent file as no records', () async {
      expect(await readBackupRecords(tmp.path), isEmpty);
    });

    // A corrupt file must not take the tab down with it. Losing the dismissals
    // re-offers some updates, which beats showing nothing at all.
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
