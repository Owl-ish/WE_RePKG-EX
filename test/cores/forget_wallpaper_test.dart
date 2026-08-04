import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:we_repkg/constants/wallpaper_type.dart';
import 'package:we_repkg/cores/base.dart';
import 'package:we_repkg/models/wallpaper.dart';
import 'package:we_repkg/provider/wallpaper.dart';
import 'package:we_repkg/utils/storage.dart';

WallpaperInfo make(String id) => WallpaperInfo(
  id: id,
  title: 'wallpaper $id',
  contentRating: 'everyone',
  tags: const [],
  previews: '',
  type: WallpaperType.scene,
  updateTime: null,
  createTime: DateTime(2024, 1, 1),
  target: 'scene.pkg',
  folder: 'C:\\wallpapers\\$id',
  size: 0,
);

class Host extends ConsumerWidget {
  const Host({super.key, required this.onRef});
  final void Function(WidgetRef ref) onRef;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    onRef(ref);
    return const SizedBox();
  }
}

void main() {
  setUp(() async {
    // Every filter off, so checkedWallpaperList sees whatever the test puts in.
    SharedPreferences.setMockInitialValues({
      'hideWeb': false,
      'hideApp': false,
      'hideVideo': false,
      'hideScene': false,
    });
    await StorageUtil.init();
  });

  // Deleting one wallpaper used to leave its id in the checked set: the batch
  // delete pruned it, the context menu and detail dialog did not.
  testWidgets('a deleted wallpaper stops counting as checked', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    late WidgetRef ref;

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: Host(onRef: (r) => ref = r)),
      ),
    );

    final WallpaperInfo doomed = make('1');
    container.read(wallpaperListProvider.notifier).addAll([doomed, make('2')]);
    container.read(checkedIdsProvider.notifier).setAll({'1', '2'}, true);

    forgetWallpaper(ref, doomed);

    expect(container.read(checkedIdsProvider), <String>{'2'});
  });

  // The sharp end of leaving it behind: ids come from the Workshop, so
  // re-subscribing brings the same one back, and it would return pre-checked.
  testWidgets('it does not come back checked if the id reappears', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    late WidgetRef ref;

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: Host(onRef: (r) => ref = r)),
      ),
    );

    final WallpaperInfo doomed = make('1');
    container.read(wallpaperListProvider.notifier).addAll([doomed]);
    container.read(checkedIdsProvider.notifier).setAll({'1'}, true);

    forgetWallpaper(ref, doomed);
    container.read(wallpaperListProvider.notifier).addAll([make('1')]);

    expect(container.read(checkedWallpaperListProvider), isEmpty);
  });
}
