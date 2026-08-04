import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:we_repkg/utils/tool.dart';

void main() {
  group('formatSize', () {
    test('bytes under 1 KB', () {
      expect(formatSize(0), '0B');
      expect(formatSize(512), '512B');
      expect(formatSize(1023), '1023B');
    });
    test('kilobytes', () {
      expect(formatSize(1024), '1.00KB');
      expect(formatSize(1536), '1.50KB');
    });
    test('megabytes', () {
      expect(formatSize(1024 * 1024), '1.00MB');
      expect(formatSize(1024 * 1024 + 512 * 1024), '1.50MB');
    });
  });

  group('splitOnFirstColon', () {
    test('splits on the first colon only', () {
      expect(splitOnFirstColon('a:b:c'), ['a', 'b:c']);
    });
    test('no colon returns empty prefix and full message', () {
      expect(splitOnFirstColon('hello'), ['', 'hello']);
    });
    test('leading colon', () {
      expect(splitOnFirstColon(':value'), ['', 'value']);
    });
  });

  group('renameFolder', () {
    test('replaces illegal filename characters with underscore', () {
      expect(renameFolder(r'a/b\c:d*e?f"g<h>i|j'), 'a_b_c_d_e_f_g_h_i_j');
    });
    test('leaves clean names unchanged', () {
      expect(renameFolder('My Wallpaper 123'), 'My Wallpaper 123');
    });
  });

  group('formattedTime', () {
    test('null returns empty string', () {
      expect(formattedTime(null), '');
    });
    test('formats to a yyyy-MM-dd HH:mm:ss shape', () {
      final result = formattedTime(1700000000);
      expect(result.length, 19);
      expect(
        RegExp(r'^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$').hasMatch(result),
        isTrue,
      );
    });
  });

  group('claimFilePath', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('we_repkg_test'));
    tearDown(() => tmp.deleteSync(recursive: true));

    test('returns the same path when nothing exists there', () async {
      final path = p.join(tmp.path, 'video.mp4');
      expect(await claimFilePath(path), path);
    });

    test('creates a placeholder so the name is actually reserved', () async {
      final path = p.join(tmp.path, 'video.mp4');
      final claimed = await claimFilePath(path);
      expect(File(claimed).existsSync(), isTrue);
      expect(File(claimed).lengthSync(), 0);
    });

    test('appends -1 when the file already exists', () async {
      final path = p.join(tmp.path, 'video.mp4');
      File(path).writeAsStringSync('x');
      expect(await claimFilePath(path), p.join(tmp.path, 'video-1.mp4'));
    });

    test('increments past an existing -1', () async {
      File(p.join(tmp.path, 'video.mp4')).writeAsStringSync('x');
      File(p.join(tmp.path, 'video-1.mp4')).writeAsStringSync('x');
      expect(
        await claimFilePath(p.join(tmp.path, 'video.mp4')),
        p.join(tmp.path, 'video-2.mp4'),
      );
    });

    test('keeps only the last extension for multi-dot names', () async {
      final path = p.join(tmp.path, 'a.b.c.mp4');
      File(path).writeAsStringSync('x');
      expect(await claimFilePath(path), p.join(tmp.path, 'a.b.c-1.mp4'));
    });

    test('handles extension-less names without throwing', () async {
      final path = p.join(tmp.path, 'README');
      File(path).writeAsStringSync('x');
      expect(await claimFilePath(path), p.join(tmp.path, 'README-1'));
    });

    test('never hands out a name twice, even without writes between', () async {
      // The property renameFile could not offer: because the claim creates the
      // file, back-to-back calls cannot both be given the same path.
      final source = p.join(tmp.path, 'frame.png');
      final handed = <String>[];
      for (int i = 0; i < 50; i++) {
        handed.add(await claimFilePath(source));
      }
      expect(handed.toSet().length, 50);
      expect(handed.first, source);
      expect(handed.last, p.join(tmp.path, 'frame-49.png'));
    });

    test('concurrent claims never collide', () async {
      // Premortem item 1: with extraction parallelised, several workers write
      // into one export folder at the same time.
      final source = p.join(tmp.path, 'cover.png');
      final claimed = await Future.wait([
        for (int i = 0; i < 40; i++) claimFilePath(source),
      ]);
      expect(claimed.toSet().length, 40, reason: 'every claim must be unique');
      for (final path in claimed) {
        expect(File(path).existsSync(), isTrue);
      }
    });

    test('respects a file created behind its back', () async {
      final source = p.join(tmp.path, 'clip.mp4');
      File(source).writeAsStringSync('x');
      expect(await claimFilePath(source), p.join(tmp.path, 'clip-1.mp4'));

      File(p.join(tmp.path, 'clip-2.mp4')).writeAsStringSync('x');
      expect(await claimFilePath(source), p.join(tmp.path, 'clip-3.mp4'));
    });

    test('keeps separate counters per directory', () async {
      final sub = Directory(p.join(tmp.path, 'sub'))..createSync();
      File(p.join(tmp.path, 'a.png')).writeAsStringSync('x');

      expect(
        await claimFilePath(p.join(tmp.path, 'a.png')),
        p.join(tmp.path, 'a-1.png'),
      );
      expect(
        await claimFilePath(p.join(sub.path, 'a.png')),
        p.join(sub.path, 'a.png'),
      );
    });

    test('surfaces a real failure instead of spinning', () async {
      // A missing parent directory is not a name collision, so it must throw
      // rather than march the suffix upward forever.
      final missing = p.join(tmp.path, 'no', 'such', 'dir', 'x.png');
      await expectLater(
        claimFilePath(missing),
        throwsA(isA<FileSystemException>()),
      );
    });

    // The batch carries a resume map so N colliding files cost N probes rather
    // than N^2. The exclusive create is what keeps names unique, so what this
    // guards is the map staying in step: resuming past the last index taken
    // would leave gaps in the run.
    test('resuming between claims still gives each one its own name', () async {
      final claims = FileNameClaims(overwrite: false);
      final source = p.join(tmp.path, 'frame.png');

      final handed = <String>[
        for (int i = 0; i < 50; i++) await claims.claim(source),
      ];

      expect(handed.toSet().length, 50);
      expect(handed.last, p.join(tmp.path, 'frame-49.png'));
    });
  });
}
