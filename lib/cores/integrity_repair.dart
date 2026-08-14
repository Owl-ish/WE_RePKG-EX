import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:path/path.dart' as path;
import 'package:we_repkg/constants/i10n.dart';
import 'package:we_repkg/constants/wallpaper_files.dart';
import 'package:we_repkg/constants/wallpaper_type.dart';
import 'package:we_repkg/cores/extract.dart';
import 'package:we_repkg/src/rust/api/simple.dart';
import 'package:we_repkg/utils/cancel_token.dart';
import 'package:we_repkg/utils/info.dart';
import 'package:we_repkg/utils/folder_entries.dart';
import 'package:we_repkg/utils/file_copy.dart';
import 'package:we_repkg/cores/integrity_rules.dart';
import 'package:we_repkg/utils/windows_file_transaction.dart';

/// Indented, because this file lands in the user's library and they open it.
const JsonEncoder _json = JsonEncoder.withIndent('  ');
const String _markerSource = 'source';
const String _markerFileIdentity = 'packedFileIdentity';
const String _markerOutput = 'output';
const String _markerOwner = 'ownerProcess';
const String _markerComplete = 'complete';
const String _markerSourceSnapshot = 'sourceSnapshot';

typedef IntegrityRepairResult = ({bool changed, String? error});
typedef RescueExtractor =
    Future<String?> Function(
      String out,
      String folder,
      String scene,
      String rePKGPath,
    );
typedef TrashFolder = Future<String?> Function(String folder);
typedef BeforeProjectPublish = Future<void> Function(File staged);

/// What Wallpaper Engine needs before it will list an unpacked scene: a title,
/// the type, and the file to load. The preview is optional and only added when
/// the folder already has an image to point at.
Future<String?> writeSceneProject(
  String folder, {
  BeforeProjectPublish? beforePublish,
}) async {
  final File file = File(path.join(folder, WallpaperFiles.project));
  Directory? stage;
  final List<FolderEntry>? entries = await listFolderEntries(Directory(folder));
  if (entries == null) return tr(AppI10n.integrityFixUnreadable);
  if (holds(entries, WallpaperFiles.project)) {
    return tr(AppI10n.integrityFixAlreadyThere);
  }
  // Naming a scene.json that is not there would swap one broken folder for
  // another, and this one would claim to be sound.
  if (!holds(entries, WallpaperFiles.unpackedScene)) {
    return tr(AppI10n.integrityFixNoScene);
  }
  try {
    await _sweepProjectStages(Directory(folder));
    stage = await Directory(
      folder,
    ).createTemp('${WallpaperFiles.projectStagePrefix}$pid-');
    final File staged = File(path.join(stage.path, WallpaperFiles.project));
    await staged.writeAsString(
      _json.convert(<String, String>{
        WallpaperProjectFields.title: path.basename(folder),
        WallpaperProjectFields.type: WallpaperType.scene,
        WallpaperProjectFields.file: WallpaperFiles.unpackedScene,
        if (_preview(entries) case final String preview)
          WallpaperProjectFields.preview: preview,
      }),
      flush: true,
    );
    if (beforePublish != null) await beforePublish(staged);
    publishWithoutReplacing(staged, file.path);
  } catch (e) {
    return '$e';
  } finally {
    if (stage != null) await _deleteDirectoryQuietly(stage);
  }
  return null;
}

