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
import 'package:we_repkg/utils/backup_tiles.dart';
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

  /// A wallpaper folder with a file in it. Empty folders have their own state
  /// now, so a fixture that leaves them bare tests that instead.
  void wallpaper(String relative) {
    File(p.join(dir(relative), 'project.json')).writeAsStringSync('{}');
  }

  String livePaths() {
    wallpaper(p.join('live', '431960', '793602574'));
    wallpaper(p.join('live', 'myprojects', 'alpha'));
    return tmp.path;
  }

  void backupBoth() {
    wallpaper(p.join('backup', '431960', '793602574'));
    wallpaper(
      p.join('backup', 'wallpaper_engine', 'projects', 'myprojects', 'alpha'),
    );
  }

  final String acfBody = '''
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
''';

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
      ..writeAsStringSync(acfBody);
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

  test('scanning does not write into the backup root', () async {
    livePaths();
    backupBoth();
    final String backupRoot = p.join(tmp.path, 'backup');
    final File acf = File(p.join(tmp.path, 'appworkshop_431960.acf'))
      ..writeAsStringSync(acfBody);
    final ProviderContainer container = await seeded(<String, Object>{
      AppKeys.wallpaperPath: p.join(tmp.path, 'live', '431960'),
      AppKeys.myProjectsLibrary: p.join(tmp.path, 'live', 'myprojects'),
      AppKeys.backupRoot: backupRoot,
      AppKeys.acfPath: acf.path,
    });

    final BackupScan scan = await container.read(backupScanProvider.future);

    expect(scan.cards, hasLength(2));
    expect(scan.missing, isEmpty);
    expect(File(p.join(backupRoot, backupRecordsName)).existsSync(), isFalse);
  });

  // The grid's own four-path wiring, which is the mistake this feature has
  // already made once: reading the extraction destination instead of the
  // myprojects library filed 1341 real backups as lost. Titles here are all
  // different, so a path crossed with another shows up as the wrong wallpaper
  // rather than as a count that still adds up.
  test('the tiles come back ordered, from the right four folders', () async {
    void titled(String relative, String title) {
      File(
        p.join(dir(relative), 'project.json'),
      ).writeAsStringSync('{"title":"$title"}');
    }

    titled(p.join('live', '431960', '793602574'), 'Workshop live');
    titled(p.join('backup', '431960', '793602574'), 'Workshop live');
    // The myprojects pair differs, so its tile reads update available and its
    // title says which of the two folders the face came from.
    titled(p.join('live', 'myprojects', 'Alpha'), 'Alpha live');
    titled(
      p.join('backup', 'wallpaper_engine', 'projects', 'myprojects', 'Alpha'),
      'Alpha in the backup',
    );
    // In the backup and in neither live library, one per side.
    titled(p.join('backup', '431960', '999'), 'Gone workshop');
    titled(
      p.join('backup', 'wallpaper_engine', 'projects', 'myprojects', 'Beta'),
      'Gone beta',
    );
    final ProviderContainer container = await seeded(<String, Object>{
      AppKeys.wallpaperPath: p.join(tmp.path, 'live', '431960'),
      AppKeys.myProjectsLibrary: p.join(tmp.path, 'live', 'myprojects'),
      AppKeys.projectPath: p.join(tmp.path, 'scratch', 'wpetest'),
      AppKeys.backupRoot: p.join(tmp.path, 'backup'),
    });

    final List<BackupTile> tiles = await container.read(
      backupTilesProvider.future,
    );

    // Worst state first, then by name. Filesystem order would not give this.
    expect(tiles.map((BackupTile t) => t.card.name), <String>[
      '999',
      'Beta',
      'Alpha',
      '793602574',
    ]);
    expect(tiles.map((BackupTile t) => t.state), <BackupState>[
      BackupState.vanished,
      BackupState.vanished,
      BackupState.updateAvailable,
      BackupState.synced,
    ]);
    // A vanished card reads from its own backup tree, a live one from its own
    // live library.
    expect(tiles.map((BackupTile t) => t.face?.title), <String>[
      'Gone workshop',
      'Gone beta',
      'Alpha live',
      'Workshop live',
    ]);
  });

  group('the backup search', () {
    /// Two Workshop wallpapers with ids that share no text with their titles,
    /// so a match can only have come from one or the other.
    Future<ProviderContainer> library() async {
      void titled(String relative, String title) {
        File(
          p.join(dir(relative), 'project.json'),
        ).writeAsStringSync('{"title":"$title"}');
      }

      titled(p.join('live', '431960', '793602574'), 'Neon City');
      titled(p.join('backup', '431960', '793602574'), 'Neon City');
      titled(p.join('live', '431960', '833227004'), 'Forest stream');
      titled(p.join('backup', '431960', '833227004'), 'Forest stream');
      // A file each side, so alpha is synced like the other two and one pill
      // shows all three. Not a project.json: these tests need it to have no
      // title to match on.
      for (final String side in <String>[
        p.join('live', 'myprojects', 'alpha'),
        p.join('backup', 'wallpaper_engine', 'projects', 'myprojects', 'alpha'),
      ]) {
        File(p.join(dir(side), 'scene.pkg')).writeAsStringSync('x');
      }
      final ProviderContainer container = await seeded(<String, Object>{
        AppKeys.wallpaperPath: p.join(tmp.path, 'live', '431960'),
        AppKeys.myProjectsLibrary: p.join(tmp.path, 'live', 'myprojects'),
        AppKeys.backupRoot: p.join(tmp.path, 'backup'),
      });
      // On the pill these three sit behind, so what the tests see is the search
      // box's doing rather than the grid opening on Not backed up.
      container
          .read(backupStateFilterProvider.notifier)
          .show(BackupState.synced);
      return container;
    }

    Future<List<String>> visible(ProviderContainer container) async =>
        (await container.read(
          backupVisibleTilesProvider.future,
        )).map((BackupTile t) => t.card.name).toList();

    test('an empty box shows everything', () async {
      final ProviderContainer container = await library();

      expect(await visible(container), hasLength(3));
    });

    test('matches the title', () async {
      final ProviderContainer container = await library();
      container.read(backupSearchProvider.notifier).update('neon');

      expect(await visible(container), <String>['793602574']);
    });

    // The reason this exists: a vanished Workshop id is what the user has to
    // hand, and the title is not searchable from a Steam link.
    test('matches the folder id', () async {
      final ProviderContainer container = await library();
      container.read(backupSearchProvider.notifier).update('8332');

      expect(await visible(container), <String>['833227004']);
    });

    // A folder with no readable project.json has no title to match on, and it
    // is one of the ones most worth finding.
    test('a card with no title is still findable by its folder', () async {
      final ProviderContainer container = await library();
      container.read(backupSearchProvider.notifier).update('ALPHA');

      expect(await visible(container), <String>['alpha']);
    });

    test('the two tabs do not share a search box', () async {
      final ProviderContainer container = await library();
      container.read(searchContentProvider.notifier).update('nothing matches');

      expect(await visible(container), hasLength(3));
    });
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
