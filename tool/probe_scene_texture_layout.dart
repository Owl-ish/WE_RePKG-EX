import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:we_repkg/cores/scene_pkg_index.dart';
import 'package:we_repkg/cores/scene_texture_summary.dart';

// Read-only coverage probe. A supported layout is not an equality verdict.
Future<void> main(List<String> arguments) async {
  if (arguments.length < 2 || arguments.length > 3) {
    stderr.writeln(
      'Usage: dart tool/probe_scene_texture_layout.dart '
      '<Workshop backup root> <MyProjects backup root> [comma-separated IDs]',
    );
    exitCode = 2;
    return;
  }
  final Directory firstRoot = Directory(arguments[0]);
  final Directory secondRoot = Directory(arguments[1]);
  if (!await firstRoot.exists() || !await secondRoot.exists()) {
    stderr.writeln('Both backup roots must exist');
    exitCode = 2;
    return;
  }
  final Set<String>? selected = arguments.length == 3
      ? arguments[2].split(',').map((String id) => id.toLowerCase()).toSet()
      : null;
  int pairs = 0;
  int fullySupportedPairs = 0;
  int pairsWithoutTextures = 0;
  int textures = 0;
  int supportedTextures = 0;
  int missingTextures = 0;
  int matchingPackedImages = 0;
  int matchingUnpackedImages = 0;
  int imagesDifferentOrAbsent = 0;
  final Map<String, int> mipmapCountDirections = <String, int>{};
  int countMismatchSameFirstSize = 0;
  int countMismatchDifferentFirstSize = 0;
  int countMismatchSameFirstBytes = 0;
  int countMismatchSharedMipsSame = 0;
  int countMismatchSharedMipsDifferent = 0;
  int countMismatchSharedMipsUnreadable = 0;
  final Stopwatch elapsed = Stopwatch()..start();

  await for (final FileSystemEntity entity in firstRoot.list(
    followLinks: false,
  )) {
    if (entity is! Directory) continue;
    final String id = path.basename(entity.path);
    if (selected != null && !selected.contains(id.toLowerCase())) continue;
    final Directory other = Directory(path.join(secondRoot.path, id));
    if (!await other.exists()) continue;
    final File firstPackage = File(path.join(entity.path, 'scene.pkg'));
    final File secondPackage = File(path.join(other.path, 'scene.pkg'));
    final bool firstPacked =
        await firstPackage.exists() &&
        !await File(path.join(entity.path, 'scene.json')).exists();
    final bool secondPacked =
        await secondPackage.exists() &&
        !await File(path.join(other.path, 'scene.json')).exists();
    if (firstPacked == secondPacked) continue;
    final Directory unpacked = firstPacked ? other : entity;
    if (!await File(path.join(unpacked.path, 'scene.json')).exists()) continue;
    final File package = firstPacked ? firstPackage : secondPackage;
    pairs++;
    final ScenePackageIndex? index = await readScenePackageIndex(package);
    if (index == null) continue;
    bool supportedPair = true;
    int pairTextures = 0;
    for (final ScenePackageEntry entry in index.entries.values) {
      if (path.extension(entry.path).toLowerCase() != '.tex') continue;
      pairTextures++;
      textures++;
      final File counterpart = File(
        path.joinAll(<String>[
          unpacked.path,
          ...entry.path.split(RegExp(r'[/\\]')),
        ]),
      );
      if (!await counterpart.exists()) {
        missingTextures++;
        supportedPair = false;
        continue;
      }
      final SceneTextureEncodedImage? packedImage =
          await readSceneTextureEncodedImage(
            package,
            offset: index.headerBytes + entry.offset,
            length: entry.length,
          );
      final SceneTextureEncodedImage? unpackedImage =
          await readSceneTextureEncodedImage(counterpart);
      if (packedImage == null || unpackedImage == null) {
        supportedPair = false;
      } else {
        supportedTextures++;
        final bool countMismatch =
            packedImage.mipmaps.length != unpackedImage.mipmaps.length;
        if (countMismatch) {
          final String direction =
              '${packedImage.mipmaps.length} packed → ${unpackedImage.mipmaps.length} unpacked';
          mipmapCountDirections.update(
            direction,
            (int count) => count + 1,
            ifAbsent: () => 1,
          );
          final SceneTextureMipmap packedFirst = packedImage.mipmaps.first;
          final SceneTextureMipmap unpackedFirst = unpackedImage.mipmaps.first;
          if (packedFirst.width == unpackedFirst.width &&
              packedFirst.height == unpackedFirst.height) {
            countMismatchSameFirstSize++;
          } else {
            countMismatchDifferentFirstSize++;
          }
          final bool? sharedSame = await _sharedMipBytesMatch(
            package,
            packedImage,
            counterpart,
            unpackedImage,
          );
          if (sharedSame == true) {
            countMismatchSharedMipsSame++;
          } else if (sharedSame == false) {
            countMismatchSharedMipsDifferent++;
          } else {
            countMismatchSharedMipsUnreadable++;
          }
        }
        final String imageRelative =
            '${entry.path.substring(0, entry.path.length - 4)}${packedImage.extension}';
        final File generatedImage = File(
          path.joinAll(<String>[
            unpacked.path,
            ...imageRelative.split(RegExp(r'[/\\]')),
          ]),
        );
        if (packedImage.extension != unpackedImage.extension ||
            !await generatedImage.exists()) {
          imagesDifferentOrAbsent++;
          continue;
        }
        final bool? packedMatch = await fileSegmentMatchesFile(
          source: package,
          offset: packedImage.payloadOffset,
          length: packedImage.payloadLength,
          counterpart: generatedImage,
        );
        final bool? unpackedMatch = await fileSegmentMatchesFile(
          source: counterpart,
          offset: unpackedImage.payloadOffset,
          length: unpackedImage.payloadLength,
          counterpart: generatedImage,
        );
        if (packedMatch == true) matchingPackedImages++;
        if (unpackedMatch == true) matchingUnpackedImages++;
        if (countMismatch && packedMatch == true && unpackedMatch == true) {
          countMismatchSameFirstBytes++;
        }
        if (packedMatch != true || unpackedMatch != true) {
          imagesDifferentOrAbsent++;
        }
      }
    }
    if (pairTextures == 0) pairsWithoutTextures++;
    if (supportedPair && pairTextures > 0) fullySupportedPairs++;
  }
  elapsed.stop();
  stdout.writeln(
    '$pairs pairs; $fullySupportedPairs with TEX have all matched layouts '
    'supported; $pairsWithoutTextures contain no TEX',
  );
  stdout.writeln(
    '$supportedTextures/$textures matched TEX layouts supported; '
    '$missingTextures missing counterparts',
  );
  stdout.writeln(
    'Embedded image bytes match generated file: '
    '$matchingPackedImages packed, $matchingUnpackedImages unpacked; '
    '$imagesDifferentOrAbsent differing/absent cases',
  );
  stdout.writeln('${elapsed.elapsedMilliseconds} ms (read-only, no RePKG)');
  stdout.writeln('Mipmap count directions: $mipmapCountDirections');
  stdout.writeln(
    'Count-mismatch first image: $countMismatchSameFirstSize same size, '
    '$countMismatchDifferentFirstSize different size, '
    '$countMismatchSameFirstBytes identical encoded bytes',
  );
  stdout.writeln(
    'Count-mismatch shared secondary mips: $countMismatchSharedMipsSame '
    'same bytes, $countMismatchSharedMipsDifferent different bytes, '
    '$countMismatchSharedMipsUnreadable unreadable',
  );
  stdout.writeln(
    'No content equality or deletion eligibility was established.',
  );
}