/// Extracts a packed wallpaper whose `project.json` is gone into [intoLibrary]
/// as a project, gives it one, and puts the folder it came from in the Recycle
/// Bin.
///
/// The bin comes last and only once the rest has worked. Until then the folder
/// is the only copy of the wallpaper there is.
Future<IntegrityRepairResult> rescuePackedScene({
  required String folder,
  required String intoLibrary,
  required String rePKGPath,
  RescueExtractor extractor = _fillRescued,
  TrashFolder? trashFolder,
}) async {
  final TrashFolder trash =
      trashFolder ?? (String source) => deleteToTrash(filePath: source);
  final String scene = path.join(folder, WallpaperFiles.packedScene);
  final String sourcePath;
  final String sourceFileIdentity;
  final Map<String, String> sourceSnapshot;
  final String out;
  final String staged;
  try {
    if (!await File(scene).exists()) {
      return (changed: false, error: tr(AppI10n.integrityFixNoPkg));
    }
    final String source = await Directory(folder).resolveSymbolicLinks();
    final String library = await Directory(intoLibrary).resolveSymbolicLinks();
    if (path.equals(source, library) || path.isWithin(source, library)) {
      return (changed: false, error: tr(AppI10n.integrityFixUnsafeDestination));
    }
    sourcePath = path.normalize(source);
    sourceSnapshot = await _sourceSnapshot(Directory(folder));
    sourceFileIdentity = windowsFileIdentity(scene);
    final Directory? pending = await _pendingRescue(
      intoLibrary,
      sourcePath,
      sourceFileIdentity,
    );
    if (pending != null) {
      return _finishRescue(pending, folder, trash);
    }
    out = await freeFolderName(path.join(intoLibrary, path.basename(folder)));
    staged = (await Directory(
      intoLibrary,
    ).createTemp('${WallpaperFiles.rescueStagePrefix}$pid-')).path;
    await _writeRescueMarker(
      Directory(staged),
      source: sourcePath,
      sourceFileIdentity: sourceFileIdentity,
      output: out,
      sourceSnapshot: sourceSnapshot,
      complete: false,
    );
  } catch (e) {
    return (changed: false, error: '$e');
  }

  final String? failure = await extractor(staged, folder, scene, rePKGPath);
  if (failure != null) {
    await _deleteDirectoryQuietly(Directory(staged));
    return (changed: false, error: failure);
  }
  try {
    await _writeRescueMarker(
      Directory(staged),
      source: sourcePath,
      sourceFileIdentity: sourceFileIdentity,
      output: out,
      sourceSnapshot: sourceSnapshot,
      complete: true,
    );
    if (await FileSystemEntity.type(out) != FileSystemEntityType.notFound) {
      await _deleteDirectoryQuietly(Directory(staged));
      return (changed: false, error: tr(AppI10n.integrityFixAlreadyThere));
    }
    publishWithoutReplacing(Directory(staged), out);
    final Directory published = Directory(out);
    return _finishRescue(published, folder, trash);
  } catch (e) {
    await _deleteDirectoryQuietly(Directory(staged));
    return (changed: false, error: '$e');
  }
}

Future<Directory?> _pendingRescue(
  String library,
  String source,
  String sourceFileIdentity,
) async {
  final List<FileSystemEntity> entities = await Directory(
    library,
  ).list(followLinks: false).toList();
  for (final FileSystemEntity entity in entities) {
    if (entity is! Directory) continue;
    if (path
        .basename(entity.path)
        .startsWith(WallpaperFiles.rescueStagePrefix)) {
      continue;
    }
    if (await _matchingRescueMarker(entity, source, sourceFileIdentity)) {
      return entity;
    }
  }
  for (final FileSystemEntity entity in entities) {
    if (entity is! Directory ||
        !path
            .basename(entity.path)
            .startsWith(WallpaperFiles.rescueStagePrefix)) {
      continue;
    }
    final File marker = File(
      path.join(entity.path, WallpaperFiles.rescueMarker),
    );
    try {
      final Map<String, dynamic>? transaction = await _readRescueMarker(marker);
      final int? owner =
          transaction?[_markerOwner] as int? ??
          _stageOwner(entity.path, WallpaperFiles.rescueStagePrefix);
      if (owner != null && windowsProcessIsRunning(owner)) continue;
      if (transaction == null ||
          transaction[_markerSource] is! String ||
          transaction[_markerFileIdentity] is! String ||
          transaction[_markerOutput] is! String) {
        continue;
      }
      final bool isCurrent =
          path.equals(transaction[_markerSource] as String, source) &&
          transaction[_markerFileIdentity] == sourceFileIdentity;
      if (!isCurrent) continue;
      if (transaction[_markerComplete] != true) {
        await _deleteDirectoryQuietly(entity);
        continue;
      }
      if (!await _rescueFilesComplete(entity)) {
        await _deleteDirectoryQuietly(entity);
        continue;
      }
      final String wanted = path.normalize(
        transaction[_markerOutput] as String,
      );
      if (!path.equals(path.dirname(wanted), path.normalize(library))) continue;
      final String recovered = await freeFolderName(wanted);
      publishWithoutReplacing(entity, recovered);
      return Directory(recovered);
    } catch (_) {}
  }
  return null;
}

