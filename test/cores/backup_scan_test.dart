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

  group('workshopVersions', () {
    Future<String> useAcf(String content, {required bool setting}) async {
      final File file = File(p.join(tmp.path, 'appworkshop_431960.acf'))
        ..writeAsStringSync(content);
      SharedPreferences.setMockInitialValues(<String, Object>{
        AppKeys.useAcfInfo: setting,
      });
      await StorageUtil.init();
      return file.path;
    }

    // useAcfInfo governs the grid's sort column. Letting it switch off update
    // detection would report every backed-up Workshop wallpaper as current.
    test('reads manifests even when the acf display setting is off', () async {
      final String acfPath = await useAcf(acf, setting: false);

      final ({Map<String, String> byId, bool acfRead}) result =
          await workshopVersions(acfPath);

      expect(result.acfRead, isTrue);
      expect(result.byId, <String, String>{'793602574': '6791066680065157913'});
    });

    test('reports the acf unread when no path is set', () async {
      final ({Map<String, String> byId, bool acfRead}) result =
          await workshopVersions(null);

      expect(result.acfRead, isFalse);
      expect(result.byId, isEmpty);
    });

    // Unread and empty are different answers: one warns, the other does not.
    test('reports the acf unread when it will not parse', () async {
      final String acfPath = await useAcf('"AppWorkshop"\n{\n', setting: true);

      expect((await workshopVersions(acfPath)).acfRead, isFalse);
    });

    // The parser returns an empty map rather than throwing when the file is not
    // an ACF at all, so the catch above never sees these. Steam killed
    // mid-write leaves exactly the first one.
    test('reports the acf unread when it holds nothing to read', () async {
      for (final String content in <String>['', 'not an acf at all']) {
        final String acfPath = await useAcf(content, setting: true);

        expect(
          (await workshopVersions(acfPath)).acfRead,
          isFalse,
          reason: 'content: "$content"',
        );
      }
    });

    // A subscription-free library is readable and empty, which is not a warning.
    test('reports the acf read when nothing is installed', () async {
      final String acfPath = await useAcf(
        '"AppWorkshop"\n{\n  "WorkshopItemsInstalled"\n  {\n  }\n}\n',
        setting: true,
      );

      final ({Map<String, String> byId, bool acfRead}) result =
          await workshopVersions(acfPath);

      expect(result.acfRead, isTrue);
      expect(result.byId, isEmpty);
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

  group('scanBackup', () {
    late Directory liveWorkshop;
    late Directory liveMyProjects;
    late Directory backupRoot;

    setUp(() {
      liveWorkshop = library(p.join('live', '431960'));
      liveMyProjects = library(p.join('live', 'myprojects'));
      backupRoot = library('backup');
    });

    // Spelled out rather than asked of the production code, so the two folder
    // names under the root are what the test pins.
    Directory backupWorkshop() => library(p.join('backup', '431960'));
    Directory backupMyProjects() =>
        library(p.join('backup', 'wallpaper_engine', 'projects', 'myprojects'));

    Future<BackupScan> scan({String? root, String? acfPath}) => scanBackup(
      backupRoot: root,
      liveWorkshopPath: liveWorkshop.path,
      liveMyProjectsPath: liveMyProjects.path,
      acfPath: acfPath,
    );

    // AC 2.
    test('with no root every live wallpaper is not backed up', () async {
      wallpaper(liveWorkshop, '793602574');
      wallpaper(liveMyProjects, 'alpha');

      final BackupScan result = await scan();

      expect(result.cards, <BackupCard, BackupState>{
        const BackupCard(WallpaperLibrary.workshop, '793602574'):
            BackupState.notBackedUp,
        const BackupCard(WallpaperLibrary.myProjects, 'alpha'):
            BackupState.notBackedUp,
      });
      expect(result.reconcile, isEmpty);
    });

    test('finds both backup libraries under the root', () async {
      wallpaper(liveWorkshop, '793602574');
      wallpaper(liveMyProjects, 'alpha');
      wallpaper(backupWorkshop(), '793602574');
      wallpaper(backupMyProjects(), 'alpha');

      final BackupScan result = await scan(root: backupRoot.path);

      expect(result.cards, hasLength(2));
      expect(result.cards.values, everyElement(BackupState.synced));
    });

    // The case the whole tab exists for: Steam removed a delisted item and only
    // the backup still has it.
    test('a name left only in the backup is vanished', () async {
      wallpaper(backupWorkshop(), '793602574');

      final BackupScan result = await scan(root: backupRoot.path);

      expect(result.cards, <BackupCard, BackupState>{
        const BackupCard(WallpaperLibrary.workshop, '793602574'):
            BackupState.vanished,
      });
      expect(result.reconcile, isEmpty);
    });

    // The unsubscribed packed original still sitting in the backup, with the
    // extraction live in myprojects.
    test('an orphan backup copy goes to reconcile, not the grid', () async {
      wallpaper(liveMyProjects, '793602574');
      wallpaper(backupWorkshop(), '793602574');
      wallpaper(backupMyProjects(), '793602574');

      final BackupScan result = await scan(root: backupRoot.path);

      expect(result.cards, isEmpty);
      expect(result.reconcile.single.name, '793602574');
      expect(result.reconcile.single.orphans, <WallpaperLibrary>{
        WallpaperLibrary.workshop,
      });
    });

    test('a republished workshop item reads as an update', () async {
      wallpaper(liveWorkshop, '793602574');
      wallpaper(backupWorkshop(), '793602574');
      await writeBackupRecords(backupRoot.path, <String, BackupRecord>{
        'workshop/793602574': const BackupRecord(backedUpVersion: 'older'),
      });
      final File acfFile = File(p.join(tmp.path, 'appworkshop_431960.acf'))
        ..writeAsStringSync(acf);

      final BackupScan result = await scan(
        root: backupRoot.path,
        acfPath: acfFile.path,
      );

      expect(result.acfRead, isTrue);
      expect(
        result.cards[const BackupCard(WallpaperLibrary.workshop, '793602574')],
        BackupState.updateAvailable,
      );
    });

    test('an edited myprojects wallpaper reads as an update', () async {
      File(
        p.join(wallpaper(liveMyProjects, 'alpha').path, 'project.json'),
      ).writeAsStringSync('{}');
      wallpaper(backupMyProjects(), 'alpha');
      await writeBackupRecords(backupRoot.path, <String, BackupRecord>{
        'myprojects/alpha': const BackupRecord(backedUpVersion: 'older'),
      });

      final BackupScan result = await scan(root: backupRoot.path);

      expect(
        result.cards[const BackupCard(WallpaperLibrary.myProjects, 'alpha')],
        BackupState.updateAvailable,
      );
    });

    // False is what puts the banner on the tab. Without the flag an unreadable
    // ACF and a library with nothing to update look the same.
    test('reports the acf unread when there is no path for it', () async {
      expect((await scan(root: backupRoot.path)).acfRead, isFalse);
    });

    // Each of the three reads as a confident wrong answer when it is not there:
    // a missing live library turns every backup folder into a vanished card,
    // and a missing backup root empties the vanished list entirely.
    test('reports each required folder that is not on disk', () async {
      final String gone = p.join(tmp.path, 'not-plugged-in');

      expect(
        (await scanBackup(
          backupRoot: gone,
          liveWorkshopPath: liveWorkshop.path,
          liveMyProjectsPath: liveMyProjects.path,
          acfPath: null,
        )).missing,
        <BackupFolder>{BackupFolder.backupRoot},
      );
      expect(
        (await scanBackup(
          backupRoot: backupRoot.path,
          liveWorkshopPath: gone,
          liveMyProjectsPath: liveMyProjects.path,
          acfPath: null,
        )).missing,
        <BackupFolder>{BackupFolder.liveWorkshop},
      );
      expect(
        (await scanBackup(
          backupRoot: backupRoot.path,
          liveWorkshopPath: liveWorkshop.path,
          liveMyProjectsPath: gone,
          acfPath: null,
        )).missing,
        <BackupFolder>{BackupFolder.liveMyProjects},
      );
    });

    // Unset is the same failure as gone. This is the shape that produced 1296
    // vanished against the real library on 2026-08-05: the live myprojects path
    // reached the scan empty and every backup folder there read as lost.
    test('an unset live path counts as missing', () async {
      final BackupScan result = await scanBackup(
        backupRoot: backupRoot.path,
        liveWorkshopPath: liveWorkshop.path,
        liveMyProjectsPath: null,
        acfPath: null,
      );

      expect(result.missing, <BackupFolder>{BackupFolder.liveMyProjects});
    });

    test('nothing is missing when all three are there', () async {
      expect((await scan(root: backupRoot.path)).missing, isEmpty);
    });
  });
}