Future<bool?> _sharedMipBytesMatch(
  File packed,
  SceneTextureEncodedImage packedImage,
  File unpacked,
  SceneTextureEncodedImage unpackedImage,
) async {
  RandomAccessFile? packedInput;
  RandomAccessFile? unpackedInput;
  try {
    packedInput = await packed.open();
    unpackedInput = await unpacked.open();
    final int count = packedImage.mipmaps.length < unpackedImage.mipmaps.length
        ? packedImage.mipmaps.length
        : unpackedImage.mipmaps.length;
    for (int index = 1; index < count; index++) {
      final SceneTextureMipmap a = packedImage.mipmaps[index];
      final SceneTextureMipmap b = unpackedImage.mipmaps[index];
      if (a.width != b.width ||
          a.height != b.height ||
          a.compression != b.compression ||
          a.decodedLength != b.decodedLength ||
          a.payloadLength != b.payloadLength) {
        return false;
      }
      await packedInput.setPosition(a.payloadOffset);
      await unpackedInput.setPosition(b.payloadOffset);
      int remaining = a.payloadLength;
      while (remaining > 0) {
        final int chunk = remaining < 64 * 1024 ? remaining : 64 * 1024;
        final List<int> first = await packedInput.read(chunk);
        final List<int> second = await unpackedInput.read(chunk);
        if (first.length != chunk || second.length != chunk) return null;
        for (int byte = 0; byte < chunk; byte++) {
          if (first[byte] != second[byte]) return false;
        }
        remaining -= chunk;
      }
    }
    return true;
  } on FileSystemException {
    return null;
  } finally {
    await packedInput?.close();
    await unpackedInput?.close();
  }
}
