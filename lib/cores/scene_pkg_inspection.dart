// scene.pkg inspection and backup-content comparison core.
//
// Owns read-only direct comparison, RePKG-backed inspection, cancellation,
// retained temporary folders, and cleanup. Confirmation, localization,
// previews, and per-file Backup choices stay in the UI layer.

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as image;
import 'package:path/path.dart' as path;
import 'package:we_repkg/constants/wallpaper_files.dart';
import 'package:we_repkg/cores/backup.dart';
import 'package:we_repkg/cores/extract.dart';
import 'package:we_repkg/cores/scene_pkg_index.dart';
import 'package:we_repkg/cores/scene_texture_summary.dart';
import 'package:we_repkg/src/rust/api/simple.dart';
import 'package:we_repkg/src/rust/frb_generated.dart';
import 'package:we_repkg/utils/cancel_token.dart';
import 'package:we_repkg/utils/backup_diff.dart';
import 'package:we_repkg/utils/repkg_output.dart';

/// File differences produced by comparing two extracted scene.pkg folders.
typedef ScenePkgExtractionComparison = ({BackupFileChanges changes});

/// Comparison result plus retained extraction folders used by detail previews.
typedef ScenePkgInspectionResult = ({
  BackupFileChanges changes,
  String rootFolder,
  String leftFolder,
  String rightFolder,
});

/// Indicates that a scene.pkg inspection could not complete safely.
class ScenePkgInspectionException implements Exception {
  const ScenePkgInspectionException();
}

/// A selected extraction cannot be saved without changing another file.
class ScenePkgSaveException implements Exception {
  const ScenePkgSaveException(this.reason, {this.possiblePartialFile = false});

  final ScenePkgSaveFailure reason;
  final bool possiblePartialFile;
}

enum ScenePkgSaveFailure {
  invalidSource,
  protectedDestination,
  exists,
  writeFailed,
}

const Duration _staleSessionAge = Duration(days: 1);

typedef ScenePackageExtractor =
    Future<bool> Function(
      String tool,
      File package,
      Directory output,
      CancelToken token,
    );

typedef SceneTextureConverter =
    Future<bool> Function(
      String tool,
      File texture,
      Directory output,
      CancelToken token,
    );

/// Optional trial decoder. Null or an error keeps the existing Dart comparison.
typedef ScenePngComparator = Future<bool?> Function(File first, File second);

/// Optional native fast path for an indexed image payload inside a package.
typedef SceneImageSegmentComparator =
    Future<bool?> Function(
      File source,
      int offset,
      int length,
      File counterpart,
    );

const Set<String> _semanticImageExtensions = <String>{
  '.png',
  '.jpg',
  '.jpeg',
  '.webp',
  '.bmp',
  '.gif',
};
const Set<String> _nativeImageExtensions = <String>{
  '.png',
  '.jpg',
  '.jpeg',
  '.gif',
};

enum DirectBackupProbeStatus {
  candidateMatch,
  different,
  differentIncomplete,
  unavailable,
}

enum DirectBackupProbeReason {
  inputUnavailable,
  packageUnavailable,
  packageContainsWrapper,
  generatedFileAmbiguous,
  textureLayoutUnsupported,
  textureHeaderDifferent,
  generatedImageUnreadable,
  generatedMetadataUnreadable,
  fileComparisonUnavailable,
}

typedef DirectBackupProbe = ({
  DirectBackupProbeStatus status,
  BackupCopyVerificationChanges changes,
  Set<DirectBackupProbeReason> reasons,
});

/// Diagnostic stage durations for one direct comparison; image time is part
/// of the asset pass, so [otherAssets] excludes it.
typedef DirectBackupProbeTiming = ({
  Duration inventory,
  Duration imageChecks,
  Duration imageByteChecks,
  Duration imagePixelFallbacks,
  Duration rawTextureChecks,
  int nativePngCalls,
  int nativeJpegCalls,
  int nativeGifCalls,
  int nativeDeclines,
  Duration otherAssets,
  Duration finalSignature,
});

enum _DirectImageStage { bytes, pixels, rawTexture }

/// A cheap invalidation key for a packed/unpacked verification result.
///
/// Deletion still performs a fresh semantic comparison. This signature only
/// prevents ordinary edits from showing a stale cached status in the grid.
Future<String?> backupCopyVerificationSignature({
  required Directory packedFolder,
  required Directory unpackedFolder,
}) async {
  final List<String>? packed = await _verificationManifest(packedFolder);
  final List<String>? unpacked = await _verificationManifest(unpackedFolder);
  if (packed == null || unpacked == null) return null;
  return sha256
      .convert(
        utf8.encode(
          'packed\n${packed.join('\n')}\nunpacked\n${unpacked.join('\n')}',
        ),
      )
      .toString();
}

Future<List<String>?> _verificationManifest(Directory folder) async {
  try {
    if (!await folder.exists()) return null;
    final List<String> entries = <String>[];
    await for (final FileSystemEntity entity in folder.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is Link) return null;
      if (entity is! File) continue;
      final String relative = path.relative(entity.path, from: folder.path);
      if (isRebuiltShaderPath(relative)) continue;
      final FileStat stat = await entity.stat();
      if (stat.type != FileSystemEntityType.file) return null;
      entries.add(
        '${relative.toLowerCase().replaceAll('/', r'\')}:${stat.size}:${stat.modified.microsecondsSinceEpoch}',
      );
    }
    entries.sort();
    return entries;
  } on FileSystemException {
    return null;
  }
}

