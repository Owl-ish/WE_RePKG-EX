@TestOn('windows')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:we_repkg/constants/wallpaper_files.dart';
import 'package:we_repkg/cores/integrity_repair.dart';
import 'package:we_repkg/utils/windows_file_transaction.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('we_repkg_fix'));
  tearDown(() => tmp.deleteSync(recursive: true));

  Directory folder(String name, Map<String, String> files) {
    final Directory dir = Directory(p.join(tmp.path, name))
      ..createSync(recursive: true);
    files.forEach((String file, String body) {
      File(p.join(dir.path, file)).writeAsStringSync(body);
    });
    return dir;
  }

  Map<String, dynamic> readProject(Directory dir) =>
      json.decode(File(p.join(dir.path, 'project.json')).readAsStringSync())
          as Map<String, dynamic>;

  group('writeSceneProject', () {
    test('names scene.json and titles the folder', () async {
      final Directory dir = folder('alpha', <String, String>{
        'scene.json': '{}',
      });

      expect(await writeSceneProject(dir.path), isNull);
      expect(readProject(dir), <String, dynamic>{
        'title': 'alpha',
        'type': 'scene',
        'file': 'scene.json',
      });
      expect(
        File(
          '${p.join(dir.path, WallpaperFiles.project)}.werepkg-ex-part',
        ).existsSync(),
        isFalse,
      );
    });

    // Wallpaper Engine draws the tile from this, and a project with no picture
    // is the one thing the user would have to fix by hand afterwards.
    test('points at a preview when the folder has one', () async {
      final Directory dir = folder('alpha', <String, String>{
        'scene.json': '{}',
        'shot.png': 'x',
        'preview.jpg': 'x',
      });

      await writeSceneProject(dir.path);

      expect(readProject(dir)['preview'], 'preview.jpg');
    });

    // Naming a scene.json that is not there would swap one broken folder for
    // another, and the new one would pass the check.
    test('refuses a folder with no scene.json', () async {
      final Directory dir = folder('alpha', <String, String>{'clip.mp4': 'x'});

      expect(await writeSceneProject(dir.path), isNotNull);
      expect(File(p.join(dir.path, 'project.json')).existsSync(), isFalse);
    });

    test(
      'refuses to write over a project.json that is already there',
      () async {
        final Directory dir = folder('alpha', <String, String>{
          'scene.json': '{}',
          'project.json': '{"title":"theirs"}',
        });

        expect(await writeSceneProject(dir.path), isNotNull);
        expect(readProject(dir)['title'], 'theirs');
      },
    );
  });

  group('atomic publication', () {
    test('does not replace a final file that already exists', () {
      final File staged = File(p.join(tmp.path, 'staged'))
        ..writeAsStringSync('ours');
      final File finalFile = File(p.join(tmp.path, 'final'))
        ..writeAsStringSync('theirs');

      expect(
        () => publishWithoutReplacing(staged, finalFile.path),
        throwsA(isA<FileSystemException>()),
      );
      expect(finalFile.readAsStringSync(), 'theirs');
      expect(staged.readAsStringSync(), 'ours');
    });

    test('file identity changes when a path is replaced', () {
      final File source = File(p.join(tmp.path, 'source'))
        ..writeAsStringSync('first');
      final String first = windowsFileIdentity(source.path);
      source
        ..deleteSync()
        ..writeAsStringSync('second');

      expect(windowsFileIdentity(source.path), isNot(first));
    });

    test('file identity changes after an in-place rewrite', () async {
      final File source = File(p.join(tmp.path, 'source'))
        ..writeAsStringSync('first');
      final String first = windowsFileIdentity(source.path);
      await Future<void>.delayed(const Duration(milliseconds: 2));
      source.writeAsStringSync('a longer second value', flush: true);

      expect(windowsFileIdentity(source.path), isNot(first));
    });

    test('concurrent project writes own separate staging paths', () async {
      final Directory dir = folder('alpha', <String, String>{
        'scene.json': '{}',
      });
      final Completer<void> firstReady = Completer<void>();
      final Completer<void> releaseFirst = Completer<void>();
      final List<String> stages = <String>[];

      final Future<String?> first = writeSceneProject(
        dir.path,
        beforePublish: (File staged) async {
          stages.add(staged.path);
          firstReady.complete();
          await releaseFirst.future;
        },
      );
      await firstReady.future;
      final String? second = await writeSceneProject(
        dir.path,
        beforePublish: (File staged) async => stages.add(staged.path),
      );
      releaseFirst.complete();

      expect(second, isNull);
      expect(await first, isNotNull);
      expect(stages, hasLength(2));
      expect(p.dirname(stages[0]), isNot(p.dirname(stages[1])));
      expect(readProject(dir)['title'], 'alpha');
    });

    test('removes a project stage left by a stopped process', () async {
      final Directory dir = folder('alpha', <String, String>{
        'scene.json': '{}',
      });
      final Directory stale = Directory(
        p.join(dir.path, '${WallpaperFiles.projectStagePrefix}999999-old'),
      )..createSync();
      File(p.join(stale.path, 'partial')).writeAsStringSync('x');

      expect(await writeSceneProject(dir.path), isNull);

      expect(stale.existsSync(), isFalse);
      expect(readProject(dir)['title'], 'alpha');
    });
  });

  group('rescuePackedScene', () {
    test('does nothing when the wallpaper is not there to extract', () async {
      final Directory dir = folder('alpha', <String, String>{'shaders': 'x'});

      expect(
        (await rescuePackedScene(
          folder: dir.path,
          intoLibrary: tmp.path,
          rePKGPath: 'where.exe',
        )).error,
        isNotNull,
      );
      expect(dir.existsSync(), isTrue);
    });

    // The folder is the only copy of the wallpaper until the extraction has
    // worked, so a tool that fails must cost nothing.
    test('leaves the folder alone when the tool fails', () async {
      final Directory dir = folder('alpha', <String, String>{'scene.pkg': 'x'});
      final Directory library = Directory(p.join(tmp.path, 'myprojects'))
        ..createSync();

      // where.exe answers those arguments with "not found" and exit 1, which is
      // a failed run without needing RePKG itself.
      final IntegrityRepairResult result = await rescuePackedScene(
        folder: dir.path,
        intoLibrary: library.path,
        rePKGPath: 'where.exe',
      );

      expect(result.changed, isFalse);
      expect(result.error, isNotNull);
      expect(dir.existsSync(), isTrue);
      expect(File(p.join(dir.path, 'scene.pkg')).existsSync(), isTrue);
      expect(
        library.listSync(),
        isEmpty,
        reason: 'a half-made folder is only in the way of trying again',
      );
    });

    test(
      'rejects a destination inside the folder that will be binned',
      () async {
        final Directory dir = folder('alpha', <String, String>{
          'scene.pkg': 'x',
        });
        final Directory nestedLibrary = Directory(
          p.join(dir.path, 'myprojects'),
        )..createSync();
        bool extracted = false;

        final IntegrityRepairResult result = await rescuePackedScene(
          folder: dir.path,
          intoLibrary: nestedLibrary.path,
          rePKGPath: 'unused',
          extractor:
              (String out, String from, String scene, String tool) async {
                extracted = true;
                return null;
              },
        );

        expect(result.changed, isFalse);
        expect(result.error, isNotNull);
        expect(extracted, isFalse);
        expect(File(p.join(dir.path, 'scene.pkg')).existsSync(), isTrue);
        expect(nestedLibrary.listSync(), isEmpty);
      },
    );

    test(
      'rejects a linked destination that resolves inside the source',
      () async {
        final Directory dir = folder('alpha', <String, String>{
          'scene.pkg': 'x',
        });
        final Directory nestedLibrary = Directory(
          p.join(dir.path, 'myprojects'),
        )..createSync();
        final Link alias = Link(p.join(tmp.path, 'library-link'));
        try {
          await alias.create(nestedLibrary.path);
        } on FileSystemException {
          markTestSkipped(
            'Windows link creation is unavailable on this machine.',
          );
          return;
        }
        bool extracted = false;

        final IntegrityRepairResult result = await rescuePackedScene(
          folder: dir.path,
          intoLibrary: alias.path,
          rePKGPath: 'unused',
          extractor:
              (String out, String from, String scene, String tool) async {
                extracted = true;
                return null;
              },
        );

        expect(result.changed, isFalse);
        expect(result.error, isNotNull);
        expect(extracted, isFalse);
      },
    );

    test('resumes a published rescue instead of making a duplicate', () async {
      final Directory dir = folder('alpha', <String, String>{'scene.pkg': 'x'});
      final Directory library = Directory(p.join(tmp.path, 'myprojects'))
        ..createSync();
      int extractions = 0;

      Future<String?> extract(
        String out,
        String from,
        String scene,
        String tool,
      ) async {
        extractions++;
        File(p.join(out, 'scene.json')).writeAsStringSync('{}');
        return writeSceneProject(out);
      }

      final IntegrityRepairResult first = await rescuePackedScene(
        folder: dir.path,
        intoLibrary: library.path,
        rePKGPath: 'unused',
        extractor: extract,
        trashFolder: (String source) async => 'Recycle Bin unavailable',
      );

      expect(first.changed, isTrue);
      expect(first.error, isNotNull);
      expect(dir.existsSync(), isTrue);
      expect(Directory(p.join(library.path, 'alpha')).existsSync(), isTrue);

      final IntegrityRepairResult second = await rescuePackedScene(
        folder: dir.path,
        intoLibrary: library.path,
        rePKGPath: 'unused',
        extractor: extract,
        trashFolder: (String source) async {
          await Directory(source).delete(recursive: true);
          return null;
        },
      );

      expect(second, (changed: true, error: null));
      expect(extractions, 1);
      expect(dir.existsSync(), isFalse);
      expect(
        library.listSync().whereType<Directory>().map(
          (Directory item) => p.basename(item.path),
        ),
        <String>['alpha'],
      );
      expect(
        File(
          p.join(library.path, 'alpha', WallpaperFiles.rescueMarker),
        ).existsSync(),
        isFalse,
      );
    });

    test(
      'marker cleanup cannot turn a completed rescue into a failure',
      () async {
        final Directory dir = folder('alpha', <String, String>{
          'scene.pkg': 'x',
        });
        final Directory library = Directory(p.join(tmp.path, 'myprojects'))
          ..createSync();

        final IntegrityRepairResult result = await rescuePackedScene(
          folder: dir.path,
          intoLibrary: library.path,
          rePKGPath: 'unused',
          extractor:
              (String out, String from, String scene, String tool) async {
                File(p.join(out, 'scene.json')).writeAsStringSync('{}');
                return writeSceneProject(out);
              },
          trashFolder: (String source) async {
            final String marker = p.join(
              library.path,
              'alpha',
              WallpaperFiles.rescueMarker,
            );
            File(marker).deleteSync();
            Directory(marker).createSync();
            await Directory(source).delete(recursive: true);
            return null;
          },
        );

        expect(result, (changed: true, error: null));
        expect(dir.existsSync(), isFalse);
      },
    );

    test('recovers a completed stage left by a stopped process', () async {
      final Directory dir = folder('alpha', <String, String>{'scene.pkg': 'x'});
      final Directory library = Directory(p.join(tmp.path, 'myprojects'))
        ..createSync();
      final Directory stage = Directory(
        p.join(library.path, '${WallpaperFiles.rescueStagePrefix}999999-abc'),
      )..createSync();
      File(p.join(stage.path, 'scene.json')).writeAsStringSync('{}');
      await writeSceneProject(stage.path);
      final String packedIdentity = windowsFileIdentity(
        p.join(dir.path, 'scene.pkg'),
      );
      File(p.join(stage.path, WallpaperFiles.rescueMarker)).writeAsStringSync(
        json.encode(<String, Object>{
          'source': await dir.resolveSymbolicLinks(),
          'packedFileIdentity': packedIdentity,
          'output': p.join(library.path, 'alpha'),
          'ownerProcess': 999999,
          'complete': true,
          'sourceSnapshot': <String, String>{'scene.pkg': packedIdentity},
        }),
      );
      bool extracted = false;

      final IntegrityRepairResult result = await rescuePackedScene(
        folder: dir.path,
        intoLibrary: library.path,
        rePKGPath: 'unused',
        extractor: (String out, String from, String scene, String tool) async {
          extracted = true;
          return null;
        },
        trashFolder: (String source) async {
          await Directory(source).delete(recursive: true);
          return null;
        },
      );

      expect(result, (changed: true, error: null));
      expect(extracted, isFalse);
      expect(stage.existsSync(), isFalse);
      expect(Directory(p.join(library.path, 'alpha')).existsSync(), isTrue);
      expect(dir.existsSync(), isFalse);
    });

    test('does not publish a damaged stage or trash its source', () async {
      final Directory dir = folder('alpha', <String, String>{'scene.pkg': 'x'});
      final Directory library = Directory(p.join(tmp.path, 'myprojects'))
        ..createSync();
      final Directory stage = Directory(
        p.join(library.path, '${WallpaperFiles.rescueStagePrefix}999999-bad'),
      )..createSync();
      File(p.join(stage.path, WallpaperFiles.project)).writeAsStringSync('{}');
      final String packedIdentity = windowsFileIdentity(
        p.join(dir.path, 'scene.pkg'),
      );
      File(p.join(stage.path, WallpaperFiles.rescueMarker)).writeAsStringSync(
        json.encode(<String, Object>{
          'source': await dir.resolveSymbolicLinks(),
          'packedFileIdentity': packedIdentity,
          'output': p.join(library.path, 'alpha'),
          'ownerProcess': 999999,
          'complete': true,
          'sourceSnapshot': <String, String>{'scene.pkg': packedIdentity},
        }),
      );
      bool trashed = false;

      final IntegrityRepairResult result = await rescuePackedScene(
        folder: dir.path,
        intoLibrary: library.path,
        rePKGPath: 'unused',
        extractor: (String out, String from, String scene, String tool) async =>
            'extraction stopped',
        trashFolder: (String source) async {
          trashed = true;
          return null;
        },
      );

      expect(result.changed, isFalse);
      expect(result.error, isNotNull);
      expect(trashed, isFalse);
      expect(dir.existsSync(), isTrue);
      expect(stage.existsSync(), isFalse);
      expect(Directory(p.join(library.path, 'alpha')).existsSync(), isFalse);
    });

    test('does not recover a stage outside the configured library', () async {
      final Directory dir = folder('alpha', <String, String>{'scene.pkg': 'x'});
      final Directory library = Directory(p.join(tmp.path, 'myprojects'))
        ..createSync();
      final Directory stage = Directory(
        p.join(library.path, '${WallpaperFiles.rescueStagePrefix}999999-bad'),
      )..createSync();
      File(p.join(stage.path, 'scene.json')).writeAsStringSync('{}');
      await writeSceneProject(stage.path);
      final String packedIdentity = windowsFileIdentity(
        p.join(dir.path, 'scene.pkg'),
      );
      final String outside = p.join(tmp.path, 'outside', 'alpha');
      File(p.join(stage.path, WallpaperFiles.rescueMarker)).writeAsStringSync(
        json.encode(<String, Object>{
          'source': await dir.resolveSymbolicLinks(),
          'packedFileIdentity': packedIdentity,
          'output': outside,
          'ownerProcess': 999999,
          'complete': true,
          'sourceSnapshot': <String, String>{'scene.pkg': packedIdentity},
        }),
      );
      bool trashed = false;

      final IntegrityRepairResult result = await rescuePackedScene(
        folder: dir.path,
        intoLibrary: library.path,
        rePKGPath: 'unused',
        extractor: (String out, String from, String scene, String tool) async =>
            'extraction stopped',
        trashFolder: (String source) async {
          trashed = true;
          return null;
        },
      );

      expect(result.changed, isFalse);
      expect(trashed, isFalse);
      expect(Directory(outside).existsSync(), isFalse);
      expect(dir.existsSync(), isTrue);
    });

    test('leaves interrupted repairs for other sources untouched', () async {
      final Directory dir = folder('alpha', <String, String>{'scene.pkg': 'x'});
      final Directory library = Directory(p.join(tmp.path, 'myprojects'))
        ..createSync();
      final Directory incomplete = Directory(
        p.join(
          library.path,
          '${WallpaperFiles.rescueStagePrefix}999999-other-incomplete',
        ),
      )..createSync();
      final Directory complete = Directory(
        p.join(
          library.path,
          '${WallpaperFiles.rescueStagePrefix}999999-other-complete',
        ),
      )..createSync();
      File(
        p.join(complete.path, WallpaperFiles.unpackedScene),
      ).writeAsStringSync('{}');
      await writeSceneProject(complete.path);
      for (final (Directory stage, bool isComplete) in <(Directory, bool)>[
        (incomplete, false),
        (complete, true),
      ]) {
        File(p.join(stage.path, WallpaperFiles.rescueMarker)).writeAsStringSync(
          json.encode(<String, Object>{
            'source': p.join(tmp.path, 'another-source'),
            'packedFileIdentity': 'another-file',
            'output': p.join(library.path, 'another-output'),
            'ownerProcess': 999999,
            'complete': isComplete,
            'sourceSnapshot': <String, String>{},
          }),
        );
      }

      final IntegrityRepairResult result = await rescuePackedScene(
        folder: dir.path,
        intoLibrary: library.path,
        rePKGPath: 'unused',
        extractor: (String out, String from, String scene, String tool) async =>
            'extraction stopped',
        trashFolder: (String source) async => null,
      );

      expect(result.changed, isFalse);
      expect(result.error, isNotNull);
      expect(incomplete.existsSync(), isTrue);
      expect(complete.existsSync(), isTrue);
      expect(
        Directory(p.join(library.path, 'another-output')).existsSync(),
        isFalse,
      );
    });

    test('does not trash a source changed during extraction', () async {
      final Directory dir = folder('alpha', <String, String>{
        'scene.pkg': 'first',
      });
      final Directory library = Directory(p.join(tmp.path, 'myprojects'))
        ..createSync();
      bool trashed = false;

      final IntegrityRepairResult result = await rescuePackedScene(
        folder: dir.path,
        intoLibrary: library.path,
        rePKGPath: 'unused',
        extractor: (String out, String from, String scene, String tool) async {
          File(p.join(out, 'scene.json')).writeAsStringSync('{}');
          final String? error = await writeSceneProject(out);
          File(scene).writeAsStringSync('replacement is longer', flush: true);
          return error;
        },
        trashFolder: (String source) async {
          trashed = true;
          return null;
        },
      );

      expect(result.changed, isTrue);
      expect(result.error, isNotNull);
      expect(trashed, isFalse);
      expect(dir.existsSync(), isTrue);
      expect(Directory(p.join(library.path, 'alpha')).existsSync(), isTrue);
    });

    test('does not trash loose files added during extraction', () async {
      final Directory dir = folder('alpha', <String, String>{'scene.pkg': 'x'});
      final Directory library = Directory(p.join(tmp.path, 'myprojects'))
        ..createSync();
      bool trashed = false;

      final IntegrityRepairResult result = await rescuePackedScene(
        folder: dir.path,
        intoLibrary: library.path,
        rePKGPath: 'unused',
        extractor: (String out, String from, String scene, String tool) async {
          File(p.join(out, 'scene.json')).writeAsStringSync('{}');
          final String? error = await writeSceneProject(out);
          File(p.join(dir.path, 'new-audio.mp3')).writeAsStringSync('new');
          return error;
        },
        trashFolder: (String source) async {
          trashed = true;
          return null;
        },
      );

      expect(result.changed, isTrue);
      expect(result.error, isNotNull);
      expect(trashed, isFalse);
      expect(File(p.join(dir.path, 'new-audio.mp3')).existsSync(), isTrue);
    });

    test('refuses a source containing a filesystem link', () async {
      final Directory dir = folder('alpha', <String, String>{'scene.pkg': 'x'});
      final Directory library = Directory(p.join(tmp.path, 'myprojects'))
        ..createSync();
      final Link link = Link(p.join(dir.path, 'linked-preview'));
      try {
        await link.create(p.join(dir.path, 'scene.pkg'));
      } on FileSystemException {
        markTestSkipped(
          'Windows link creation is unavailable on this machine.',
        );
        return;
      }
      bool extracted = false;

      final IntegrityRepairResult result = await rescuePackedScene(
        folder: dir.path,
        intoLibrary: library.path,
        rePKGPath: 'unused',
        extractor: (String out, String from, String scene, String tool) async {
          extracted = true;
          return null;
        },
      );

      expect(result.changed, isFalse);
      expect(result.error, isNotNull);
      expect(extracted, isFalse);
      expect(dir.existsSync(), isTrue);
    });

    test('does not resume against a replacement at the same path', () async {
      Directory dir = folder('alpha', <String, String>{'scene.pkg': 'first'});
      final Directory library = Directory(p.join(tmp.path, 'myprojects'))
        ..createSync();
      int extractions = 0;

      Future<String?> extract(
        String out,
        String from,
        String scene,
        String tool,
      ) async {
        extractions++;
        File(p.join(out, 'scene.json')).writeAsStringSync('{}');
        return writeSceneProject(out);
      }

      final IntegrityRepairResult first = await rescuePackedScene(
        folder: dir.path,
        intoLibrary: library.path,
        rePKGPath: 'unused',
        extractor: extract,
        trashFolder: (String source) async => 'Recycle Bin unavailable',
      );
      expect(first.changed, isTrue);

      dir.deleteSync(recursive: true);
      dir = folder('alpha', <String, String>{'scene.pkg': 'replacement'});
      final IntegrityRepairResult second = await rescuePackedScene(
        folder: dir.path,
        intoLibrary: library.path,
        rePKGPath: 'unused',
        extractor: extract,
        trashFolder: (String source) async {
          await Directory(source).delete(recursive: true);
          return null;
        },
      );

      expect(second, (changed: true, error: null));
      expect(extractions, 2);
      expect(dir.existsSync(), isFalse);
      expect(
        library.listSync().whereType<Directory>().map(
          (Directory item) => p.basename(item.path),
        ),
        <String>['alpha', 'alpha-2'],
      );
    });

    test('concurrent rescues own separate staging folders', () async {
      final Directory dir = folder('alpha', <String, String>{'scene.pkg': 'x'});
      final Directory library = Directory(p.join(tmp.path, 'myprojects'))
        ..createSync();
      final Completer<void> firstReady = Completer<void>();
      final Completer<void> releaseFirst = Completer<void>();
      final List<String> stages = <String>[];

      Future<String?> fill(String out) async {
        stages.add(out);
        File(p.join(out, 'scene.json')).writeAsStringSync('{}');
        return writeSceneProject(out);
      }

      final Future<IntegrityRepairResult> first = rescuePackedScene(
        folder: dir.path,
        intoLibrary: library.path,
        rePKGPath: 'unused',
        extractor: (String out, String from, String scene, String tool) async {
          final String? error = await fill(out);
          firstReady.complete();
          await releaseFirst.future;
          return error;
        },
        trashFolder: (String source) async => 'keep source',
      );
      await firstReady.future;

      final IntegrityRepairResult second = await rescuePackedScene(
        folder: dir.path,
        intoLibrary: library.path,
        rePKGPath: 'unused',
        extractor: (String out, String from, String scene, String tool) =>
            fill(out),
        trashFolder: (String source) async => 'keep source',
      );
      releaseFirst.complete();
      final IntegrityRepairResult firstResult = await first;

      expect(stages, hasLength(2));
      expect(stages[0], isNot(stages[1]));
      expect(second.changed, isTrue);
      expect(firstResult.changed, isFalse);
      expect(dir.existsSync(), isTrue);
      expect(
        library.listSync().whereType<Directory>().map(
          (Directory item) => p.basename(item.path),
        ),
        <String>['alpha'],
      );
    });
  });

  // The extraction takes the scene and nothing else, and the folder it came
  // from is about to go in the bin.
  group('carryLooseFiles', () {
    test('brings everything but the packed scene across', () async {
      final Directory from = folder('alpha', <String, String>{
        'scene.pkg': 'x',
        'preview.jpg': 'a picture',
      });
      Directory(p.join(from.path, 'audio')).createSync();
      File(p.join(from.path, 'audio', 'hum.mp3')).writeAsStringSync('sound');
      final Directory to = folder('out', <String, String>{'scene.json': '{}'});

      expect(await carryLooseFiles(from.path, to.path), isNull);
      expect(
        File(p.join(to.path, 'preview.jpg')).readAsStringSync(),
        'a picture',
      );
      expect(
        File(p.join(to.path, 'audio', 'hum.mp3')).readAsStringSync(),
        'sound',
      );
      expect(File(p.join(to.path, 'scene.pkg')).existsSync(), isFalse);
    });

    test('leaves what the extraction already wrote alone', () async {
      final Directory from = folder('alpha', <String, String>{
        'scene.json': 'the old one',
      });
      final Directory to = folder('out', <String, String>{
        'scene.json': 'the extracted one',
      });

      await carryLooseFiles(from.path, to.path);

      expect(
        File(p.join(to.path, 'scene.json')).readAsStringSync(),
        'the extracted one',
      );
    });
  });

  group('freeFolderName', () {
    test('steps aside rather than landing inside what is there', () async {
      final String wanted = p.join(tmp.path, 'alpha');
      Directory(wanted).createSync();
      Directory('$wanted-2').createSync();

      expect(await freeFolderName(wanted), '$wanted-3');
    });

    test('keeps the name when nothing holds it', () async {
      final String wanted = p.join(tmp.path, 'beta');

      expect(await freeFolderName(wanted), wanted);
    });
  });
}
