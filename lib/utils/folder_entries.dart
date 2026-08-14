import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:we_repkg/cores/integrity_rules.dart';

/// What is directly inside [folder], or null if it could not be read.
///
/// A folder that moved mid-scan comes back null so the caller can skip it
/// rather than abort the library it is walking.
Future<List<FolderEntry>?> listFolderEntries(Directory folder) async {
  final List<FolderEntry> entries = <FolderEntry>[];
  try {
    await for (final FileSystemEntity entity in folder.list()) {
      entries.add((
        name: path.basename(entity.path),
        isDirectory: entity is Directory,
      ));
    }
  } on FileSystemException {
    return null;
  }
  return entries;
}
