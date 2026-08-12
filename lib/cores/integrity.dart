import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:we_repkg/cores/backup.dart';
import 'package:we_repkg/utils/folder_entries.dart';
import 'package:we_repkg/utils/info.dart';
import 'package:we_repkg/utils/wallpaper_integrity.dart';

/// The four folders the check walks. Live and backup are reported apart, so a
/// folder broken in the backup and sound live reads as one problem rather than
/// two, and the reverse is visible at all.
enum IntegrityRoot {
  liveWorkshop,
  liveMyProjects,
  backupWorkshop,
  backupMyProjects,
}

typedef IntegrityFinding = ({
  IntegrityRoot root,
  String name,
  IntegrityVerdict verdict,
  int bytes,
  String folder,
});

typedef IntegrityReport = ({
  /// Only the folders Wallpaper Engine could not load. A sound folder is
  /// counted and dropped, or a clean library would build a 3600 entry list to
  /// display nothing.
  List<IntegrityFinding> findings,
  Map<IntegrityRoot, int> scanned,
  Set<IntegrityRoot> missing,
});

/// Batched, or a large library opens too many file handles at once. Per root,
/// and the four run together, so four times this many listings are in flight.
const int _batchSize = 24;

/// Sorts every wallpaper folder in all four roots by whether it is loadable.
///
/// Paths rather than a `WidgetRef`, so this runs against a temp directory in a
/// test. Read-only throughout: it opens files to read and writes nothing.
Future<IntegrityReport> scanIntegrity({
  required String? liveWorkshopPath,
  required String? liveMyProjectsPath,
  required String? backupRoot,
}) async {
  final Map<IntegrityRoot, String?> roots = <IntegrityRoot, String?>{
    IntegrityRoot.liveWorkshop: liveWorkshopPath,
    IntegrityRoot.liveMyProjects: liveMyProjectsPath,
    IntegrityRoot.backupWorkshop: backupWorkshopPath(backupRoot),
    IntegrityRoot.backupMyProjects: backupMyProjectsPath(backupRoot),
  };

  final List<IntegrityFinding> findings = <IntegrityFinding>[];
  final Map<IntegrityRoot, int> scanned = <IntegrityRoot, int>{};
  final Set<IntegrityRoot> missing = <IntegrityRoot>{};

  await Future.wait(
    roots.entries.map((MapEntry<IntegrityRoot, String?> entry) async {
      final List<IntegrityFinding>? found = await _scanRoot(
        entry.key,
        entry.value,
      );
      if (found == null) {
        missing.add(entry.key);
        return;
      }
      scanned[entry.key] = found.length;
      findings.addAll(
        found.where(
          (IntegrityFinding f) => f.verdict != IntegrityVerdict.sound,
        ),
      );
    }),
  );

  // Worst first within a root, then by name, so the list reads the same on
  // every run rather than in whatever order the filesystem gave them up.
  findings.sort((IntegrityFinding a, IntegrityFinding b) {
    final int byRoot = a.root.index.compareTo(b.root.index);
    if (byRoot != 0) return byRoot;
    final int byVerdict = a.verdict.index.compareTo(b.verdict.index);
    return byVerdict != 0 ? byVerdict : a.name.compareTo(b.name);
  });
  return (findings: findings, scanned: scanned, missing: missing);
}

/// Null when the root is unset or not on disk, which is a different thing from
/// a root holding nothing.
Future<List<IntegrityFinding>?> _scanRoot(
  IntegrityRoot root,
  String? rootPath,
) async {
  if (rootPath == null) return null;
  final Directory dir = Directory(rootPath);
  if (!await dir.exists()) return null;

  final List<Directory> folders = <Directory>[];
  await for (final FileSystemEntity entity in dir.list()) {
    if (entity is Directory) folders.add(entity);
  }

  final List<IntegrityFinding> found = <IntegrityFinding>[];
  for (int i = 0; i < folders.length; i += _batchSize) {
    final List<IntegrityFinding?> batch = await Future.wait(
      folders.skip(i).take(_batchSize).map((Directory f) => _inspect(root, f)),
    );
    for (final IntegrityFinding? finding in batch) {
      if (finding != null) found.add(finding);
    }
  }

  // A library always holds wallpapers. A root where not one folder is loadable
  // is a path pointed somewhere else entirely, and sizing it would recursively
  // stat whatever that is: pick C:\Windows and every folder in it comes back
  // media-only. The verdicts still say what is there; the sizes are skipped.
  final bool isLibrary = found.any(
    (IntegrityFinding f) => f.verdict == IntegrityVerdict.sound,
  );
  if (!isLibrary) return found;
  return _withSizes(found);
}

