import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:we_repkg/constants/i10n.dart';
import 'package:we_repkg/cores/toast.dart';
import 'package:we_repkg/cores/wallpaper.dart';
import 'package:we_repkg/models/enums.dart';
import 'package:we_repkg/models/error.dart';
import 'package:we_repkg/models/wallpaper.dart';
import 'package:we_repkg/provider/system.dart';
import 'package:we_repkg/provider/wallpaper.dart';
import 'package:we_repkg/src/rust/api/simple.dart';
import 'package:we_repkg/utils/backup_diff.dart';
import 'package:we_repkg/utils/info.dart';
import 'package:we_repkg/widgets/confirm_dialog.dart';

import 'library_scan_refresh.dart';

Future<List<WallpaperInfo>> getAllFile(WidgetRef ref) async {
  // Read before any await: switching folders unmounts the widget owning `ref`,
  // so the scan writes back through these captured notifiers instead.
  final wallpaperPathNotifier = ref.read(wallpaperPathProvider.notifier);
  final CurrentState currentState = ref.read(currentStateProvider.notifier);
  final earliestTimeNotifier = ref.read(earliestTimeProvider.notifier);
  final WallpaperLibrary library = ref.read(currentLibraryProvider);
  final String? myProjects = ref.read(myProjectsLibraryProvider);
  String? folderPath = ref.read(wallpaperPathProvider);
  // Only the Workshop library is worth hunting for across the drives; the
  // myprojects one is derived from whatever that search settles on.
  if (folderPath == null) {
    folderPath = await getWallpaperPath();
    wallpaperPathNotifier.update(folderPath);
  }
  if (library == WallpaperLibrary.myProjects) {
    // Derived here rather than taken from the provider, which settled on null
    // back when the Workshop path was still unknown.
    folderPath =
        myProjects ??
        (folderPath == null ? null : projectDefaultPath(folderPath));
  }
  currentState.update(RunState.initial);
  List<WallpaperInfo> wallpapers = [];
  try {
    final result = await scanWallpapers(folderPath);
    wallpapers = result.wallpapers;
    final earliest = result.earliestDate;
    if (earliest != null) {
      earliestTimeNotifier.update(earliest.toString().substring(0, 10));
    }
    currentState.update(RunState.complete);
  } catch (e) {
    showErrorView([
      ErrorInfo(
        wallpaper: null,
        message: '${tr(AppI10n.errorGetWallpaperFailed)} $e',
      ),
    ]);
  }
  if (wallpapers.isEmpty) currentState.update(RunState.empty);
  return wallpapers;
}

Future<void> refreshWallpaper(WidgetRef ref) async {
  // Capture the notifier before awaiting so a refresh can't crash if the
  // widget owning `ref` is unmounted mid-scan.
  final wallpaperListNotifier = ref.read(wallpaperListProvider.notifier);
  wallpaperListNotifier.clear();
  // The library is about to be replaced, so ids selected against the old one
  // mean nothing.
  ref.read(checkedIdsProvider.notifier).clear();
  List<WallpaperInfo> wallpapers = await getAllFile(ref);
  wallpaperListNotifier.addAll(wallpapers);
}

Future<void> playVideo(WallpaperInfo wallpaper) async {
  String videoPath = wallpaper.target;
  if (!File(videoPath).existsSync()) {
    return showErrorToast(tr(AppI10n.dialogFileNoExist));
  }
  final Uri fileUri = Uri.file(videoPath);
  if (await canLaunchUrl(fileUri)) {
    await launchUrl(fileUri);
  } else {
    showErrorToast(tr(AppI10n.dialogPlayVideoFailed));
  }
}

/// Ids of the wallpapers whose folder is no longer on disk.
///
/// `trash::delete_all` can fail partway through a batch, leaving some folders
/// deleted and others intact, and its error value says nothing about which is
/// which. Asking the filesystem is the only way to know what to drop from the
/// list. Probes run concurrently; [probe] is injectable for tests.
Future<Set<String>> findDeletedWallpapers(
  List<WallpaperInfo> wallpapers, {
  DirectoryProbe probe = directoryExists,
}) async {
  if (wallpapers.isEmpty) return <String>{};
  final survives = await Future.wait(wallpapers.map((w) => probe(w.folder)));
  return <String>{
    for (int i = 0; i < wallpapers.length; i++)
      if (!survives[i]) wallpapers[i].id,
  };
}