/// Read-only whole-pair trial comparing primary wallpaper assets. Secondary
/// texture mipmaps do not affect this result. An incomplete difference proves
/// the pair differs, but its changed-file list may omit unsupported textures.
/// Candidate matches have no durable content signature and must not authorize
/// backup deletion yet.
Future<DirectBackupProbe> probePackedBackupCopyDirect({
  required Directory packedFolder,
  required Directory unpackedFolder,
  CancelToken? cancelToken,
  void Function(DirectBackupProbeTiming timing)? onTiming,
  bool useNativeImages = true,
}) async {
  int nativePngCalls = 0;
  int nativeJpegCalls = 0;
  int nativeGifCalls = 0;
  int nativeDeclines = 0;
  final SceneImageSegmentComparator? compareImageSegment =
      useNativeImages && RustLib.instance.initialized
      ? (File source, int offset, int length, File counterpart) async {
          if (onTiming != null) {
            switch (path.extension(counterpart.path).toLowerCase()) {
              case '.png':
                nativePngCalls++;
                break;
              case '.jpg':
              case '.jpeg':
                nativeJpegCalls++;
                break;
              case '.gif':
                nativeGifCalls++;
                break;
            }
          }
          try {
            final bool? result = await compareImageSegmentRust(
              sourcePath: source.path,
              offset: BigInt.from(offset),
              length: BigInt.from(length),
              counterpartPath: counterpart.path,
            );
            if (result == null && onTiming != null) nativeDeclines++;
            return result;
          } catch (_) {
            if (onTiming != null) nativeDeclines++;
            rethrow;
          }
        }
      : null;
  final Future<bool?> Function(File, File)? compareImageFiles =
      compareImageSegment == null
      ? null
      : (File first, File second) async =>
            compareImageSegment(first, 0, await first.length(), second);
  final Stopwatch totalTime = Stopwatch()..start();
  Duration imageTime = Duration.zero;
  Duration imageByteTime = Duration.zero;
  Duration imagePixelTime = Duration.zero;
  Duration rawTextureTime = Duration.zero;
  void recordImageStage(_DirectImageStage stage, Duration elapsed) {
    switch (stage) {
      case _DirectImageStage.bytes:
        imageByteTime += elapsed;
        break;
      case _DirectImageStage.pixels:
        imagePixelTime += elapsed;
        break;
      case _DirectImageStage.rawTexture:
        rawTextureTime += elapsed;
        break;
    }
  }

  final void Function(_DirectImageStage, Duration)? onImageStage =
      onTiming == null ? null : recordImageStage;
  Future<bool?> imageCheck(Future<bool?> Function() compare) async {
    if (onTiming == null) return compare();
    final Stopwatch watch = Stopwatch()..start();
    try {
      return await compare();
    } finally {
      imageTime += watch.elapsed;
    }
  }

  final CancelToken token = cancelToken ?? CancelToken();
  DirectBackupProbe unavailable(DirectBackupProbeReason reason) => (
    status: DirectBackupProbeStatus.unavailable,
    changes: (
      modified: <String>[],
      onlyPacked: <String>[],
      onlyUnpacked: <String>[],
    ),
    reasons: <DirectBackupProbeReason>{reason},
  );
  final String? before = await backupCopyVerificationSignature(
    packedFolder: packedFolder,
    unpackedFolder: unpackedFolder,
  );
  if (before == null ||
      token.isCancelled ||
      await inspectBackupCopyFormat(packedFolder) != BackupCopyFormat.packed ||
      await inspectBackupCopyFormat(unpackedFolder) !=
          BackupCopyFormat.unpacked) {
    return unavailable(DirectBackupProbeReason.inputUnavailable);
  }
  final File package = File(
    path.join(packedFolder.path, WallpaperFiles.packedScene),
  );
  final ScenePackageIndex? index = await readScenePackageIndex(package);
  final Map<String, File>? unpackedFiles = await _semanticFiles(
    unpackedFolder,
    skipWrapperFiles: true,
  );
  if (index == null || unpackedFiles == null) {
    return unavailable(DirectBackupProbeReason.packageUnavailable);
  }
  final Duration inventoryTime = totalTime.elapsed;

  final List<String> modified = <String>[];
  final List<String> onlyPacked = <String>[];
  final List<String> onlyUnpacked = <String>[];
  final Set<String> seen = <String>{};
  final Set<DirectBackupProbeReason> reasons = <DirectBackupProbeReason>{};
  for (final MapEntry<String, ScenePackageEntry> indexed
      in index.entries.entries) {
    if (token.isCancelled) {
      return unavailable(DirectBackupProbeReason.inputUnavailable);
    }
    final String key = indexed.key;
    final ScenePackageEntry entry = indexed.value;
    if (isRebuiltShaderPath(entry.path)) continue;
    if (_isWrapperFile(entry.path)) {
      reasons.add(DirectBackupProbeReason.packageContainsWrapper);
      continue;
    }
    final File? counterpart = unpackedFiles[key];
    if (counterpart == null) {
      onlyPacked.add(entry.path);
      if (path.extension(key).toLowerCase() == '.tex') {
        final SceneTextureEncodedImage? packedImage =
            await readSceneTextureEncodedImage(
              package,
              offset: index.headerBytes + entry.offset,
              length: entry.length,
            );
        if (packedImage == null) {
          reasons.add(DirectBackupProbeReason.textureLayoutUnsupported);
          _markPossibleGeneratedTextureFiles(seen, key, unpackedFiles);
        } else {
          final String imageKey =
              '${key.substring(0, key.length - 4)}${packedImage.extension}';
          final String metadataKey = '$key-json';
          if (index.entries.containsKey(imageKey) ||
              index.entries.containsKey(metadataKey)) {
            reasons.add(DirectBackupProbeReason.generatedFileAmbiguous);
          }
          if (unpackedFiles.containsKey(imageKey)) {
            seen.add(imageKey);
            reasons.add(DirectBackupProbeReason.generatedFileAmbiguous);
          } else {
            onlyPacked.add(imageKey);
          }
          if (unpackedFiles.containsKey(metadataKey)) {
            seen.add(metadataKey);
            reasons.add(DirectBackupProbeReason.generatedFileAmbiguous);
          } else {
            onlyPacked.add(metadataKey);
          }
        }
      }
      continue;
    }
    seen.add(key);
    final bool? rawMatch = await scenePackageEntryMatchesFile(
      package: package,
      index: index,
      entry: entry,
      unpacked: counterpart,
      isCancelled: () => token.isCancelled,
    );
    if (rawMatch == null) {
      reasons.add(DirectBackupProbeReason.fileComparisonUnavailable);
      continue;
    }
    final String extension = path.extension(key).toLowerCase();
    if (extension == '.tex') {
      final SceneTextureEncodedImage? packedImage =
          await readSceneTextureEncodedImage(
            package,
            offset: index.headerBytes + entry.offset,
            length: entry.length,
          );
      final SceneTextureEncodedImage? unpackedImage =
          await readSceneTextureEncodedImage(counterpart);
      if (packedImage == null || unpackedImage == null) {
        final SceneTextureRawImage? packedRaw = packedImage == null
            ? await readSceneTextureRawImage(
                package,
                offset: index.headerBytes + entry.offset,
                length: entry.length,
              )
            : null;
        final SceneTextureRawImage? unpackedRaw = unpackedImage != null
            ? null
            : rawMatch
            ? packedRaw
            : await readSceneTextureRawImage(counterpart);
        final SceneTextureVideo? packedVideo =
            packedImage == null && packedRaw == null
            ? await readSceneTextureVideo(
                package,
                offset: index.headerBytes + entry.offset,
                length: entry.length,
              )
            : null;
        final SceneTextureVideo? unpackedVideo =
            unpackedImage != null || unpackedRaw != null
            ? null
            : rawMatch
            ? packedVideo
            : await readSceneTextureVideo(counterpart);
        if (packedImage == null &&
            packedRaw == null &&
            packedVideo == null &&
            rawMatch) {
          final SceneTextureGif? gif = await readSceneTextureGif(
            package,
            offset: index.headerBytes + entry.offset,
            length: entry.length,
          );
          if (gif != null) {
            final String imageKey = '${key.substring(0, key.length - 4)}.gif';
            final String metadataKey = '$key-json';
            seen.addAll(<String>[imageKey, metadataKey]);
            if (index.entries.containsKey(imageKey) ||
                index.entries.containsKey(metadataKey)) {
              reasons.add(DirectBackupProbeReason.generatedFileAmbiguous);
              continue;
            }
            if (unpackedFiles.containsKey(imageKey)) {
              reasons.add(DirectBackupProbeReason.generatedImageUnreadable);
            } else {
              onlyPacked.add(imageKey);
            }
            if (unpackedFiles.containsKey(metadataKey)) {
              reasons.add(DirectBackupProbeReason.generatedMetadataUnreadable);
            } else {
              onlyPacked.add(metadataKey);
            }
            continue;
          }
        }
        if ((packedImage != null || packedRaw != null || packedVideo != null) &&
            (unpackedImage != null ||
                unpackedRaw != null ||
                unpackedVideo != null)) {
          final SceneTextureSummary packedSummary =
              packedImage?.summary ??
              packedRaw?.summary ??
              packedVideo!.summary;
          final SceneTextureSummary unpackedSummary =
              unpackedImage?.summary ??
              unpackedRaw?.summary ??
              unpackedVideo!.summary;
          final String imageKey =
              '${key.substring(0, key.length - 4)}${unpackedVideo == null ? unpackedImage?.extension ?? '.png' : '.mp4'}';
          final String metadataKey = '$key-json';
          seen.addAll(<String>[imageKey, metadataKey]);
          if (index.entries.containsKey(imageKey) ||
              index.entries.containsKey(metadataKey)) {
            reasons.add(DirectBackupProbeReason.generatedFileAmbiguous);
            continue;
          }
          if (((packedSummary.flags ^ unpackedSummary.flags) & (4 | 32)) != 0 ||
              sceneTextureMetadataDiffers(
                packedSummary,
                unpackedSummary,
                compareMipSetting: false,
              )) {
            modified.add(entry.path);
            continue;
          }
          final File? generatedImage = unpackedFiles[imageKey];
          final File? generatedMetadata = unpackedFiles[metadataKey];
          if (generatedImage == null) {
            onlyPacked.add(imageKey);
          } else {
            final bool? packedMatches = await imageCheck(
              () => _texturePrimaryImageMatchesFile(
                source: package,
                encoded: packedImage,
                raw: packedRaw,
                video: packedVideo,
                generatedImage: generatedImage,
                token: token,
                onStage: onImageStage,
                compareImageSegment: compareImageSegment,
              ),
            );
            final bool? unpackedMatches = rawMatch
                ? packedMatches
                : await imageCheck(
                    () => _texturePrimaryImageMatchesFile(
                      source: counterpart,
                      encoded: unpackedImage,
                      raw: unpackedRaw,
                      video: unpackedVideo,
                      generatedImage: generatedImage,
                      token: token,
                      onStage: onImageStage,
                      compareImageSegment: compareImageSegment,
                    ),
                  );
            if (packedMatches == false || unpackedMatches == false) {
              modified.add(entry.path);
            } else if (packedMatches == null || unpackedMatches == null) {
              reasons.add(DirectBackupProbeReason.generatedImageUnreadable);
            }
          }
          if (generatedMetadata == null) {
            onlyPacked.add(metadataKey);
          } else {
            final bool? packedMatches = await _generatedTextureMetadataMatches(
              packedSummary,
              generatedMetadata,
            );
            final bool? unpackedMatches = rawMatch
                ? packedMatches
                : await _generatedTextureMetadataMatches(
                    unpackedSummary,
                    generatedMetadata,
                  );
            if (packedMatches == false || unpackedMatches == false) {
              modified.add(entry.path);
            } else if (packedMatches == null || unpackedMatches == null) {
              reasons.add(DirectBackupProbeReason.generatedMetadataUnreadable);
            }
          }
          continue;
        }
        reasons.add(DirectBackupProbeReason.textureLayoutUnsupported);
        if (!rawMatch) {
          final SceneTextureSummary? packedSummary = readSceneTextureSummary(
            await _packageEntryPrefix(package, index, entry) ?? Uint8List(0),
          );
          final SceneTextureSummary? unpackedSummary = readSceneTextureSummary(
            await _filePrefix(counterpart) ?? Uint8List(0),
          );
          if (packedSummary != null &&
              unpackedSummary != null &&
              sceneTextureMetadataDiffers(
                packedSummary,
                unpackedSummary,
                compareMipSetting: false,
              )) {
            modified.add(entry.path);
          } else {
            reasons.add(DirectBackupProbeReason.textureLayoutUnsupported);
          }
        } else {
          reasons.add(DirectBackupProbeReason.textureLayoutUnsupported);
        }
        _markPossibleGeneratedTextureFiles(seen, key, unpackedFiles);
        continue;
      }
      final String imageKey =
          '${key.substring(0, key.length - 4)}${packedImage.extension}';
      final String metadataKey = '$key-json';
      seen.addAll(<String>[imageKey, metadataKey]);
      if (index.entries.containsKey(imageKey) ||
          index.entries.containsKey(metadataKey)) {
        reasons.add(DirectBackupProbeReason.generatedFileAmbiguous);
        continue;
      }
      if (sceneTextureMetadataDiffers(
            packedImage.summary,
            unpackedImage.summary,
            compareMipSetting: false,
          ) ||
          packedImage.extension != unpackedImage.extension) {
        modified.add(entry.path);
        continue;
      }
      if (!rawMatch &&
          !sceneTexturePrimaryAssetLayoutMatches(packedImage, unpackedImage)) {
        reasons.add(DirectBackupProbeReason.textureHeaderDifferent);
        continue;
      }
      final File? generatedImage = unpackedFiles[imageKey];
      final File? generatedMetadata = unpackedFiles[metadataKey];
      if (generatedImage == null) onlyPacked.add(imageKey);
      if (generatedMetadata == null) onlyPacked.add(metadataKey);
      if (generatedImage != null) {
        final bool? packedPixels = await imageCheck(
          () => _imageSegmentMatchesFile(
            package,
            packedImage.payloadOffset,
            packedImage.payloadLength,
            generatedImage,
            token,
            onStage: onImageStage,
            compareImageSegment: compareImageSegment,
          ),
        );
        final bool? unpackedPixels = rawMatch
            ? packedPixels
            : await imageCheck(
                () => _imageSegmentMatchesFile(
                  counterpart,
                  unpackedImage.payloadOffset,
                  unpackedImage.payloadLength,
                  generatedImage,
                  token,
                  onStage: onImageStage,
                  compareImageSegment: compareImageSegment,
                ),
              );
        if (packedPixels == false || unpackedPixels == false) {
          modified.add(entry.path);
        } else if (packedPixels == null || unpackedPixels == null) {
          reasons.add(DirectBackupProbeReason.generatedImageUnreadable);
        }
      }
      if (generatedMetadata != null) {
        final bool? packedMetadata = await _generatedTextureMetadataMatches(
          packedImage.summary,
          generatedMetadata,
        );
        final bool? unpackedMetadata = rawMatch
            ? packedMetadata
            : await _generatedTextureMetadataMatches(
                unpackedImage.summary,
                generatedMetadata,
              );
        if (packedMetadata == false || unpackedMetadata == false) {
          modified.add(entry.path);
        } else if (packedMetadata == null || unpackedMetadata == null) {
          reasons.add(DirectBackupProbeReason.generatedMetadataUnreadable);
        }
      }
    } else if (!rawMatch) {
      bool? same;
      if (extension == '.json' || extension == '.tex-json') {
        same = await _jsonPackageEntryMatchesFile(
          package,
          index,
          entry,
          counterpart,
        );
      } else if (_semanticImageExtensions.contains(extension)) {
        same = await imageCheck(
          () => _imageSegmentMatchesFile(
            package,
            index.headerBytes + entry.offset,
            entry.length,
            counterpart,
            token,
            onStage: onImageStage,
            compareImageSegment: compareImageSegment,
          ),
        );
      } else {
        same = false;
      }
      if (same == false) {
        modified.add(entry.path);
      } else if (same == null) {
        reasons.add(DirectBackupProbeReason.fileComparisonUnavailable);
      }
    }
  }
  for (final MapEntry<String, File> file in unpackedFiles.entries) {
    if (!seen.contains(file.key)) {
      onlyUnpacked.add(
        path.relative(file.value.path, from: unpackedFolder.path),
      );
    }
  }
  try {
    await _compareWrapperMetadata(
      packedFolder: packedFolder,
      unpackedFolder: unpackedFolder,
      modified: modified,
      onlyPacked: onlyPacked,
      onlyUnpacked: onlyUnpacked,
      comparePngPixels: null,
      compareImageFiles: compareImageFiles,
    );
  } on FileSystemException {
    return unavailable(DirectBackupProbeReason.fileComparisonUnavailable);
  }
  final Duration beforeFinalSignature = totalTime.elapsed;
  final String? after = await backupCopyVerificationSignature(
    packedFolder: packedFolder,
    unpackedFolder: unpackedFolder,
  );
  final Duration finalSignatureTime = totalTime.elapsed - beforeFinalSignature;
  onTiming?.call((
    inventory: inventoryTime,
    imageChecks: imageTime,
    imageByteChecks: imageByteTime,
    imagePixelFallbacks: imagePixelTime,
    rawTextureChecks: rawTextureTime,
    nativePngCalls: nativePngCalls,
    nativeJpegCalls: nativeJpegCalls,
    nativeGifCalls: nativeGifCalls,
    nativeDeclines: nativeDeclines,
    otherAssets: beforeFinalSignature - inventoryTime - imageTime,
    finalSignature: finalSignatureTime,
  ));
  if (token.isCancelled || after != before) {
    return unavailable(DirectBackupProbeReason.inputUnavailable);
  }
  void sort(List<String> values) {
    values.sort(
      (String a, String b) => a.toLowerCase().compareTo(b.toLowerCase()),
    );
  }

  sort(modified);
  sort(onlyPacked);
  sort(onlyUnpacked);
  final bool different =
      modified.isNotEmpty || onlyPacked.isNotEmpty || onlyUnpacked.isNotEmpty;
  return (
    status: reasons.isNotEmpty
        ? different
              ? DirectBackupProbeStatus.differentIncomplete
              : DirectBackupProbeStatus.unavailable
        : different
        ? DirectBackupProbeStatus.different
        : DirectBackupProbeStatus.candidateMatch,
    changes: (
      modified: modified.toSet().toList(),
      onlyPacked: onlyPacked.toSet().toList(),
      onlyUnpacked: onlyUnpacked.toSet().toList(),
    ),
    reasons: reasons,
  );
}

