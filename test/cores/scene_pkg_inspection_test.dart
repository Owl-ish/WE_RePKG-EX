import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:we_repkg/cores/scene_pkg_inspection.dart';

void main() {
  late Directory temporary;

  setUp(() {
    temporary = Directory.systemTemp.createTempSync('werepkg-scene-pkg-');
  });

  tearDown(() async {
    if (await temporary.exists()) await temporary.delete(recursive: true);
  });

  test(
    'saves either extracted copy without replacing files or writing to sources',
    () async {
      final Directory extracted = Directory(
        path.join(temporary.path, 'extracted'),
      )..createSync();
      final Directory left = Directory(path.join(extracted.path, 'left'))
        ..createSync();
      final Directory right = Directory(path.join(extracted.path, 'right'))
        ..createSync();
      final Directory live = Directory(path.join(temporary.path, 'live'))
        ..createSync();
      final Directory backup = Directory(path.join(temporary.path, 'backup'))
        ..createSync();
      File(path.join(left.path, 'image.png')).writeAsBytesSync(<int>[1, 2, 3]);
      File(path.join(right.path, 'image.png')).writeAsBytesSync(<int>[4, 5, 6]);
      final ScenePkgInspectionResult result = (
        rootFolder: extracted.path,
        leftFolder: left.path,
        rightFolder: right.path,
        changes: (
          modified: <String>['image.png'],
          onlyLive: <String>[],
          onlyBackup: <String>[],
        ),
      );
      Future<void> save(
        String destination, {
        bool fromLive = true,
        String relative = 'image.png',
      }) => saveScenePkgExtractedFile(
        result: result,
        relativePath: relative,
        live: fromLive,
        destination: destination,
        liveFolder: live.path,
        backupFolder: backup.path,
      );
      final File newCopy = File(path.join(temporary.path, 'new.png'));
      final File oldCopy = File(path.join(temporary.path, 'old.png'));
      await save(newCopy.path);
      await save(oldCopy.path, fromLive: false);
      expect(await newCopy.readAsBytes(), <int>[1, 2, 3]);
      expect(await oldCopy.readAsBytes(), <int>[4, 5, 6]);
      await expectLater(
        save(oldCopy.path),
        throwsA(
          isA<ScenePkgSaveException>().having(
            (e) => e.reason,
            'reason',
            ScenePkgSaveFailure.exists,
          ),
        ),
      );
      expect(await oldCopy.readAsBytes(), <int>[4, 5, 6]);
      for (final Directory protected in <Directory>[live, backup, extracted]) {
        final String destination = path.join(protected.path, 'saved.png');
        await expectLater(
          save(destination),
          throwsA(
            isA<ScenePkgSaveException>().having(
              (e) => e.reason,
              'reason',
              ScenePkgSaveFailure.protectedDestination,
            ),
          ),
        );
        expect(File(destination).existsSync(), isFalse);
      }
      final String escaped = path.join(temporary.path, 'escaped.png');
      await expectLater(
        save(escaped, relative: path.join('..', 'right', 'image.png')),
        throwsA(
          isA<ScenePkgSaveException>().having(
            (e) => e.reason,
            'reason',
            ScenePkgSaveFailure.invalidSource,
          ),
        ),
      );
      expect(File(escaped).existsSync(), isFalse);
    },
  );

  test('keeps numbered filename variants as separate files', () async {
    final Directory left = Directory(path.join(temporary.path, 'left'))
      ..createSync();
    final Directory right = Directory(path.join(temporary.path, 'right'))
      ..createSync();
    final Directory leftMaterials = Directory(path.join(left.path, 'materials'))
      ..createSync();
    final Directory rightMaterials = Directory(
      path.join(right.path, 'materials'),
    )..createSync();

    File(
      path.join(left.path, 'project.json'),
    ).writeAsStringSync('left sidecar');
    File(
      path.join(right.path, 'project.json'),
    ).writeAsStringSync('right sidecar');
    File(path.join(left.path, 'scene.json')).writeAsStringSync('new scene');
    File(path.join(right.path, 'scene.json')).writeAsStringSync('old scene');
    File(path.join(left.path, 'new.txt')).writeAsStringSync('new');
    File(path.join(right.path, 'old.txt')).writeAsStringSync('old');

    File(
      path.join(leftMaterials.path, 'asset (2).png'),
    ).writeAsBytesSync(<int>[1, 2, 3, 4]);
    File(
      path.join(rightMaterials.path, 'asset.png'),
    ).writeAsBytesSync(<int>[1, 2, 3, 4]);
    File(
      path.join(leftMaterials.path, 'changed (3).tex'),
    ).writeAsBytesSync(<int>[9, 8, 7]);
    File(
      path.join(rightMaterials.path, 'changed.tex'),
    ).writeAsBytesSync(<int>[9, 8, 6]);

    final ScenePkgExtractionComparison? result =
        await compareScenePkgExtractionFolders(
          leftFolder: left.path,
          rightFolder: right.path,
        );

    expect(result, isNotNull);
    expect(result!.changes.modified, <String>['scene.json']);
    expect(result.changes.onlyLive, <String>[
      path.join('materials', 'asset (2).png'),
      path.join('materials', 'changed (3).tex'),
      'new.txt',
    ]);
    expect(result.changes.onlyBackup, <String>[
      path.join('materials', 'asset.png'),
      path.join('materials', 'changed.tex'),
      'old.txt',
    ]);
  });

  test('only exact relative path matches can be modified', () async {
    final Directory left = Directory(path.join(temporary.path, 'left'))
      ..createSync();
    final Directory right = Directory(path.join(temporary.path, 'right'))
      ..createSync();
    final Directory leftMaterials = Directory(path.join(left.path, 'materials'))
      ..createSync();
    final Directory rightMaterials = Directory(
      path.join(right.path, 'materials'),
    )..createSync();

    File(
      path.join(leftMaterials.path, 'asset.png'),
    ).writeAsBytesSync(<int>[1, 2, 3]);
    File(
      path.join(rightMaterials.path, 'asset.png'),
    ).writeAsBytesSync(<int>[1, 2, 4]);
    File(
      path.join(leftMaterials.path, 'asset (2).png'),
    ).writeAsBytesSync(<int>[5, 6, 7]);
    File(
      path.join(rightMaterials.path, 'asset (3).png'),
    ).writeAsBytesSync(<int>[5, 6, 7]);

    final ScenePkgExtractionComparison? result =
        await compareScenePkgExtractionFolders(
          leftFolder: left.path,
          rightFolder: right.path,
        );

    expect(result, isNotNull);
    expect(result!.changes.modified, <String>[
      path.join('materials', 'asset.png'),
    ]);
    expect(result.changes.onlyLive, <String>[
      path.join('materials', 'asset (2).png'),
    ]);
    expect(result.changes.onlyBackup, <String>[
      path.join('materials', 'asset (3).png'),
    ]);
  });
}
