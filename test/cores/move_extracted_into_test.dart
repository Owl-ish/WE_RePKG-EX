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

    expect(await moveExtractedInto(from.path, to.path, FileNameClaims(overwrite: false)), isNull);

    expect(File('${to.path}\\art.png').readAsStringSync(), 'a');
    expect(File('${to.path}\\materials\\deep.png').readAsStringSync(), 'b');
    expect(File('${from.path}\\art.png').existsSync(), isFalse);
  });

  // Two wallpapers can produce the same filename, and one silently overwriting
  // the other is the whole reason each extracts somewhere private first.
  test('suffixes a name another wallpaper already took', () async {
    write(to, 'cover.png', 'first');
    write(from, 'cover.png', 'second');

    expect(await moveExtractedInto(from.path, to.path, FileNameClaims(overwrite: false)), isNull);

    expect(File('${to.path}\\cover.png').readAsStringSync(), 'first');
    expect(File('${to.path}\\cover-1.png').readAsStringSync(), 'second');
  });

  group('with replace existing files on', () {
    // The setting used to do nothing here, because publication always took a
    // free name, so extracting the same wallpaper twice left art.png beside
    // art-1.png and a third run added art-2.png.
    test('replaces what an earlier run left', () async {
      write(to, 'cover.png', 'last run');
      write(from, 'cover.png', 'this run');

      expect(
        await moveExtractedInto(
          from.path,
          to.path,
          FileNameClaims(overwrite: true),
        ),
        isNull,
      );

      expect(File('${to.path}\\cover.png').readAsStringSync(), 'this run');
      expect(File('${to.path}\\cover-1.png').existsSync(), isFalse);
    });

    // Overwriting across runs must not become two wallpapers in one run
    // overwriting each other.
    test('still suffixes a second claim inside the same run', () async {
      final claims = FileNameClaims(overwrite: true);
      write(from, 'cover.png', 'first');
      expect(await moveExtractedInto(from.path, to.path, claims), isNull);

      final Directory second = Directory('${root.path}\\from2')..createSync();
      write(second, 'cover.png', 'second');
      expect(await moveExtractedInto(second.path, to.path, claims), isNull);

      expect(File('${to.path}\\cover.png').readAsStringSync(), 'first');
      expect(File('${to.path}\\cover-1.png').readAsStringSync(), 'second');
    });

    test('a differently cased name counts as the same claim', () async {
      final claims = FileNameClaims(overwrite: true);
      write(from, 'Cover.PNG', 'first');
      expect(await moveExtractedInto(from.path, to.path, claims), isNull);

      final Directory second = Directory('${root.path}\\from3')..createSync();
      write(second, 'cover.png', 'second');
      expect(await moveExtractedInto(second.path, to.path, claims), isNull);

      expect(File('${to.path}\\cover-1.png').readAsStringSync(), 'second');
    });
  });

  test('an empty directory moves nothing and reports no error', () async {
    expect(await moveExtractedInto(from.path, to.path, FileNameClaims(overwrite: false)), isNull);
    expect(to.listSync(), isEmpty);
  });

  // The caller deletes the source directory straight after, so a file that
  // cannot move must not cost the ones behind it.
  test('one unmovable file does not strand the rest', () async {
    write(from, 'a.png', 'a');
    write(from, 'blocked\\stuck.png', 'x');
    write(from, 'z.png', 'z');
    // A file where that subfolder needs to be, so creating it throws.
    write(to, 'blocked', 'in the way');

    final String? err = await moveExtractedInto(from.path, to.path, FileNameClaims(overwrite: false));

    expect(err, isNotNull);
    expect(err, contains('stuck.png'));
    expect(File('${to.path}\\a.png').readAsStringSync(), 'a');
    expect(File('${to.path}\\z.png').readAsStringSync(), 'z');
  });

  // A file that could not be moved is still in the scene's temp folder. The
  // caller used to delete that folder regardless, destroying output it had just
  // named in an error the user could do nothing about.
  group('keeping what could not be moved', () {
    test('renames the leftovers under the output folder', () async {
      final Directory temp = Directory('${to.path}\\.werepkg-77')..createSync();
      File('${temp.path}\\stuck.png').writeAsStringSync('x');

      final String kept = await keepUnmovedFiles(temp, to.path, '77');

      expect(kept, '${to.path}\\77-unmoved');
      expect(File('$kept\\stuck.png').readAsStringSync(), 'x');
      expect(temp.existsSync(), isFalse);
    });

    test('survives the next run clearing stale scene folders', () async {
      final Directory temp = Directory('${to.path}\\.werepkg-77')..createSync();
      File('${temp.path}\\stuck.png').writeAsStringSync('x');
      final String kept = await keepUnmovedFiles(temp, to.path, '77');

      await sweepStaleSceneDirs(to.path);

      expect(File('$kept\\stuck.png').existsSync(), isTrue);
    });

    test('a second failure replaces the first rather than piling up', () async {
      for (final String body in <String>['first', 'second']) {
        final Directory temp = Directory('${to.path}\\.werepkg-77')
          ..createSync();
        File('${temp.path}\\stuck.png').writeAsStringSync(body);
        await keepUnmovedFiles(temp, to.path, '77');
      }

      expect(
        File('${to.path}\\77-unmoved\\stuck.png').readAsStringSync(),
        'second',
      );
    });
  });

  group('stale sweep', () {
    test('clears scene directories a killed run left behind', () async {
      write(to, '.werepkg-123\\half-done.png', 'x');
      write(to, 'keep.png', 'y');
      Directory('${to.path}\\materials').createSync();

      await sweepStaleSceneDirs(to.path);

      expect(Directory('${to.path}\\.werepkg-123').existsSync(), isFalse);
      expect(File('${to.path}\\keep.png').existsSync(), isTrue);
      expect(Directory('${to.path}\\materials').existsSync(), isTrue);
    });

    test('does nothing to a folder with none, or one that is gone', () async {
      write(to, 'keep.png', 'y');

      await sweepStaleSceneDirs(to.path);
      await sweepStaleSceneDirs('${to.path}\\missing');

      expect(File('${to.path}\\keep.png').existsSync(), isTrue);
    });
  });
}