void _markPossibleGeneratedTextureFiles(
  Set<String> seen,
  String key,
  Map<String, File> files,
) {
  final String stem = key.substring(0, key.length - 4);
  seen.add('$key-json');
  for (final String extension in _semanticImageExtensions) {
    if (files.containsKey('$stem$extension')) seen.add('$stem$extension');
  }
}

Future<bool?> _generatedTextureMetadataMatches(
  SceneTextureSummary summary,
  File file,
) async {
  final Map<String, Object?>? expected = sceneTextureGeneratedMetadata(summary);
  if (expected == null) return null;
  try {
    final Object? actual = jsonDecode(await file.readAsString());
    if (actual is! Map<String, dynamic>) return false;
    actual.remove('nomip');
    expected.remove('nomip');
    return jsonEncode(_canonicalJson(actual)) ==
        jsonEncode(_canonicalJson(expected));
  } on FileSystemException {
    return null;
  } on FormatException {
    return false;
  }
}

Future<bool?> _jsonPackageEntryMatchesFile(
  File package,
  ScenePackageIndex index,
  ScenePackageEntry entry,
  File counterpart,
) async {
  if (entry.length > 16 * 1024 * 1024) return null;
  RandomAccessFile? input;
  try {
    input = await package.open();
    await input.setPosition(index.headerBytes + entry.offset);
    final List<int> bytes = await input.read(entry.length);
    if (bytes.length != entry.length) return null;
    final Object? packed = jsonDecode(utf8.decode(bytes));
    final Object? unpacked = jsonDecode(await counterpart.readAsString());
    return jsonEncode(_canonicalJson(packed)) ==
        jsonEncode(_canonicalJson(unpacked));
  } on FileSystemException {
    return null;
  } on FormatException {
    return false;
  } finally {
    await input?.close();
  }
}

