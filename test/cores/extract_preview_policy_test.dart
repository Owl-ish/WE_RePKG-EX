import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:we_repkg/cores/extract.dart';
import 'package:we_repkg/models/wallpaper.dart';

/// Body of the top level function named [name], up to the next declaration in
/// column 0. Nothing here depends on the return type or on which function is
/// declared next, so renaming or moving a neighbour cannot break it.
String functionBody(String source, String name) {
  final List<String> lines = source.split('\n');
  final int start = lines.indexWhere(
    (l) => RegExp('^[A-Za-z_].*\\b$name\\(').hasMatch(l),
  );
  expect(start, isNonNegative, reason: '$name was not found');
  final int after = lines.indexWhere(
    (l) => l.isNotEmpty && !l.startsWith(RegExp(r'[\s})]')),
    start + 1,
  );
  return lines.sublist(start, after == -1 ? lines.length : after).join('\n');
}

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

  // Which mode copies the preview cannot be reached from a test, because both
  // batch functions take a WidgetRef and drive toasts. Reading the source is the
  // cheap stand-in until that changes.
  group('only project extraction copies it', () {
    final String source = File('lib/cores/extract.dart').readAsStringSync();

    test('the wallpaper branch does not', () {
      expect(
        functionBody(source, 'extractBranch'),
        isNot(contains('copyProjectPreviewImage(')),
      );
    });

    test('the project worker does', () {
      expect(
        functionBody(source, '_extractProjectOne'),
        contains('copyProjectPreviewImage('),
      );
    });
  });
}
