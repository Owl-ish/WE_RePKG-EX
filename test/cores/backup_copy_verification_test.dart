import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:path/path.dart' as path;
import 'package:we_repkg/cores/scene_pkg_inspection.dart';
import 'package:we_repkg/cores/scene_pkg_index.dart';
import 'package:we_repkg/cores/scene_texture_summary.dart';
import 'package:we_repkg/cores/backup_records.dart';
import 'package:we_repkg/provider/backup.dart';
import 'package:we_repkg/utils/backup_diff.dart';
import 'package:we_repkg/utils/cancel_token.dart';

void main() {
  late Directory temporary;

  setUp(() {
    temporary = Directory.systemTemp.createTempSync('backup-verification');
  });

  tearDown(() {
    if (temporary.existsSync()) temporary.deleteSync(recursive: true);
  });

  test('accepts equivalent pixels and texture serialization', () async {
    final fixtures = _pair(temporary);
    final image.Image pixels = image.Image(width: 2, height: 2);
    image.fill(pixels, color: image.ColorRgba8(20, 40, 60, 255));
    File(
      path.join(fixtures.packed.path, 'preview.png'),
    ).writeAsBytesSync(image.encodePng(pixels));
    File(
      path.join(fixtures.unpacked.path, 'preview.bmp'),
    ).writeAsBytesSync(image.encodeBmp(pixels));
    _writeContent(fixtures.extracted, texture: 'packed bytes');
    _writeContent(fixtures.unpacked, texture: 'unpacked bytes');

    final BackupCopyVerification result = await verifyPackedBackupCopy(
      tool: 'unused',
      packedFolder: fixtures.packed,
      unpackedFolder: fixtures.unpacked,
      extract: _copyExtraction(fixtures.extracted),
      convertTexture: _convertMatchingTexture,
    );

    expect(result.status, BackupCopyVerificationStatus.equivalent);
    expect(result.changes.modified, isEmpty);
  });

  test('trial PNG decoder falls back to Dart when it declines', () async {
    final fixtures = _pair(temporary);
    _writeContent(fixtures.extracted, texture: 'same');
    _writeContent(fixtures.unpacked, texture: 'same');
    final image.Image edited = image.Image(width: 2, height: 2);
    image.fill(edited, color: image.ColorRgba8(9, 8, 7, 255));
    File(
      path.join(fixtures.unpacked.path, 'materials', 'sample.png'),
    ).writeAsBytesSync(image.encodePng(edited));
    int calls = 0;

    final BackupCopyVerification result = await verifyPackedBackupCopy(
      tool: 'unused',
      packedFolder: fixtures.packed,
      unpackedFolder: fixtures.unpacked,
      extract: _copyExtraction(fixtures.extracted),
      comparePngPixels: (File first, File second) async {
        calls++;
        return null;
      },
    );

    expect(calls, greaterThan(0));
    expect(result.status, BackupCopyVerificationStatus.different);
    expect(
      result.changes.modified,
      contains(path.join('materials', 'sample.png')),
    );
  });

  test('reports an edited unpacked scene as different', () async {
    final fixtures = _pair(temporary);
    _writeContent(fixtures.extracted, texture: 'same');
    _writeContent(fixtures.unpacked, texture: 'same');
    File(
      path.join(fixtures.unpacked.path, 'scene.json'),
    ).writeAsStringSync('{"changed":true}');

    final BackupCopyVerification result = await verifyPackedBackupCopy(
      tool: 'unused',
      packedFolder: fixtures.packed,
      unpackedFolder: fixtures.unpacked,
      extract: _copyExtraction(fixtures.extracted),
    );

    expect(result.status, BackupCopyVerificationStatus.different);
    expect(result.changes.modified, contains('scene.json'));
  });

  test('cancelled verification cannot report identical', () async {
    final fixtures = _pair(temporary);
    _writeContent(fixtures.extracted, texture: 'same');
    _writeContent(fixtures.unpacked, texture: 'same');
    final CancelToken token = CancelToken();
    final BackupCopyVerification result = await verifyPackedBackupCopy(
      tool: 'unused',
      packedFolder: fixtures.packed,
      unpackedFolder: fixtures.unpacked,
      cancelToken: token,
      extract: (tool, package, output, receivedToken) async {
        expect(receivedToken, same(token));
        await _copyExtraction(fixtures.extracted)(
          tool,
          package,
          output,
          receivedToken,
        );
        token.cancel();
        return true;
      },
    );
    expect(result.status, BackupCopyVerificationStatus.unavailable);
  });

  test('concurrent verifications own separate temporary folders', () async {
    final fixtures = _pair(temporary);
    _writeContent(fixtures.extracted, texture: 'same');
    _writeContent(fixtures.unpacked, texture: 'same');
    final List<String> roots = <String>[];
    final Completer<void> bothStarted = Completer<void>();
    Future<bool> extract(
      String tool,
      File package,
      Directory output,
      CancelToken token,
    ) async {
      roots.add(output.parent.path);
      if (roots.length == 2) bothStarted.complete();
      await bothStarted.future.timeout(const Duration(seconds: 5));
      return _copyExtraction(fixtures.extracted)(tool, package, output, token);
    }

    final List<BackupCopyVerification> results = await Future.wait(
      List<Future<BackupCopyVerification>>.generate(
        2,
        (_) => verifyPackedBackupCopy(
          tool: 'unused',
          packedFolder: fixtures.packed,
          unpackedFolder: fixtures.unpacked,
          extract: extract,
        ),
      ),
    );

    expect(roots.toSet(), hasLength(2));
    expect(
      results.map((BackupCopyVerification result) => result.status),
      everyElement(BackupCopyVerificationStatus.equivalent),
    );
  });

  test('rejects a changed texture with a stale matching PNG', () async {
    final fixtures = _pair(temporary);
    _writeContent(fixtures.extracted, texture: 'packed bytes');
    _writeContent(fixtures.unpacked, texture: 'edited bytes');

    final BackupCopyVerification result = await verifyPackedBackupCopy(
      tool: 'unused',
      packedFolder: fixtures.packed,
      unpackedFolder: fixtures.unpacked,
      extract: _copyExtraction(fixtures.extracted),
      convertTexture: _convertEditedTexture,
    );

    expect(result.status, BackupCopyVerificationStatus.different);
    expect(
      result.changes.modified,
      contains(path.join('materials', 'sample.tex')),
    );
  });

  test('signature changes when an unpacked file changes', () async {
    final fixtures = _pair(temporary);
    _writeContent(fixtures.unpacked, texture: 'before');
    final String? before = await backupCopyVerificationSignature(
      packedFolder: fixtures.packed,
      unpackedFolder: fixtures.unpacked,
    );

    await Future<void>.delayed(const Duration(milliseconds: 2));
    File(
      path.join(fixtures.unpacked.path, 'scene.json'),
    ).writeAsStringSync('{"longer":true}');
    final String? after = await backupCopyVerificationSignature(
      packedFolder: fixtures.packed,
      unpackedFolder: fixtures.unpacked,
    );

    expect(after, isNot(before));
  });

  test('completed verification survives a cache round trip', () async {
    const BackupCopyVerification saved = BackupCopyVerification(
      status: BackupCopyVerificationStatus.different,
      signature: 'signature',
      changes: (
        modified: <String>['scene.json'],
        onlyPacked: <String>['packed.bin'],
        onlyUnpacked: <String>['added.png'],
      ),
    );

    await writeBackupVerificationCache(
      temporary.path,
      <String, BackupCopyVerification>{'demo': saved},
    );
    final BackupCopyVerification restored = (await readBackupVerificationCache(
      temporary.path,
    ))['demo']!;

    expect(restored.status, saved.status);
    expect(restored.signature, saved.signature);
    expect(restored.changes.modified, saved.changes.modified);
    expect(restored.changes.onlyPacked, saved.changes.onlyPacked);
    expect(restored.changes.onlyUnpacked, saved.changes.onlyUnpacked);
  });

  test('a second explicit check does not reuse the earlier result', () async {
    final fixtures = _pair(temporary);
    final File package = File(path.join(fixtures.packed.path, 'scene.pkg'));
    _writePackage(package, <String, List<int>>{
      'materials/mask.tex': _texturePrefix(mipmaps: 4),
    });
    File(
      path.join(fixtures.unpacked.path, 'scene.json'),
    ).writeAsStringSync('{}');
    final Directory materials = Directory(
      path.join(fixtures.unpacked.path, 'materials'),
    )..createSync();
    final File texture = File(path.join(materials.path, 'mask.tex'))
      ..writeAsBytesSync(_texturePrefix(mipmaps: 1));
    final File tool = File(path.join(temporary.path, 'RePKG.exe'))
      ..writeAsStringSync('fixture');
    final String signature = (await backupCopyVerificationSignature(
      packedFolder: fixtures.packed,
      unpackedFolder: fixtures.unpacked,
    ))!;
    final BackupVerificationCoordinator coordinator =
        BackupVerificationCoordinator();
    Future<BackupCopyVerification> verify() => coordinator.verify(
      backupRoot: temporary.path,
      name: 'example',
      tool: tool.path,
      packedFolder: fixtures.packed,
      unpackedFolder: fixtures.unpacked,
      signature: signature,
    );
    expect((await verify()).status, BackupCopyVerificationStatus.different);
    texture.writeAsBytesSync(_texturePrefix(mipmaps: 9));
    expect((await verify()).status, BackupCopyVerificationStatus.unavailable);
  });

  test('package index compares raw entries without extracting', () async {
    final File package = File(path.join(temporary.path, 'scene.pkg'));
    _writePackage(package, <String, List<int>>{
      'materials/壁纸.json': utf8.encode('{"same":true}'),
      'scene.json': utf8.encode('{"scene":1}'),
    });
    final ScenePackageIndex index = (await readScenePackageIndex(package))!;
    expect(
      index.entries.keys,
      containsAll(<String>[r'materials\壁纸.json', 'scene.json']),
    );
    expect(index.headerBytes, lessThan(await package.length()));

    final File unpacked = File(path.join(temporary.path, 'scene.json'))
      ..writeAsStringSync('{"scene":1}');
    final ScenePackageEntry entry = index.entries['scene.json']!;
    expect(
      await scenePackageEntryMatchesFile(
        package: package,
        index: index,
        entry: entry,
        unpacked: unpacked,
      ),
      isTrue,
    );
    unpacked.writeAsStringSync('{"scene":2}');
    expect(
      await scenePackageEntryMatchesFile(
        package: package,
        index: index,
        entry: entry,
        unpacked: unpacked,
      ),
      isFalse,
    );
  });

  test(
    'package index rejects path traversal and overlapping payloads',
    () async {
      final File package = File(path.join(temporary.path, 'scene.pkg'));
      _writePackage(package, <String, List<int>>{
        '../scene.json': utf8.encode('{}'),
      });
      expect(await readScenePackageIndex(package), isNull);

      _writePackage(
        package,
        <String, List<int>>{
          'first.bin': <int>[1, 2],
          'second.bin': <int>[3, 4],
        },
        offsets: <int>[0, 1],
      );
      expect(await readScenePackageIndex(package), isNull);
    },
  );

  test('texture header difference skips extraction', () async {
    final List<int> packedTexture = _texturePrefix(mipmaps: 4);
    final List<int> unpackedTexture = _texturePrefix(mipmaps: 1);
    expect(
      readSceneTextureSummary(
        Uint8List.fromList(packedTexture),
      )?.firstMipmapCount,
      4,
    );
    expect(
      readSceneTextureSummary(
        Uint8List.fromList(unpackedTexture),
      )?.firstMipmapCount,
      1,
    );
    final SceneTextureSummary packedSummary = readSceneTextureSummary(
      Uint8List.fromList(packedTexture),
    )!;
    final SceneTextureSummary otherMipmaps = readSceneTextureSummary(
      Uint8List.fromList(_texturePrefix(mipmaps: 9)),
    )!;
    expect(sceneTextureMetadataDiffers(packedSummary, otherMipmaps), isFalse);
    final fixtures = _pair(temporary);
    _writePackage(
      File(path.join(fixtures.packed.path, 'scene.pkg')),
      <String, List<int>>{
        'materials/mask.tex': packedTexture,
        'scene.json': utf8.encode('{}'),
      },
    );
    File(
      path.join(fixtures.unpacked.path, 'scene.json'),
    ).writeAsStringSync('{}');
    final Directory materials = Directory(
      path.join(fixtures.unpacked.path, 'materials'),
    )..createSync();
    File(
      path.join(materials.path, 'mask.tex'),
    ).writeAsBytesSync(unpackedTexture);

    final BackupCopyVerification result = await verifyPackedBackupCopy(
      tool: 'unused',
      packedFolder: fixtures.packed,
      unpackedFolder: fixtures.unpacked,
    );
    expect(result.status, BackupCopyVerificationStatus.different);
    expect(result.changes.modified, contains('materials/mask.tex'));

    File(
      path.join(materials.path, 'mask.tex'),
    ).writeAsBytesSync(_texturePrefix(mipmaps: 9));
    final BackupCopyVerification ambiguous = await verifyPackedBackupCopy(
      tool: 'missing-repkg-for-fallback-test',
      packedFolder: fixtures.packed,
      unpackedFolder: fixtures.unpacked,
    );
    expect(ambiguous.status, BackupCopyVerificationStatus.unavailable);
  });

  test('direct probe checks generated texture files without RePKG', () async {
    final fixtures = _pair(temporary);
    final image.Image pixels = image.Image(width: 2, height: 2);
    image.fill(pixels, color: image.ColorRgba8(10, 20, 30, 255));
    final List<int> png = image.encodePng(pixels);
    final List<int> texture = _encodedTexture(png);
    _writePackage(
      File(path.join(fixtures.packed.path, 'scene.pkg')),
      <String, List<int>>{
        'scene.json': utf8.encode('{"scene":1}'),
        'materials/sample.tex': texture,
      },
    );
    File(
      path.join(fixtures.unpacked.path, 'scene.json'),
    ).writeAsStringSync('{"scene":1}');
    final Directory materials = Directory(
      path.join(fixtures.unpacked.path, 'materials'),
    )..createSync();
    File(path.join(materials.path, 'sample.tex')).writeAsBytesSync(texture);
    final File generatedImage = File(path.join(materials.path, 'sample.png'))
      ..writeAsBytesSync(png);
    final SceneTextureSummary summary = readSceneTextureSummary(
      Uint8List.fromList(texture),
    )!;
    expect(sceneTextureGeneratedMetadata(summary)?['clampuvs'], false);
    File(
      path.join(materials.path, 'sample.tex-json'),
    ).writeAsStringSync(jsonEncode(sceneTextureGeneratedMetadata(summary)));

    final DirectBackupProbe matching = await probePackedBackupCopyDirect(
      packedFolder: fixtures.packed,
      unpackedFolder: fixtures.unpacked,
    );
    expect(matching.status, DirectBackupProbeStatus.candidateMatch);

    final List<int> changedTexture = List<int>.from(texture);
    changedTexture[42] ^= 1;
    File(
      path.join(materials.path, 'sample.tex'),
    ).writeAsBytesSync(changedTexture);
    final DirectBackupProbe changedUnknownField =
        await probePackedBackupCopyDirect(
          packedFolder: fixtures.packed,
          unpackedFolder: fixtures.unpacked,
        );
    expect(changedUnknownField.status, DirectBackupProbeStatus.candidateMatch);
    changedTexture[22] = 1;
    File(
      path.join(materials.path, 'sample.tex'),
    ).writeAsBytesSync(changedTexture);
    final DirectBackupProbe changedFlags = await probePackedBackupCopyDirect(
      packedFolder: fixtures.packed,
      unpackedFolder: fixtures.unpacked,
    );
    expect(changedFlags.status, DirectBackupProbeStatus.different);
    expect(changedFlags.changes.modified, contains('materials/sample.tex'));
    File(path.join(materials.path, 'sample.tex')).writeAsBytesSync(texture);

    image.fill(pixels, color: image.ColorRgba8(90, 20, 30, 255));
    generatedImage.writeAsBytesSync(image.encodePng(pixels));
    final DirectBackupProbe edited = await probePackedBackupCopyDirect(
      packedFolder: fixtures.packed,
      unpackedFolder: fixtures.unpacked,
    );
    expect(edited.status, DirectBackupProbeStatus.different);
    expect(edited.changes.modified, contains('materials/sample.tex'));

    generatedImage.writeAsBytesSync(png);
    File(
      path.join(materials.path, 'sample.tex'),
    ).writeAsStringSync('unsupported texture');
    final DirectBackupProbe unsupported = await probePackedBackupCopyDirect(
      packedFolder: fixtures.packed,
      unpackedFolder: fixtures.unpacked,
    );
    expect(unsupported.status, DirectBackupProbeStatus.unavailable);
    expect(
      unsupported.reasons,
      contains(DirectBackupProbeReason.textureLayoutUnsupported),
    );

    File(
      path.join(fixtures.unpacked.path, 'scene.json'),
    ).writeAsStringSync('{"edited":true}');
    final DirectBackupProbe incomplete = await probePackedBackupCopyDirect(
      packedFolder: fixtures.packed,
      unpackedFolder: fixtures.unpacked,
    );
    expect(incomplete.status, DirectBackupProbeStatus.differentIncomplete);
    expect(incomplete.changes.modified, contains('scene.json'));
    expect(
      incomplete.reasons,
      contains(DirectBackupProbeReason.textureLayoutUnsupported),
    );
    File(
      path.join(fixtures.unpacked.path, 'scene.json'),
    ).writeAsStringSync('{"scene":1}');

    File(path.join(materials.path, 'sample.tex')).deleteSync();
    generatedImage.deleteSync();
    File(path.join(materials.path, 'sample.tex-json')).deleteSync();
    final DirectBackupProbe missing = await probePackedBackupCopyDirect(
      packedFolder: fixtures.packed,
      unpackedFolder: fixtures.unpacked,
    );
    expect(missing.status, DirectBackupProbeStatus.different);
    expect(missing.changes.onlyPacked, hasLength(3));
  });

  test('direct probe checks an unchanged LZ4 raw texture', () async {
    final fixtures = _pair(temporary);
    final image.Image pixels = image.Image(width: 2, height: 2);
    image.fill(pixels, color: image.ColorRgba8(10, 20, 30, 255));
    final List<int> raw = pixels.getBytes(order: image.ChannelOrder.rgba);
    final List<int> png = image.encodePng(pixels);
    final List<int> texture = _rawTexture(<int>[0xf0, 1, ...raw]);
    _writePackage(
      File(path.join(fixtures.packed.path, 'scene.pkg')),
      <String, List<int>>{
        'scene.json': utf8.encode('{"scene":1}'),
        'materials/sample.tex': texture,
      },
    );
    File(
      path.join(fixtures.unpacked.path, 'scene.json'),
    ).writeAsStringSync('{"scene":1}');
    final Directory materials = Directory(
      path.join(fixtures.unpacked.path, 'materials'),
    )..createSync();
    File(path.join(materials.path, 'sample.tex')).writeAsBytesSync(texture);
    final File generatedImage = File(path.join(materials.path, 'sample.png'))
      ..writeAsBytesSync(png);
    final SceneTextureSummary summary = readSceneTextureSummary(
      Uint8List.fromList(texture),
    )!;
    File(
      path.join(materials.path, 'sample.tex-json'),
    ).writeAsStringSync(jsonEncode(sceneTextureGeneratedMetadata(summary)));

    final DirectBackupProbe matching = await probePackedBackupCopyDirect(
      packedFolder: fixtures.packed,
      unpackedFolder: fixtures.unpacked,
    );
    expect(matching.status, DirectBackupProbeStatus.candidateMatch);

    File(
      path.join(materials.path, 'sample.tex'),
    ).writeAsBytesSync(_rawTexture(<int>[0xf0, 1, ...raw], version4: true));
    final DirectBackupProbe version4 = await probePackedBackupCopyDirect(
      packedFolder: fixtures.packed,
      unpackedFolder: fixtures.unpacked,
    );
    expect(version4.status, DirectBackupProbeStatus.candidateMatch);
    File(path.join(materials.path, 'sample.tex')).writeAsBytesSync(texture);

    final List<int> editedRaw = List<int>.from(texture)..[89] = 11;
    File(path.join(materials.path, 'sample.tex')).writeAsBytesSync(editedRaw);
    final DirectBackupProbe editedTexture = await probePackedBackupCopyDirect(
      packedFolder: fixtures.packed,
      unpackedFolder: fixtures.unpacked,
    );
    expect(editedTexture.status, DirectBackupProbeStatus.different);
    expect(editedTexture.changes.modified, contains('materials/sample.tex'));
    File(path.join(materials.path, 'sample.tex')).writeAsBytesSync(texture);

    image.fill(pixels, color: image.ColorRgba8(11, 20, 30, 255));
    generatedImage.writeAsBytesSync(image.encodePng(pixels));
    final DirectBackupProbe changed = await probePackedBackupCopyDirect(
      packedFolder: fixtures.packed,
      unpackedFolder: fixtures.unpacked,
    );
    expect(changed.status, DirectBackupProbeStatus.different);
    expect(changed.changes.modified, contains('materials/sample.tex'));

    generatedImage.writeAsBytesSync(png);
    final List<int> invalidTexture = List<int>.from(texture);
    invalidTexture[88] = 2;
    _writePackage(
      File(path.join(fixtures.packed.path, 'scene.pkg')),
      <String, List<int>>{
        'scene.json': utf8.encode('{"scene":1}'),
        'materials/sample.tex': invalidTexture,
      },
    );
    File(
      path.join(materials.path, 'sample.tex'),
    ).writeAsBytesSync(invalidTexture);
    final DirectBackupProbe invalid = await probePackedBackupCopyDirect(
      packedFolder: fixtures.packed,
      unpackedFolder: fixtures.unpacked,
    );
    expect(invalid.status, DirectBackupProbeStatus.unavailable);
  });

  test('direct probe compares a raw texture with an encoded texture', () async {
    final fixtures = _pair(temporary);
    final image.Image pixels = image.Image(width: 2, height: 2);
    image.fill(pixels, color: image.ColorRgba8(10, 20, 30, 255));
    final List<int> png = image.encodePng(pixels);
    final List<int> raw = pixels.getBytes(order: image.ChannelOrder.rgba);
    final List<int> packedTexture = _rawTexture(<int>[0xf0, 1, ...raw]);
    _writePackage(
      File(path.join(fixtures.packed.path, 'scene.pkg')),
      <String, List<int>>{
        'scene.json': utf8.encode('{"scene":1}'),
        'materials/sample.tex': packedTexture,
      },
    );
    File(
      path.join(fixtures.unpacked.path, 'scene.json'),
    ).writeAsStringSync('{"scene":1}');
    final Directory materials = Directory(
      path.join(fixtures.unpacked.path, 'materials'),
    )..createSync();
    final File looseTexture = File(path.join(materials.path, 'sample.tex'))
      ..writeAsBytesSync(_encodedTexture(png));
    File(path.join(materials.path, 'sample.png')).writeAsBytesSync(png);
    final SceneTextureSummary summary = readSceneTextureSummary(
      Uint8List.fromList(packedTexture),
    )!;
    File(
      path.join(materials.path, 'sample.tex-json'),
    ).writeAsStringSync(jsonEncode(sceneTextureGeneratedMetadata(summary)));

    final DirectBackupProbe matching = await probePackedBackupCopyDirect(
      packedFolder: fixtures.packed,
      unpackedFolder: fixtures.unpacked,
    );
    expect(matching.status, DirectBackupProbeStatus.candidateMatch);

    image.fill(pixels, color: image.ColorRgba8(11, 20, 30, 255));
    looseTexture.writeAsBytesSync(_encodedTexture(image.encodePng(pixels)));
    final DirectBackupProbe changed = await probePackedBackupCopyDirect(
      packedFolder: fixtures.packed,
      unpackedFolder: fixtures.unpacked,
    );
    expect(changed.status, DirectBackupProbeStatus.different);
    expect(changed.changes.modified, contains('materials/sample.tex'));
  });

  test('direct probe streams a video texture against its MP4', () async {
    final fixtures = _pair(temporary);
    final List<int> mp4 = <int>[0, 0, 0, 0, ...ascii.encode('ftypisom'), 1, 2];
    final List<int> texture = _rawTexture(
      mp4,
      flags: 32,
      compressed: false,
      decodedLength: 0,
    );
    _writePackage(
      File(path.join(fixtures.packed.path, 'scene.pkg')),
      <String, List<int>>{
        'scene.json': utf8.encode('{"scene":1}'),
        'materials/sample.tex': texture,
      },
    );
    File(
      path.join(fixtures.unpacked.path, 'scene.json'),
    ).writeAsStringSync('{"scene":1}');
    final Directory materials = Directory(
      path.join(fixtures.unpacked.path, 'materials'),
    )..createSync();
    File(path.join(materials.path, 'sample.tex')).writeAsBytesSync(texture);
    final File generated = File(path.join(materials.path, 'sample.mp4'))
      ..writeAsBytesSync(mp4);
    final SceneTextureSummary summary = readSceneTextureSummary(
      Uint8List.fromList(texture),
    )!;
    File(
      path.join(materials.path, 'sample.tex-json'),
    ).writeAsStringSync(jsonEncode(sceneTextureGeneratedMetadata(summary)));

    final DirectBackupProbe matching = await probePackedBackupCopyDirect(
      packedFolder: fixtures.packed,
      unpackedFolder: fixtures.unpacked,
    );
    expect(matching.status, DirectBackupProbeStatus.candidateMatch);

    generated.writeAsBytesSync(<int>[...mp4.take(mp4.length - 1), 3]);
    final DirectBackupProbe changed = await probePackedBackupCopyDirect(
      packedFolder: fixtures.packed,
      unpackedFolder: fixtures.unpacked,
    );
    expect(changed.status, DirectBackupProbeStatus.different);
    expect(changed.changes.modified, contains('materials/sample.tex'));
  });

  test(
    'direct probe compares main images and ignores secondary mipmaps',
    () async {
      final fixtures = _pair(temporary);
      final image.Image pixels = image.Image(width: 2, height: 2);
      pixels.setPixelRgba(0, 0, 10, 20, 30, 255);
      pixels.setPixelRgba(1, 0, 40, 50, 60, 255);
      pixels.setPixelRgba(0, 1, 70, 80, 90, 255);
      pixels.setPixelRgba(1, 1, 100, 110, 120, 255);
      final List<int> packedPng = image.encodePng(
        pixels,
        filter: image.PngFilter.none,
      );
      final List<int> unpackedPng = image.encodePng(
        pixels,
        filter: image.PngFilter.paeth,
      );
      expect(packedPng, isNot(equals(unpackedPng)));
      final image.Image small = image.Image(width: 1, height: 1);
      image.fill(small, color: image.ColorRgba8(10, 20, 30, 255));
      final List<int> secondMipmap = image.encodePng(small);
      final List<int> packedTexture = _encodedTexture(
        packedPng,
        secondMipmap: secondMipmap,
      );
      final List<int> unpackedTexture = _encodedTexture(
        unpackedPng,
        secondMipmap: secondMipmap,
      );
      _writePackage(
        File(path.join(fixtures.packed.path, 'scene.pkg')),
        <String, List<int>>{
          'scene.json': utf8.encode('{"scene":1}'),
          'materials/sample.tex': packedTexture,
        },
      );
      File(
        path.join(fixtures.unpacked.path, 'scene.json'),
      ).writeAsStringSync('{"scene":1}');
      final Directory materials = Directory(
        path.join(fixtures.unpacked.path, 'materials'),
      )..createSync();
      final File unpackedFile = File(path.join(materials.path, 'sample.tex'))
        ..writeAsBytesSync(unpackedTexture);
      final List<int> generatedPng = image.encodePng(pixels);
      File(
        path.join(materials.path, 'sample.png'),
      ).writeAsBytesSync(generatedPng);
      final SceneTextureSummary summary = readSceneTextureSummary(
        Uint8List.fromList(packedTexture),
      )!;
      File(
        path.join(materials.path, 'sample.tex-json'),
      ).writeAsStringSync(jsonEncode(sceneTextureGeneratedMetadata(summary)));

      final DirectBackupProbe candidate = await probePackedBackupCopyDirect(
        packedFolder: fixtures.packed,
        unpackedFolder: fixtures.unpacked,
      );
      expect(candidate.status, DirectBackupProbeStatus.candidateMatch);

      unpackedFile.writeAsBytesSync(_encodedTexture(unpackedPng));
      final DirectBackupProbe fewerMips = await probePackedBackupCopyDirect(
        packedFolder: fixtures.packed,
        unpackedFolder: fixtures.unpacked,
      );
      expect(fewerMips.status, DirectBackupProbeStatus.candidateMatch);

      image.fill(small, color: image.ColorRgba8(11, 20, 30, 255));
      unpackedFile.writeAsBytesSync(
        _encodedTexture(unpackedPng, secondMipmap: image.encodePng(small)),
      );
      final DirectBackupProbe changedLaterMipmap =
          await probePackedBackupCopyDirect(
            packedFolder: fixtures.packed,
            unpackedFolder: fixtures.unpacked,
          );
      expect(changedLaterMipmap.status, DirectBackupProbeStatus.candidateMatch);

      image.fill(pixels, color: image.ColorRgba8(12, 20, 30, 255));
      unpackedFile.writeAsBytesSync(
        _encodedTexture(image.encodePng(pixels), secondMipmap: secondMipmap),
      );
      final DirectBackupProbe changedMainImage =
          await probePackedBackupCopyDirect(
            packedFolder: fixtures.packed,
            unpackedFolder: fixtures.unpacked,
          );
      expect(changedMainImage.status, DirectBackupProbeStatus.different);
      expect(
        changedMainImage.changes.modified,
        contains('materials/sample.tex'),
      );
    },
  );
}

