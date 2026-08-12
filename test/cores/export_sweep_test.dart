import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:we_repkg/cores/extract.dart';

void main() {
  late Directory out;

  setUp(() => out = Directory.systemTemp.createTempSync('export_sweep'));
  tearDown(() => out.deleteSync(recursive: true));

  Directory sceneFolder(String name) =>
      Directory('${out.path}\\$name')..createSync();

  test('a batch clears what an earlier run left behind', () async {
    final Directory stale = sceneFolder('.werepkg-ex-793602574');

    await withExportSweep(out.path, () async {});

    expect(stale.existsSync(), isFalse);
  });

  // Two runs overlapping is ordinary: picking an export folder returns while
  // the first run is still going. The second one's sweep used to delete the
  // first one's scene folder out from under RePKG.
  test('a second batch leaves the first one\'s folder alone', () async {
    final Completer<void> first = Completer<void>();
    final Future<void> running = withExportSweep(out.path, () => first.future);
    // Made after the first sweep, the way RePKG's output folder is.
    final Directory live = sceneFolder('.werepkg-ex-833227004');

    await withExportSweep(out.path, () async {});

    expect(live.existsSync(), isTrue);
    first.complete();
    await running;
  });

  // Named by wallpaper id alone, a second run on the same wallpaper deleted the
  // first one's directory going in and emptied it again going out.
  test('two runs on one wallpaper get a directory each', () {
    expect(sceneTempName('793602574'), isNot(sceneTempName('793602574')));
    expect(sceneTempName('793602574'), startsWith('.werepkg-ex-793602574-'));
  });

  group('an extraction that wrote nothing', () {
    test('an empty tree counts as nothing written', () async {
      Directory('${out.path}\\scene\\materials').createSync(recursive: true);

      expect(await isEmptyOfFiles(Directory('${out.path}\\scene')), isTrue);
    });

    test('one file anywhere in it counts as something', () async {
      Directory('${out.path}\\scene\\materials').createSync(recursive: true);
      File('${out.path}\\scene\\materials\\art.png').writeAsStringSync('x');

      expect(await isEmptyOfFiles(Directory('${out.path}\\scene')), isFalse);
    });

    test('a folder that is not there is not an error', () async {
      expect(await isEmptyOfFiles(Directory('${out.path}\\gone')), isTrue);
    });
  });

  // The first run to finish must not free the folder while a second is still
  // writing into it, or a third run's sweep deletes live output.
  test('the folder is only free once every batch has left', () async {
    final Completer<void> second = Completer<void>();
    final Future<void> first = withExportSweep(out.path, () async {});
    final Future<void> running = withExportSweep(out.path, () => second.future);
    await first;
    final Directory live = sceneFolder('.werepkg-ex-833227004-0');

    await withExportSweep(out.path, () async {});

    expect(live.existsSync(), isTrue);
    second.complete();
    await running;
  });

  test('the next batch sweeps again once the folder is free', () async {
    await withExportSweep(out.path, () async {});
    final Directory stale = sceneFolder('.werepkg-ex-833227004');

    await withExportSweep(out.path, () async {});

    expect(stale.existsSync(), isFalse);
  });
}
