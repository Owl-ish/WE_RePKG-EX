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