Future<String?> deleteChecked(WidgetRef ref) async {
  final container = ProviderScope.containerOf(ref.context, listen: false);
  String? err;
  List<WallpaperInfo> wallpapers = ref.read(checkedWallpaperListProvider);
  if (wallpapers.isEmpty) return null;
  // Confirm first: the delete button sits beside the extract buttons and the
  // selection can be large.
  final bool confirmed = await showConfirmDialog(
    title: tr(AppI10n.dialogDeleteConfirmTitle),
    message: wallpapers.length == 1
        ? tr(
            AppI10n.dialogDeleteConfirmOne,
            namedArgs: {'title': wallpapers.first.title},
          )
        : tr(
            AppI10n.dialogDeleteConfirmMany,
            namedArgs: {'count': '${wallpapers.length}'},
          ),
  );
  if (!confirmed) return null;
  List<String> paths = wallpapers.map((e) => e.folder).toList();
  try {
    final String? trashErr = await withLibraryScanRefresh(
      container,
      () => deleteAllToTrash(filePaths: paths),
    );
    if (trashErr != null) {
      err = '${tr(AppI10n.dialogDeleteFailed)} $trashErr';
    }
    // Remove exactly what actually went away. The previous version dropped
    // every selected wallpaper regardless of the result, so a failed delete
    // showed a success toast and hid folders that were still on disk.
    final Set<String> gone = await findDeletedWallpapers(wallpapers);
    if (gone.isNotEmpty) {
      WallpaperInfo? selectedWallpaper = ref.read(selectedWallpaperProvider);
      if (selectedWallpaper != null && gone.contains(selectedWallpaper.id)) {
        ref.read(selectedWallpaperProvider.notifier).update(null);
      }
      ref.read(wallpaperListProvider.notifier).removeAll(gone);
      // Selection is held by id, so a deleted wallpaper would otherwise stay in
      // the set and come back with anything that reused its id.
      ref.read(checkedIdsProvider.notifier).forget(gone);
    }
  } catch (e) {
    debugPrint('${tr(AppI10n.logDeleteCheckedFailed)} $e');
    err = '${tr(AppI10n.dialogDeleteFailed)} $e';
  }
  // The only caller discards this return value, so report the outcome here.
  if (err == null) {
    showDeleteToast();
  } else {
    showErrorToast(err);
  }
  return err;
}

Future<void> browserCurrent(WallpaperInfo wallpaper) =>
    browserFolder(wallpaper.folder);

Future<void> browserFolder(String folder) async {
  if (!Directory(folder).existsSync()) {
    return showErrorToast(tr(AppI10n.dialogFileNoExist));
  }
  final fixedPath = 'file:///${folder.replaceAll('\\', '/')}';
  final uri = Uri.parse(fixedPath);
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri);
  } else {
    showErrorToast(tr(AppI10n.dialogOpenFolderFailed));
  }
}

/// Drops [wallpaper] from the library, the selection and the checked set.
///
/// Selection is held by id, so leaving the id behind keeps it counted as
/// checked, and it would come back checked if a later scan reused the id.
void forgetWallpaper(WidgetRef ref, WallpaperInfo wallpaper) {
  ref.read(wallpaperListProvider.notifier).remove(wallpaper);
  ref.read(selectedWallpaperProvider.notifier).update(null);
  ref.read(checkedIdsProvider.notifier).forget({wallpaper.id});
}

Future<void> deleteCurrent(WidgetRef ref, WallpaperInfo wallpaper) async {
  final container = ProviderScope.containerOf(ref.context, listen: false);
  final bool confirmed = await showConfirmDialog(
    title: tr(AppI10n.dialogDeleteConfirmTitle),
    message: tr(
      AppI10n.dialogDeleteConfirmOne,
      namedArgs: {'title': wallpaper.title},
    ),
  );
  if (!confirmed) return;
  try {
    // deleteToTrash reports failure through its return value, not by throwing.
    // Awaiting it and discarding the result dropped the row from the list while
    // the folder was still on disk.
    final String? trashErr = await withLibraryScanRefresh(
      container,
      () => deleteToTrash(filePath: wallpaper.folder),
    );
    if (trashErr != null) {
      debugPrint('${tr(AppI10n.logDeleteFileFailed)} $trashErr');
      return showErrorToast('${tr(AppI10n.dialogDeleteFailed)} $trashErr');
    }
    forgetWallpaper(ref, wallpaper);
    showDeleteToast();
  } catch (e) {
    debugPrint('${tr(AppI10n.logDeleteFileFailed)} $e');
    showErrorToast('${tr(AppI10n.dialogDeleteFailed)} $e');
  }
}
