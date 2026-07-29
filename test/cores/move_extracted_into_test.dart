import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:we_repkg/cores/extract.dart';
import 'package:we_repkg/utils/tool.dart';

void main() {
  late Directory root;
  late Directory from;
  late Directory to;

  setUp(() {
    resetClaimCache();
    root = Directory.systemTemp.createTempSync('move_extracted');
    from = Directory('${root.path}\\from')..createSync();
    to = Directory('${root.path}\\to')..createSync();
  });
  tearDown(() => root.deleteSync(recursive: true));

  void write(Directory dir, String relative, String body) {
    final File file = File('${dir.path}\\$relative');
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(body);
  }

  test('moves files and keeps their relative paths', () async {
    write(from, 'art.png', 'a');
    write(from, 'materials\\deep.png', 'b');

    expect(await moveExtractedInto(from.path, to.path), isNull);

    expect(File('${to.path}\\art.png').readAsStringSync(), 'a');
    expect(File('${to.path}\\materials\\deep.png').readAsStringSync(), 'b');
    expect(File('${from.path}\\art.png').existsSync(), isFalse);
  });

  // Two wallpapers can produce the same filename, and one silently overwriting
  // the other is the whole reason each extracts somewhere private first.
  test('suffixes a name another wallpaper already took', () async {
    write(to, 'cover.png', 'first');
    write(from, 'cover.png', 'second');

    expect(await moveExtractedInto(from.path, to.path), isNull);

    expect(File('${to.path}\\cover.png').readAsStringSync(), 'first');
    expect(File('${to.path}\\cover-1.png').readAsStringSync(), 'second');
  });

  test('an empty directory moves nothing and reports no error', () async {
    expect(await moveExtractedInto(from.path, to.path), isNull);
    expect(to.listSync(), isEmpty);
  });
}
