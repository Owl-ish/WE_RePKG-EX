import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:we_repkg/cores/base.dart';

void main() {
  late Directory out;

  setUp(() => out = Directory.systemTemp.createTempSync('delete_other_only'));
  tearDown(() {
    if (out.existsSync()) out.deleteSync(recursive: true);
  });

  File touch(String name) {
    final File file = File('${out.path}\\$name');
    file.writeAsStringSync('x');
    return file;
  }

  test('clears everything that is not an image', () async {
    touch('keep.png');
    touch('keep.JPEG');
    touch('raw.tex');

    expect(await deleteOther(out.path, const []), isNull);

    expect(File('${out.path}\\keep.png').existsSync(), isTrue);
    expect(File('${out.path}\\keep.JPEG').existsSync(), isTrue);
    expect(File('${out.path}\\raw.tex').existsSync(), isFalse);
  });

  test('leaves a file that was already there alone', () async {
    final File mine = touch('notes.txt');

    expect(await deleteOther(out.path, <FileSystemEntity>[mine]), isNull);
    expect(mine.existsSync(), isTrue);
  });

  // The caller shows a success toast on null, so a file it could not remove has
  // to come back as an error rather than a debugPrint nobody reads.
  test('reports a file it could not delete', () async {
    touch('raw.tex');
    final File locked = touch('locked.tex');
    // An open handle is enough to make delete fail on Windows.
    final RandomAccessFile handle = locked.openSync(mode: FileMode.write);
    addTearDown(handle.closeSync);

    final String? err = await deleteOther(out.path, const []);

    expect(err, isNotNull);
    expect(err, contains('locked.tex'));
    // The rest of the sweep still runs.
    expect(File('${out.path}\\raw.tex').existsSync(), isFalse);
  });
}
