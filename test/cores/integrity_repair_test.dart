@TestOn('windows')
library;

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
    final Directory directory = Directory(p.join(tmp.path, name))
      ..createSync(recursive: true);
    for (final MapEntry<String, String> file in files.entries) {
      final File target = File(p.join(directory.path, file.key));
      target.parent.createSync(recursive: true);
      target.writeAsStringSync(file.value);
    }
    return directory;
  }

  Map<String, dynamic> readProject(Directory directory) =>
      json.decode(
            File(
              p.join(directory.path, WallpaperFiles.project),
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;

  group('shader cache cleanup', () {
    Directory shaderCache(String name) {
      final Directory directory = Directory(p.join(tmp.path, name))
        ..createSync();
      Directory(
        p.join(directory.path, WallpaperDirectories.shaders),
      ).createSync();
      return directory;
    }

    test('sends a shader-only folder to the Recycle Bin helper', () async {
      final Directory cache = shaderCache('leftover');
      String? trashed;

      final IntegrityRepairResult result = await recycleShaderCacheFolder(
        folder: cache.path,
        trashFolder: (String target) async {
          trashed = target;
          await Directory(target).delete(recursive: true);
          return null;
        },
      );

      expect(result, (changed: true, error: null));
      expect(trashed, cache.path);
      expect(cache.existsSync(), isFalse);
    });

    test('leaves a folder containing anything else untouched', () async {
      final Directory cache = shaderCache('wallpaper');
      File(p.join(cache.path, 'scene.pkg')).writeAsStringSync('payload');
      bool trashCalled = false;

      final IntegrityRepairResult result = await recycleShaderCacheFolder(
        folder: cache.path,
        trashFolder: (String target) async {
          trashCalled = true;
          return null;
        },
      );

      expect(result.changed, isFalse);
      expect(result.error, isNotNull);
      expect(trashCalled, isFalse);
      expect(cache.existsSync(), isTrue);
    });

    test('reports a Recycle Bin failure without claiming success', () async {
      final Directory cache = shaderCache('leftover');

      final IntegrityRepairResult result = await recycleShaderCacheFolder(
        folder: cache.path,
        trashFolder: (String target) async => 'Recycle Bin unavailable',
      );

      expect(result.changed, isFalse);
      expect(result.error, isNotNull);
      expect(cache.existsSync(), isTrue);
    });

    test('requires the folder to disappear before reporting success', () async {
      final Directory cache = shaderCache('leftover');

      final IntegrityRepairResult result = await recycleShaderCacheFolder(
        folder: cache.path,
        trashFolder: (String target) async => null,
      );

      expect(result.changed, isFalse);
      expect(result.error, isNotNull);
      expect(cache.existsSync(), isTrue);
    });
  });

  group('project metadata', () {
    test('writes the minimum project file for an unpacked scene', () async {
      final Directory directory = folder('alpha', <String, String>{
        WallpaperFiles.unpackedScene: '{}',
      });

      expect(await writeSceneProject(directory.path), isNull);
      expect(readProject(directory), <String, dynamic>{
        WallpaperProjectFields.title: 'alpha',
        WallpaperProjectFields.type: 'scene',
        WallpaperProjectFields.file: WallpaperFiles.unpackedScene,
      });
    });

    test('uses an existing preview and never overwrites metadata', () async {
      final Directory directory = folder('alpha', <String, String>{
        WallpaperFiles.unpackedScene: '{}',
        'preview.jpg': 'image',
      });

      expect(await writeSceneProject(directory.path), isNull);
      expect(
        readProject(directory)[WallpaperProjectFields.preview],
        'preview.jpg',
      );
      expect(await writeSceneProject(directory.path), isNotNull);
    });

    test('refuses to describe a scene that is not there', () async {
      final Directory directory = folder('alpha', <String, String>{});

      expect(await writeSceneProject(directory.path), isNotNull);
      expect(
        File(p.join(directory.path, WallpaperFiles.project)).existsSync(),
        isFalse,
      );
    });

    test('publishing never replaces a destination that appeared', () {
      final File staged = File(p.join(tmp.path, 'staged'))
        ..writeAsStringSync('new');
      final File destination = File(p.join(tmp.path, 'final'))
        ..writeAsStringSync('existing');

      expect(
        () => publishWithoutReplacing(staged, destination.path),
        throwsA(isA<FileSystemException>()),
      );
      expect(destination.readAsStringSync(), 'existing');
    });
  });

  group('counterpart repairs', () {
    test('restores the exact missing file from a healthy match', () async {
      final Directory target = folder('live/same', <String, String>{
        WallpaperFiles.project:
            '{"title":"Same","type":"video","file":"clip.mp4"}',
      });
      final Directory healthy = folder('backup/same', <String, String>{
        WallpaperFiles.project:
            '{"title":"Same","type":"video","file":"clip.mp4"}',
        'clip.mp4': 'healthy payload',
      });

      final IntegrityRepairResult result = await restoreMissingPayload(
        folder: target.path,
        counterpart: healthy.path,
        missing: 'clip.mp4',
      );

      expect(result, (changed: true, error: null));
      expect(
        File(p.join(target.path, 'clip.mp4')).readAsStringSync(),
        'healthy payload',
      );
    });

    test('does not restore from a different or unhealthy match', () async {
      final Directory target = folder('live/same', <String, String>{
        WallpaperFiles.project:
            '{"title":"Same","type":"video","file":"clip.mp4"}',
      });
      final Directory unhealthy = folder('backup/same', <String, String>{
        WallpaperFiles.project:
            '{"title":"Same","type":"video","file":"other.mp4"}',
        'other.mp4': 'other payload',
      });

      final IntegrityRepairResult result = await restoreMissingPayload(
        folder: target.path,
        counterpart: unhealthy.path,
        missing: 'clip.mp4',
      );

      expect(result.changed, isFalse);
      expect(File(p.join(target.path, 'clip.mp4')).existsSync(), isFalse);
    });

    test('replaces damaged metadata with its healthy counterpart', () async {
      final Directory target = folder('live/same', <String, String>{
        WallpaperFiles.project: '{broken',
        WallpaperFiles.unpackedScene: '{}',
      });
      final Directory healthy = folder('backup/same', <String, String>{
        WallpaperFiles.project:
            '{"title":"Healthy","type":"scene","file":"scene.json"}',
        WallpaperFiles.unpackedScene: '{}',
      });

      final IntegrityRepairResult result = await replaceProjectFromCounterpart(
        folder: target.path,
        counterpart: healthy.path,
      );

      expect(result, (changed: true, error: null));
      expect(readProject(target)[WallpaperProjectFields.title], 'Healthy');
    });
  });

  group('media-only repair', () {
    test('creates a video project without changing the video', () async {
      final Directory media = folder('video', <String, String>{
        'clip.mp4': 'video bytes',
        'preview.jpg': 'preview bytes',
      });

      final IntegrityRepairResult result = await writeMediaProject(media.path);

      expect(result, (changed: true, error: null));
      expect(readProject(media), <String, dynamic>{
        WallpaperProjectFields.title: 'video',
        WallpaperProjectFields.type: 'video',
        WallpaperProjectFields.file: 'clip.mp4',
        WallpaperProjectFields.preview: 'preview.jpg',
      });
      expect(
        File(p.join(media.path, 'clip.mp4')).readAsStringSync(),
        'video bytes',
      );
    });

    test('creates a loadable local web project for one image', () async {
      final Directory media = folder('image', <String, String>{
        'wallpaper.png': 'image bytes',
      });

      final IntegrityRepairResult result = await writeMediaProject(media.path);

      expect(result, (changed: true, error: null));
      expect(readProject(media)[WallpaperProjectFields.type], 'web');
      expect(
        readProject(media)[WallpaperProjectFields.file],
        WallpaperFiles.webEntry,
      );
      expect(
        File(p.join(media.path, WallpaperFiles.webEntry)).readAsStringSync(),
        contains('wallpaper.png'),
      );
    });

    test('does not guess when more than one main media file exists', () async {
      final Directory media = folder('mixed', <String, String>{
        'one.mp4': 'one',
        'two.mp4': 'two',
      });

      final IntegrityRepairResult result = await writeMediaProject(media.path);

      expect(result.changed, isFalse);
      expect(
        File(p.join(media.path, WallpaperFiles.project)).existsSync(),
        isFalse,
      );
    });

    test('recycles a media folder only after rechecking it', () async {
      final Directory media = folder('media', <String, String>{
        'one.png': 'one',
        'two.png': 'two',
      });

      final IntegrityRepairResult result = await recycleMediaFolder(
        folder: media.path,
        trashFolder: (String target) async {
          await Directory(target).delete(recursive: true);
          return null;
        },
      );

      expect(result, (changed: true, error: null));
      expect(media.existsSync(), isFalse);
    });
  });

  group('packed-scene rescue', () {
    late Directory source;
    late Directory library;

    setUp(() {
      source = folder(p.join('source', 'alpha'), <String, String>{
        WallpaperFiles.packedScene: 'packed',
      });
      library = Directory(p.join(tmp.path, 'myprojects'))..createSync();
    });

    Future<String?> extract(
      String output,
      String from,
      String scene,
      String tool,
    ) async {
      File(
        p.join(output, WallpaperFiles.unpackedScene),
      ).writeAsStringSync('{}');
      return writeSceneProject(output);
    }

    test('leaves the source alone when extraction fails', () async {
      final IntegrityRepairResult result = await rescuePackedScene(
        folder: source.path,
        intoLibrary: library.path,
        rePKGPath: 'unused',
        extractor:
            (String output, String from, String scene, String tool) async =>
                'extraction failed',
      );

      expect(result.changed, isFalse);
      expect(result.error, isNotNull);
      expect(source.existsSync(), isTrue);
      expect(library.listSync(), isEmpty);
    });

    test('publishes the rescue before recycling its source', () async {
      final List<String> events = <String>[];

      final IntegrityRepairResult result = await rescuePackedScene(
        folder: source.path,
        intoLibrary: library.path,
        rePKGPath: 'unused',
        extractor:
            (String output, String from, String scene, String tool) async {
              events.add('extract');
              return extract(output, from, scene, tool);
            },
        trashFolder: (String target) async {
          events.add(
            File(
                  p.join(library.path, 'alpha', WallpaperFiles.project),
                ).existsSync()
                ? 'trash-after-publish'
                : 'trash-before-publish',
          );
          await Directory(target).delete(recursive: true);
          return null;
        },
      );

      expect(result, (changed: true, error: null));
      expect(events, <String>['extract', 'trash-after-publish']);
      expect(source.existsSync(), isFalse);
      expect(
        File(
          p.join(library.path, 'alpha', WallpaperFiles.rescueMarker),
        ).existsSync(),
        isFalse,
      );
    });

    test(
      'a retry finishes a published rescue without extracting twice',
      () async {
        int extractions = 0;
        Future<String?> counted(
          String output,
          String from,
          String scene,
          String tool,
        ) async {
          extractions++;
          return extract(output, from, scene, tool);
        }

        final IntegrityRepairResult first = await rescuePackedScene(
          folder: source.path,
          intoLibrary: library.path,
          rePKGPath: 'unused',
          extractor: counted,
          trashFolder: (String target) async => 'Recycle Bin unavailable',
        );
        final IntegrityRepairResult second = await rescuePackedScene(
          folder: source.path,
          intoLibrary: library.path,
          rePKGPath: 'unused',
          extractor: counted,
          trashFolder: (String target) async {
            await Directory(target).delete(recursive: true);
            return null;
          },
        );

        expect(first.changed, isTrue);
        expect(first.error, isNotNull);
        expect(second, (changed: true, error: null));
        expect(extractions, 1);
      },
    );

    test('does not recycle a source changed during extraction', () async {
      bool trashCalled = false;

      final IntegrityRepairResult result = await rescuePackedScene(
        folder: source.path,
        intoLibrary: library.path,
        rePKGPath: 'unused',
        extractor:
            (String output, String from, String scene, String tool) async {
              final String? error = await extract(output, from, scene, tool);
              File(scene).writeAsStringSync('changed after extraction');
              return error;
            },
        trashFolder: (String target) async {
          trashCalled = true;
          return null;
        },
      );

      expect(result.changed, isTrue, reason: 'the rescued copy was published');
      expect(result.error, isNotNull);
      expect(trashCalled, isFalse);
      expect(source.existsSync(), isTrue);
    });

    test('rejects a destination inside the source', () async {
      final Directory nested = Directory(p.join(source.path, 'myprojects'))
        ..createSync();
      bool extracted = false;

      final IntegrityRepairResult result = await rescuePackedScene(
        folder: source.path,
        intoLibrary: nested.path,
        rePKGPath: 'unused',
        extractor:
            (String output, String from, String scene, String tool) async {
              extracted = true;
              return null;
            },
      );

      expect(result.changed, isFalse);
      expect(result.error, isNotNull);
      expect(extracted, isFalse);
      expect(source.existsSync(), isTrue);
    });
  });

  test('loose files are copied without replacing extracted files', () async {
    final Directory source = folder('source', <String, String>{
      WallpaperFiles.packedScene: 'packed',
      'preview.jpg': 'source preview',
      p.join('assets', 'sound.mp3'): 'sound',
    });
    final Directory output = folder('output', <String, String>{
      'preview.jpg': 'extracted preview',
    });

    expect(await carryLooseFiles(source.path, output.path), isNull);
    expect(
      File(p.join(output.path, 'preview.jpg')).readAsStringSync(),
      'extracted preview',
    );
    expect(
      File(p.join(output.path, 'assets', 'sound.mp3')).existsSync(),
      isTrue,
    );
    expect(
      File(p.join(output.path, WallpaperFiles.packedScene)).existsSync(),
      isFalse,
    );
  });

  test('a rescue output never lands inside an existing folder', () async {
    final Directory wanted = Directory(p.join(tmp.path, 'alpha'))..createSync();

    expect(await freeFolderName(wanted.path), '${wanted.path}-2');
  });
}