List<int> _rawTexture(
  List<int> payload, {
  bool version4 = false,
  int flags = 0,
  bool compressed = true,
  int decodedLength = 16,
}) {
  final BytesBuilder bytes = BytesBuilder();
  void name(String value) {
    bytes.add(utf8.encode(value));
    bytes.addByte(0);
  }

  void word(int value) {
    bytes.add(
      (ByteData(4)..setInt32(0, value, Endian.little)).buffer.asUint8List(),
    );
  }

  name('TEXV0005');
  name('TEXI0001');
  for (final int value in <int>[0, flags, 2, 2, 2, 2, 0]) {
    word(value);
  }
  name(version4 ? 'TEXB0004' : 'TEXB0003');
  word(1);
  word(-1);
  if (version4) word(0);
  word(1);
  for (final int value in <int>[
    2,
    2,
    compressed ? 1 : 0,
    decodedLength,
    payload.length,
  ]) {
    word(value);
  }
  bytes.add(payload);
  return bytes.toBytes();
}

List<int> _encodedTexture(List<int> png, {List<int>? secondMipmap}) {
  final BytesBuilder bytes = BytesBuilder();
  void name(String value) {
    bytes.add(utf8.encode(value));
    bytes.addByte(0);
  }

  void word(int value) {
    final ByteData data = ByteData(4)..setInt32(0, value, Endian.little);
    bytes.add(data.buffer.asUint8List());
  }

  name('TEXV0005');
  name('TEXI0001');
  for (final int value in <int>[0, 0, 2, 2, 2, 2, 0]) {
    word(value);
  }
  name('TEXB0003');
  word(1);
  word(13);
  word(secondMipmap == null ? 1 : 2);
  for (final int value in <int>[2, 2, 0, 0, png.length]) {
    word(value);
  }
  bytes.add(png);
  if (secondMipmap != null) {
    for (final int value in <int>[1, 1, 0, 0, secondMipmap.length]) {
      word(value);
    }
    bytes.add(secondMipmap);
  }
  return bytes.toBytes();
}

