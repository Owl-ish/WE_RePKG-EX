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

  group('renameFile', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('we_repkg_test'));
    tearDown(() => tmp.deleteSync(recursive: true));

    test('returns the same path when nothing exists there', () {
      final path = p.join(tmp.path, 'video.mp4');
      expect(renameFile(path), path);
    });
    test('appends -1 when the file already exists', () {
      final path = p.join(tmp.path, 'video.mp4');
      File(path).writeAsStringSync('x');
      expect(renameFile(path), p.join(tmp.path, 'video-1.mp4'));
    });
    test('increments past an existing -1', () {
      File(p.join(tmp.path, 'video.mp4')).writeAsStringSync('x');
      File(p.join(tmp.path, 'video-1.mp4')).writeAsStringSync('x');
      expect(
        renameFile(p.join(tmp.path, 'video.mp4')),
        p.join(tmp.path, 'video-2.mp4'),
      );
    });
    test('keeps only the last extension for multi-dot names', () {
      final path = p.join(tmp.path, 'a.b.c.mp4');
      File(path).writeAsStringSync('x');
      expect(renameFile(path), p.join(tmp.path, 'a.b.c-1.mp4'));
    });
    test('handles extension-less names without throwing', () {
      final path = p.join(tmp.path, 'README');
      File(path).writeAsStringSync('x');
      expect(renameFile(path), p.join(tmp.path, 'README-1'));
    });
  });
}
