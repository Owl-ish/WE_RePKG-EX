// scene.pkg extraction and comparison lifecycle for Backup detail inspection.
//
// Owns RePKG execution, cancellation, retained temporary folders, stale-session
// cleanup, and extracted-file comparison. Confirmation, localization, previews,
// and per-file Backup choices stay in the UI layer.

import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:we_repkg/constants/wallpaper_files.dart';
import 'package:we_repkg/cores/backup.dart';
import 'package:we_repkg/cores/extract.dart';
import 'package:we_repkg/utils/cancel_token.dart';
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

const Duration _staleSessionAge = Duration(days: 1);

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

  /// Cancels active work and removes any extraction retained for previews.
  Future<void> dispose() async {
    _disposed = true;
    _token?.cancel();
    final Directory? root = _retainedTempRoot;
    _retainedTempRoot = null;
    if (root != null) await _deleteTempDirectory(root);
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