List<int> _texturePrefix({required int mipmaps}) {
  final BytesBuilder bytes = BytesBuilder();
  void name(String value) {
    bytes.add(utf8.encode(value));
    bytes.addByte(0);
  }

  void word(int value) {
    final ByteData data = ByteData(4)..setInt32(0, value, Endian.little);
    bytes.add(data.buffer.asUint8List());
  }

  name('TEXV0005');
  name('TEXI0001');
  for (final int value in <int>[0, 0, 2, 2, 2, 2, 0]) {
    word(value);
  }
  name('TEXB0002');
  word(1);
  word(mipmaps);
  return bytes.toBytes();
}

void _writePackage(
  File package,
  Map<String, List<int>> entries, {
  List<int>? offsets,
}) {
  final BytesBuilder bytes = BytesBuilder();
  void writeInt(int value) {
    final ByteData word = ByteData(4)..setInt32(0, value, Endian.little);
    bytes.add(word.buffer.asUint8List());
  }

  final List<int> magic = utf8.encode('PKGV0014');
  writeInt(magic.length);
  bytes.add(magic);
  writeInt(entries.length);
  int offset = 0;
  int index = 0;
  for (final MapEntry<String, List<int>> entry in entries.entries) {
    final List<int> name = utf8.encode(entry.key);
    writeInt(name.length);
    bytes.add(name);
    writeInt(offsets?[index] ?? offset);
    writeInt(entry.value.length);
    offset += entry.value.length;
    index++;
  }
  for (final List<int> data in entries.values) {
    bytes.add(data);
  }
  package.writeAsBytesSync(bytes.toBytes());
}

