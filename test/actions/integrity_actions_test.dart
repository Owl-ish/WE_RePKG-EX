import 'dart:io';

import 'package:bot_toast/bot_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:we_repkg/constants/i10n.dart';
import 'package:we_repkg/constants/keys.dart';
import 'package:we_repkg/constants/wallpaper_files.dart';
import 'package:we_repkg/cores/integrity_rules.dart';
import 'package:we_repkg/cores/integrity_scan.dart';
import 'package:we_repkg/models/enums.dart';
import 'package:we_repkg/models/wallpaper.dart';
import 'package:we_repkg/provider/system.dart';
import 'package:we_repkg/provider/integrity.dart';
import 'package:we_repkg/provider/wallpaper.dart';
import 'package:we_repkg/utils/backup_diff.dart';
import 'package:we_repkg/utils/storage.dart';
import 'package:we_repkg/actions/integrity_actions.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  IntegrityFinding finding(IntegrityRoot root) => (
    root: root,
    name: 'same-name',
    verdict: IntegrityVerdict.packedSceneNoProject,
    bytes: 1,
    folder: r'C:\same-name',
    missing: null,
  );

  WallpaperInfo wallpaper() => WallpaperInfo(
    id: 'same-name',
    title: 'Same name',
    contentRating: '',
    tags: const <String>[],
    previews: '',
    type: '',
    updateTime: null,
    createTime: DateTime(2026),
    target: '',
    folder: r'C:\same-name',
    size: 1,
  );

  Future<ProviderContainer> grid(WallpaperLibrary library) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      AppKeys.currentLibrary: library.index,
    });
    await StorageUtil.init();
    final ProviderContainer container = ProviderContainer();
    addTearDown(container.dispose);
    final WallpaperInfo item = wallpaper();
    container.read(wallpaperListProvider.notifier).addAll(<WallpaperInfo>[
      item,
    ]);
    container.read(checkedIdsProvider.notifier).setAll(<String>{item.id}, true);
    container.read(selectedWallpaperProvider.notifier).update(item);
    container.read(currentStateProvider.notifier).update(RunState.complete);
    return container;
  }

  test('counterparts stay within the matching library pair', () {
    const IntegrityFinding liveWorkshop = (
      root: IntegrityRoot.liveWorkshop,
      name: '123',
      verdict: IntegrityVerdict.payloadMissing,
      bytes: 1,
      folder: r'C:\live-workshop\123',
      missing: 'clip.mp4',
    );
    const IntegrityFinding backupProjects = (
      root: IntegrityRoot.backupMyProjects,
      name: 'mine',
      verdict: IntegrityVerdict.projectUnreadable,
      bytes: 1,
      folder: r'C:\backup\wallpaper_engine\projects\myprojects\mine',
      missing: null,
    );

    expect(
      integrityCounterpartFolder(
        liveWorkshop,
        workshop: r'C:\live-workshop',
        myProjects: r'C:\myprojects',
        backupRoot: r'C:\backup',
      ),
      r'C:\backup\431960\123',
    );
    expect(
      integrityCounterpartFolder(
        backupProjects,
        workshop: r'C:\live-workshop',
        myProjects: r'C:\myprojects',
        backupRoot: r'C:\backup',
      ),
      r'C:\myprojects\mine',
    );
  });

  test('a myprojects rescue does not remove the same Workshop id', () async {
    final ProviderContainer container = await grid(WallpaperLibrary.workshop);

    markExtractGridStaleAfterIntegrityRepair(
      container,
      IntegrityRepair.rescue,
      <IntegrityFinding>[finding(IntegrityRoot.liveMyProjects)],
    );

    expect(container.read(wallpaperListProvider), hasLength(1));
    expect(container.read(checkedIdsProvider), <String>{'same-name'});
    expect(container.read(currentStateProvider), RunState.complete);
  });

  test('a write in the shown live library marks its grid stale', () async {
    final ProviderContainer container = await grid(WallpaperLibrary.myProjects);

    markExtractGridStaleAfterIntegrityRepair(
      container,
      IntegrityRepair.writeProject,
      <IntegrityFinding>[finding(IntegrityRoot.liveMyProjects)],
    );

    expect(container.read(wallpaperListProvider), isEmpty);
    expect(container.read(checkedIdsProvider), isEmpty);
    expect(container.read(selectedWallpaperProvider), isNull);
    expect(container.read(currentStateProvider), RunState.initial);
  });

  test('rescuing a backup adds a live myprojects folder', () async {
    final ProviderContainer container = await grid(WallpaperLibrary.myProjects);

    markExtractGridStaleAfterIntegrityRepair(
      container,
      IntegrityRepair.rescue,
      <IntegrityFinding>[finding(IntegrityRoot.backupWorkshop)],
    );

    expect(container.read(wallpaperListProvider), isEmpty);
  });

  test('writing metadata in a backup does not touch a live grid', () async {
    final ProviderContainer container = await grid(WallpaperLibrary.workshop);

    markExtractGridStaleAfterIntegrityRepair(
      container,
      IntegrityRepair.writeProject,
      <IntegrityFinding>[finding(IntegrityRoot.backupWorkshop)],
    );

    expect(container.read(wallpaperListProvider), hasLength(1));
    expect(container.read(currentStateProvider), RunState.complete);
  });

  test('a partial live cache cleanup marks its matching grid stale', () async {
    final ProviderContainer container = await grid(WallpaperLibrary.workshop);

    markExtractGridStaleAfterIntegrityRepair(
      container,
      IntegrityRepair.recycleShaderCache,
      <IntegrityFinding>[finding(IntegrityRoot.liveWorkshop)],
    );

    expect(container.read(wallpaperListProvider), isEmpty);
    expect(container.read(currentStateProvider), RunState.initial);
  });

  test('a backup cache cleanup leaves both live grids mounted', () async {
    final ProviderContainer container = await grid(WallpaperLibrary.workshop);

    markExtractGridStaleAfterIntegrityRepair(
      container,
      IntegrityRepair.recycleShaderCache,
      <IntegrityFinding>[finding(IntegrityRoot.backupWorkshop)],
    );

    expect(container.read(wallpaperListProvider), hasLength(1));
    expect(container.read(currentStateProvider), RunState.complete);
  });

  test('a cache cleanup leaves the other live grid mounted', () async {
    final ProviderContainer container = await grid(WallpaperLibrary.myProjects);

    markExtractGridStaleAfterIntegrityRepair(
      container,
      IntegrityRepair.recycleShaderCache,
      <IntegrityFinding>[finding(IntegrityRoot.liveWorkshop)],
    );

    expect(container.read(wallpaperListProvider), hasLength(1));
    expect(container.read(currentStateProvider), RunState.complete);
  });

  testWidgets('Cancel stops shader cleanup before its core action', (
    tester,
  ) async {
    final Directory temporary = Directory.systemTemp.createTempSync(
      'werepkg-integrity-cancel-',
    );
    addTearDown(() async {
      if (await temporary.exists()) await temporary.delete(recursive: true);
    });
    final Directory cacheFolder = Directory(path.join(temporary.path, 'cache'))
      ..createSync();
    Directory(
      path.join(cacheFolder.path, WallpaperDirectories.shaders),
    ).createSync();

    late BuildContext context;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          builder: BotToastInit(),
          navigatorObservers: <NavigatorObserver>[BotToastNavigatorObserver()],
          home: Builder(
            builder: (BuildContext value) {
              context = value;
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    final IntegrityFinding target = (
      root: IntegrityRoot.liveWorkshop,
      name: 'cache',
      verdict: IntegrityVerdict.shaderCacheOnly,
      bytes: 1,
      folder: cacheFolder.path,
      missing: null,
    );

    final Future<void> action = applyIntegrityRepair(
      context,
      IntegrityRepair.recycleShaderCache,
      <IntegrityFinding>[target],
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppI10n.cancel));
    await tester.pumpAndSettle();
    await action;

    expect(cacheFolder.existsSync(), isTrue);
  });

  testWidgets('a successful repair is added to the session history', (
    tester,
  ) async {
    late BuildContext context;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          builder: BotToastInit(),
          navigatorObservers: <NavigatorObserver>[BotToastNavigatorObserver()],
          home: Builder(
            builder: (BuildContext value) {
              context = value;
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    final IntegrityFinding target = (
      root: IntegrityRoot.liveMyProjects,
      name: 'project',
      verdict: IntegrityVerdict.unpackedSceneNoProject,
      bytes: 2,
      folder: r'C:\myprojects\project',
      missing: null,
    );

    final Future<void> action = applyIntegrityRepair(
      context,
      IntegrityRepair.writeProject,
      <IntegrityFinding>[target],
      runRepair: (_, _) async => (changed: true, error: null),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppI10n.ok));
    await tester.pumpAndSettle();
    await action;

    final ProviderContainer container = ProviderScope.containerOf(
      context,
      listen: false,
    );
    expect(
      container.read(integrityResolvedProvider).issues,
      <ResolvedIntegrityIssue>[
        (finding: target, resolution: IntegrityResolution.createdProject),
      ],
    );
  });
}