Future<bool?> _texturePrimaryImageMatchesFile({
  required File source,
  required SceneTextureEncodedImage? encoded,
  required SceneTextureRawImage? raw,
  required SceneTextureVideo? video,
  required File generatedImage,
  required CancelToken token,
  void Function(_DirectImageStage, Duration)? onStage,
  SceneImageSegmentComparator? compareImageSegment,
}) {
  if (token.isCancelled) return Future<bool?>.value(null);
  if (encoded != null) {
    return _imageSegmentMatchesFile(
      source,
      encoded.payloadOffset,
      encoded.payloadLength,
      generatedImage,
      token,
      onStage: onStage,
      compareImageSegment: compareImageSegment,
    );
  }
  if (raw != null) {
    return _timeDirectImageStage(
      _DirectImageStage.rawTexture,
      onStage,
      () => sceneTextureRawImageMatchesFile(source, raw, generatedImage),
    );
  }
  if (video != null) {
    return _timeDirectImageStage(
      _DirectImageStage.bytes,
      onStage,
      () => fileSegmentMatchesFile(
        source: source,
        offset: video.payloadOffset,
        length: video.payloadLength,
        counterpart: generatedImage,
        isCancelled: () => token.isCancelled,
      ),
    );
  }
  return Future<bool?>.value(null);
}

Future<bool?> _imageSegmentMatchesFile(
  File source,
  int offset,
  int length,
  File counterpart,
  CancelToken token, {
  void Function(_DirectImageStage, Duration)? onStage,
  SceneImageSegmentComparator? compareImageSegment,
}) async {
  final bool? raw = await _timeDirectImageStage(
    _DirectImageStage.bytes,
    onStage,
    () => fileSegmentMatchesFile(
      source: source,
      offset: offset,
      length: length,
      counterpart: counterpart,
      isCancelled: () => token.isCancelled,
    ),
  );
  if (raw != false || token.isCancelled) return raw;
  try {
    if (length > 64 * 1024 * 1024 ||
        await counterpart.length() > 64 * 1024 * 1024) {
      return null;
    }
    if (compareImageSegment != null &&
        _nativeImageExtensions.contains(
          path.extension(counterpart.path).toLowerCase(),
        )) {
      try {
        final bool? native = await _timeDirectImageStage(
          _DirectImageStage.pixels,
          onStage,
          () => compareImageSegment(source, offset, length, counterpart),
        );
        if (native != null) return native;
      } catch (_) {
        // Unsupported or failed native comparisons retain the Dart verdict.
      }
    }
    return await _timeDirectImageStage(
      _DirectImageStage.pixels,
      onStage,
      () => Isolate.run(
        () => _compareImageSegmentPixels(
          source.path,
          offset,
          length,
          counterpart.path,
        ),
      ),
    );
  } catch (_) {
    return null;
  }
}

Future<T> _timeDirectImageStage<T>(
  _DirectImageStage stage,
  void Function(_DirectImageStage, Duration)? onStage,
  Future<T> Function() run,
) async {
  if (onStage == null) return run();
  final Stopwatch watch = Stopwatch()..start();
  try {
    return await run();
  } finally {
    onStage(stage, watch.elapsed);
  }
}

bool? _compareImageSegmentPixels(
  String sourcePath,
  int offset,
  int length,
  String counterpartPath,
) {
  RandomAccessFile? input;
  try {
    input = File(sourcePath).openSync();
    if (offset < 0 ||
        offset > input.lengthSync() ||
        length > input.lengthSync() - offset) {
      return null;
    }
    input.setPositionSync(offset);
    final List<int> bytes = input.readSync(length);
    if (bytes.length != length) return null;
    final image.Image? first = image.decodeImage(Uint8List.fromList(bytes));
    final image.Image? second = image.decodeImage(
      File(counterpartPath).readAsBytesSync(),
    );
    if (first == null ||
        second == null ||
        first.width != second.width ||
        first.height != second.height ||
        first.numFrames != second.numFrames) {
      return null;
    }
    for (int frame = 0; frame < first.numFrames; frame++) {
      if (first.frames[frame].frameDuration !=
              second.frames[frame].frameDuration ||
          !_bytesEqual(
            first.frames[frame].getBytes(order: image.ChannelOrder.rgba),
            second.frames[frame].getBytes(order: image.ChannelOrder.rgba),
          )) {
        return false;
      }
    }
    return true;
  } catch (_) {
    return null;
  } finally {
    input?.closeSync();
  }
}

