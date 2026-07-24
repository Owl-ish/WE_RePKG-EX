import 'package:flutter_test/flutter_test.dart';
import 'package:we_repkg/cores/extract.dart';
import 'package:we_repkg/models/wallpaper.dart';

WallpaperInfo make(String id, String title) => WallpaperInfo(
  id: id,
  title: title,
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

  const base = r'C:\out';

  test('uses the id when title naming is off', () {
    final folders = resolveProjectFolders(
      [make('111', 'Neon'), make('222', 'Forest')],
      base,
      useTitleName: false,
    );

    expect(folders['111'], r'C:\out\111');
    expect(folders['222'], r'C:\out\222');
  });

  test('uses the sanitised title when title naming is on', () {
    final folders = resolveProjectFolders(
      [make('111', 'Neon: City?')],
      base,
      useTitleName: true,
    );

    expect(folders['111'], r'C:\out\Neon_ City_');
  });

  test('every wallpaper gets a distinct folder', () {
    // The property parallel extraction depends on. Two workers writing into one
    // directory at the same time is the failure this prevents.
    final folders = resolveProjectFolders(
      [make('1', 'Sunset'), make('2', 'Sunset'), make('3', 'Sunset')],
      base,
      useTitleName: true,
    );

    expect(folders.values.toSet().length, 3);
    expect(folders['1'], r'C:\out\Sunset');
    expect(folders['2'], r'C:\out\Sunset-1');
    expect(folders['3'], r'C:\out\Sunset-2');
  });

  test('titles that collide only after sanitising are separated too', () {
    // "A/B" and "A:B" both sanitise to "A_B".
    final folders = resolveProjectFolders(
      [make('1', 'A/B'), make('2', 'A:B')],
      base,
      useTitleName: true,
    );

    expect(folders.values.toSet().length, 2);
    expect(folders['1'], r'C:\out\A_B');
    expect(folders['2'], r'C:\out\A_B-1');
  });

  test(
    'collisions are detected case-insensitively, as Windows treats them',
    () {
      final folders = resolveProjectFolders(
        [make('1', 'Sunset'), make('2', 'SUNSET')],
        base,
        useTitleName: true,
      );

      expect(folders.values.toSet().length, 2);
      expect(folders['2'], r'C:\out\SUNSET-1');
    },
  );

  test('ids are unique already, so nothing gets suffixed', () {
    final folders = resolveProjectFolders(
      [make('1', 'Same'), make('2', 'Same')],
      base,
      useTitleName: false,
    );

    expect(folders['1'], r'C:\out\1');
    expect(folders['2'], r'C:\out\2');
  });

  test('an empty batch resolves to an empty map', () {
    expect(resolveProjectFolders([], base, useTitleName: true), isEmpty);
  });

  test('assignment is deterministic across runs', () {
    final wallpapers = [make('1', 'Dup'), make('2', 'Dup'), make('3', 'Other')];
    final first = resolveProjectFolders(wallpapers, base, useTitleName: true);
    final second = resolveProjectFolders(wallpapers, base, useTitleName: true);
    expect(first, second);
  });
}
