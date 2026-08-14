import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:path/path.dart' as path;
import 'package:we_repkg/constants/i10n.dart';
import 'package:we_repkg/constants/wallpaper_files.dart';
import 'package:we_repkg/constants/wallpaper_type.dart';
import 'package:we_repkg/cores/extract.dart';
import 'package:we_repkg/cores/integrity_scan.dart';
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

/// Moves a folder to the Recycle Bin after one final contents check.
Future<IntegrityRepairResult> recycleShaderCacheFolder({
  required String folder,
  TrashFolder? trashFolder,
}) => _recycleCheckedFolder(
  folder: folder,
  isSafe: _isShaderCacheOnlyFolder,
  changedMessage: AppI10n.integrityFixCacheChanged,
  trashFolder: trashFolder,
);

/// Moves a media-only folder to the Recycle Bin after rechecking its contents.
Future<IntegrityRepairResult> recycleMediaFolder({
  required String folder,
  TrashFolder? trashFolder,
}) => _recycleCheckedFolder(
  folder: folder,
  isSafe: (String target) async =>
      await isMediaOnlyWallpaperFolder(target) && !await _containsLink(target),
  changedMessage: AppI10n.integrityFixMediaChanged,
  trashFolder: trashFolder,
);

Future<IntegrityRepairResult> _recycleCheckedFolder({
  required String folder,
  required Future<bool> Function(String folder) isSafe,
  required String changedMessage,
  TrashFolder? trashFolder,
}) async {
  final TrashFolder trash =
      trashFolder ?? (String source) => deleteToTrash(filePath: source);
  final String target = path.normalize(folder);
  try {
    if (!await isSafe(target)) {
      return (changed: false, error: tr(changedMessage));
    }
    final String? error = await trash(target);
    if (await FileSystemEntity.type(target, followLinks: false) ==
        FileSystemEntityType.notFound) {
      return (changed: true, error: error);
    }
    if (error != null) return (changed: false, error: error);
    return (changed: false, error: tr(AppI10n.integrityFixTrashUnconfirmed));
  } catch (error) {
    return (changed: false, error: '$error');
  }
}

Future<bool> _isShaderCacheOnlyFolder(String folder) async {
  try {
    if (await FileSystemEntity.type(folder, followLinks: false) !=
        FileSystemEntityType.directory) {
      return false;
    }
    final List<FolderEntry> entries = <FolderEntry>[];
    await for (final FileSystemEntity entity in Directory(
      folder,
    ).list(followLinks: false)) {
      // A link can point outside the folder the confirmation named.
      if (entity is Link) return false;
      entries.add((
        name: path.basename(entity.path),
        isDirectory: entity is Directory,
      ));
    }
    return holdsOnlyRebuiltShaders(entries);
  } on FileSystemException {
    return false;
  }
}

/// What Wallpaper Engine needs before it will list an unpacked scene: a title,
/// the type, and the file to load. The preview is optional and only added when
/// the folder already has an image to point at.
Future<String?> writeSceneProject(String folder) async {
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
    await _writeProject(folder, <String, String>{
      WallpaperProjectFields.title: path.basename(folder),
      WallpaperProjectFields.type: WallpaperType.scene,
      WallpaperProjectFields.file: WallpaperFiles.unpackedScene,
      if (_preview(entries) case final String preview)
        WallpaperProjectFields.preview: preview,
    });
    return null;
  } catch (error) {
    return '$error';
  }
}

/// Restores one missing payload from the same wallpaper in its paired library.
Future<IntegrityRepairResult> restoreMissingPayload({
  required String folder,
  required String? counterpart,
  required String? missing,
}) async {
  try {
    if (counterpart == null || missing == null || missing.isEmpty) {
      return (changed: false, error: tr(AppI10n.integrityFixNoCounterpart));
    }
    if (!_safeRelativePath(folder, missing)) {
      return (changed: false, error: tr(AppI10n.integrityFixUnsafeFile));
    }
    final Map<String, dynamic>? targetProject = await _readProject(folder);
    if (!_projectNames(targetProject, missing)) {
      return (changed: false, error: tr(AppI10n.integrityFixTargetChanged));
    }
    if (!await isHealthyWallpaperFolder(counterpart)) {
      return (changed: false, error: tr(AppI10n.integrityFixNoCounterpart));
    }
    final Map<String, dynamic>? sourceProject = await _readProject(counterpart);
    if (!_projectNames(sourceProject, missing)) {
      return (changed: false, error: tr(AppI10n.integrityFixNoCounterpart));
    }
    final File source = File(path.join(counterpart, missing));
    final File destination = File(path.join(folder, missing));
    if (await FileSystemEntity.type(source.path, followLinks: false) !=
            FileSystemEntityType.file ||
        await FileSystemEntity.type(destination.path, followLinks: false) !=
            FileSystemEntityType.notFound) {
      return (changed: false, error: tr(AppI10n.integrityFixTargetChanged));
    }
    await _copyWithoutReplacing(source, destination, folder);
    return (changed: true, error: null);
  } catch (error) {
    return (changed: false, error: '$error');
  }
}