/// Extracts and semantically compares a packed backup with an unpacked copy.
/// Equivalent image pixels are accepted across encodings. A serialized `.tex`
/// difference is accepted only when decoding the unpacked texture reproduces
/// the packed image and both texture metadata sidecars.
Future<BackupCopyVerification> verifyPackedBackupCopy({
  required String tool,
  required Directory packedFolder,
  required Directory unpackedFolder,
  ScenePackageExtractor? extract,
  SceneTextureConverter? convertTexture,
  ScenePngComparator? comparePngPixels,
  CancelToken? cancelToken,
}) async {
  final CancelToken token = cancelToken ?? CancelToken();
  final String? before = await backupCopyVerificationSignature(
    packedFolder: packedFolder,
    unpackedFolder: unpackedFolder,
  );
  if (token.isCancelled ||
      before == null ||
      await inspectBackupCopyFormat(packedFolder) != BackupCopyFormat.packed ||
      await inspectBackupCopyFormat(unpackedFolder) !=
          BackupCopyFormat.unpacked) {
    return BackupCopyVerification(
      status: BackupCopyVerificationStatus.unavailable,
      signature: before ?? '',
    );
  }

  final File package = File(
    path.join(packedFolder.path, WallpaperFiles.packedScene),
  );
  if (extract == null) {
    final String? definiteDifference = await _differentTextureStructure(
      package,
      unpackedFolder,
      token,
    );
    if (token.isCancelled) {
      return BackupCopyVerification(
        status: BackupCopyVerificationStatus.unavailable,
        signature: before,
      );
    }
    if (definiteDifference != null) {
      final String? after = await backupCopyVerificationSignature(
        packedFolder: packedFolder,
        unpackedFolder: unpackedFolder,
      );
      if (token.isCancelled || after != before) {
        return BackupCopyVerification(
          status: BackupCopyVerificationStatus.unavailable,
          signature: after ?? before,
        );
      }
      return BackupCopyVerification(
        status: BackupCopyVerificationStatus.different,
        signature: before,
        changes: (
          modified: <String>[definiteDifference],
          onlyPacked: const <String>[],
          onlyUnpacked: const <String>[],
        ),
      );
    }
  }

  final Directory base = Directory(
    path.join(Directory.systemTemp.path, 'WeRePKG', 'backup-verify'),
  );
  Directory? root;
  try {
    if (token.isCancelled) throw const FormatException('Cancelled');
    await base.create(recursive: true);
    // Concurrent checks need OS-allocated names; a clock tick can repeat.
    root = await base.createTemp('pair-');
    final Directory output = Directory(path.join(root.path, 'packed'));
    await output.create(recursive: true);
    final bool extracted = await (extract ?? _extractPackage)(
      tool,
      package,
      output,
      token,
    );
    if (token.isCancelled || !extracted) {
      return BackupCopyVerification(
        status: BackupCopyVerificationStatus.unavailable,
        signature: before,
      );
    }
    final BackupCopyVerificationChanges? changes =
        await _comparePackedWithUnpacked(
          tool: tool,
          packedFolder: packedFolder,
          extractedFolder: output,
          unpackedFolder: unpackedFolder,
          conversionFolder: Directory(path.join(root.path, 'textures')),
          token: token,
          convertTexture: convertTexture ?? _convertTexture,
          comparePngPixels: comparePngPixels,
        );
    final String? after = await backupCopyVerificationSignature(
      packedFolder: packedFolder,
      unpackedFolder: unpackedFolder,
    );
    if (token.isCancelled || changes == null || after != before) {
      return BackupCopyVerification(
        status: BackupCopyVerificationStatus.unavailable,
        signature: after ?? before,
      );
    }
    final bool equivalent =
        changes.modified.isEmpty &&
        changes.onlyPacked.isEmpty &&
        changes.onlyUnpacked.isEmpty;
    return BackupCopyVerification(
      status: equivalent
          ? BackupCopyVerificationStatus.equivalent
          : BackupCopyVerificationStatus.different,
      signature: before,
      changes: changes,
    );
  } catch (_) {
    return BackupCopyVerification(
      status: BackupCopyVerificationStatus.unavailable,
      signature: before,
    );
  } finally {
    if (root != null) await _deleteTempDirectory(root);
  }
}

/// A changed TEX header setting proves a difference without extraction.
/// Other byte changes still need the full semantic path for pixels, generated
/// images, sidecars, and other package files.
Future<String?> _differentTextureStructure(
  File package,
  Directory unpackedFolder,
  CancelToken token,
) async {
  final ScenePackageIndex? index = await readScenePackageIndex(package);
  if (index == null) return null;
  for (final ScenePackageEntry entry in index.entries.values) {
    if (token.isCancelled) return null;
    if (path.extension(entry.path).toLowerCase() != '.tex') continue;
    final File unpacked = File(
      path.joinAll(<String>[
        unpackedFolder.path,
        ...entry.path.split(RegExp(r'[/\\]')),
      ]),
    );
    final bool? exact = await scenePackageEntryMatchesFile(
      package: package,
      index: index,
      entry: entry,
      unpacked: unpacked,
      isCancelled: () => token.isCancelled,
    );
    if (exact != false || !await unpacked.exists()) continue;
    final Uint8List? packedPrefix = await _packageEntryPrefix(
      package,
      index,
      entry,
    );
    final Uint8List? unpackedPrefix = await _filePrefix(unpacked);
    if (packedPrefix == null || unpackedPrefix == null) continue;
    final SceneTextureSummary? packedSummary = readSceneTextureSummary(
      packedPrefix,
    );
    final SceneTextureSummary? unpackedSummary = readSceneTextureSummary(
      unpackedPrefix,
    );
    if (packedSummary != null &&
        unpackedSummary != null &&
        sceneTextureMetadataDiffers(packedSummary, unpackedSummary)) {
      return entry.path;
    }
  }
  return null;
}

Future<Uint8List?> _packageEntryPrefix(
  File package,
  ScenePackageIndex index,
  ScenePackageEntry entry,
) async {
  RandomAccessFile? input;
  try {
    input = await package.open();
    await input.setPosition(index.headerBytes + entry.offset);
    return Uint8List.fromList(
      await input.read(entry.length < 128 ? entry.length : 128),
    );
  } on FileSystemException {
    return null;
  } finally {
    await input?.close();
  }
}

Future<Uint8List?> _filePrefix(File file) async {
  RandomAccessFile? input;
  try {
    input = await file.open();
    return Uint8List.fromList(await input.read(128));
  } on FileSystemException {
    return null;
  } finally {
    await input?.close();
  }
}

Future<bool> _extractPackage(
  String tool,
  File package,
  Directory output,
  CancelToken token,
) async {
  final result = await runRePKG(tool, <String>[
    'extract',
    '-c',
    '-o',
    output.path,
    package.path,
  ], token);
  final RePKGOutputSummary summary = summarizeRePKGOutput(
    result.stdout,
    result.stderr,
  );
  return result.exitCode == 0 && !summary.claimedSuccessWithoutWriting;
}

