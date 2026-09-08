import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:we_repkg/constants/keys.dart';
import 'package:we_repkg/constants/strings.dart';
import 'package:we_repkg/cores/backup.dart';
import 'package:we_repkg/constants/wallpaper_files.dart';
import 'package:we_repkg/utils/backup_diff.dart';
import 'package:we_repkg/utils/storage.dart';
import 'package:we_repkg/utils/wallpaper_junk.dart';

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

  // With no backup root the scan has nothing to compare, so live cards remain
  // visible as not backed up rather than failing the scan.
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
      wallpaper(lib, '${WallpaperFiles.rescueStagePrefix}123-abc');
      wallpaper(lib, '${WallpaperFiles.restoreStagePrefix}123-abc');
      wallpaper(lib, '${WallpaperFiles.emptyBackupStagePrefix}123-abc');
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

    // The lightweight MyProjects token intentionally watches top-level files
    // only; recursive mirror equality is handled by the backup comparison.
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

  group('copyStandings', () {
    late Directory live;
    late Directory backup;
    setUp(() {
      live = library('live');
      backup = library('backup');
    });

    Directory pair(String name, {String liveBody = 'x', String? backupBody}) {
      File(
        p.join(wallpaper(live, name).path, 'project.json'),
      ).writeAsStringSync(liveBody);
      final Directory folder = wallpaper(backup, name);
      if (backupBody != null) {
        File(p.join(folder.path, 'project.json')).writeAsStringSync(backupBody);
      }
      return folder;
    }

    Future<Map<String, CopyStanding>> run({
      required Set<String> shared,
      Set<String>? compare,
      bool recursive = true,
    }) => copyStandings(
      livePath: live.path,
      backupPath: backup.path,
      recursive: recursive,
      shared: shared,
      compare: compare ?? shared,
    );

    // Comparing a folder with no counterpart buys nothing, and the walk is the
    // expensive half of the whole scan.
    test('only the named folders are compared', () async {
      pair('alpha', backupBody: 'x');
      pair('beta', backupBody: 'x');

      expect((await run(shared: <String>{'alpha'})).keys, <String>{'alpha'});
    });

    test('nothing shared means nothing is opened', () async {
      pair('alpha', backupBody: 'x');

      expect(await run(shared: const <String>{}), isEmpty);
    });

    // The split between the libraries: Workshop is packed so its payload sits
    // at the top level, myprojects is usually unpacked so its edits do not.
    test('a subfolder counts only when the walk is recursive', () async {
      final Directory backupFolder = pair('alpha', backupBody: 'x');
      for (final Directory folder in <Directory>[
        Directory(p.join(live.path, 'alpha')),
        backupFolder,
      ]) {
        Directory(p.join(folder.path, 'materials')).createSync();
        File(
          p.join(folder.path, 'materials', 'sky.tex'),
        ).writeAsStringSync('same');
      }
      File(
        p.join(live.path, 'alpha', 'materials', 'sky.tex'),
      ).writeAsStringSync('a much larger texture');

      expect(
        (await run(shared: <String>{'alpha'}))['alpha'],
        CopyStanding.behind,
      );
      expect(
        (await run(shared: <String>{'alpha'}, recursive: false))['alpha'],
        CopyStanding.covers,
        reason: 'the top level is identical, so a shallow walk sees no change',
      );
    });

    // Copying rewrites every timestamp, so a comparison that noticed would
    // refuse to recognise any hand-made backup as a backup.
    test('a copy made at a different time still covers', () async {
      final Directory backupFolder = pair(
        'alpha',
        liveBody: 'same',
        backupBody: 'same',
      );
      File(
        p.join(backupFolder.path, 'project.json'),
      ).setLastModifiedSync(DateTime(2001));

      expect(
        (await run(shared: <String>{'alpha'}))['alpha'],
        CopyStanding.covers,
      );
    });

    test('an extra meaningful backup file makes the mirror stale', () async {
      final Directory backupFolder = pair(
        'alpha',
        liveBody: 'same',
        backupBody: 'same',
      );
      File(p.join(backupFolder.path, 'legacy.txt')).writeAsStringSync('old');

      expect(
        (await run(shared: <String>{'alpha'}))['alpha'],
        CopyStanding.behind,
      );
    });

    // Emptiness is judged separately from whichever folders this pass compares.
    test('an uncompared empty folder is left to the junk scan', () async {
      pair('alpha');

      final Map<String, CopyStanding> standings = await run(
        shared: <String>{'alpha'},
        compare: const <String>{},
      );

      expect(standings, isEmpty);
    });

    test('an uncompared shader-only folder is left to the junk scan', () async {
      final Directory backupFolder = pair('alpha');
      File(p.join(backupFolder.path, 'shaders', 'blobsSM40', 'cache.bin'))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('rebuilt');

      final Map<String, CopyStanding> standings = await run(
        shared: <String>{'alpha'},
        compare: const <String>{},
      );

      expect(standings, isEmpty);
    });

    // Outside compare, a folder with content is left unjudged rather than
    // guessed at, so the record can answer for it.
    test('an uncompared folder with content gets no verdict', () async {
      pair('alpha', backupBody: 'x');

      expect(
        await run(shared: <String>{'alpha'}, compare: const <String>{}),
        isEmpty,
      );
    });

    test('an uncompared folder that disappears gets no verdict', () async {
      expect(
        await run(shared: <String>{'gone'}, compare: const <String>{}),
        isEmpty,
      );
    });

    test('an unset or absent folder gives nothing', () async {
      expect(
        await copyStandings(
          livePath: null,
          backupPath: backup.path,
          recursive: true,
          shared: <String>{'alpha'},
          compare: <String>{'alpha'},
        ),
        isEmpty,
      );
      expect(
        await copyStandings(
          livePath: live.path,
          backupPath: p.join(tmp.path, 'nope'),
          recursive: true,
          shared: <String>{'alpha'},
          compare: <String>{'alpha'},
        ),
        isEmpty,
      );
    });

    test('detail comparison reports exact file changes on demand', () async {
      final Directory liveFolder = wallpaper(live, 'alpha');
      final Directory backupFolder = wallpaper(backup, 'alpha');
      File(p.join(liveFolder.path, 'same.txt')).writeAsStringSync('same');
      File(p.join(backupFolder.path, 'same.txt')).writeAsStringSync('same');
      File(p.join(liveFolder.path, 'changed.txt')).writeAsStringSync('newer');
      File(p.join(backupFolder.path, 'changed.txt')).writeAsStringSync('old');
      File(p.join(liveFolder.path, 'same-size.txt')).writeAsStringSync('abc');
      File(p.join(backupFolder.path, 'same-size.txt')).writeAsStringSync('xyz');
      File(p.join(liveFolder.path, 'materials', 'new.tex'))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('new');
      File(p.join(backupFolder.path, 'legacy.txt')).writeAsStringSync('old');
      for (final Directory folder in <Directory>[liveFolder, backupFolder]) {
        File(p.join(folder.path, 'shaders', 'blobsSM40', 'cache.bin'))
          ..parent.createSync(recursive: true)
          ..writeAsStringSync(folder == liveFolder ? 'live cache' : 'backup');
      }

      final BackupFileChanges? changes = await compareBackupFileChanges(
        liveFolder: liveFolder.path,
        backupFolder: backupFolder.path,
      );

      expect(changes, isNotNull);
      expect(changes!.modified, <String>['changed.txt', 'same-size.txt']);
      expect(changes.onlyLive, <String>[p.join('materials', 'new.tex')]);
      expect(changes.onlyBackup, <String>['legacy.txt']);
    });

    test('detailed comparison retains files proven identical', () async {
      final Directory first = wallpaper(live, 'matching');
      final Directory second = wallpaper(backup, 'matching');
      for (final Directory folder in <Directory>[first, second]) {
        File(p.join(folder.path, 'project.json')).writeAsStringSync('same');
        File(
          p.join(folder.path, 'scene.pkg'),
        ).writeAsStringSync('same package');
      }
      File(p.join(first.path, 'changed.txt')).writeAsStringSync('left');
      File(p.join(second.path, 'changed.txt')).writeAsStringSync('rift');

      final FolderFileComparison? comparison = await compareFolderFilesDetailed(
        firstFolder: first.path,
        secondFolder: second.path,
      );

      expect(comparison, isNotNull);
      expect(comparison!.matching, <String>['project.json', 'scene.pkg']);
      expect(comparison.changes.modified, <String>['changed.txt']);
      expect(comparison.changes.onlyFirst, isEmpty);
      expect(comparison.changes.onlySecond, isEmpty);
    });

    test('JSON detail comparison works for any relative JSON file', () async {
      final Directory liveFolder = wallpaper(live, 'json-live');
      final Directory backupFolder = wallpaper(backup, 'json-live');
      final String jsonPath = p.join('effects', 'settings.json');
      File(p.join(backupFolder.path, jsonPath))
        ..createSync(recursive: true)
        ..writeAsStringSync(
          '{"title":"Old","type":"scene","tags":["Anime"],'
          '"nested":{"speed":1,"keep":null},"removed":"gone"}',
        );
      File(p.join(liveFolder.path, jsonPath))
        ..createSync(recursive: true)
        ..writeAsStringSync(
          '{"title":"New","type":"scene","tags":["Anime","Game"],'
          '"nested":{"speed":2,"keep":null},"added":true}',
        );

      final List<BackupJsonFieldChange>? changes =
          await compareBackupJsonChanges(
            beforeFolder: backupFolder.path,
            afterFolder: liveFolder.path,
            relativePath: jsonPath,
          );

      expect(changes, isNotNull);
      final Map<String, BackupJsonFieldChange> byField =
          <String, BackupJsonFieldChange>{
            for (final BackupJsonFieldChange change in changes!)
              change.field: change,
          };
      expect(
        byField.keys,
        containsAll(<String>[
          r'$.title',
          r'$.tags[1]',
          r'$.nested.speed',
          r'$.added',
          r'$.removed',
        ]),
      );
      expect(byField[r'$.title']!.before, 'Old');
      expect(byField[r'$.title']!.after, 'New');
      expect(byField[r'$.nested.speed']!.before, 1);
      expect(byField[r'$.nested.speed']!.after, 2);
      expect(byField[r'$.tags[1]']!.beforePresent, isFalse);
      expect(byField[r'$.tags[1]']!.after, 'Game');
      expect(byField[r'$.added']!.beforePresent, isFalse);
      expect(byField[r'$.added']!.after, isTrue);
      expect(byField[r'$.removed']!.before, 'gone');
      expect(byField[r'$.removed']!.afterPresent, isFalse);
      expect(byField.containsKey(r'$.nested.keep'), isFalse);
      expect(byField.containsKey(r'$.type'), isFalse);
    });

    test(
      'detail comparison returns null when a folder cannot be read',
      () async {
        final Directory liveFolder = wallpaper(live, 'alpha');
        File(p.join(liveFolder.path, 'project.json')).writeAsStringSync('x');

        expect(
          await compareBackupFileChanges(
            liveFolder: liveFolder.path,
            backupFolder: p.join(backup.path, 'missing'),
          ),
          isNull,
        );
      },
    );

    // Cross enough batch boundaries to prove every requested folder contributes
    // a result; dropping one could falsely leave a card looking current.
    test('every folder survives the batching', () async {
      final Set<String> names = <String>{
        for (int i = 0; i < 60; i++) 'wallpaper-$i',
      };
      for (final String name in names) {
        pair(name, backupBody: 'x');
      }

      final Map<String, CopyStanding> standings = await run(shared: names);

      expect(standings, hasLength(60));
      expect(standings.values, everyElement(CopyStanding.covers));
    });
  });

  group('readCardFaces', () {
    void project(Directory folder, String body) =>
        File(p.join(folder.path, 'project.json')).writeAsStringSync(body);

    // Exercise both libraries because each vanished card must read from its own
    // backup tree rather than borrowing the other library's copy.
    test(
      'reads live folders, and the backup copy for a vanished card',
      () async {
        final Directory liveW = library('live-workshop');
        final Directory liveM = library('live-myprojects');
        final Directory backupW = library(
          p.join('backup', AppStrings.backupWorkshopDir),
        );
        final Directory backupM = library(
          p.join('backup', AppStrings.backupProjectDir),
        );
        project(
          wallpaper(liveW, '793602574'),
          '{"title":"Alive","preview":"a.jpg"}',
        );
        project(
          wallpaper(backupW, '833227004'),
          '{"title":"Gone","preview":"g.jpg"}',
        );
        project(wallpaper(backupM, 'beta'), '{"title":"Gone Beta"}');
        // Both names also sit somewhere they must not be read from: one in its
        // own live library, one in the other library's backup tree.
        project(
          wallpaper(liveW, '833227004'),
          '{"title":"Wrong","preview":"w.jpg"}',
        );
        project(wallpaper(backupW, 'beta'), '{"title":"Wrong Beta"}');

        final List<BackupScanProgress> progress = <BackupScanProgress>[];
        final Map<BackupCard, CardFace> faces = await readCardFaces(
          backupRoot: p.join(tmp.path, 'backup'),
          liveWorkshopPath: liveW.path,
          liveMyProjectsPath: liveM.path,
          cards: <BackupCard, BackupState>{
            const BackupCard(WallpaperLibrary.workshop, '793602574'):
                BackupState.synced,
            const BackupCard(WallpaperLibrary.workshop, '833227004'):
                BackupState.vanished,
            const BackupCard(WallpaperLibrary.myProjects, 'beta'):
                BackupState.vanished,
          },
          onProgress: progress.add,
        );

        expect(
          faces[const BackupCard(WallpaperLibrary.workshop, '793602574')]!
              .title,
          'Alive',
        );
        final CardFace gone =
            faces[const BackupCard(WallpaperLibrary.workshop, '833227004')]!;
        expect(gone.title, 'Gone');
        expect(gone.preview, p.join(backupW.path, '833227004', 'g.jpg'));
        expect(
          faces[const BackupCard(WallpaperLibrary.myProjects, 'beta')]!.title,
          'Gone Beta',
        );
        expect(progress.last.phase, BackupScanPhase.preparing);
        expect(progress.last.done, progress.last.total);
        expect(
          progress.where(
            (value) =>
                value.phase == BackupScanPhase.details &&
                value.done == value.total,
          ),
          isEmpty,
        );
      },
    );

    // Common on a self-made wallpaper, and then the folder name is all the grid
    // has left to call it by.
    test('a wallpaper with no title falls back to the folder name', () async {
      final Directory liveM = library('live-myprojects');
      project(wallpaper(liveM, 'alpha'), '{"preview":"a.jpg"}');

      final Map<BackupCard, CardFace> faces = await readCardFaces(
        backupRoot: null,
        liveWorkshopPath: null,
        liveMyProjectsPath: liveM.path,
        cards: <BackupCard, BackupState>{
          const BackupCard(WallpaperLibrary.myProjects, 'alpha'):
              BackupState.synced,
        },
      );

      expect(
        faces[const BackupCard(WallpaperLibrary.myProjects, 'alpha')]!.title,
        'alpha',
      );
    });

    // A folder the app cannot read still occupies the backup. Dropping it here
    // would be the one place the tab lies about what is on disk.
    test(
      'a missing or broken project.json leaves the card without a face',
      () async {
        final Directory liveM = library('live-myprojects');
        wallpaper(liveM, 'no-project');
        project(wallpaper(liveM, 'broken'), '{ not json');
        // A hand-made wallpaper with a number where the title belongs, which is
        // the case that drops a folder out of the extract grid entirely.
        project(wallpaper(liveM, 'numbered'), '{"title":7}');

        final Map<BackupCard, CardFace> faces = await readCardFaces(
          backupRoot: null,
          liveWorkshopPath: null,
          liveMyProjectsPath: liveM.path,
          cards: <BackupCard, BackupState>{
            for (final String name in <String>[
              'no-project',
              'broken',
              'numbered',
            ])
              BackupCard(WallpaperLibrary.myProjects, name): BackupState.synced,
          },
        );

        expect(faces, isEmpty);
      },
    );

    test('a wallpaper with no preview still gets its title', () async {
      final Directory liveM = library('live-myprojects');
      project(wallpaper(liveM, 'alpha'), '{"title":"Alpha"}');

      final Map<BackupCard, CardFace> faces = await readCardFaces(
        backupRoot: null,
        liveWorkshopPath: null,
        liveMyProjectsPath: liveM.path,
        cards: <BackupCard, BackupState>{
          const BackupCard(WallpaperLibrary.myProjects, 'alpha'):
              BackupState.synced,
        },
      );

      final CardFace face =
          faces[const BackupCard(WallpaperLibrary.myProjects, 'alpha')]!;
      expect(face.title, 'Alpha');
      expect(face.preview, isEmpty);
    });

    // The filter button is shared with the extract tab, so a card has to carry
    // the two fields it filters on, and the date its order goes by.
    test('a face carries the type, the rating and a date', () async {
      final Directory liveM = library('live-myprojects');
      project(
        wallpaper(liveM, 'alpha'),
        '{"title":"Alpha","type":"Scene","contentrating":"Mature"}',
      );

      final Map<BackupCard, CardFace> faces = await readCardFaces(
        backupRoot: null,
        liveWorkshopPath: null,
        liveMyProjectsPath: liveM.path,
        cards: <BackupCard, BackupState>{
          const BackupCard(WallpaperLibrary.myProjects, 'alpha'):
              BackupState.synced,
        },
      );

      final CardFace face =
          faces[const BackupCard(WallpaperLibrary.myProjects, 'alpha')]!;
      // Lowercased on the way in, the way the extract scan does it, or the
      // filter would have to know about both spellings.
      expect(face.type, 'scene');
      expect(face.rating, 'mature');
      // The project.json's own timestamp, not the folder's and not the time of
      // the scan: either of those would order the grid by nothing at all.
      expect(
        face.modified,
        File(p.join(liveM.path, 'alpha', 'project.json')).statSync().changed,
      );
    });

    // Reading the details is the rest of the wait after the counts are up, and
    // it was the half of it with nothing to watch.
    test('reading the details counts its way to the end', () async {
      final Directory liveM = library('live-myprojects');
      final List<String> names = <String>[for (int i = 0; i < 30; i++) 'w$i'];
      for (final String name in names) {
        project(wallpaper(liveM, name), '{"title":"$name"}');
      }
      final List<BackupScanProgress> seen = <BackupScanProgress>[];

      await readCardFaces(
        backupRoot: null,
        liveWorkshopPath: null,
        liveMyProjectsPath: liveM.path,
        cards: <BackupCard, BackupState>{
          for (final String name in names)
            BackupCard(WallpaperLibrary.myProjects, name): BackupState.synced,
        },
        onProgress: seen.add,
      );

      expect(
        seen.map((BackupScanProgress p) => p.phase),
        containsAllInOrder(<BackupScanPhase>[
          BackupScanPhase.details,
          BackupScanPhase.preparing,
        ]),
      );
      expect(seen.first.done, 0, reason: 'the line starts before the reading');
      expect(
        seen.last,
        (phase: BackupScanPhase.preparing, done: 30, total: 30),
        reason: 'the full count belongs to the uncounted preparation handoff',
      );
    });
  });

  group('reconcileFolders', () {
    ({String? backup, String? live}) foldersFor({
      required bool liveWorkshop,
      required bool liveMyProjects,
      required bool backupWorkshop,
      required bool backupMyProjects,
    }) => reconcileFolders(
      entry: ReconcileEntry(
        name: 'alpha',
        reason: BackupReconcileReason.duplicateLiveCopies,
        states: <WallpaperLibrary, BackupState>{
          if (liveWorkshop) WallpaperLibrary.workshop: BackupState.synced,
          if (liveMyProjects)
            WallpaperLibrary.myProjects: BackupState.notBackedUp,
        },
        backupWorkshop: backupWorkshop,
        backupMyProjects: backupMyProjects,
      ),
      backupRoot: r'C:\backup',
      liveWorkshopPath: r'C:\live\431960',
      liveMyProjectsPath: r'C:\live\myprojects',
    );

    final String liveW = p.join(r'C:\live\431960', 'alpha');
    final String liveM = p.join(r'C:\live\myprojects', 'alpha');
    final String backupW = p.join(r'C:\backup', '431960', 'alpha');
    final String backupM = p.join(
      r'C:\backup',
      'wallpaper_engine',
      'projects',
      'myprojects',
      'alpha',
    );

    // The myprojects copy is the one the author edits, so where there is a
    // choice it is the one the details and the folder actions land on.
    test('prefers myprojects on both sides', () {
      final ({String? backup, String? live}) folders = foldersFor(
        liveWorkshop: true,
        liveMyProjects: true,
        backupWorkshop: true,
        backupMyProjects: true,
      );

      expect(folders.live, liveM);
      expect(folders.backup, backupM);
    });

    // The half a preference alone gets wrong: with no myprojects copy on a
    // side, that side falls through to the Workshop one rather than offering a
    // path that is not there.
    test('falls through to workshop where myprojects has no copy', () {
      final ({String? backup, String? live}) folders = foldersFor(
        liveWorkshop: true,
        liveMyProjects: false,
        backupWorkshop: true,
        backupMyProjects: false,
      );

      expect(folders.live, liveW);
      expect(folders.backup, backupW);
    });

    test('a folder that is not there is not offered', () {
      final ({String? backup, String? live}) folders = foldersFor(
        liveWorkshop: false,
        liveMyProjects: true,
        backupWorkshop: false,
        backupMyProjects: false,
      );

      expect(folders.live, liveM);
      expect(folders.backup, isNull);
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

    // The file lives in the user's backup and they open it by hand. Sorted as
    // well as indented, so one changed wallpaper does not reshuffle the file.
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

    Future<BackupScan> scan({
      String? root,
      String? acfPath,
      void Function(BackupScanProgress)? onProgress,
    }) => scanBackup(
      backupRoot: root,
      liveWorkshopPath: liveWorkshop.path,
      liveMyProjectsPath: liveMyProjects.path,
      acfPath: acfPath,
      onProgress: onProgress,
    );

    /// A wallpaper in a library, with a file in it so the folder is not empty.
    Directory filled(Directory lib, String id, [String body = '{}']) {
      final Directory folder = wallpaper(lib, id);
      File(p.join(folder.path, 'project.json')).writeAsStringSync(body);
      return folder;
    }

    /// What Steam leaves behind: the folder, holding only the cache Wallpaper
    /// Engine wrote into it.
    Directory husk(Directory lib, String id) {
      final Directory folder = wallpaper(lib, id);
      File(p.join(folder.path, 'shaders', 'blobsSM40', 'cache.dxs'))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('rebuilt');
      return folder;
    }

    test('with no root every live wallpaper is not backed up', () async {
      filled(liveWorkshop, '793602574');
      filled(liveMyProjects, 'alpha');

      final BackupScan result = await scan();

      expect(result.cards, <BackupCard, BackupState>{
        const BackupCard(WallpaperLibrary.workshop, '793602574'):
            BackupState.notBackedUp,
        const BackupCard(WallpaperLibrary.myProjects, 'alpha'):
            BackupState.notBackedUp,
      });
      expect(result.reconcile, isEmpty);
    });

    test('stale wrong-side backup plans update and sync', () async {
      filled(liveMyProjects, 'alpha', 'live payload');
      filled(backupWorkshop(), 'alpha', 'old');

      final BackupScan result = await scan(root: backupRoot.path);
      const BackupCard card = BackupCard(WallpaperLibrary.myProjects, 'alpha');

      expect(result.cards[card], BackupState.updateAvailable);
      expect(
        result.updates[card],
        const BackupUpdatePlan(
          updateContent: true,
          sync: BackupSyncPlan(
            kind: BackupSyncKind.relocate,
            from: WallpaperLibrary.workshop,
            to: WallpaperLibrary.myProjects,
          ),
        ),
      );
    });

    test('equivalent duplicate backups are sent to update/sync', () async {
      filled(liveWorkshop, '793602574', 'same');
      filled(backupWorkshop(), '793602574', 'same');
      filled(backupMyProjects(), '793602574', 'same');

      final BackupScan result = await scan(root: backupRoot.path);

      expect(
        result.cards[const BackupCard(WallpaperLibrary.workshop, '793602574')],
        BackupState.updateAvailable,
      );
      expect(result.reconcile, isEmpty);
    });

    test('different duplicate backups remain reconcile', () async {
      filled(liveWorkshop, '793602574', 'same');
      filled(backupWorkshop(), '793602574', 'same');
      filled(backupMyProjects(), '793602574', 'different');

      final BackupScan result = await scan(root: backupRoot.path);

      expect(result.cards, isEmpty);
      expect(result.reconcile, hasLength(1));
    });

    // Steam can leave shader-cache-only folders after removing an unsubscribed
    // wallpaper; they are cleanup residue rather than wallpaper content.
    group('a folder Steam left behind', () {
      test('appears under Empty/Junk in either live library', () async {
        filled(liveWorkshop, '793602574');
        husk(liveWorkshop, '3776838872');
        husk(liveMyProjects, 'abandoned');

        final BackupScan result = await scan(root: backupRoot.path);

        expect(
          result.cards[const BackupCard(
            WallpaperLibrary.workshop,
            '3776838872',
          )],
          BackupState.emptyBackup,
        );
        expect(
          result.cards[const BackupCard(
            WallpaperLibrary.myProjects,
            'abandoned',
          )],
          BackupState.emptyBackup,
        );
      });

      // A valid backup still protects the name even when the live side is only
      // junk; cleanup classification must not erase the surviving backup card.
      test('keeps its card when the backup still holds it', () async {
        husk(liveWorkshop, '3776838872');
        filled(backupWorkshop(), '3776838872');

        final BackupScan result = await scan(root: backupRoot.path);

        expect(
          result.cards[const BackupCard(
            WallpaperLibrary.workshop,
            '3776838872',
          )],
          BackupState.emptyBackup,
        );
        expect(result.junk['workshop/3776838872'], (
          live: true,
          backup: false,
          kind: WallpaperJunkKind.shaderCacheOnly,
        ));
      });

      // Keep junk detection narrow: meaningful nested content can still be
      // recoverable even when the top level is not loadable as a wallpaper.
      test('a folder with content in a subfolder keeps its card', () async {
        final Directory nested = wallpaper(liveWorkshop, '3373795844');
        File(p.join(nested.path, '1110-5', 'clip.mp4'))
          ..parent.createSync(recursive: true)
          ..writeAsStringSync('8.7GB in spirit');

        final BackupScan result = await scan(root: backupRoot.path);

        expect(
          result.cards[const BackupCard(
            WallpaperLibrary.workshop,
            '3373795844',
          )],
          BackupState.notBackedUp,
        );
      });

      // The live Workshop folder is only junk, so the usable MyProjects backup
      // is the sole remaining copy and therefore reads as Vanished.
      test('a myprojects backup of the same name reads as vanished', () async {
        husk(liveWorkshop, '3776838872');
        filled(backupMyProjects(), '3776838872');

        final BackupScan result = await scan(root: backupRoot.path);

        expect(
          result.cards[const BackupCard(
            WallpaperLibrary.myProjects,
            '3776838872',
          )],
          BackupState.vanished,
        );
        expect(
          result.cards[const BackupCard(
            WallpaperLibrary.workshop,
            '3776838872',
          )],
          BackupState.emptyBackup,
        );
        expect(result.reconcile, isEmpty);
      });

      test('an empty live folder also appears under Empty/Junk', () async {
        wallpaper(liveWorkshop, 'empty');

        final BackupScan result = await scan(root: backupRoot.path);

        expect(
          result.cards[const BackupCard(WallpaperLibrary.workshop, 'empty')],
          BackupState.emptyBackup,
        );
        expect(result.presence['workshop/empty'], (live: true, backup: false));
      });

      test(
        'valid backups keep their status when they also have cache',
        () async {
          final Directory live = filled(liveMyProjects, 'alpha');
          final Directory backup = filled(backupMyProjects(), 'alpha');
          for (final Directory folder in <Directory>[live, backup]) {
            File(p.join(folder.path, 'shaders', 'blobsSM40', 'cache.bin'))
              ..createSync(recursive: true)
              ..writeAsStringSync('cache');
          }
          final Directory liveOnly = filled(liveMyProjects, 'beta');
          File(p.join(liveOnly.path, 'shaders', 'blobsSM40', 'cache.bin'))
            ..createSync(recursive: true)
            ..writeAsStringSync('cache');

          final BackupScan result = await scan(root: backupRoot.path);

          expect(
            result.cards[const BackupCard(
              WallpaperLibrary.myProjects,
              'alpha',
            )],
            BackupState.synced,
          );
          expect(result.presence['myprojects/alpha'], (
            live: true,
            backup: true,
          ));
          expect(
            result.cards[const BackupCard(WallpaperLibrary.myProjects, 'beta')],
            BackupState.notBackedUp,
          );
        },
      );
    });

    test('a missing Workshop ACF falls back to folder comparison', () async {
      filled(liveWorkshop, '793602574');
      filled(liveMyProjects, 'alpha');
      filled(backupWorkshop(), '793602574');
      filled(backupMyProjects(), 'alpha');

      final BackupScan result = await scan(root: backupRoot.path);

      expect(
        result.cards[const BackupCard(WallpaperLibrary.workshop, '793602574')],
        BackupState.synced,
      );
      expect(
        result.cards[const BackupCard(WallpaperLibrary.myProjects, 'alpha')],
        BackupState.synced,
      );
      expect(result.reconcile, isEmpty);
    });

    // Mirror comparisons can be long-running, so the scan must report both
    // its phase and counted progress instead of leaving the UI silent.
    test('the scan reports what it is doing and how far it has got', () async {
      for (int i = 0; i < 30; i++) {
        filled(liveMyProjects, 'wallpaper-$i');
        filled(backupMyProjects(), 'wallpaper-$i');
      }
      final List<BackupScanProgress> seen = <BackupScanProgress>[];

      await scan(root: backupRoot.path, onProgress: seen.add);

      expect(seen.first.phase, BackupScanPhase.reading);
      expect(
        seen.map((BackupScanProgress p) => p.phase),
        containsAll(<BackupScanPhase>[
          BackupScanPhase.comparing,
          BackupScanPhase.finishing,
        ]),
      );
      expect(seen.last, (
        phase: BackupScanPhase.preparing,
        done: 30,
        total: 30,
      ));
      expect(
        seen.where((p) => p.phase == BackupScanPhase.comparing && p.done == 30),
        isEmpty,
        reason: 'comparison must not claim 100% while another arm is running',
      );
      // Batched below 30, so this is more than one report. A single jump
      // from nothing to done would tell the user nothing while it runs.
      expect(
        seen.where((BackupScanProgress p) => p.done > 0).length,
        greaterThan(1),
      );
    });

    // A cancelled copy leaves the folder behind with nothing in it. Reading
    // that as backed up is the quiet-wrong answer this tab exists to avoid.
    test('a backup folder with nothing in it is not backed up', () async {
      filled(liveMyProjects, 'alpha');
      wallpaper(backupMyProjects(), 'alpha');

      final BackupScan result = await scan(root: backupRoot.path);

      expect(
        result.cards[const BackupCard(WallpaperLibrary.myProjects, 'alpha')],
        BackupState.notBackedUp,
      );
      expect(result.junk['myprojects/alpha'], (
        live: false,
        backup: true,
        kind: WallpaperJunkKind.empty,
      ));
    });

    // Wallpaper Engine rebuilds these, so a folder holding only them holds
    // nothing that counts as a backup.
    test('a backup holding only rebuilt shaders is not backed up', () async {
      filled(liveMyProjects, 'alpha');
      final Directory folder = wallpaper(backupMyProjects(), 'alpha');
      Directory(
        p.join(folder.path, 'shaders', 'blobsSM40'),
      ).createSync(recursive: true);
      File(
        p.join(folder.path, 'shaders', 'blobsSM40', 'cache.bin'),
      ).writeAsStringSync('rebuilt');

      final BackupScan result = await scan(root: backupRoot.path);

      expect(
        result.cards[const BackupCard(WallpaperLibrary.myProjects, 'alpha')],
        BackupState.notBackedUp,
      );
      expect(
        result.junk['myprojects/alpha']?.kind,
        WallpaperJunkKind.shaderCacheOnly,
      );
    });

    test('a backup holding only nested dxs files is not backed up', () async {
      filled(liveMyProjects, 'alpha');
      final Directory folder = wallpaper(backupMyProjects(), 'alpha');
      File(p.join(folder.path, 'nested', 'cache.dxs'))
        ..createSync(recursive: true)
        ..writeAsStringSync('rebuilt');

      final BackupScan result = await scan(root: backupRoot.path);

      expect(
        result.cards[const BackupCard(WallpaperLibrary.myProjects, 'alpha')],
        BackupState.notBackedUp,
      );
      expect(
        result.junk['myprojects/alpha']?.kind,
        WallpaperJunkKind.shaderCacheOnly,
      );
    });

    test(
      'junk-only backup with no live copy is cleanup, not vanished',
      () async {
        wallpaper(backupMyProjects(), 'alpha');

        final BackupScan result = await scan(root: backupRoot.path);

        expect(
          result.cards[const BackupCard(WallpaperLibrary.myProjects, 'alpha')],
          BackupState.emptyBackup,
        );
        expect(result.reconcile, isEmpty);
        expect(result.junk['myprojects/alpha'], (
          live: false,
          backup: true,
          kind: WallpaperJunkKind.empty,
        ));
      },
    );

    test(
      'valid backup stays synced while opposite junk stays cleanup',
      () async {
        filled(liveMyProjects, 'alpha');
        filled(backupMyProjects(), 'alpha');
        wallpaper(backupWorkshop(), 'alpha');

        final BackupScan result = await scan(root: backupRoot.path);

        expect(
          result.cards[const BackupCard(WallpaperLibrary.myProjects, 'alpha')],
          BackupState.synced,
        );
        expect(
          result.cards[const BackupCard(WallpaperLibrary.workshop, 'alpha')],
          BackupState.emptyBackup,
        );
        expect(result.junk['workshop/alpha'], (
          live: false,
          backup: true,
          kind: WallpaperJunkKind.empty,
        ));
      },
    );

    // The case the whole tab exists for: Steam removed a delisted item and only
    // the backup still has it.
    test('a name left only in the backup is vanished', () async {
      filled(backupWorkshop(), '793602574');

      final BackupScan result = await scan(root: backupRoot.path);

      expect(result.cards, <BackupCard, BackupState>{
        const BackupCard(WallpaperLibrary.workshop, '793602574'):
            BackupState.vanished,
      });
      expect(result.presence['workshop/793602574'], (
        live: false,
        backup: true,
      ));
      expect(result.reconcile, isEmpty);
    });

    // Equivalent copies in both backup trees are deterministic cleanup: the live
    // library tells us which backup tree should remain.
    test('equivalent duplicate backups go to update/sync', () async {
      filled(liveMyProjects, '793602574');
      filled(backupWorkshop(), '793602574');
      filled(backupMyProjects(), '793602574');

      final BackupScan result = await scan(root: backupRoot.path);

      expect(result.cards, <BackupCard, BackupState>{
        const BackupCard(WallpaperLibrary.myProjects, '793602574'):
            BackupState.updateAvailable,
      });
      expect(result.reconcile, isEmpty);
    });

    test('a republished workshop item reads as an update', () async {
      filled(liveWorkshop, '793602574');
      filled(backupWorkshop(), '793602574');
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

    // myprojects keeps no baseline, so this needs no record at all: the two
    // folders are compared against each other. A hand-made backup is therefore
    // judged correctly from the very first scan.
    test('an edited myprojects wallpaper reads as an update', () async {
      File(
        p.join(wallpaper(liveMyProjects, 'alpha').path, 'project.json'),
      ).writeAsStringSync('{"edited":true}');
      File(
        p.join(wallpaper(backupMyProjects(), 'alpha').path, 'project.json'),
      ).writeAsStringSync('{}');

      final BackupScan result = await scan(root: backupRoot.path);

      expect(
        result.cards[const BackupCard(WallpaperLibrary.myProjects, 'alpha')],
        BackupState.updateAvailable,
      );
    });

    // The other half: a copy that still matches is left alone, and the copy's
    // own timestamps must not enter into it.
    test('an untouched myprojects backup reads as synced', () async {
      File(
        p.join(wallpaper(liveMyProjects, 'alpha').path, 'project.json'),
      ).writeAsStringSync('{"same":true}');
      final File copy = File(
        p.join(wallpaper(backupMyProjects(), 'alpha').path, 'project.json'),
      )..writeAsStringSync('{"same":true}');
      copy.setLastModifiedSync(DateTime(2001));

      final BackupScan result = await scan(root: backupRoot.path);

      expect(
        result.cards[const BackupCard(WallpaperLibrary.myProjects, 'alpha')],
        BackupState.synced,
      );
    });

    // Subfolders are where a myprojects edit usually lands, and the top level
    // alone found 3 of 46 real cases.
    test('a myprojects edit below the top level is still an update', () async {
      final Directory live = wallpaper(liveMyProjects, 'alpha');
      final Directory backup = wallpaper(backupMyProjects(), 'alpha');
      for (final Directory folder in <Directory>[live, backup]) {
        File(p.join(folder.path, 'project.json')).writeAsStringSync('{}');
        Directory(p.join(folder.path, 'materials')).createSync();
      }
      File(
        p.join(live.path, 'materials', 'sky.tex'),
      ).writeAsStringSync('a much larger texture');
      File(
        p.join(backup.path, 'materials', 'sky.tex'),
      ).writeAsStringSync('old');

      final BackupScan result = await scan(root: backupRoot.path);

      expect(
        result.cards[const BackupCard(WallpaperLibrary.myProjects, 'alpha')],
        BackupState.updateAvailable,
      );
    });

    // Wallpaper Engine rebuilds shader caches locally, so recursive MyProjects
    // mirror comparison must ignore them on both sides.
    test('rebuilt shaders do not make a backup look stale', () async {
      final Directory live = wallpaper(liveMyProjects, 'alpha');
      final Directory backup = wallpaper(backupMyProjects(), 'alpha');
      for (final Directory folder in <Directory>[live, backup]) {
        File(p.join(folder.path, 'project.json')).writeAsStringSync('{}');
      }
      Directory(
        p.join(live.path, 'shaders', 'blobsSM40'),
      ).createSync(recursive: true);
      File(
        p.join(live.path, 'shaders', 'blobsSM40', 'cache.bin'),
      ).writeAsStringSync('rebuilt locally');

      final BackupScan result = await scan(root: backupRoot.path);

      expect(
        result.cards[const BackupCard(WallpaperLibrary.myProjects, 'alpha')],
        BackupState.synced,
      );
    });

    test(
      'a matching workshop backup is synced without writing state',
      () async {
        final Directory live = wallpaper(liveWorkshop, '793602574');
        final Directory backup = wallpaper(backupWorkshop(), '793602574');
        for (final Directory folder in <Directory>[live, backup]) {
          File(p.join(folder.path, 'project.json')).writeAsStringSync('{}');
        }
        final File acfFile = File(p.join(tmp.path, 'appworkshop_431960.acf'))
          ..writeAsStringSync(acf);

        final BackupScan result = await scan(
          root: backupRoot.path,
          acfPath: acfFile.path,
        );

        expect(
          result.cards[const BackupCard(
            WallpaperLibrary.workshop,
            '793602574',
          )],
          BackupState.synced,
        );
        expect(
          File(p.join(backupRoot.path, backupRecordsName)).existsSync(),
          isFalse,
        );
      },
    );

    test('a workshop backup that differs reports an update', () async {
      File(
        p.join(wallpaper(liveWorkshop, '793602574').path, 'project.json'),
      ).writeAsStringSync('{"republished":true}');
      File(
        p.join(wallpaper(backupWorkshop(), '793602574').path, 'project.json'),
      ).writeAsStringSync('{}');
      final File acfFile = File(p.join(tmp.path, 'appworkshop_431960.acf'))
        ..writeAsStringSync(acf);

      final BackupScan result = await scan(
        root: backupRoot.path,
        acfPath: acfFile.path,
      );

      expect(
        result.cards[const BackupCard(WallpaperLibrary.workshop, '793602574')],
        BackupState.updateAvailable,
      );
    });

    // myprojects folder names come from wallpaper titles, so they are not all
    // safely numeric and the two sides need not agree on case. Getting this
    // wrong drops the wallpaper out of the comparison entirely, and an
    // uncompared card reads as synced however stale it is.
    test('a differently cased folder name still compares', () async {
      File(
        p.join(wallpaper(liveMyProjects, 'Cool Wallpaper').path, 'scene.json'),
      ).writeAsStringSync('a good deal of content');
      File(
        p.join(
          wallpaper(backupMyProjects(), 'cool wallpaper').path,
          'scene.json',
        ),
      ).writeAsStringSync('old');

      final BackupScan result = await scan(root: backupRoot.path);

      expect(
        result.cards[const BackupCard(
          WallpaperLibrary.myProjects,
          'Cool Wallpaper',
        )],
        BackupState.updateAvailable,
      );
    });

    test('a workshop baseline cannot hide a direct mirror mismatch', () async {
      File(
        p.join(wallpaper(liveWorkshop, '793602574').path, 'project.json'),
      ).writeAsStringSync('{"republished":true}');
      File(
        p.join(wallpaper(backupWorkshop(), '793602574').path, 'project.json'),
      ).writeAsStringSync('{}');
      await writeBackupRecords(backupRoot.path, <String, BackupRecord>{
        'workshop/793602574': const BackupRecord(
          backedUpVersion: '6791066680065157913',
        ),
      });
      final File acfFile = File(p.join(tmp.path, 'appworkshop_431960.acf'))
        ..writeAsStringSync(acf);

      final BackupScan result = await scan(
        root: backupRoot.path,
        acfPath: acfFile.path,
      );

      expect(
        result.cards[const BackupCard(WallpaperLibrary.workshop, '793602574')],
        BackupState.updateAvailable,
        reason: 'the saved manifest cannot prove backup-only or changed files',
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

    // An unset live path is unavailable, not an empty library; treating it as
    // empty would falsely classify every backup-only name as Vanished.
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