/// Replaces unreadable metadata with the healthy matching wallpaper's copy.
Future<IntegrityRepairResult> replaceProjectFromCounterpart({
  required String folder,
  required String? counterpart,
}) async {
  try {
    if (counterpart == null || !await isHealthyWallpaperFolder(counterpart)) {
      return (changed: false, error: tr(AppI10n.integrityFixNoCounterpart));
    }
    final Map<String, dynamic>? targetProject = await _readProject(folder);
    if (targetProject != null && projectFieldsUsable(targetProject)) {
      return (changed: false, error: tr(AppI10n.integrityFixTargetChanged));
    }
    final File source = File(path.join(counterpart, WallpaperFiles.project));
    final File destination = File(path.join(folder, WallpaperFiles.project));
    if (await FileSystemEntity.type(source.path, followLinks: false) !=
            FileSystemEntityType.file ||
        await FileSystemEntity.type(destination.path, followLinks: false) !=
            FileSystemEntityType.file) {
      return (changed: false, error: tr(AppI10n.integrityFixTargetChanged));
    }
    await _copyReplacing(source, destination, folder);
    return (changed: true, error: null);
  } catch (error) {
    return (changed: false, error: '$error');
  }
}

/// Creates a loadable Wallpaper Engine project around one image or MP4.
Future<IntegrityRepairResult> writeMediaProject(String folder) async {
  final ({String file, String type, String? preview})? media =
      await _mediaProject(folder);
  if (media == null) {
    return (changed: false, error: tr(AppI10n.integrityFixMediaAmbiguous));
  }
  final String? html = media.type == WallpaperType.web
      ? _imageWallpaperHtml(media.file)
      : null;
  bool wroteHtml = false;
  try {
    if (html != null) {
      final File entry = File(path.join(folder, WallpaperFiles.webEntry));
      await _writeTextWithoutReplacing(entry, html, folder);
      wroteHtml = true;
    }
    await _writeProject(folder, <String, String>{
      WallpaperProjectFields.title: path.basename(folder),
      WallpaperProjectFields.type: media.type,
      WallpaperProjectFields.file: html == null
          ? media.file
          : WallpaperFiles.webEntry,
      if (media.preview case final String preview)
        WallpaperProjectFields.preview: preview,
    });
    return (changed: true, error: null);
  } catch (error) {
    if (wroteHtml && html != null) {
      await _deleteMatchingFile(
        File(path.join(folder, WallpaperFiles.webEntry)),
        html,
      );
    }
    return (changed: false, error: '$error');
  }
}

Future<void> _writeProject(String folder, Map<String, String> project) =>
    _writeTextWithoutReplacing(
      File(path.join(folder, WallpaperFiles.project)),
      _json.convert(project),
      folder,
    );

Future<({String file, String type, String? preview})?> _mediaProject(
  String folder,
) async {
  final List<FolderEntry>? entries = await _mediaEntries(folder);
  if (entries == null || !_holdsOnlyMedia(entries)) {
    return null;
  }
  final List<String> files = entries
      .map((FolderEntry entry) => entry.name)
      .toList();
  List<String> primary = files
      .where(
        (String name) => !sameName(
          path.basenameWithoutExtension(name),
          WallpaperFiles.previewStem,
        ),
      )
      .toList();
  if (primary.isEmpty && files.length == 1) primary = files;
  if (primary.length != 1) return null;
  final String file = primary.single;
  return (
    file: file,
    type: isVideo(file) ? WallpaperType.video : WallpaperType.web,
    preview: _preview(entries),
  );
}

Future<List<FolderEntry>?> _mediaEntries(String folder) async {
  final List<FolderEntry> entries = <FolderEntry>[];
  try {
    await for (final FileSystemEntity entity in Directory(
      folder,
    ).list(followLinks: false)) {
      if (entity is! File) return null;
      entries.add((name: path.basename(entity.path), isDirectory: false));
    }
    return entries;
  } on FileSystemException {
    return null;
  }
}

Future<bool> _containsLink(String folder) async {
  try {
    await for (final FileSystemEntity entity in Directory(
      folder,
    ).list(recursive: true, followLinks: false)) {
      if (entity is Link) return true;
    }
    return false;
  } on FileSystemException {
    return true;
  }
}

bool _holdsOnlyMedia(List<FolderEntry> entries) =>
    entries.isNotEmpty &&
    entries.every(
      (FolderEntry entry) =>
          !entry.isDirectory && (isImage(entry.name) || isVideo(entry.name)),
    );

Future<Map<String, dynamic>?> _readProject(String folder) async {
  try {
    final Object? decoded = json.decode(
      await File(path.join(folder, WallpaperFiles.project)).readAsString(),
    );
    return decoded is Map<String, dynamic> ? decoded : null;
  } catch (_) {
    return null;
  }
}

