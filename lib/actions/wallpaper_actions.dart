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
  // Capture notifiers before awaiting; switching folders may unmount the widget.
  final wallpaperPathNotifier = ref.read(wallpaperPathProvider.notifier);
  final CurrentState currentState = ref.read(currentStateProvider.notifier);
  final earliestTimeNotifier = ref.read(earliestTimeProvider.notifier);
  final WallpaperLibrary library = ref.read(currentLibraryProvider);
  final String? myProjects = ref.read(myProjectsLibraryProvider);
  String? folderPath = ref.read(wallpaperPathProvider);
  // Discover Workshop first; it supplies the default MyProjects path.
  if (folderPath == null) {
    folderPath = await getWallpaperPath();
    wallpaperPathNotifier.update(folderPath);
  }
  if (library == WallpaperLibrary.myProjects) {
    // The captured MyProjects path may predate Workshop discovery.
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
  // Keep the notifier available if the widget unmounts during the scan.
  final wallpaperListNotifier = ref.read(wallpaperListProvider.notifier);
  wallpaperListNotifier.clear();
  // Clear selection before replacing the library.
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

/// Finds deleted wallpaper IDs by checking disk after a potentially partial deletion.
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
    // A batch can fail partially; remove only folders confirmed absent.
    final Set<String> gone = await findDeletedWallpapers(wallpapers);
    if (gone.isNotEmpty) {
      WallpaperInfo? selectedWallpaper = ref.read(selectedWallpaperProvider);
      if (selectedWallpaper != null && gone.contains(selectedWallpaper.id)) {
        ref.read(selectedWallpaperProvider.notifier).update(null);
      }
      ref.read(wallpaperListProvider.notifier).removeAll(gone);
      // Prevent a reused ID from inheriting the deleted wallpaper's selection.
      ref.read(checkedIdsProvider.notifier).forget(gone);
    }
  } catch (e) {
    debugPrint('${tr(AppI10n.logDeleteCheckedFailed)} $e');
    err = '${tr(AppI10n.dialogDeleteFailed)} $e';
  }
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

/// Removes the wallpaper and its selection state, including its stored checked ID.
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
    // Check the returned error before removing the wallpaper from the list.
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