({Directory packed, Directory unpacked, Directory extracted}) _pair(
  Directory root,
) {
  final Directory packed = Directory(path.join(root.path, 'packed'))
    ..createSync();
  final Directory unpacked = Directory(path.join(root.path, 'unpacked'))
    ..createSync();
  final Directory extracted = Directory(path.join(root.path, 'extracted'))
    ..createSync();
  File(path.join(packed.path, 'scene.pkg')).writeAsStringSync('package');
  File(path.join(packed.path, 'project.json')).writeAsStringSync('{"a":1}');
  File(
    path.join(unpacked.path, 'project.json'),
  ).writeAsStringSync('{\n  "a": 1\n}');
  return (packed: packed, unpacked: unpacked, extracted: extracted);
}

void _writeContent(Directory root, {required String texture}) {
  final Directory materials = Directory(path.join(root.path, 'materials'))
    ..createSync(recursive: true);
  File(path.join(root.path, 'scene.json')).writeAsStringSync('{"scene":1}');
  File(path.join(materials.path, 'sample.tex')).writeAsStringSync(texture);
  File(
    path.join(materials.path, 'sample.tex-json'),
  ).writeAsStringSync('{"format":"rgba"}');
  final image.Image pixels = image.Image(width: 2, height: 2);
  image.fill(pixels, color: image.ColorRgba8(1, 2, 3, 255));
  File(
    path.join(materials.path, 'sample.png'),
  ).writeAsBytesSync(image.encodePng(pixels));
}

