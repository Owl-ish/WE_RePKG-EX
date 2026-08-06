import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:we_repkg/constants/keys.dart';
import 'package:we_repkg/cores/backup.dart';
import 'package:we_repkg/provider/backup.dart';
import 'package:we_repkg/provider/system.dart';
import 'package:we_repkg/utils/backup_diff.dart';
import 'package:we_repkg/utils/storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('we_repkg_backup_provider');
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  String dir(String name) =>
      (Directory(p.join(tmp.path, name))..createSync(recursive: true)).path;

  Future<ProviderContainer> seeded(Map<String, Object> settings) async {
    SharedPreferences.setMockInitialValues(settings);
    await StorageUtil.init();
    final ProviderContainer container = ProviderContainer();
    addTearDown(container.dispose);
    return container;
  }

  String livePaths() {
    dir(p.join('live', '431960', '793602574'));
    dir(p.join('live', 'myprojects', 'alpha'));
    return tmp.path;
  }

  void backupBoth() {
    dir(p.join('backup', '431960', '793602574'));
    dir(
      p.join('backup', 'wallpaper_engine', 'projects', 'myprojects', 'alpha'),
    );
  }

  // Every path setting has to reach its own side of the comparison. Swapping
  // any two puts a wallpaper in the wrong library, which changes its state.
  //
  // `projectPath` is set to a folder that does not exist throughout, because
  // reading the extraction destination instead of the myprojects library is
  // exactly the bug these settings were split apart to prevent.
  test('each path setting reaches its own side', () async {
    livePaths();
    backupBoth();
    final ProviderContainer container = await seeded(<String, Object>{
      AppKeys.wallpaperPath: p.join(tmp.path, 'live', '431960'),
      AppKeys.myProjectsLibrary: p.join(tmp.path, 'live', 'myprojects'),
      AppKeys.projectPath: p.join(tmp.path, 'scratch', 'wpetest'),
      AppKeys.backupRoot: p.join(tmp.path, 'backup'),
    });

    final BackupScan scan = await container.read(backupScanProvider.future);

    expect(scan.missing, isEmpty);
    expect(scan.cards, hasLength(2));
    expect(scan.cards.values, everyElement(BackupState.synced));
    expect(scan.reconcile, isEmpty);
  });

  test('the acf path reaches workshop update detection', () async {
    livePaths();
    backupBoth();
    final String backupRoot = p.join(tmp.path, 'backup');
    await writeBackupRecords(backupRoot, <String, BackupRecord>{
      'workshop/793602574': const BackupRecord(backedUpVersion: 'older'),
    });
    final File acf = File(p.join(tmp.path, 'appworkshop_431960.acf'))
      ..writeAsStringSync('''
"AppWorkshop"
{
  "WorkshopItemsInstalled"
  {
    "793602574"
    {
      "manifest"  "6791066680065157913"
    }
  }
}
''');
    final ProviderContainer container = await seeded(<String, Object>{
      AppKeys.wallpaperPath: p.join(tmp.path, 'live', '431960'),
      AppKeys.myProjectsLibrary: p.join(tmp.path, 'live', 'myprojects'),
      AppKeys.backupRoot: backupRoot,
      AppKeys.acfPath: acf.path,
    });

    final BackupScan scan = await container.read(backupScanProvider.future);

    expect(scan.acfRead, isTrue);
    expect(
      scan.cards[const BackupCard(WallpaperLibrary.workshop, '793602574')],
      BackupState.updateAvailable,
    );
  });

  // Watched, not read once: choosing a root has to rescan rather than leave the
  // tab reporting the answer it got before there was anywhere to look.
  test('setting a root rescans', () async {
    livePaths();
    backupBoth();
    final ProviderContainer container = await seeded(<String, Object>{
      AppKeys.wallpaperPath: p.join(tmp.path, 'live', '431960'),
      AppKeys.myProjectsLibrary: p.join(tmp.path, 'live', 'myprojects'),
    });

    expect(
      (await container.read(backupScanProvider.future)).cards.values,
      everyElement(BackupState.notBackedUp),
    );

    container
        .read(backupRootProvider.notifier)
        .update(p.join(tmp.path, 'backup'));

    expect(
      (await container.read(backupScanProvider.future)).cards.values,
      everyElement(BackupState.synced),
    );
  });
}