/// Totals each broken folder, leaving the sound ones at zero so a healthy
/// library never pays for a recursive walk.
Future<List<IntegrityFinding>> _withSizes(List<IntegrityFinding> found) async {
  final List<IntegrityFinding> sized = <IntegrityFinding>[];
  for (final IntegrityFinding f in found) {
    sized.add(
      f.verdict == IntegrityVerdict.sound
          ? f
          : (
              root: f.root,
              name: f.name,
              verdict: f.verdict,
              bytes: await folderBytes(Directory(f.folder)),
              folder: f.folder,
            ),
    );
  }
  return sized;
}

Future<IntegrityFinding?> _inspect(IntegrityRoot root, Directory folder) async {
  // A folder that moved mid-scan drops out of the checked count too, which is
  // the honest answer: nobody read it.
  final List<FolderEntry>? entries = await listFolderEntries(folder);
  if (entries == null) return null;

  final ProjectRead project = await _readProject(folder, entries);
  // Only looked up when `file` is absent, which is the only case the app falls
  // back to it, so the common wallpaper costs no extra stat.
  final bool hasCustomDirectory =
      project.readable &&
      project.file == null &&
      await Directory(
        path.join(folder.path, 'directories', 'customdirectory'),
      ).exists();

  IntegrityVerdict verdict = classifyFolder(
    entries: entries,
    project: project,
    hasCustomDirectory: hasCustomDirectory,
  );
  final String? named = project.file;
  if (verdict == IntegrityVerdict.payloadMissing &&
      named != null &&
      named.isNotEmpty &&
      await _resolves(folder, named)) {
    verdict = IntegrityVerdict.sound;
  }
  // Unsized: whether the walk is worth doing depends on the whole root, which
  // this cannot see.
  return (
    root: root,
    name: path.basename(folder.path),
    verdict: verdict,
    bytes: 0,
    folder: folder.path,
  );
}

/// Whether `file` names something on disk after all.
///
/// `project.json` may point into a subfolder, which the app resolves by joining
/// the path but a listing of the top level cannot see. Only reached for a
/// folder already about to be accused, so an ordinary wallpaper never pays for
/// it. The PowerShell version of this check skipped it and cried wolf twice.
Future<bool> _resolves(Directory folder, String file) async {
  final String target = path.join(folder.path, file);
  return await File(target).exists() || await Directory(target).exists();
}

Future<ProjectRead> _readProject(
  Directory folder,
  List<FolderEntry> entries,
) async {
  final bool present = entries.any(
    (FolderEntry e) => !e.isDirectory && e.name.toLowerCase() == 'project.json',
  );
  if (!present) return (present: false, readable: false, file: null);
  try {
    final Object? decoded = json.decode(
      await File(path.join(folder.path, 'project.json')).readAsString(),
    );
    if (decoded is! Map<String, dynamic> || !_typesUsable(decoded)) {
      return (present: true, readable: false, file: null);
    }
    final Object? file = decoded['file'];
    return (present: true, readable: true, file: file is String ? file : null);
  } catch (_) {
    return (present: true, readable: false, file: null);
  }
}

/// Whether the grid could read this `project.json` too.
///
/// `_parseWallpaperFolder` assigns these fields straight into typed locals
/// under a bare `catch`, so a number where a string belongs drops the wallpaper
/// out of the library without a word. Calling such a folder sound would send
/// someone here to be told nothing is wrong with the wallpaper they cannot see.
bool _typesUsable(Map<String, dynamic> project) {
  bool stringOrAbsent(String key) =>
      project[key] == null || project[key] is String;
  return stringOrAbsent('title') &&
      stringOrAbsent('contentrating') &&
      stringOrAbsent('type') &&
      stringOrAbsent('preview') &&
      stringOrAbsent('file') &&
      (project['tags'] == null || project['tags'] is List);
}
