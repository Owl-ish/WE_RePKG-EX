import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:we_repkg/provider/backup.dart';
import 'package:we_repkg/provider/integrity.dart';
import 'package:we_repkg/provider/system.dart';

/// Refreshes cached inspections after an operation that can change a library.
/// An error can follow partial writes or deletion, so it must refresh too.
/// Call after confirmation. When [outputFolder] is supplied, unrelated exports
/// keep their cached scans. This is a conservative path check, not write tracking.
Future<T> withLibraryScanRefresh<T>(
  ProviderContainer container,
  Future<T> Function() operation, {
  String? outputFolder,
}) async {
  try {
    return await operation();
  } finally {
    if (outputFolder == null ||
        <String?>[
          container.read(wallpaperPathProvider),
          container.read(myProjectsLibraryProvider),
          container.read(backupRootProvider),
        ].any((root) => root != null && _overlaps(outputFolder, root))) {
      container.invalidate(backupScanProvider);
      container.invalidate(integrityScanProvider);
    }
  }
}

bool _overlaps(String output, String root) {
  final destination = path.normalize(path.absolute(output));
  final library = path.normalize(path.absolute(root));
  return path.equals(destination, library) ||
      path.isWithin(library, destination) ||
      path.isWithin(destination, library);
}