ScenePackageExtractor _copyExtraction(Directory source) =>
    (String _, File _, Directory output, CancelToken _) async {
      await for (final FileSystemEntity entity in source.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is! File) continue;
        final String relative = path.relative(entity.path, from: source.path);
        final File destination = File(path.join(output.path, relative));
        await destination.parent.create(recursive: true);
        await entity.copy(destination.path);
      }
      return true;
    };

Future<bool> _convertMatchingTexture(
  String _,
  File _,
  Directory output,
  CancelToken _,
) async {
  final image.Image pixels = image.Image(width: 2, height: 2);
  image.fill(pixels, color: image.ColorRgba8(1, 2, 3, 255));
  await File(
    path.join(output.path, 'sample.png'),
  ).writeAsBytes(image.encodePng(pixels));
  await File(
    path.join(output.path, 'sample.tex-json'),
  ).writeAsString('{"format":"rgba"}');
  return true;
}

Future<bool> _convertEditedTexture(
  String tool,
  File texture,
  Directory output,
  CancelToken token,
) async {
  final image.Image pixels = image.Image(width: 2, height: 2);
  image.fill(pixels, color: image.ColorRgba8(9, 8, 7, 255));
  await File(
    path.join(output.path, 'sample.png'),
  ).writeAsBytes(image.encodePng(pixels));
  await File(
    path.join(output.path, 'sample.tex-json'),
  ).writeAsString('{"format":"rgba"}');
  return true;
}
