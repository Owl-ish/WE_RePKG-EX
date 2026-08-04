import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:we_repkg/cores/base.dart';

void main() {
  late Directory out;

  setUp(() => out = Directory.systemTemp.createTempSync('delete_other'));
  tearDown(() => out.deleteSync(recursive: true));

  File touch(String relative) {
    final File file = File('${out.path}\\$relative');
    file.parent.createSync(recursive: true);
    file.writeAsStringSync('x');
    return file;
  }

  test('moves images out of materials and clears the rest', () async {
    touch('materials\\art.png');
    touch('materials\\masks\\mask.png');
    touch('shaders\\a.frag');
    touch('scene.json');

    expect(await deleteOtherAndTexture(out.path), isNull);

    expect(File('${out.path}\\art.png').existsSync(), isTrue);
    expect(Directory('${out.path}\\materials').existsSync(), isFalse);
    expect(Directory('${out.path}\\shaders').existsSync(), isFalse);
    expect(File('${out.path}\\scene.json').existsSync(), isFalse);
  });

  // A scene can hold a texture and a root file of the same name. Renaming the
  // promoted one straight up replaced the other and lost it silently.
  test('a promoted image does not replace one already at the root', () async {
    touch('art.png').writeAsStringSync('root');
    touch('materials\\art.png').writeAsStringSync('promoted');

    expect(await deleteOtherAndTexture(out.path), isNull);

    expect(File('${out.path}\\art.png').readAsStringSync(), 'root');
    expect(File('${out.path}\\art-1.png').readAsStringSync(), 'promoted');
  });

  // Wallpaper mode extracts tex entries only, so there is no scene.json to
  // remove. Deleting it unconditionally reported a failure over a clean run.
  test('succeeds when scene.json was never extracted', () async {
    touch('materials\\art.png');

    expect(await deleteOtherAndTexture(out.path), isNull);
    expect(File('${out.path}\\art.png').existsSync(), isTrue);
  });

  test('succeeds on an output folder that has nothing to clean', () async {
    expect(await deleteOtherAndTexture(out.path), isNull);
  });

  // Why this may only ever be pointed at a directory the app created and owns.
  // It takes no record of what was there first, so given the user's export
  // folder it would delete an unpacked wallpaper sitting in it. Extraction calls
  // it on the private per-scene directory for exactly this reason.
  test('deletes a wallpaper it never created', () async {
    touch('models\\mine.mdl');
    touch('sounds\\mine.ogg');
    touch('scene.json');

    expect(await deleteOtherAndTexture(out.path), isNull);

    expect(Directory('${out.path}\\models').existsSync(), isFalse);
    expect(Directory('${out.path}\\sounds').existsSync(), isFalse);
    expect(File('${out.path}\\scene.json').existsSync(), isFalse);
  });
}
