import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:we_repkg/cores/extract.dart';
import 'package:we_repkg/models/extract_settings.dart';
import 'package:we_repkg/models/wallpaper.dart';
import 'package:we_repkg/utils/cancel_token.dart';
import 'package:we_repkg/utils/tool.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('preview_policy'));
  tearDown(() => tmp.deleteSync(recursive: true));

  WallpaperInfo wallpaper({required String previews}) => WallpaperInfo(
    id: '1',
    title: 'Wallpaper',
    contentRating: 'everyone',
    tags: const [],
    previews: previews,
    type: 'scene',
    updateTime: null,
    createTime: DateTime(2024, 1, 1),
    target: 'scene.pkg',
    folder: tmp.path,
    size: 0,
  );

  group('copyProjectPreviewImage', () {
    test('brings the preview across', () async {
      final File preview = File(p.join(tmp.path, 'preview.jpg'))
        ..writeAsStringSync('image');
      final Directory dest = Directory(p.join(tmp.path, 'out'))..createSync();

      await copyProjectPreviewImage(
        wallpaper(previews: preview.path),
        dest.path,
      );

      expect(
        File(p.join(dest.path, 'preview.jpg')).readAsStringSync(),
        'image',
      );
    });

    test('a wallpaper with no preview is not an error', () async {
      final Directory dest = Directory(p.join(tmp.path, 'out'))..createSync();

      await copyProjectPreviewImage(wallpaper(previews: ''), dest.path);
      await copyProjectPreviewImage(
        wallpaper(previews: p.join(tmp.path, 'gone.jpg')),
        dest.path,
      );

      expect(dest.listSync(), isEmpty);
    });

    test('takes a free name rather than replacing what is there', () async {
      final File preview = File(p.join(tmp.path, 'preview.jpg'))
        ..writeAsStringSync('new');
      final Directory dest = Directory(p.join(tmp.path, 'out'))..createSync();
      File(p.join(dest.path, 'preview.jpg')).writeAsStringSync('already here');

      await copyProjectPreviewImage(
        wallpaper(previews: preview.path),
        dest.path,
      );

      expect(
        File(p.join(dest.path, 'preview.jpg')).readAsStringSync(),
        'already here',
      );
      expect(
        File(p.join(dest.path, 'preview-1.jpg')).readAsStringSync(),
        'new',
      );
    });
  });

  // Wallpaper mode publishes into a folder the user also keeps their own files
  // in, so it copies only what the wallpaper itself holds. Project mode gets a
  // folder of its own and adds the preview, which is the only thing naming an
  // extracted scene.
  test('the wallpaper branch does not copy the preview in', () async {
    // Outside the wallpaper folder, so the folder copy cannot bring it along
    // and anything that arrives came from copyProjectPreviewImage.
    final File preview = File(p.join(tmp.path, 'preview.jpg'))
      ..writeAsStringSync('image');
    final Directory src = Directory(p.join(tmp.path, 'src'))..createSync();
    File(p.join(src.path, 'index.html')).writeAsStringSync('<html>');
    final Directory out = Directory(p.join(tmp.path, 'out'))..createSync();

    final String? err = await extractBranch(
      (_) {},
      const ExtractSettings(
        rePKGPath: null,
        excludeTexture: false,
        onlySaveImage: false,
        deleteTransparency: false,
        overwrite: false,
        useTitleName: false,
        newFlags: true,
        supportsThreads: true,
        plan: ExtractPlan(concurrency: 1, threads: 1, memoryMb: 1024),
      ),
      WallpaperInfo(
        id: '1',
        title: 'Wallpaper',
        contentRating: 'everyone',
        tags: const [],
        previews: preview.path,
        // Not a pkg, mp4 or customdirectory, so this falls through to the
        // whole-folder copy that web and application wallpapers take.
        target: p.join(src.path, 'index.html'),
        type: 'web',
        updateTime: null,
        createTime: DateTime(2024, 1, 1),
        folder: src.path,
        size: 0,
      ),
      out.path,
      FileNameClaims(overwrite: false),
      CancelToken(),
    );

    expect(err, isNull);
    final List<String> written = out
        .listSync(recursive: true)
        .map((e) => p.basename(e.path))
        .toList();
    expect(written, contains('index.html'));
    expect(written, isNot(contains('preview.jpg')));
  });
}
