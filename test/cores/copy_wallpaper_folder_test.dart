import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Mirrors the copy loop in copyWallpaperFolder, which cannot be called directly
/// from a unit test because it takes a WidgetRef and drives loading toasts.
///
/// The behaviour under test is the directory-creation bookkeeping: the previous
/// version issued a recursive create for every file's parent, even though the
/// walk had just created it. Counting creates here catches a regression that a
/// pure output comparison would miss, since both versions produce an identical
/// tree.
Future<({int creates, int files})> copyTree(
  Directory src,
  String destDir, {
  required bool overwrite,
}) async {
  int creates = 0;
  int files = 0;
  await Directory(destDir).create(recursive: true);
  creates++;
  final Set<String> createdDirs = {destDir};
  await for (final entity in src.list(recursive: true, followLinks: false)) {
    final dest = p.join(destDir, p.relative(entity.path, from: src.path));
    if (entity is Directory) {
      if (createdDirs.add(dest)) {
        await Directory(dest).create(recursive: true);
        creates++;
      }
    } else if (entity is File) {
      if (!overwrite && await File(dest).exists()) continue;
      final parent = p.dirname(dest);
      if (createdDirs.add(parent)) {
        await Directory(parent).create(recursive: true);
        creates++;
      }
      await entity.copy(dest);
      files++;
    }
  }
  return (creates: creates, files: files);
}

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

  test('copies the whole tree faithfully', () async {
    final src = buildSource();
    final dest = p.join(tmp.path, 'out');

    final result = await copyTree(src, dest, overwrite: true);

    expect(result.files, 26); // 1 project.json + 24 + 1 nested
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

  test('creates each directory once, not once per file', () async {
    final src = buildSource();

    final result = await copyTree(
      src,
      p.join(tmp.path, 'out'),
      overwrite: true,
    );

    // 1 destination root + materials + shaders + models + materials/deep.
    expect(result.creates, 5);
    expect(
      result.creates,
      lessThan(result.files),
      reason: 'the old version created a directory per file copied',
    );
  });

  test('overwrite false leaves existing files alone', () async {
    final src = buildSource();
    final dest = p.join(tmp.path, 'out');
    await copyTree(src, dest, overwrite: true);
    final victim = File(p.join(dest, 'project.json'))
      ..writeAsStringSync('edited by hand');

    final second = await copyTree(src, dest, overwrite: false);

    expect(second.files, 0, reason: 'everything was already present');
    expect(victim.readAsStringSync(), 'edited by hand');
  });

  test('overwrite true replaces existing files', () async {
    final src = buildSource();
    final dest = p.join(tmp.path, 'out');
    await copyTree(src, dest, overwrite: true);
    File(p.join(dest, 'project.json')).writeAsStringSync('edited by hand');

    await copyTree(src, dest, overwrite: true);

    expect(File(p.join(dest, 'project.json')).readAsStringSync(), '{}');
  });
}
