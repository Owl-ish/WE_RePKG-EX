import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:we_repkg/cores/extract.dart';
import 'package:we_repkg/models/wallpaper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('we_repkg_copy'));
  tearDown(() => tmp.deleteSync(recursive: true));

  Directory buildSource() {
    final src = Directory(p.join(tmp.path, 'src'))..createSync();
    File(p.join(src.path, 'project.json')).writeAsStringSync('{}');
    for (final name in ['materials', 'shaders', 'models']) {
      final dir = Directory(p.join(src.path, name))..createSync();
      for (int i = 0; i < 8; i++) {
        File(p.join(dir.path, 'f$i.bin')).writeAsStringSync('data $i');
      }
    }
    final nested = Directory(p.join(src.path, 'materials', 'deep'))
      ..createSync();
    File(p.join(nested.path, 'inner.bin')).writeAsStringSync('inner');
    return src;
  }

  WallpaperInfo wallpaperIn(Directory folder) => WallpaperInfo(
    id: '1',
    title: 'Wallpaper',
    contentRating: 'everyone',
    tags: const [],
    previews: '',
    type: 'web',
    updateTime: null,
    createTime: DateTime(2024, 1, 1),
    target: '',
    folder: folder.path,
    size: 0,
  );

  test('copies the whole tree faithfully', () async {
    final src = buildSource();
    final dest = p.join(tmp.path, 'out');

    expect(
      await copyWallpaperFolderTo(wallpaperIn(src), dest, overwrite: true),
      isNull,
    );

    for (final entity in src.listSync(recursive: true)) {
      final mirrored = p.join(dest, p.relative(entity.path, from: src.path));
      expect(
        FileSystemEntity.typeSync(mirrored),
        isNot(FileSystemEntityType.notFound),
        reason: 'missing $mirrored',
      );
    }
    expect(
      File(p.join(dest, 'materials', 'deep', 'inner.bin')).readAsStringSync(),
      'inner',
    );
  });

  test('overwrite false leaves existing files alone', () async {
    final src = buildSource();
    final dest = p.join(tmp.path, 'out');
    await copyWallpaperFolderTo(wallpaperIn(src), dest, overwrite: true);
    final victim = File(p.join(dest, 'project.json'))
      ..writeAsStringSync('edited by hand');

    await copyWallpaperFolderTo(wallpaperIn(src), dest, overwrite: false);

    expect(victim.readAsStringSync(), 'edited by hand');
  });

  test('overwrite true replaces existing files', () async {
    final src = buildSource();
    final dest = p.join(tmp.path, 'out');
    await copyWallpaperFolderTo(wallpaperIn(src), dest, overwrite: true);
    File(p.join(dest, 'project.json')).writeAsStringSync('edited by hand');

    await copyWallpaperFolderTo(wallpaperIn(src), dest, overwrite: true);

    expect(File(p.join(dest, 'project.json')).readAsStringSync(), '{}');
  });

  test('a source folder that is gone comes back as an error', () async {
    final wallpaper = wallpaperIn(Directory(p.join(tmp.path, 'missing')));

    expect(
      await copyWallpaperFolderTo(
        wallpaper,
        p.join(tmp.path, 'out'),
        overwrite: true,
      ),
      isNotNull,
    );
  });
}
