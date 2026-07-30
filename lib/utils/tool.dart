import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:path/path.dart' as path;
import 'package:we_repkg/constants/i10n.dart';
import 'package:we_repkg/constants/wallpaper_type.dart';

String typeText(String type) {
  switch (type) {
    case WallpaperType.video:
      return tr(AppI10n.homeVideo);
    case WallpaperType.scene:
      return tr(AppI10n.homeScene);
    case WallpaperType.web:
      return tr(AppI10n.homeWeb);
    case WallpaperType.application:
      return tr(AppI10n.homeApplication);
    case WallpaperType.unknown:
      return tr(AppI10n.homeUnknown);
    default:
      return type;
  }
}

String formatSize(int size) {
  if (size < 1024) {
    return '${size}B';
  } else if (size < 1024 * 1024) {
    return '${(size / 1024).toStringAsFixed(2)}KB';
  } else {
    return '${(size / 1024 / 1024).toStringAsFixed(2)}MB';
  }
}

List<String> splitOnFirstColon(String message) {
  int colonIndex = message.indexOf(':');
  if (colonIndex == -1) return ['', message];
  String beforeColon = message.substring(0, colonIndex);
  String afterColon = message.substring(colonIndex + 1);
  return [beforeColon, afterColon];
}

/// Hands out the output names for one extraction run.
///
/// With [overwrite] off this is [claimFilePath]: everything takes a free name, so
/// an earlier run's files survive beside the new ones. With it on a name is
/// reused once, replacing what a previous run left, but never twice within the
/// same run, so two wallpapers whose files share a name still get one each
/// instead of the second destroying the first.
class FileNameClaims {
  FileNameClaims({required this.overwrite});

  final bool overwrite;

  /// Lower-cased, because Windows resolves two spellings to the same file.
  final Set<String> _taken = <String>{};

  Future<String> claim(String filePath) async {
    if (!overwrite) return claimFilePath(filePath);

    final String dirPath = path.dirname(filePath);
    final String fileName = path.basename(filePath);
    final String stem = path.basenameWithoutExtension(fileName);
    final String ext = path.extension(fileName);
    int index = 0;
    while (true) {
      final String candidate = index == 0
          ? path.join(dirPath, fileName)
          : path.join(dirPath, '$stem-$index$ext');
      if (_taken.add(candidate.toLowerCase())) return candidate;
      index++;
    }
  }
}

/// Highest suffix index already claimed, keyed by directory + stem + extension.
/// Lets [claimFilePath] resume probing instead of restarting at 1.
final Map<String, int> _claimIndexCache = {};

/// Clears the suffix cache. For tests, and for any caller that deletes output
/// files behind [claimFilePath]'s back and wants low indices reconsidered.
void resetClaimCache() => _claimIndexCache.clear();

// 写一个重命名文件名的方法，先检测文件是否已存在，存在就在文件名后面加“-1”，如果“-1”也存在，就加“-2”，以此类推
/// Atomically reserves a free filename near [filePath] and returns it.
///
/// Creates a zero-byte placeholder with `exclusive: true`, so testing the name
/// and taking it are a single filesystem operation. The previous version probed
/// for a free name and returned it without creating anything, which is a
/// time-of-check to time-of-use race: once extraction runs several wallpapers at
/// once into one shared export folder, two workers can both be handed
/// "cover.png" and one silently overwrites the other.
///
/// The suffix cache resumes where the last claim for this name stopped, so
/// exporting N colliding files costs N attempts rather than N^2.
Future<String> claimFilePath(String filePath) async {
  final String dirPath = path.dirname(filePath);
  final String fileName = path.basename(filePath);
  // Split off only the last extension so multi-dot names ("a.b.c.mp4") and
  // extension-less names are handled correctly.
  final String stem = path.basenameWithoutExtension(fileName);
  final String ext = path.extension(fileName);
  // The key joins on |, which Windows forbids in a path, so a directory ending
  // in a space cannot collide with a stem that starts with one.
  final String cacheKey = '$dirPath|$stem|$ext';

  int index = _claimIndexCache[cacheKey] ?? 0;
  while (true) {
    final String candidate = index == 0
        ? path.join(dirPath, fileName)
        : path.join(dirPath, '$stem-$index$ext');
    try {
      await File(candidate).create(exclusive: true);
      _claimIndexCache[cacheKey] = index;
      return candidate;
    } on FileSystemException {
      // Distinguish "name already taken" from a real failure such as a missing
      // parent or a read-only directory. Advancing the suffix on a genuine
      // error would spin instead of surfacing it.
      if (FileSystemEntity.typeSync(candidate) ==
          FileSystemEntityType.notFound) {
        rethrow;
      }
      index++;
    }
  }
}

String renameFolder(String folderName) {
  List<String> illegalCharacter = [
    '\\',
    '/',
    ':',
    '*',
    '?',
    '"',
    '<',
    '>',
    '|',
  ];
  String pattern = illegalCharacter.map((c) => RegExp.escape(c)).join('|');
  String result = folderName.replaceAll(RegExp(pattern), '_');
  return result;
}

String formattedTime(int? time) {
  if (time == null) return '';
  DateTime dateTime = DateTime.fromMillisecondsSinceEpoch(time * 1000);
  return dateTime.toString().substring(0, 19);
}