int? _stageOwner(String stage, String prefix) {
  final String name = path.basename(stage);
  if (!name.startsWith(prefix)) return null;
  return int.tryParse(name.substring(prefix.length).split('-').first);
}

Future<void> _sweepProjectStages(Directory folder) async {
  await for (final FileSystemEntity entity in folder.list(followLinks: false)) {
    if (entity is! Directory ||
        !path
            .basename(entity.path)
            .startsWith(WallpaperFiles.projectStagePrefix)) {
      continue;
    }
    final int? owner = _stageOwner(
      entity.path,
      WallpaperFiles.projectStagePrefix,
    );
    if (owner != null && !windowsProcessIsRunning(owner)) {
      await _deleteDirectoryQuietly(entity);
    }
  }
}

Future<bool> _matchingRescueMarker(
  Directory directory,
  String source,
  String sourceFileIdentity,
) async {
  final Map<String, dynamic>? transaction = await _readRescueMarker(
    File(path.join(directory.path, WallpaperFiles.rescueMarker)),
  );
  return transaction?[_markerComplete] == true &&
      transaction?[_markerSource] is String &&
      path.equals(transaction![_markerSource] as String, source) &&
      transaction[_markerFileIdentity] == sourceFileIdentity &&
      await _rescueFilesComplete(directory);
}

Future<bool> _rescueFilesComplete(Directory directory) async =>
    await File(path.join(directory.path, WallpaperFiles.project)).exists() &&
    await File(
      path.join(directory.path, WallpaperFiles.unpackedScene),
    ).exists();

Future<Map<String, dynamic>?> _readRescueMarker(File marker) async {
  try {
    if (!await marker.exists()) return null;
    final Object? decoded = json.decode(await marker.readAsString());
    return decoded is Map<String, dynamic> ? decoded : null;
  } catch (_) {
    return null;
  }
}

Future<void> _writeRescueMarker(
  Directory directory, {
  required String source,
  required String sourceFileIdentity,
  required String output,
  required Map<String, String> sourceSnapshot,
  required bool complete,
}) async {
  final File marker = File(
    path.join(directory.path, WallpaperFiles.rescueMarker),
  );
  final File staged = File('${marker.path}$partSuffix');
  await staged.writeAsString(
    json.encode(<String, Object>{
      _markerSource: source,
      _markerFileIdentity: sourceFileIdentity,
      _markerOutput: output,
      _markerOwner: pid,
      _markerComplete: complete,
      _markerSourceSnapshot: sourceSnapshot,
    }),
    flush: true,
  );
  await staged.rename(marker.path);
}

Future<IntegrityRepairResult> _finishRescue(
  Directory published,
  String source,
  TrashFolder trash,
) async {
  try {
    final Map<String, dynamic>? transaction = await _readRescueMarker(
      File(path.join(published.path, WallpaperFiles.rescueMarker)),
    );
    final Map<String, String>? expected = _snapshotFromMarker(transaction);
    if (expected == null ||
        !_sameSnapshot(expected, await _sourceSnapshot(Directory(source)))) {
      return (changed: true, error: tr(AppI10n.integrityFixSourceChanged));
    }
    final String? error = await trash(source);
    if (error != null) return (changed: true, error: error);
    final File marker = File(
      path.join(published.path, WallpaperFiles.rescueMarker),
    );
    try {
      if (await marker.exists()) await marker.delete();
    } catch (_) {}
    return (changed: true, error: null);
  } catch (e) {
    return (changed: true, error: '$e');
  }
}

