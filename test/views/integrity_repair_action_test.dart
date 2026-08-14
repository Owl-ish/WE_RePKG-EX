import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:we_repkg/constants/keys.dart';
import 'package:we_repkg/cores/integrity_rules.dart';
import 'package:we_repkg/cores/integrity_scan.dart';
import 'package:we_repkg/models/enums.dart';
import 'package:we_repkg/models/wallpaper.dart';
import 'package:we_repkg/provider/system.dart';
import 'package:we_repkg/provider/wallpaper.dart';
import 'package:we_repkg/utils/backup_diff.dart';
import 'package:we_repkg/utils/storage.dart';
import 'package:we_repkg/views/backup/integrity_repair_action.dart';

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
}
