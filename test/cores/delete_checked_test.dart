import 'package:flutter_test/flutter_test.dart';
import 'package:we_repkg/cores/base.dart';
import 'package:we_repkg/models/wallpaper.dart';

WallpaperInfo wallpaper(String id) => WallpaperInfo(
  id: id,
  title: 'wallpaper $id',
  contentRating: 'everyone',
  tags: const [],
  previews: '',
  type: 'scene',
  updateTime: null,
  createTime: DateTime(2024, 1, 1),
  target: 'scene.pkg',
  folder: 'C:\\wallpapers\\$id',
  size: 0,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('findDeletedWallpapers', () {
    test('reports nothing when every folder survived', () async {
      final gone = await findDeletedWallpapers([
        wallpaper('a'),
        wallpaper('b'),
      ], probe: (_) async => true);
      expect(gone, isEmpty);
    });

    test('reports everything when the whole batch went to the trash', () async {
      final gone = await findDeletedWallpapers([
        wallpaper('a'),
        wallpaper('b'),
      ], probe: (_) async => false);
      expect(gone, {'a', 'b'});
    });

    test('reports only the folders that actually went away', () async {
      // trash::delete_all can fail partway through, which is the case the old
      // code got wrong: it dropped all three rows regardless.
      final survivors = {'C:\\wallpapers\\b'};
      final gone = await findDeletedWallpapers([
        wallpaper('a'),
        wallpaper('b'),
        wallpaper('c'),
      ], probe: (path) async => survivors.contains(path));
      expect(gone, {'a', 'c'});
    });

    test('probes the folder path of each wallpaper', () async {
      final probed = <String>[];
      await findDeletedWallpapers(
        [wallpaper('a'), wallpaper('b')],
        probe: (path) async {
          probed.add(path);
          return true;
        },
      );
      expect(probed, ['C:\\wallpapers\\a', 'C:\\wallpapers\\b']);
    });

    test('an empty selection probes nothing', () async {
      var called = false;
      final gone = await findDeletedWallpapers(
        [],
        probe: (_) async {
          called = true;
          return false;
        },
      );
      expect(gone, isEmpty);
      expect(called, isFalse);
    });

    test('probes concurrently rather than one folder at a time', () async {
      int inFlight = 0;
      int peak = 0;
      await findDeletedWallpapers(
        [for (int i = 0; i < 30; i++) wallpaper('$i')],
        probe: (_) async {
          inFlight++;
          peak = peak > inFlight ? peak : inFlight;
          await Future<void>.delayed(const Duration(milliseconds: 5));
          inFlight--;
          return true;
        },
      );
      expect(peak, 30);
    });
  });
}