Map<String, String>? _snapshotFromMarker(Map<String, dynamic>? marker) {
  final Object? raw = marker?[_markerSourceSnapshot];
  if (raw is! Map<String, dynamic> ||
      raw.values.any((Object? value) => value is! String)) {
    return null;
  }
  return raw.map(
    (String key, Object? value) =>
        MapEntry<String, String>(key, value! as String),
  );
}

Future<Map<String, String>> _sourceSnapshot(Directory source) async {
  final Map<String, String> snapshot = <String, String>{};
  await for (final FileSystemEntity entity in source.list(
    recursive: true,
    followLinks: false,
  )) {
    final String relative = path.relative(entity.path, from: source.path);
    if (entity is Link) {
      throw FileSystemException(
        'Repair source contains a link that cannot be copied safely',
        entity.path,
      );
    }
    if (entity is File) {
      snapshot[relative] = windowsFileIdentity(entity.path);
    } else if (entity is Directory) {
      snapshot['$relative${path.separator}'] = 'directory';
    }
  }
  return snapshot;
}

bool _sameSnapshot(Map<String, String> before, Map<String, String> after) =>
    before.length == after.length &&
    before.entries.every(
      (MapEntry<String, String> entry) => after[entry.key] == entry.value,
    );

Future<void> _deleteDirectoryQuietly(Directory directory) async {
  try {
    if (await directory.exists()) await directory.delete(recursive: true);
  } catch (_) {}
}

Future<String?> _fillRescued(
  String out,
  String folder,
  String scene,
  String rePKGPath,
) async {
  try {
    // The same call the extract tab makes for "extract as project".
    final ({int exitCode, String stdout, String stderr}) result =
        await runRePKG(rePKGPath, <String>[
          'extract',
          '-c',
          '-o',
          out,
          scene,
        ], CancelToken());
    if (result.exitCode != 0) {
      return '${tr(AppI10n.errorExtractFailed)} ${result.stderr.trim()}';
    }
  } catch (e) {
    return '${tr(AppI10n.errorExtractFailed)} $e';
  }
  return await carryLooseFiles(folder, out) ?? await writeSceneProject(out);
}

/// Everything beside the packed scene, copied across before the folder it came
/// from is binned.
///
/// The extraction takes the scene and nothing else, so the preview image and
/// anything the wallpaper shipped alongside it would go into the Recycle Bin
/// with the folder. Whatever the extraction already wrote wins.
Future<String?> carryLooseFiles(String from, String to) async {
  try {
    await for (final FileSystemEntity entity in Directory(
      from,
    ).list(recursive: true, followLinks: false)) {
      final String relative = path.relative(entity.path, from: from);
      if (sameName(relative, WallpaperFiles.packedScene)) continue;
      final String destination = path.join(to, relative);
      if (entity is Directory) {
        await Directory(destination).create(recursive: true);
      } else if (entity is File && !await File(destination).exists()) {
        await Directory(path.dirname(destination)).create(recursive: true);
        await entity.copy(destination);
      }
    }
  } catch (e) {
    return '$e';
  }
  return null;
}

/// [wanted], or the first free name beside it. Two Workshop folders can carry
/// the same wallpaper, and the second must not land inside the first.
Future<String> freeFolderName(String wanted) async {
  if (!await Directory(wanted).exists()) return wanted;
  for (int n = 2; ; n++) {
    final String next = '$wanted-$n';
    if (!await Directory(next).exists()) return next;
  }
}

/// An image at the top level, `preview.*` first, which is what Steam's copy
/// would have named.
String? _preview(List<FolderEntry> entries) {
  final List<String> images = <String>[
    for (final FolderEntry entry in entries)
      if (!entry.isDirectory && isImage(entry.name)) entry.name,
  ];
  if (images.isEmpty) return null;
  return images.firstWhere(
    (String name) => sameName(
      path.basenameWithoutExtension(name),
      WallpaperFiles.previewStem,
    ),
    orElse: () => images.first,
  );
}
