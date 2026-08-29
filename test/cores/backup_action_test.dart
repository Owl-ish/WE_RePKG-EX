import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:we_repkg/cores/backup.dart';
import 'package:we_repkg/cores/backup_action.dart';
import 'package:we_repkg/utils/backup_diff.dart';
import 'package:we_repkg/utils/wallpaper_junk.dart';

void main() {
  late Directory temporary;

  setUp(() {
    temporary = Directory.systemTemp.createTempSync('werepkg-backup-action-');
  });

  tearDown(() async {
    if (await temporary.exists()) await temporary.delete(recursive: true);
  });

  test('states expose only their approved action', () {
    expect(actionForBackupState(BackupState.notBackedUp), BackupAction.backUp);
    expect(
      actionForBackupState(BackupState.updateAvailable),
      BackupAction.update,
    );
    expect(actionForBackupState(BackupState.vanished), BackupAction.restore);
    expect(
      actionForBackupState(BackupState.emptyBackup),
      BackupAction.recycleJunk,
    );
    expect(
      actionForBackupState(BackupState.updateDismissed),
      BackupAction.showUpdateAgain,
    );
    expect(actionForBackupState(BackupState.synced), isNull);
  });

  test(
    'update mirrors changed files, removes residue, and skips shader cache',
    () async {
      final Directory liveRoot = Directory(path.join(temporary.path, 'live'))
        ..createSync();
      final Directory backupRoot = Directory(
        path.join(temporary.path, 'backup'),
      )..createSync();
      final Directory live = Directory(path.join(liveRoot.path, 'demo'))
        ..createSync();
      File(path.join(live.path, 'project.json')).writeAsStringSync('{}');
      File(path.join(live.path, 'scene.json')).writeAsStringSync('new version');
      File(path.join(live.path, 'shaders', 'blobsSM40', 'cache.bin'))
        ..createSync(recursive: true)
        ..writeAsStringSync('cache');
      final Directory backup = Directory(
        path.join(backupMyProjectsPath(backupRoot.path)!, 'demo'),
      )..createSync(recursive: true);
      File(path.join(backup.path, 'scene.json')).writeAsStringSync('old');
      File(path.join(backup.path, 'residue.txt')).writeAsStringSync('keep');

      final result = await backUpWallpaper(
        card: const BackupCard(WallpaperLibrary.myProjects, 'demo'),
        backupRoot: backupRoot.path,
        liveWorkshopPath: null,
        liveMyProjectsPath: liveRoot.path,
        acfPath: null,
        mirror: true,
      );

      expect(result, (changed: true, error: null));
      expect(
        File(path.join(backup.path, 'scene.json')).readAsStringSync(),
        'new version',
      );
      expect(File(path.join(backup.path, 'residue.txt')).existsSync(), isFalse);
      expect(
        File(
          path.join(backup.path, 'shaders', 'blobsSM40', 'cache.bin'),
        ).existsSync(),
        isFalse,
      );
      expect(
        (await readBackupRecords(
          backupRoot.path,
        ))['myprojects/demo']?.backedUpVersion,
        isNotNull,
      );
    },
  );

  test(
    'update copies same-size same-mtime files when their bytes differ',
    () async {
      final Directory liveRoot = Directory(path.join(temporary.path, 'live'))
        ..createSync();
      final Directory backupRoot = Directory(
        path.join(temporary.path, 'backup'),
      )..createSync();
      final Directory live = Directory(path.join(liveRoot.path, 'demo'))
        ..createSync();
      File(path.join(live.path, 'project.json')).writeAsStringSync('{}');
      final File liveFile = File(path.join(live.path, 'scene.json'))
        ..writeAsStringSync('new!');
      final Directory backup = Directory(
        path.join(backupMyProjectsPath(backupRoot.path)!, 'demo'),
      )..createSync(recursive: true);
      File(path.join(backup.path, 'project.json')).writeAsStringSync('{}');
      final File backupFile = File(path.join(backup.path, 'scene.json'))
        ..writeAsStringSync('old!');
      final DateTime sharedModified = DateTime.utc(2026, 1, 2, 3, 4, 5);
      liveFile.setLastModifiedSync(sharedModified);
      backupFile.setLastModifiedSync(sharedModified);

      final result = await backUpWallpaper(
        card: const BackupCard(WallpaperLibrary.myProjects, 'demo'),
        backupRoot: backupRoot.path,
        liveWorkshopPath: null,
        liveMyProjectsPath: liveRoot.path,
        acfPath: null,
        mirror: true,
      );

      expect(result.error, isNull);
      expect(backupFile.readAsStringSync(), 'new!');
      expect(backupFile.lastModifiedSync().toUtc(), sharedModified);
    },
  );

  test('ordinary Back up never deletes destination-only files', () async {
    final Directory liveRoot = Directory(path.join(temporary.path, 'live'))
      ..createSync();
    final Directory backupRoot = Directory(path.join(temporary.path, 'backup'))
      ..createSync();
    final Directory live = Directory(path.join(liveRoot.path, 'demo'))
      ..createSync();
    File(path.join(live.path, 'project.json')).writeAsStringSync('{}');
    final Directory backup = Directory(
      path.join(backupMyProjectsPath(backupRoot.path)!, 'demo'),
    )..createSync(recursive: true);
    File(path.join(backup.path, 'legacy.txt')).writeAsStringSync('keep');

    final result = await backUpWallpaper(
      card: const BackupCard(WallpaperLibrary.myProjects, 'demo'),
      backupRoot: backupRoot.path,
      liveWorkshopPath: null,
      liveMyProjectsPath: liveRoot.path,
      acfPath: null,
    );

    expect(result, (changed: true, error: null));
    expect(File(path.join(backup.path, 'project.json')).existsSync(), isTrue);
    expect(
      File(path.join(backup.path, 'legacy.txt')).readAsStringSync(),
      'keep',
    );
  });

  test('backup reports a late failure as changed after copying', () async {
    final Directory liveRoot = Directory(path.join(temporary.path, 'live'))
      ..createSync();
    final Directory backupRoot = Directory(path.join(temporary.path, 'backup'))
      ..createSync();
    final Directory live = Directory(path.join(liveRoot.path, 'demo'))
      ..createSync();
    File(path.join(live.path, 'project.json')).writeAsStringSync('{}');

    // Block the atomic metadata write after the wallpaper copy has completed.
    Directory(
      path.join(backupRoot.path, '$backupRecordsName$backupRecordsPartSuffix'),
    ).createSync();

    final result = await backUpWallpaper(
      card: const BackupCard(WallpaperLibrary.myProjects, 'demo'),
      backupRoot: backupRoot.path,
      liveWorkshopPath: null,
      liveMyProjectsPath: liveRoot.path,
      acfPath: null,
    );

    expect(result.changed, isTrue);
    expect(result.error, isNotNull);
    expect(
      File(
        path.join(
          backupMyProjectsPath(backupRoot.path)!,
          'demo',
          'project.json',
        ),
      ).existsSync(),
      isTrue,
    );
  });

  test('update syncs a misplaced backup into the live library tree', () async {
    final Directory liveWorkshop = Directory(
      path.join(temporary.path, 'live-workshop'),
    )..createSync();
    final Directory liveMyProjects = Directory(
      path.join(temporary.path, 'live-myprojects'),
    )..createSync();
    final Directory backupRoot = Directory(path.join(temporary.path, 'backup'))
      ..createSync();
    final Directory live = Directory(path.join(liveMyProjects.path, 'demo'))
      ..createSync();
    File(path.join(live.path, 'project.json')).writeAsStringSync('{}');
    File(path.join(live.path, 'scene.json')).writeAsStringSync('current');
    final Directory misplaced = Directory(
      path.join(backupWorkshopPath(backupRoot.path)!, 'demo'),
    )..createSync(recursive: true);
    File(path.join(misplaced.path, 'scene.json')).writeAsStringSync('old');

    final result = await backUpWallpaper(
      card: const BackupCard(WallpaperLibrary.myProjects, 'demo'),
      backupRoot: backupRoot.path,
      liveWorkshopPath: liveWorkshop.path,
      liveMyProjectsPath: liveMyProjects.path,
      acfPath: null,
      mirror: true,
      trashFolder: (String claimed) async {
        await Directory(claimed).delete(recursive: true);
        return null;
      },
    );

    final Directory aligned = Directory(
      path.join(backupMyProjectsPath(backupRoot.path)!, 'demo'),
    );
    expect(result, (changed: true, error: null));
    expect(misplaced.existsSync(), isFalse);
    expect(
      File(path.join(aligned.path, 'scene.json')).readAsStringSync(),
      'current',
    );
  });

  test('update refuses same-size conflicting duplicate backups', () async {
    final Directory liveWorkshop = Directory(
      path.join(temporary.path, 'live-workshop'),
    )..createSync();
    final Directory liveMyProjects = Directory(
      path.join(temporary.path, 'live-myprojects'),
    )..createSync();
    final Directory backupRoot = Directory(path.join(temporary.path, 'backup'))
      ..createSync();
    final Directory live = Directory(path.join(liveMyProjects.path, 'demo'))
      ..createSync();
    File(path.join(live.path, 'project.json')).writeAsStringSync('{}');
    final Directory own = Directory(
      path.join(backupMyProjectsPath(backupRoot.path)!, 'demo'),
    )..createSync(recursive: true);
    File(path.join(own.path, 'scene.json')).writeAsStringSync('alpha');
    final Directory other = Directory(
      path.join(backupWorkshopPath(backupRoot.path)!, 'demo'),
    )..createSync(recursive: true);
    File(path.join(other.path, 'scene.json')).writeAsStringSync('bravo');

    final result = await backUpWallpaper(
      card: const BackupCard(WallpaperLibrary.myProjects, 'demo'),
      backupRoot: backupRoot.path,
      liveWorkshopPath: liveWorkshop.path,
      liveMyProjectsPath: liveMyProjects.path,
      acfPath: null,
      mirror: true,
      trashFolder: (String claimed) async {
        fail('conflicting backups must not be recycled');
      },
    );

    expect(result.changed, isFalse);
    expect(result.error, isNotNull);
    expect(other.existsSync(), isTrue);
  });

  test('show update again clears only the dismissal', () async {
    final Directory backupRoot = Directory(path.join(temporary.path, 'backup'))
      ..createSync();
    await writeBackupRecords(backupRoot.path, <String, BackupRecord>{
      'workshop/demo': const BackupRecord(
        backedUpVersion: 'old',
        dismissedVersion: 'new',
      ),
    });

    final result = await showBackupUpdateAgain(
      card: const BackupCard(WallpaperLibrary.workshop, 'demo'),
      backupRoot: backupRoot.path,
    );
    final BackupRecord record = (await readBackupRecords(
      backupRoot.path,
    ))['workshop/demo']!;

    expect(result, (changed: true, error: null));
    expect(record.backedUpVersion, 'old');
    expect(record.dismissedVersion, isNull);
  });

  test('ignore update records the current live version', () async {
    final Directory backupRoot = Directory(path.join(temporary.path, 'backup'))
      ..createSync();
    final Directory liveMyProjects = Directory(
      path.join(temporary.path, 'live-myprojects'),
    )..createSync();
    final Directory live = Directory(path.join(liveMyProjects.path, 'demo'))
      ..createSync();
    File(path.join(live.path, 'project.json')).writeAsStringSync('{}');

    final BackupActionResult result = await ignoreBackupUpdate(
      card: const BackupCard(WallpaperLibrary.myProjects, 'demo'),
      backupRoot: backupRoot.path,
      liveWorkshopPath: null,
      liveMyProjectsPath: liveMyProjects.path,
      acfPath: null,
    );
    final BackupRecord record = (await readBackupRecords(
      backupRoot.path,
    ))['myprojects/demo']!;

    expect(result, (changed: true, error: null));
    expect(record.dismissedVersion, isNotNull);
  });

  test(
    'empty cleanup recycles the claimed folder, not a replacement',
    () async {
      final Directory backupRoot = Directory(
        path.join(temporary.path, 'backup'),
      )..createSync();
      final BackupCard card = const BackupCard(
        WallpaperLibrary.workshop,
        'demo',
      );
      final Directory original = Directory(
        path.join(backupWorkshopPath(backupRoot.path)!, card.name),
      )..createSync(recursive: true);

      final Directory liveWorkshop = Directory(
        path.join(temporary.path, 'live-workshop'),
      )..createSync();
      final Directory liveMyProjects = Directory(
        path.join(temporary.path, 'live-myprojects'),
      )..createSync();
      final result = await recycleBackupJunk(
        card: card,
        backupRoot: backupRoot.path,
        liveWorkshopPath: liveWorkshop.path,
        liveMyProjectsPath: liveMyProjects.path,
        trashFolder: (String claimed) async {
          expect(original.existsSync(), isFalse);
          original.createSync();
          File(
            path.join(original.path, 'replacement.pkg'),
          ).writeAsStringSync('x');
          await Directory(claimed).delete(recursive: true);
          return null;
        },
      );

      expect(result, (changed: true, error: null));
      expect(
        File(path.join(original.path, 'replacement.pkg')).existsSync(),
        isTrue,
      );
    },
  );

  test(
    'junk cleanup handles live dxs and cache-only backup separately',
    () async {
      final Directory liveWorkshop = Directory(
        path.join(temporary.path, 'live-workshop'),
      )..createSync();
      final Directory liveMyProjects = Directory(
        path.join(temporary.path, 'live-myprojects'),
      )..createSync();
      final Directory backupRoot = Directory(
        path.join(temporary.path, 'backup'),
      )..createSync();
      final Directory live = Directory(path.join(liveWorkshop.path, 'demo'))
        ..createSync();
      File(path.join(live.path, 'nested', 'cache.dxs'))
        ..createSync(recursive: true)
        ..writeAsStringSync('cache');
      final Directory backup = Directory(
        path.join(backupWorkshopPath(backupRoot.path)!, 'demo'),
      )..createSync(recursive: true);
      final Directory cache = backupShaderCache(backup)
        ..createSync(recursive: true);
      File(path.join(cache.path, 'cache.bin')).writeAsStringSync('cache');

      final result = await recycleBackupJunk(
        card: const BackupCard(WallpaperLibrary.workshop, 'demo'),
        backupRoot: backupRoot.path,
        liveWorkshopPath: liveWorkshop.path,
        liveMyProjectsPath: liveMyProjects.path,
        trashFolder: (String claimed) async {
          await Directory(claimed).delete(recursive: true);
          return null;
        },
      );

      expect(result, (changed: true, error: null));
      expect(live.existsSync(), isFalse);
      expect(cache.existsSync(), isFalse);
      expect(backup.existsSync(), isFalse);
    },
  );

  test('junk cleanup leaves cache inside a valid backup alone', () async {
    final Directory liveWorkshop = Directory(
      path.join(temporary.path, 'live-workshop'),
    )..createSync();
    final Directory liveMyProjects = Directory(
      path.join(temporary.path, 'live-myprojects'),
    )..createSync();
    final Directory backupRoot = Directory(path.join(temporary.path, 'backup'))
      ..createSync();
    final Directory live = Directory(path.join(liveWorkshop.path, 'demo'))
      ..createSync();
    File(path.join(live.path, 'scene.pkg')).writeAsStringSync('wallpaper');
    final Directory backup = Directory(
      path.join(backupWorkshopPath(backupRoot.path)!, 'demo'),
    )..createSync(recursive: true);
    File(path.join(backup.path, 'scene.pkg')).writeAsStringSync('wallpaper');
    final Directory cache = backupShaderCache(backup)
      ..createSync(recursive: true);
    File(path.join(cache.path, 'cache.bin')).writeAsStringSync('cache');
    int trashCalls = 0;

    final result = await recycleBackupJunk(
      card: const BackupCard(WallpaperLibrary.workshop, 'demo'),
      backupRoot: backupRoot.path,
      liveWorkshopPath: liveWorkshop.path,
      liveMyProjectsPath: liveMyProjects.path,
      trashFolder: (String claimed) async {
        trashCalls++;
        return null;
      },
    );

    expect(result.changed, isFalse);
    expect(trashCalls, 0);
    expect(cache.existsSync(), isTrue);
  });

  test('junk cleanup recycles a backup containing only nested dxs', () async {
    final Directory liveWorkshop = Directory(
      path.join(temporary.path, 'live-workshop'),
    )..createSync();
    final Directory liveMyProjects = Directory(
      path.join(temporary.path, 'live-myprojects'),
    )..createSync();
    final Directory backupRoot = Directory(path.join(temporary.path, 'backup'))
      ..createSync();
    final Directory backup = Directory(
      path.join(backupWorkshopPath(backupRoot.path)!, 'demo'),
    )..createSync(recursive: true);
    File(path.join(backup.path, 'nested', 'cache.dxs'))
      ..createSync(recursive: true)
      ..writeAsStringSync('cache');

    final result = await recycleBackupJunk(
      card: const BackupCard(WallpaperLibrary.workshop, 'demo'),
      backupRoot: backupRoot.path,
      liveWorkshopPath: liveWorkshop.path,
      liveMyProjectsPath: liveMyProjects.path,
      trashFolder: (String claimed) async {
        await Directory(claimed).delete(recursive: true);
        return null;
      },
    );

    expect(result, (changed: true, error: null));
    expect(backup.existsSync(), isFalse);
  });

  test(
    'restore prefers an unpacked myprojects backup and restores once',
    () async {
      final Directory backupRoot = Directory(
        path.join(temporary.path, 'backup'),
      )..createSync();
      final Directory liveMyProjects = Directory(
        path.join(temporary.path, 'live-myprojects'),
      )..createSync();
      final Directory workshop = Directory(
        path.join(backupWorkshopPath(backupRoot.path)!, 'same'),
      )..createSync(recursive: true);
      File(
        path.join(workshop.path, 'source.txt'),
      ).writeAsStringSync('workshop');
      final Directory projects = Directory(
        path.join(backupMyProjectsPath(backupRoot.path)!, 'same'),
      )..createSync(recursive: true);
      File(path.join(projects.path, 'scene.json')).writeAsStringSync('{}');
      File(path.join(projects.path, 'project.json')).writeAsStringSync('{}');
      File(
        path.join(projects.path, 'source.txt'),
      ).writeAsStringSync('myprojects');

      final result = await restoreVanishedWallpaper(
        cards: const <BackupCard>[
          BackupCard(WallpaperLibrary.workshop, 'same'),
          BackupCard(WallpaperLibrary.myProjects, 'same'),
        ],
        backupRoot: backupRoot.path,
        liveMyProjectsPath: liveMyProjects.path,
      );

      expect(result, (changed: true, error: null));
      expect(
        File(
          path.join(liveMyProjects.path, 'same', 'source.txt'),
        ).readAsStringSync(),
        'myprojects',
      );
      expect(Directory(workshop.path).existsSync(), isTrue);
      expect(Directory(projects.path).existsSync(), isTrue);
    },
  );
}