Future<BackupCopyVerificationChanges?> _comparePackedWithUnpacked({
  required String tool,
  required Directory packedFolder,
  required Directory extractedFolder,
  required Directory unpackedFolder,
  required Directory conversionFolder,
  required CancelToken token,
  required SceneTextureConverter convertTexture,
  required ScenePngComparator? comparePngPixels,
}) async {
  final Map<String, File>? packedFiles = await _semanticFiles(
    extractedFolder,
    skipWrapperFiles: true,
  );
  final Map<String, File>? unpackedFiles = await _semanticFiles(
    unpackedFolder,
    skipWrapperFiles: true,
  );
  if (packedFiles == null || unpackedFiles == null) return null;

  final List<String> modified = <String>[];
  final List<String> onlyPacked = <String>[];
  final List<String> onlyUnpacked = <String>[];
  final Set<String> keys = <String>{...packedFiles.keys, ...unpackedFiles.keys};
  int textureIndex = 0;
  for (final String key in keys) {
    if (token.isCancelled) return null;
    final File? packed = packedFiles[key];
    final File? unpacked = unpackedFiles[key];
    if (packed == null) {
      onlyUnpacked.add(_displayPath(unpacked!, unpackedFolder));
      continue;
    }
    if (unpacked == null) {
      onlyPacked.add(_displayPath(packed, extractedFolder));
      continue;
    }
    final bool? same = await _semanticFilesEqual(
      key: key,
      first: packed,
      second: unpacked,
      firstFiles: packedFiles,
      secondFiles: unpackedFiles,
      tool: tool,
      conversionFolder: Directory(
        path.join(conversionFolder.path, '${textureIndex++}'),
      ),
      token: token,
      convertTexture: convertTexture,
      comparePngPixels: comparePngPixels,
    );
    if (same == null) return null;
    if (!same) {
      modified.add(_displayPath(unpacked, unpackedFolder));
    }
  }

  await _compareWrapperMetadata(
    packedFolder: packedFolder,
    unpackedFolder: unpackedFolder,
    modified: modified,
    onlyPacked: onlyPacked,
    onlyUnpacked: onlyUnpacked,
    comparePngPixels: comparePngPixels,
  );
  void sort(List<String> values) => values.sort(
    (String a, String b) => a.toLowerCase().compareTo(b.toLowerCase()),
  );
  sort(modified);
  sort(onlyPacked);
  sort(onlyUnpacked);
  return (
    modified: modified,
    onlyPacked: onlyPacked,
    onlyUnpacked: onlyUnpacked,
  );
}

Future<Map<String, File>?> _semanticFiles(
  Directory folder, {
  bool skipWrapperFiles = false,
}) async {
  try {
    final Map<String, File> files = <String, File>{};
    await for (final FileSystemEntity entity in folder.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is Link) return null;
      if (entity is! File) continue;
      final String relative = path.relative(entity.path, from: folder.path);
      if (isRebuiltShaderPath(relative) ||
          (skipWrapperFiles && _isWrapperFile(relative))) {
        continue;
      }
      final String key = _pathKey(relative);
      if (files.containsKey(key)) return null;
      files[key] = entity;
    }
    return files;
  } on FileSystemException {
    return null;
  }
}

bool _isWrapperFile(String relative) {
  if (path.dirname(relative) != '.') return false;
  final String name = path.basename(relative).toLowerCase();
  return name == WallpaperFiles.project ||
      name == WallpaperFiles.packedScene ||
      path.basenameWithoutExtension(name) == WallpaperFiles.previewStem;
}

