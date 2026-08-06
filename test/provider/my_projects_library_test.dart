import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:we_repkg/constants/keys.dart';
import 'package:we_repkg/provider/system.dart';
import 'package:we_repkg/utils/storage.dart';

const String _workshop = r'C:\Steam\steamapps\workshop\content\431960';
const String _derived =
    r'C:\Steam\steamapps\common\wallpaper_engine\projects\myprojects';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<ProviderContainer> seeded(Map<String, Object> settings) async {
    SharedPreferences.setMockInitialValues(settings);
    await StorageUtil.init();
    final ProviderContainer container = ProviderContainer();
    addTearDown(container.dispose);
    return container;
  }

  // The setting has to fill itself in, or a working install would show the
  // backup tab an empty myprojects library until someone went and set it.
  test('falls back to the folder beside the workshop library', () async {
    final ProviderContainer container = await seeded(<String, Object>{
      AppKeys.wallpaperPath: _workshop,
    });

    expect(container.read(myProjectsLibraryProvider), _derived);
  });

  test('is null while there is no workshop library to derive from', () async {
    expect(
      (await seeded(<String, Object>{})).read(myProjectsLibraryProvider),
      isNull,
    );
  });

  test('a stored override wins over the derived folder', () async {
    final ProviderContainer container = await seeded(<String, Object>{
      AppKeys.wallpaperPath: _workshop,
      AppKeys.myProjectsLibrary: r'D:\elsewhere\myprojects',
    });

    expect(
      container.read(myProjectsLibraryProvider),
      r'D:\elsewhere\myprojects',
    );
  });

  test('a chosen folder reaches storage', () async {
    final ProviderContainer container = await seeded(<String, Object>{
      AppKeys.wallpaperPath: _workshop,
    });

    container.read(myProjectsLibraryProvider.notifier).update(r'D:\picked');
    await pumpEventQueue();

    expect(StorageUtil.getString(AppKeys.myProjectsLibrary), r'D:\picked');
    expect(container.read(myProjectsLibraryProvider), r'D:\picked');
  });

  // Refresh removes the override rather than writing the derived value, or the
  // two would drift apart the next time the library moved.
  test('refresh clears the override and follows the library again', () async {
    final ProviderContainer container = await seeded(<String, Object>{
      AppKeys.wallpaperPath: _workshop,
      AppKeys.myProjectsLibrary: r'D:\elsewhere\myprojects',
    });

    await container.read(myProjectsLibraryProvider.notifier).reset();

    expect(StorageUtil.getString(AppKeys.myProjectsLibrary), isNull);
    expect(container.read(myProjectsLibraryProvider), _derived);
  });

  // The bug this setting exists for: extraction pointed at a scratch folder
  // used to be what the backup tab read as the live myprojects library.
  test('is independent of the extraction destination', () async {
    final ProviderContainer container = await seeded(<String, Object>{
      AppKeys.wallpaperPath: _workshop,
      AppKeys.projectPath: r'C:\scratch\wpetest\project',
    });

    expect(container.read(projectPathProvider), r'C:\scratch\wpetest\project');
    expect(container.read(myProjectsLibraryProvider), _derived);
  });
}
