import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:we_repkg/constants/keys.dart';
import 'package:we_repkg/constants/strings.dart';
import 'package:we_repkg/utils/storage.dart';

String? getToolPath() {
  String? toolPath = StorageUtil.getString(AppKeys.toolPath);
  if (toolPath == null) {
    String appPath = Platform.resolvedExecutable;
    String folder = path.dirname(appPath);
    toolPath = path.join(folder, 'RePKG.exe');
    if (!File(toolPath).existsSync()) {
      toolPath = null;
    }
  }
  return toolPath;
}

/// Extracts RePKG's semantic version from its `version` command output.
///
/// RePKG has written this line to both stdout and stderr across releases. Build
/// metadata identifies the commit but is not part of the user-facing version.
String? parseRepkgVersionOutput(Object? stdout, Object? stderr) {
  final RegExp versionLine = RegExp(
    r'^\s*RePKG\s+([^\s+]+)(?:\+[^\s]+)?\s*$',
    multiLine: true,
    caseSensitive: false,
  );
  for (final Object? output in <Object?>[stdout, stderr]) {
    final Match? match = versionLine.firstMatch(output?.toString() ?? '');
    if (match != null) return match.group(1);
  }
  return null;
}

/// An older RePKG rejects an unknown option and exits 0 having written nothing,
/// so callers must ask before sending `-p` or `--progress-json`. The `-ex`
/// suffix is required: addallno's fork is also 0.5.1 and has neither flag.
bool repkgSupportsExtractFlags(String? version) {
  final Match? match = RegExp(
    r'^(\d+)\.(\d+)\.(\d+)-ex$',
  ).firstMatch(version?.trim() ?? '');
  if (match == null) return false;
  const List<int> required = <int>[0, 5, 1];
  for (int i = 0; i < required.length; i++) {
    final int part = int.parse(match.group(i + 1)!);
    if (part != required[i]) return part > required[i];
  }
  return true;
}

/// Reads the version reported by the active RePKG executable.
///
/// About must remain usable if the configured tool is missing or broken, so
/// failures and slow processes resolve to null rather than escaping.
Future<String?> readRepkgVersion(String? toolPath) async {
  if (toolPath == null || !await File(toolPath).exists()) return null;
  try {
    final ProcessResult result = await Process.run(toolPath, const <String>[
      'version',
    ]).timeout(const Duration(seconds: 2));
    if (result.exitCode != 0) return null;
    return parseRepkgVersionOutput(result.stdout, result.stderr);
  } catch (_) {
    return null;
  }
}

String? getAcfPath([String? filePath]) {
  String? acfPath = StorageUtil.getString(AppKeys.acfPath);
  if (acfPath == null) {
    filePath ??= StorageUtil.getString(AppKeys.wallpaperPath);
    if (filePath == null) return null;
    acfPath = path.join(
      path.dirname(path.dirname(filePath)),
      AppStrings.acfName,
    );
  }
  return File(acfPath).existsSync() ? acfPath : null;
}

Future<int> getSize(String filePath) async {
  int size = 0;
  if (filePath.endsWith('customdirectory')) {
    Directory dir = Directory(filePath);
    final entities = await dir.list().toList();
    for (final entity in entities) {
      final currentSize = await getSize(entity.path);
      size += currentSize;
    }
  } else {
    File file = File(filePath);
    if (await file.exists()) size = await file.length();
  }
  return size;
}

bool isImage(String filePath) {
  List<String> imgs = ['jpg', 'jpeg', 'png', 'gif', 'webp'];
  String ext = filePath.split('.').last.toLowerCase();
  return imgs.contains(ext);
}

IconData getThemeModeIcon(ThemeMode mode) {
  switch (mode) {
    case ThemeMode.light:
      return Icons.light_mode_rounded;
    case ThemeMode.dark:
      return Icons.dark_mode_rounded;
    case ThemeMode.system:
      return Icons.brightness_4_rounded;
  }
}

Future<bool> toolExist(String? toolPath) async {
  if (toolPath == null) return false;
  return await File(toolPath).exists();
}

String projectDefaultPath(String filePath) {
  String workshopPath = path.dirname(path.dirname(filePath));
  return path.join(path.dirname(workshopPath), AppStrings.baseProjectPath);
}
