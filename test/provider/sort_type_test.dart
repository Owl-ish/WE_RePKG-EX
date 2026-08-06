import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:we_repkg/constants/keys.dart';
import 'package:we_repkg/models/enums.dart';
import 'package:we_repkg/provider/setting.dart';
import 'package:we_repkg/utils/storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<ProviderContainer> seeded(Map<String, Object> settings) async {
    SharedPreferences.setMockInitialValues(settings);
    await StorageUtil.init();
    final ProviderContainer container = ProviderContainer();
    addTearDown(container.dispose);
    return container;
  }

  test('the stored sort is used when the acf is being read', () async {
    final ProviderContainer container = await seeded(<String, Object>{
      AppKeys.sortType: SortType.update.index,
      AppKeys.useAcfInfo: true,
    });

    expect(container.read(wallpaperSortTypeProvider), SortType.update);
  });

  // Sorting by update reads the ACF's timestamps. With that setting off the
  // top bar stops offering the option, so leaving the value there would sort on
  // data that was never loaded under a label the menu no longer lists.
  test('sorting by update stands down while the acf is not read', () async {
    final ProviderContainer container = await seeded(<String, Object>{
      AppKeys.sortType: SortType.update.index,
      AppKeys.useAcfInfo: false,
    });

    expect(container.read(wallpaperSortTypeProvider), SortType.time);
  });

  // Held, not overwritten, so the preference survives a look at the setting.
  test('turning the acf setting off and on again restores the sort', () async {
    final ProviderContainer container = await seeded(<String, Object>{
      AppKeys.sortType: SortType.update.index,
      AppKeys.useAcfInfo: true,
    });

    container.read(useAcfInfoProvider.notifier).update(false);
    expect(container.read(wallpaperSortTypeProvider), SortType.time);

    container.read(useAcfInfoProvider.notifier).update(true);
    expect(container.read(wallpaperSortTypeProvider), SortType.update);
  });

  test('the other sorts are left alone', () async {
    final ProviderContainer container = await seeded(<String, Object>{
      AppKeys.sortType: SortType.size.index,
      AppKeys.useAcfInfo: false,
    });

    expect(container.read(wallpaperSortTypeProvider), SortType.size);
  });
}
