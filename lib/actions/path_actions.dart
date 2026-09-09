import 'package:easy_localization/easy_localization.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:we_repkg/actions/wallpaper_actions.dart';
import 'package:we_repkg/constants/i10n.dart';
import 'package:we_repkg/constants/keys.dart';
import 'package:we_repkg/constants/strings.dart';
import 'package:we_repkg/cores/toast.dart';
import 'package:we_repkg/cores/wallpaper.dart';
import 'package:we_repkg/models/enums.dart';
import 'package:we_repkg/provider/navigation.dart';
import 'package:we_repkg/provider/setting.dart';
import 'package:we_repkg/provider/system.dart';
import 'package:we_repkg/provider/wallpaper.dart';
import 'package:we_repkg/utils/info.dart';
import 'package:we_repkg/utils/storage.dart';

// Capture notifiers before opening a picker; its widget may unmount while browsing.
Future<bool> setExportPath(WidgetRef ref, [bool show = false]) async {
  if (show) showSelectFolderToast(tr(AppI10n.extractFolderToast));
  final notifier = ref.read(exportPathProvider.notifier);
  final String? exportPath = await getDirectoryPath();
  if (exportPath == null) return false;
  notifier.update(exportPath);
  return true;
}

Future<void> setBackupRoot(WidgetRef ref) async {
  final notifier = ref.read(backupRootProvider.notifier);
  final String? backupRoot = await getDirectoryPath();
  if (backupRoot != null) notifier.update(backupRoot);
}

Future<void> setToolPath(WidgetRef ref) async {
  final notifier = ref.read(toolPathProvider.notifier);
  final xType = XTypeGroup(label: 'RePKG', extensions: ['exe']);
  final XFile? file = await openFile(acceptedTypeGroups: [xType]);
  if (file != null) notifier.update(file.path);
}

Future<void> refreshToolPath(WidgetRef ref) async {
  await StorageUtil.remove(AppKeys.toolPath);
  ref.read(toolPathProvider.notifier).update(getToolPath());
}

Future<bool> setProjectPath(WidgetRef ref, [bool show = false]) async {
  if (show) showSelectFolderToast(tr(AppI10n.projectFolderToast));
  final notifier = ref.read(projectPathProvider.notifier);
  final String? projectPath = await getDirectoryPath();
  if (projectPath == null) return false;
  notifier.update(projectPath);
  return true;
}

Future<void> setMyProjectsLibrary(WidgetRef ref) async {
  final notifier = ref.read(myProjectsLibraryProvider.notifier);
  final String? picked = await getDirectoryPath();
  if (picked != null) notifier.update(picked);
}

/// Removes the override so MyProjects is derived from the Workshop path again.
void refreshMyProjectsLibrary(WidgetRef ref) =>
    ref.read(myProjectsLibraryProvider.notifier).reset();

void refreshExportPath(WidgetRef ref) =>
    ref.read(exportPathProvider.notifier).clear();

void refreshProjectPath(WidgetRef ref) {
  String? wallpaperPath = StorageUtil.getString(AppKeys.wallpaperPath);
  if (wallpaperPath != null) {
    String projectPath = projectDefaultPath(wallpaperPath);
    ref.read(projectPathProvider.notifier).update(projectPath);
  }
}

Future<void> setWallpaperPath(WidgetRef ref) async {
  final String? previousPath = ref.read(wallpaperPathProvider);
  final section = ref.read(currentSectionProvider.notifier);
  final selected = ref.read(selectedWallpaperProvider.notifier);
  final pathNotifier = ref.read(wallpaperPathProvider.notifier);
  final updateOtherFolder = otherFolderUpdater(ref);
  final String? wallpaperPath = await getDirectoryPath();
  if (wallpaperPath == null) return;

  if (wallpaperPath != previousPath) {
    section.requestEntrance(NavSection.extract);
  }
  selected.update(null);
  pathNotifier.update(wallpaperPath);
  updateOtherFolder(wallpaperPath);
  await refreshWallpaper(ref);
}

Future<void> refreshWallpaperPath(WidgetRef ref) async {
  final String? previousPath = ref.read(wallpaperPathProvider);
  final section = ref.read(currentSectionProvider.notifier);
  final pathNotifier = ref.read(wallpaperPathProvider.notifier);
  final updateOtherFolder = otherFolderUpdater(ref);
  final String? wallpaperPath = await getWallpaperPath();
  if (wallpaperPath != null) {
    if (wallpaperPath != previousPath) {
      section.requestEntrance(NavSection.extract);
    }
    pathNotifier.update(wallpaperPath);
    updateOtherFolder(wallpaperPath);
  }
  await refreshWallpaper(ref);
}

/// Captures settings and notifiers for updating related paths after a picker closes.
void Function(String wallpaperPath) otherFolderUpdater(WidgetRef ref) {
  final bool alwaysProject = ref.read(updateProjectPathProvider);
  final bool alwaysAcf = ref.read(updateAcfPathProvider);
  final projectNotifier = ref.read(projectPathProvider.notifier);
  final acfNotifier = ref.read(acfPathProvider.notifier);

  return (String wallpaperPath) {
    final String? projectPath = StorageUtil.getString(AppKeys.projectPath);
    final String? acfPath = StorageUtil.getString(AppKeys.acfPath);
    if (alwaysProject || projectPath == null) {
      projectNotifier.update(projectDefaultPath(wallpaperPath));
    }
    if (alwaysAcf || acfPath == null) {
      if (acfPath != null) StorageUtil.remove(AppKeys.acfPath);
      acfNotifier.update(getAcfPath(wallpaperPath));
    }
  };
}

Future<void> setAcfPath(WidgetRef ref) async {
  final xType = XTypeGroup(label: AppStrings.acfName, extensions: ['acf']);
  final XFile? file = await openFile(acceptedTypeGroups: [xType]);
  if (file != null) {
    ref.read(acfPathProvider.notifier).update(file.path);
    await refreshWallpaperPath(ref);
  }
}

Future<void> refreshAcfPath(WidgetRef ref) async {
  await StorageUtil.remove(AppKeys.acfPath);
  ref.read(acfPathProvider.notifier).update(getAcfPath());
  await refreshWallpaperPath(ref);
}

Future<bool> checkExportPath(WidgetRef ref, [bool show = false]) async {
  String? exportPath = ref.read(exportPathProvider);
  if (exportPath == null) return await setExportPath(ref, show);
  return true;
}

Future<bool> checkProjectPath(WidgetRef ref, [bool show = false]) async {
  String? projectPath = ref.read(projectPathProvider);
  if (projectPath == null) return await setProjectPath(ref, show);
  return true;
}
