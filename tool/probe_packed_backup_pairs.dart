import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as path;
import 'package:we_repkg/cores/scene_pkg_index.dart';
import 'package:we_repkg/cores/scene_texture_summary.dart';

// Read-only feasibility probe. Its results must never authorize deletion.
Future<void> main(List<String> arguments) async {
  if (arguments.length < 2 ||
      arguments.length > 3 ||
      (arguments.length == 3 && arguments[2] != '--details')) {
    stderr.writeln(
      'Usage: dart tool/probe_packed_backup_pairs.dart '
      '<Workshop backup root> <MyProjects backup root> [--details]',
    );
    exitCode = 2;
    return;
  }
  final Directory workshop = Directory(arguments[0]);
  final Directory myProjects = Directory(arguments[1]);
  if (!await workshop.exists() || !await myProjects.exists()) {
    stderr.writeln('Both backup roots must exist');
    exitCode = 2;
    return;
  }

  final Stopwatch total = Stopwatch()..start();
  final Map<String, Directory> first = await _childFolders(workshop);
  final Map<String, Directory> second = await _childFolders(myProjects);
  final List<String> names =
      first.keys.toSet().intersection(second.keys.toSet()).toList()..sort();
  int eligible = 0;
  int definiteDifference = 0;
  int unresolved = 0;
  int unavailable = 0;
  int rawEqualEntries = 0;
  int rawDifferentEntries = 0;
  int missingEntries = 0;
  int comparedBytes = 0;
  int slowestMilliseconds = 0;
  String slowestName = '';
  final List<String> definiteNames = <String>[];
  final List<String> unresolvedDetails = <String>[];

  for (final String name in names) {
    final Directory a = first[name]!;
    final Directory b = second[name]!;
    final bool aPacked = await _isPacked(a);
    final bool bPacked = await _isPacked(b);
    final bool aUnpacked = await _isUnpacked(a);
    final bool bUnpacked = await _isUnpacked(b);
    if (!((aPacked && bUnpacked) || (bPacked && aUnpacked))) continue;
    eligible++;
    final Stopwatch pairTime = Stopwatch()..start();
    final Directory packed = aPacked ? a : b;
    final Directory unpacked = aPacked ? b : a;
    final File package = File(path.join(packed.path, 'scene.pkg'));
    final ScenePackageIndex? index = await readScenePackageIndex(package);
    if (index == null) {
      unavailable++;
      continue;
    }

    bool different = false;
    bool failed = false;
    int changedTextures = 0;
    int changedJson = 0;
    int changedOther = 0;
    int absent = 0;
    for (final ScenePackageEntry entry in index.entries.values) {
      final File counterpart = File(
        path.joinAll(<String>[
          unpacked.path,
          ...entry.path.split(RegExp(r'[/\\]')),
        ]),
      );
      if (!await counterpart.exists()) {
        missingEntries++;
        absent++;
        continue;
      }
      comparedBytes += entry.length;
      final bool? equal = await scenePackageEntryMatchesFile(
        package: package,
        index: index,
        entry: entry,
        unpacked: counterpart,
      );
      if (equal == null) {
        failed = true;
        break;
      }
      if (equal) {
        rawEqualEntries++;
        continue;
      }
      rawDifferentEntries++;
      final String extension = path.extension(entry.path).toLowerCase();
      if (extension != '.tex') {
        if (extension == '.json') {
          changedJson++;
        } else {
          changedOther++;
        }
        continue;
      }
      changedTextures++;
      final Uint8List? packedPrefix = await _entryPrefix(package, index, entry);
      final Uint8List? unpackedPrefix = await _filePrefix(counterpart);
      if (packedPrefix == null || unpackedPrefix == null) {
        failed = true;
        break;
      }
      final SceneTextureSummary? packedSummary = readSceneTextureSummary(
        packedPrefix,
      );
      final SceneTextureSummary? unpackedSummary = readSceneTextureSummary(
        unpackedPrefix,
      );
      if (packedSummary != null &&
          unpackedSummary != null &&
          sceneTextureMetadataDiffers(
            packedSummary,
            unpackedSummary,
            compareMipSetting: false,
          )) {
        different = true;
        break;
      }
    }
    pairTime.stop();
    if (pairTime.elapsedMilliseconds > slowestMilliseconds) {
      slowestMilliseconds = pairTime.elapsedMilliseconds;
      slowestName = name;
    }
    if (failed) {
      unavailable++;
    } else if (different) {
      definiteDifference++;
      definiteNames.add(name);
    } else {
      unresolved++;
      unresolvedDetails.add(
        '$name: changed TEX $changedTextures, JSON $changedJson, '
        'other $changedOther, absent $absent',
      );
    }
  }
  total.stop();
  stdout.writeln(
    'Shared folder names: ${names.length}; packed/unpacked pairs: $eligible',
  );
  stdout.writeln(
    'Definite primary texture-metadata differences: $definiteDifference; '
    'unresolved: $unresolved; unavailable: $unavailable',
  );
  stdout.writeln(
    'Raw entries: $rawEqualEntries equal, $rawDifferentEntries different, '
    '$missingEntries absent; candidate bytes: $comparedBytes',
  );
  stdout.writeln(
    'Elapsed: ${total.elapsedMilliseconds} ms; slowest pair: '
    '$slowestName ($slowestMilliseconds ms)',
  );
  if (definiteNames.isNotEmpty) {
    stdout.writeln(
      'First definite difference IDs: ${definiteNames.take(10).join(', ')}',
    );
  }
  if (arguments.length == 3) {
    for (final String detail in unresolvedDetails) {
      stdout.writeln(detail);
    }
  }
  stdout.writeln('No pair is certified identical by this probe.');
}

Future<Map<String, Directory>> _childFolders(Directory root) async {
  final Map<String, Directory> folders = <String, Directory>{};
  await for (final FileSystemEntity item in root.list(followLinks: false)) {
    if (item is Directory) {
      folders[path.basename(item.path).toLowerCase()] = item;
    }
  }
  return folders;
}

Future<bool> _isPacked(Directory folder) async =>
    await File(path.join(folder.path, 'scene.pkg')).exists() &&
    !await File(path.join(folder.path, 'scene.json')).exists();

Future<bool> _isUnpacked(Directory folder) async =>
    await File(path.join(folder.path, 'scene.json')).exists() &&
    !await File(path.join(folder.path, 'scene.pkg')).exists();

Future<Uint8List?> _entryPrefix(
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