bool _projectNames(Map<String, dynamic>? project, String expected) =>
    project != null &&
    projectFieldsUsable(project) &&
    project[WallpaperProjectFields.file] is String &&
    path.equals(
      path.normalize(project[WallpaperProjectFields.file] as String),
      path.normalize(expected),
    );

bool _safeRelativePath(String folder, String relative) {
  if (path.isAbsolute(relative)) return false;
  final String root = path.normalize(path.absolute(folder));
  final String target = path.normalize(
    path.absolute(path.join(root, relative)),
  );
  return path.isWithin(root, target);
}

Future<void> _copyWithoutReplacing(
  File source,
  File destination,
  String folder,
) async {
  await destination.parent.create(recursive: true);
  await _publishNewFile(
    destination,
    folder,
    (File staged) => _copyStable(source, staged),
  );
}

Future<void> _copyReplacing(
  File source,
  File destination,
  String folder,
) async {
  final Directory stage = await Directory(
    folder,
  ).createTemp(WallpaperFiles.projectStagePrefix);
  try {
    final File staged = File(
      path.join(stage.path, path.basename(destination.path)),
    );
    await _copyStable(source, staged);
    await staged.rename(destination.path);
  } finally {
    await _deleteDirectoryQuietly(stage);
  }
}

Future<void> _copyStable(File source, File destination) async {
  final FileStat before = await source.stat();
  await source.copy(destination.path);
  final FileStat after = await source.stat();
  if (before.size != after.size || before.modified != after.modified) {
    throw FileSystemException(
      'The healthy copy changed while it was read',
      source.path,
    );
  }
}

Future<void> _writeTextWithoutReplacing(
  File destination,
  String contents,
  String folder,
) => _publishNewFile(destination, folder, (File staged) async {
  await staged.writeAsString(contents, flush: true);
});

Future<void> _publishNewFile(
  File destination,
  String folder,
  Future<void> Function(File staged) prepare,
) async {
  final Directory stage = await Directory(
    folder,
  ).createTemp(WallpaperFiles.projectStagePrefix);
  try {
    final File staged = File(
      path.join(stage.path, path.basename(destination.path)),
    );
    await prepare(staged);
    publishWithoutReplacing(staged, destination.path);
  } finally {
    await _deleteDirectoryQuietly(stage);
  }
}

Future<void> _deleteMatchingFile(File file, String expected) async {
  try {
    if (await file.exists() && await file.readAsString() == expected) {
      await file.delete();
    }
  } catch (_) {}
}

String _imageWallpaperHtml(String image) =>
    '<!doctype html><html><head><meta charset="utf-8">'
    '<style>html,body{margin:0;width:100%;height:100%;overflow:hidden;'
    'background:#000}img{width:100%;height:100%;object-fit:cover}</style>'
    '</head><body><img src="${Uri.encodeComponent(image)}"></body></html>';

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
    final Directory? pending = await _pendingRescue(
      intoLibrary,
      sourcePath,
      sourceSnapshot,
    );
    if (pending != null) {
      return _finishRescue(pending, folder, trash);
    }
    out = await freeFolderName(path.join(intoLibrary, path.basename(folder)));
    staged = (await Directory(
      intoLibrary,
    ).createTemp(WallpaperFiles.rescueStagePrefix)).path;
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
      sourceSnapshot: sourceSnapshot,
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
  Map<String, String> sourceSnapshot,
) async {
  await for (final FileSystemEntity entity in Directory(
    library,
  ).list(followLinks: false)) {
    if (entity is! Directory) continue;
    if (path
        .basename(entity.path)
        .startsWith(WallpaperFiles.rescueStagePrefix)) {
      continue;
    }
    if (await _matchingRescueMarker(entity, source, sourceSnapshot)) {
      return entity;
    }
  }
  return null;
}

Future<bool> _matchingRescueMarker(
  Directory directory,
  String source,
  Map<String, String> sourceSnapshot,
) async {
  final Map<String, dynamic>? transaction = await _readRescueMarker(
    File(path.join(directory.path, WallpaperFiles.rescueMarker)),
  );
  return transaction?[_markerSource] is String &&
      path.equals(transaction![_markerSource] as String, source) &&
      _sameSnapshot(
        _snapshotFromMarker(transaction) ?? const {},
        sourceSnapshot,
      ) &&
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
  required Map<String, String> sourceSnapshot,
}) async {
  final File marker = File(
    path.join(directory.path, WallpaperFiles.rescueMarker),
  );
  final File staged = File('${marker.path}$partSuffix');
  await staged.writeAsString(
    json.encode(<String, Object>{
      _markerSource: source,
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
      final FileStat stat = await entity.stat();
      snapshot[relative] =
          '${stat.size}:${stat.modified.millisecondsSinceEpoch}';
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