String _pathKey(String value) => value.toLowerCase().replaceAll('/', r'\');

String _displayPath(File file, Directory root) =>
    path.relative(file.path, from: root.path);

Future<bool?> _semanticFilesEqual({
  required String key,
  required File first,
  required File second,
  required Map<String, File> firstFiles,
  required Map<String, File> secondFiles,
  required String tool,
  required Directory conversionFolder,
  required CancelToken token,
  required SceneTextureConverter convertTexture,
  required ScenePngComparator? comparePngPixels,
}) async {
  if (token.isCancelled) return null;
  final bool? exact = await filesHaveSameContents(
    first,
    second,
    isCancelled: () => token.isCancelled,
  );
  if (token.isCancelled) return null;
  if (exact != false) return exact ?? false;
  final String extension = path.extension(key).toLowerCase();
  if (extension == '.json' || extension == '.tex-json') {
    return _jsonFilesEquivalent(first, second);
  }
  if (_semanticImageExtensions.contains(extension)) {
    return _imagesHaveSamePixels(
      first,
      second,
      bytesAlreadyDifferent: true,
      comparePngPixels: comparePngPixels,
    );
  }
  if (extension != '.tex') return false;

  final String stem = key.substring(0, key.length - extension.length);
  File? firstImage;
  for (final String imageExtension in _semanticImageExtensions) {
    final File? candidateFirst = firstFiles['$stem$imageExtension'];
    if (candidateFirst != null) {
      firstImage = candidateFirst;
      break;
    }
  }
  if (firstImage == null) return false;
  await conversionFolder.create(recursive: true);
  if (!await convertTexture(tool, second, conversionFolder, token)) {
    return null;
  }
  if (token.isCancelled) return null;
  final List<File> convertedImages = <File>[
    await for (final FileSystemEntity file in conversionFolder.list(
      followLinks: false,
    ))
      if (file is File &&
          _semanticImageExtensions.contains(
            path.extension(file.path).toLowerCase(),
          ))
        file,
  ];
  if (convertedImages.length != 1 ||
      !await _imagesHaveSamePixels(
        firstImage,
        convertedImages.single,
        comparePngPixels: comparePngPixels,
      )) {
    return false;
  }
  final File? firstMetadata = firstFiles['$key-json'];
  final File? secondMetadata = secondFiles['$key-json'];
  final File convertedMetadata = File(
    path.join(
      conversionFolder.path,
      '${path.basenameWithoutExtension(second.path)}.tex-json',
    ),
  );
  return firstMetadata != null &&
      secondMetadata != null &&
      await convertedMetadata.exists() &&
      await _jsonFilesEquivalent(firstMetadata, convertedMetadata) &&
      await _jsonFilesEquivalent(secondMetadata, convertedMetadata);
}

Future<bool> _convertTexture(
  String tool,
  File texture,
  Directory output,
  CancelToken token,
) async {
  final result = await runRePKG(tool, <String>[
    'extract',
    '-o',
    output.path,
    texture.path,
  ], token);
  final RePKGOutputSummary summary = summarizeRePKGOutput(
    result.stdout,
    result.stderr,
  );
  return result.exitCode == 0 && !summary.claimedSuccessWithoutWriting;
}

Future<bool> _imagesHaveSamePixels(
  File first,
  File second, {
  bool bytesAlreadyDifferent = false,
  ScenePngComparator? comparePngPixels,
  Future<bool?> Function(File, File)? compareImageFiles,
}) async {
  try {
    if (!bytesAlreadyDifferent &&
        await filesHaveSameContents(first, second) == true) {
      return true;
    }
    final String firstPath = first.path;
    final String secondPath = second.path;
    if (compareImageFiles != null &&
        _nativeImageExtensions.contains(
          path.extension(firstPath).toLowerCase(),
        ) &&
        _nativeImageExtensions.contains(
          path.extension(secondPath).toLowerCase(),
        )) {
      try {
        final bool? nativeResult = await compareImageFiles(first, second);
        if (nativeResult != null) return nativeResult;
      } catch (_) {
        // Unsupported image variants keep the existing Dart result.
      }
    }
    if (comparePngPixels != null &&
        path.extension(firstPath).toLowerCase() == '.png' &&
        path.extension(secondPath).toLowerCase() == '.png') {
      try {
        final bool? nativeResult = await comparePngPixels(first, second);
        if (nativeResult != null) return nativeResult;
      } catch (_) {
        // The trial decoder must not replace the existing verifier on failure.
      }
    }
    return await Isolate.run(() => _compareImagePixels(firstPath, secondPath));
  } catch (_) {
    return false;
  }
}

bool _compareImagePixels(String firstPath, String secondPath) {
  try {
    final image.Image? firstImage = image.decodeImage(
      File(firstPath).readAsBytesSync(),
    );
    final image.Image? secondImage = image.decodeImage(
      File(secondPath).readAsBytesSync(),
    );
    if (firstImage == null || secondImage == null) return false;
    if (firstImage.width != secondImage.width ||
        firstImage.height != secondImage.height ||
        firstImage.numFrames != secondImage.numFrames) {
      return false;
    }
    for (int index = 0; index < firstImage.numFrames; index++) {
      final image.Image firstFrame = firstImage.frames[index];
      final image.Image secondFrame = secondImage.frames[index];
      if (firstFrame.frameDuration != secondFrame.frameDuration ||
          !_bytesEqual(
            firstFrame.getBytes(order: image.ChannelOrder.rgba),
            secondFrame.getBytes(order: image.ChannelOrder.rgba),
          )) {
        return false;
      }
    }
    return true;
  } catch (_) {
    return false;
  }
}

bool _bytesEqual(Uint8List first, Uint8List second) {
  if (first.length != second.length) return false;
  for (int index = 0; index < first.length; index++) {
    if (first[index] != second[index]) return false;
  }
  return true;
}

Future<void> _compareWrapperMetadata({
  required Directory packedFolder,
  required Directory unpackedFolder,
  required List<String> modified,
  required List<String> onlyPacked,
  required List<String> onlyUnpacked,
  required ScenePngComparator? comparePngPixels,
  Future<bool?> Function(File, File)? compareImageFiles,
}) async {
  await for (final FileSystemEntity entity in packedFolder.list(
    recursive: true,
    followLinks: false,
  )) {
    if (entity is! File) continue;
    final String name = path.relative(entity.path, from: packedFolder.path);
    if (!_isWrapperFile(name) && !isRebuiltShaderPath(name)) {
      onlyPacked.add(name);
    }
  }
  final File packedProject = File(
    path.join(packedFolder.path, WallpaperFiles.project),
  );
  final File unpackedProject = File(
    path.join(unpackedFolder.path, WallpaperFiles.project),
  );
  final bool packedProjectExists = await packedProject.exists();
  final bool unpackedProjectExists = await unpackedProject.exists();
  if (packedProjectExists != unpackedProjectExists) {
    (packedProjectExists ? onlyPacked : onlyUnpacked).add(
      WallpaperFiles.project,
    );
  } else if (packedProjectExists &&
      !await _jsonFilesEquivalent(packedProject, unpackedProject)) {
    modified.add(WallpaperFiles.project);
  }

  final List<File> packedPreviews = await _rootPreviews(packedFolder);
  final List<File> unpackedPreviews = await _rootPreviews(unpackedFolder);
  if (packedPreviews.length != 1 || unpackedPreviews.length != 1) {
    if (packedPreviews.isNotEmpty) {
      onlyPacked.addAll(
        packedPreviews.map((File file) => path.basename(file.path)),
      );
    }
    if (unpackedPreviews.isNotEmpty) {
      onlyUnpacked.addAll(
        unpackedPreviews.map((File file) => path.basename(file.path)),
      );
    }
  } else if (!await _imagesHaveSamePixels(
    packedPreviews.single,
    unpackedPreviews.single,
    comparePngPixels: comparePngPixels,
    compareImageFiles: compareImageFiles,
  )) {
    modified.add(path.basename(unpackedPreviews.single.path));
  }
}

Future<List<File>> _rootPreviews(Directory folder) async {
  try {
    return <File>[
      await for (final FileSystemEntity entity in folder.list(
        followLinks: false,
      ))
        if (entity is File &&
            path.basenameWithoutExtension(entity.path).toLowerCase() ==
                WallpaperFiles.previewStem)
          entity,
    ];
  } on FileSystemException {
    return const <File>[];
  }
}

Future<bool> _jsonFilesEquivalent(File first, File second) async {
  try {
    final Object? firstJson = jsonDecode(await first.readAsString());
    final Object? secondJson = jsonDecode(await second.readAsString());
    return jsonEncode(_canonicalJson(firstJson)) ==
        jsonEncode(_canonicalJson(secondJson));
  } catch (_) {
    return await filesHaveSameContents(first, second) == true;
  }
}

Object? _canonicalJson(Object? value) {
  if (value is List<Object?>) {
    return <Object?>[for (final Object? item in value) _canonicalJson(item)];
  }
  if (value is Map<String, Object?>) {
    final List<String> keys = value.keys.toList()..sort();
    return <String, Object?>{
      for (final String key in keys) key: _canonicalJson(value[key]),
    };
  }
  return value;
}

/// Removes abandoned extraction sessions without touching recently active ones.
Future<void> _clearStaleSessions(Directory base) async {
  try {
    await base.create(recursive: true);
    final DateTime cutoff = DateTime.now().subtract(_staleSessionAge);
    await for (final FileSystemEntity entity in base.list(followLinks: false)) {
      if (entity is! Directory) continue;
      try {
        final FileStat stat = await entity.stat();
        if (stat.modified.isBefore(cutoff)) {
          await _deleteTempDirectory(entity);
        }
      } on FileSystemException {
        // Another process may be creating or removing a session concurrently.
      }
    }
  } on FileSystemException {
    // Inspection itself will report a real filesystem failure if the base path
    // remains unusable. Stale cleanup must never block a new attempt.
  }
}

/// Best-effort cleanup for temporary package extraction folders.
Future<void> _deleteTempDirectory(Directory directory) async {
  for (int attempt = 0; attempt < 3; attempt++) {
    try {
      if (!await directory.exists()) return;
      await directory.delete(recursive: true);
      return;
    } on FileSystemException {
      if (attempt == 2) return;
      await Future<void>.delayed(const Duration(milliseconds: 40));
    }
  }
}

/// Owns one temporary scene.pkg comparison session from extraction through cleanup.
///
/// The session deliberately has no Backup selection or UI policy. It returns
/// extracted file differences and keeps their temporary folders alive only long
/// enough for the caller to inspect them.
class ScenePkgInspectionSession {
  CancelToken? _token;
  bool _disposed = false;
  Directory? _retainedTempRoot;

  String get temporaryBasePath =>
      path.join(Directory.systemTemp.path, 'WeRePKG', 'pkg-diff');

  /// Creates the shared temporary base early so confirmation can show its path.
  Future<void> prepareTemporaryBase() async {
    try {
      await Directory(temporaryBasePath).create(recursive: true);
    } on FileSystemException {
      // Inspection reports the real failure later; confirmation can still show
      // the intended temporary location when pre-creation is blocked.
    }
  }

  /// Extracts both scene.pkg files and compares their meaningful contents.
  ///
  /// Returns null when cancellation or disposal wins the race. Extraction or
  /// comparison failures throw [ScenePkgInspectionException] for the UI to map
  /// to its localized error state.
  Future<ScenePkgInspectionResult?> inspect({
    required String tool,
    required String wallpaperName,
    required String filePath,
    required String leftFolder,
    required String rightFolder,
  }) async {
    if (_disposed) return null;
    final File leftPkg = File(path.join(leftFolder, filePath));
    final File rightPkg = File(path.join(rightFolder, filePath));
    if (!await leftPkg.exists() || !await rightPkg.exists()) {
      throw const ScenePkgInspectionException();
    }

    final Directory base = Directory(temporaryBasePath);
    await _clearStaleSessions(base);
    final String safeName = wallpaperName
        .replaceAll(RegExp(r'[<>:"/\\|?*]'), '_')
        .replaceAll(RegExp(r'\s+'), '_');
    final String shortName = String.fromCharCodes(safeName.runes.take(48));
    final Directory root = Directory(
      path.join(
        base.path,
        '$shortName-${DateTime.now().microsecondsSinceEpoch}',
      ),
    );
    final Directory leftOut = Directory(path.join(root.path, 'left'));
    final Directory rightOut = Directory(path.join(root.path, 'right'));
    await leftOut.create(recursive: true);
    await rightOut.create(recursive: true);

    final CancelToken token = CancelToken();
    _token = token;
    bool retainUntilDispose = false;
    try {
      final targets = <({File source, Directory output})>[
        (source: leftPkg, output: leftOut),
        (source: rightPkg, output: rightOut),
      ];
      for (final target in targets) {
        final result = await runRePKG(tool, <String>[
          'extract',
          '-c',
          '-o',
          target.output.path,
          target.source.path,
        ], token);
        if (token.isCancelled) return null;
        final RePKGOutputSummary summary = summarizeRePKGOutput(
          result.stdout,
          result.stderr,
        );
        if (result.exitCode != 0 || summary.claimedSuccessWithoutWriting) {
          throw const ScenePkgInspectionException();
        }
      }

      final ScenePkgExtractionComparison? comparison =
          await compareScenePkgExtractionFolders(
            leftFolder: leftOut.path,
            rightFolder: rightOut.path,
          );
      if (comparison == null || token.isCancelled || _disposed) return null;

      retainUntilDispose = true;
      _retainedTempRoot = root;
      return (
        changes: comparison.changes,
        rootFolder: root.path,
        leftFolder: leftOut.path,
        rightFolder: rightOut.path,
      );
    } finally {
      if (identical(_token, token)) _token = null;
      if (!retainUntilDispose) await _deleteTempDirectory(root);
    }
  }

  /// Saves one inspected file as a new, user-chosen copy outside either library.
  /// Existing destinations are never replaced. A failed write removes its
  /// incomplete copy when possible and reports if cleanup could not finish.
  Future<void> saveExtractedFile({
    required ScenePkgInspectionResult result,
    required String relativePath,
    required bool live,
    required String destination,
    required String liveFolder,
    required String backupFolder,
  }) async {
    final Directory? retained = _retainedTempRoot;
    if (_disposed ||
        retained == null ||
        !path.equals(retained.path, result.rootFolder) ||
        path.isAbsolute(relativePath)) {
      throw const ScenePkgSaveException(ScenePkgSaveFailure.invalidSource);
    }
    await saveScenePkgExtractedFile(
      result: result,
      relativePath: relativePath,
      live: live,
      destination: destination,
      liveFolder: liveFolder,
      backupFolder: backupFolder,
    );
  }

  /// Cancels active work and removes any extraction retained for previews.
  Future<void> dispose() async {
    _disposed = true;
    _token?.cancel();
    final Directory? root = _retainedTempRoot;
    _retainedTempRoot = null;
    if (root != null) await _deleteTempDirectory(root);
  }
}

/// Saves a file from an already-extracted comparison without overwriting files.
/// The caller must keep the extraction alive until this operation completes.
Future<void> saveScenePkgExtractedFile({
  required ScenePkgInspectionResult result,
  required String relativePath,
  required bool live,
  required String destination,
  required String liveFolder,
  required String backupFolder,
}) async {
  if (path.isAbsolute(relativePath)) {
    throw const ScenePkgSaveException(ScenePkgSaveFailure.invalidSource);
  }
  final String extractedRoot = live ? result.leftFolder : result.rightFolder;
  final String sourcePath = path.normalize(
    path.join(extractedRoot, relativePath),
  );
  if (!path.isWithin(extractedRoot, sourcePath) ||
      await FileSystemEntity.type(sourcePath, followLinks: false) !=
          FileSystemEntityType.file) {
    throw const ScenePkgSaveException(ScenePkgSaveFailure.invalidSource);
  }
  final String resolvedSession = await Directory(
    result.rootFolder,
  ).resolveSymbolicLinks();
  final String resolvedRoot = await Directory(
    extractedRoot,
  ).resolveSymbolicLinks();
  final String resolvedSource = await File(sourcePath).resolveSymbolicLinks();
  if (!path.isWithin(resolvedSession, resolvedRoot) ||
      !path.isWithin(resolvedRoot, resolvedSource)) {
    throw const ScenePkgSaveException(ScenePkgSaveFailure.invalidSource);
  }

  final String destinationPath = path.normalize(path.absolute(destination));
  final String destinationParent = await Directory(
    path.dirname(destinationPath),
  ).resolveSymbolicLinks();
  final String resolvedDestination = path.join(
    destinationParent,
    path.basename(destinationPath),
  );
  for (final String library in <String>[
    liveFolder,
    backupFolder,
    result.rootFolder,
  ]) {
    final String absoluteLibrary = path.normalize(path.absolute(library));
    if (path.equals(absoluteLibrary, destinationPath) ||
        path.isWithin(absoluteLibrary, destinationPath)) {
      throw const ScenePkgSaveException(
        ScenePkgSaveFailure.protectedDestination,
      );
    }
    final String resolvedLibrary = await Directory(
      library,
    ).resolveSymbolicLinks();
    if (path.equals(resolvedLibrary, resolvedDestination) ||
        path.isWithin(resolvedLibrary, resolvedDestination)) {
      throw const ScenePkgSaveException(
        ScenePkgSaveFailure.protectedDestination,
      );
    }
  }

  final File output = File(destinationPath);
  try {
    await output.create(exclusive: true);
  } on PathExistsException {
    throw const ScenePkgSaveException(ScenePkgSaveFailure.exists);
  }
  try {
    await File(sourcePath).openRead().pipe(output.openWrite());
  } catch (_) {
    bool possiblePartialFile = false;
    try {
      await output.delete();
    } on FileSystemException {
      possiblePartialFile = true;
    }
    throw ScenePkgSaveException(
      ScenePkgSaveFailure.writeFailed,
      possiblePartialFile: possiblePartialFile,
    );
  }
}

/// Compares two already-extracted scene.pkg folders.
///
/// Relative paths are matched directly; filenames are never normalized into
/// inferred relationships. Files with different names remain different files,
/// including numeric variants such as `(2)` or `(3)`.
Future<ScenePkgExtractionComparison?> compareScenePkgExtractionFolders({
  required String leftFolder,
  required String rightFolder,
}) async {
  final BackupFileChanges? raw = await compareBackupFileChanges(
    liveFolder: leftFolder,
    backupFolder: rightFolder,
  );
  if (raw == null) return null;

  bool packageContent(String candidate) =>
      path.basename(candidate).toLowerCase() !=
      WallpaperFiles.project.toLowerCase();

  final List<String> modified = raw.modified.where(packageContent).toList();
  final List<String> onlyLeft = raw.onlyLive.where(packageContent).toList();
  final List<String> onlyRight = raw.onlyBackup.where(packageContent).toList();

  void sortPaths(List<String> values) => values.sort(
    (String a, String b) => a.toLowerCase().compareTo(b.toLowerCase()),
  );
  sortPaths(modified);
  sortPaths(onlyLeft);
  sortPaths(onlyRight);

  return (
    changes: (modified: modified, onlyLive: onlyLeft, onlyBackup: onlyRight),
  );
}
