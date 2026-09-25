import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:we_repkg/cores/scene_pkg_index.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 2) {
    stderr.writeln(
      'Usage: dart tool/benchmark_scene_pkg_index.dart '
      '<packed folder> <unpacked folder>',
    );
    exitCode = 2;
    return;
  }

  final Directory packedFolder = Directory(arguments[0]);
  final Directory unpackedFolder = Directory(arguments[1]);
  final File package = File(path.join(packedFolder.path, 'scene.pkg'));
  if (!await packedFolder.exists() ||
      !await unpackedFolder.exists() ||
      !await package.exists()) {
    stderr.writeln('Both folders and the packed scene.pkg must exist');
    exitCode = 1;
    return;
  }
  final Stopwatch indexClock = Stopwatch()..start();
  final ScenePackageIndex? index = await readScenePackageIndex(package);
  indexClock.stop();
  if (index == null) {
    stderr.writeln('Package index unavailable');
    exitCode = 1;
    return;
  }

  int exact = 0;
  int changed = 0;
  int absent = 0;
  int unreadable = 0;
  int candidateBytes = 0;
  final Stopwatch rawClock = Stopwatch()..start();
  for (final ScenePackageEntry entry in index.entries.values) {
    final File unpacked = File(
      path.joinAll(<String>[
        unpackedFolder.path,
        ...entry.path.split(RegExp(r'[/\\]')),
      ]),
    );
    if (!await unpacked.exists()) {
      absent++;
      continue;
    }
    candidateBytes += entry.length;
    final bool? matches = await scenePackageEntryMatchesFile(
      package: package,
      index: index,
      entry: entry,
      unpacked: unpacked,
    );
    if (matches == true) {
      exact++;
    } else if (matches == false) {
      changed++;
    } else {
      unreadable++;
    }
  }
  rawClock.stop();
  stdout.writeln(
    'Index: ${indexClock.elapsedMilliseconds} ms, '
    '${index.headerBytes} header bytes, ${index.entries.length} entries',
  );
  stdout.writeln(
    'Raw comparison: ${rawClock.elapsedMilliseconds} ms, '
    '$candidateBytes candidate bytes, $exact exact, $changed changed, '
    '$absent absent, $unreadable unreadable',
  );
}
