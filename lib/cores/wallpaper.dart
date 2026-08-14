import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:we_repkg/constants/i10n.dart';
import 'package:we_repkg/constants/keys.dart';
import 'package:we_repkg/constants/strings.dart';
import 'package:we_repkg/constants/wallpaper_files.dart';
import 'package:we_repkg/constants/wallpaper_type.dart';
import 'package:we_repkg/cores/toast.dart';
import 'package:we_repkg/models/acf.dart';
import 'package:we_repkg/models/enums.dart';
import 'package:we_repkg/models/error.dart';
import 'package:we_repkg/models/wallpaper.dart';
import 'package:we_repkg/provider/system.dart';
import 'package:we_repkg/provider/wallpaper.dart';
import 'package:we_repkg/utils/backup_diff.dart';
import 'package:we_repkg/utils/info.dart';
import 'package:we_repkg/utils/parse_acf.dart';
import 'package:we_repkg/utils/storage.dart';

/// Tests whether a directory exists. Injectable so the drive scan can be tested
/// without touching real hardware.
typedef DirectoryProbe = Future<bool> Function(String path);

Future<bool> directoryExists(String path) => Directory(path).exists();

Future<List<String>> getWindowsDisks({
  DirectoryProbe probe = directoryExists,
}) async {
  // Probing letters beats the deprecated `wmic` and spawns no process. All 26
  // go at once because an absent A: or B: can block for seconds. Future.wait
  // keeps input order, so the system drive stays first as
  // _generateWallpaperPaths expects.
  try {
    final letters = [
      for (int code = 'A'.codeUnitAt(0); code <= 'Z'.codeUnitAt(0); code++)
        String.fromCharCode(code),
    ];
    final found = await Future.wait(letters.map((l) => probe('$l:\\')));
    return [
      for (int i = 0; i < letters.length; i++)
        if (found[i]) '${letters[i]}:',
    ];
  } catch (e) {
    debugPrint('${tr(AppI10n.logGetDisksFailed)} $e');
    return [];
  }
}

Future<String?> getWallpaperPath() async {
  final disks = await getWindowsDisks();
  if (disks.isEmpty) return null;
  final tempPaths = _generateWallpaperPaths(disks);
  final wallpaperPath = await _findWallpaperPath(tempPaths);
  await _handleStorageLogic(wallpaperPath);
  return wallpaperPath;
}

List<String> _generateWallpaperPaths(List<String> disks) {
  final tempPaths = <String>[];
  // 为第一个磁盘（通常是系统盘）添加特殊路径
  tempPaths.add('${disks.first}${AppStrings.systemDiskWallpaperPath}');
  // 为所有磁盘添加基础路径
  for (final disk in disks) {
    tempPaths.add('$disk${AppStrings.baseWallpaperPath1}');
    tempPaths.add('$disk${AppStrings.baseWallpaperPath2}');
  }
  return tempPaths;
}

/// 优先返回有内容的目录，全空时退回第一个存在的。
Future<String?> _findWallpaperPath(List<String> tempPaths) async {
  String? emptyPath, wallpaperPath;
  for (String tempPath in tempPaths) {
    if (!(await Directory(tempPath).exists())) continue;
    emptyPath ??= tempPath;
    Directory dir = Directory(tempPath);
    bool hasContent = await dir.list().isEmpty == false;
    if (hasContent) {
      wallpaperPath = tempPath;
      break;
    }
  }
  wallpaperPath ??= emptyPath;
  return wallpaperPath;
}

Future<void> _handleStorageLogic(String? wallpaperPath) async {
  if (wallpaperPath != null) {
    String? acfPath = getAcfPath(wallpaperPath);
    if (acfPath != null) await StorageUtil.setString(AppKeys.acfPath, acfPath);
    String projectPath = projectDefaultPath(wallpaperPath);
    await StorageUtil.setString(AppKeys.projectPath, projectPath);
  }
}

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

Future<List<AcfInfo>> getAcfInfo() async {
  List<AcfInfo> acfInfoList = [];
  bool getInfo = StorageUtil.getNullBool(AppKeys.useAcfInfo) ?? true;
  if (!getInfo) return acfInfoList;
  String? acfPath = StorageUtil.getString(AppKeys.acfPath);
  if (acfPath == null) return acfInfoList;
  if (!(await File(acfPath).exists())) return acfInfoList;
  try {
    Map<String, dynamic> content = await parseAcf(acfPath);
    if (content.isEmpty) return acfInfoList;
    acfInfoList = convertToAcfInfoList(content); // 转换为AcfInfo对象列表
  } catch (e) {
    // Not fatal for the grid, which only loses size and update time. It does
    // cost the backup tab its update detection, so that warns for itself.
    debugPrint('${tr(AppI10n.errorParseAcfFailed)} $e');
  }
  return acfInfoList;
}

/// Reads every project.json in bounded parallel batches and returns the
/// wallpapers in directory order, plus the earliest create time. Holds no
/// WidgetRef, so the caller writes the results into providers.
Future<({List<WallpaperInfo> wallpapers, DateTime? earliestDate})>
scanWallpapers(String? folderPath) async {
  final List<WallpaperInfo> wallpapers = [];
  if (folderPath == null) return (wallpapers: wallpapers, earliestDate: null);
  Directory dir = Directory(folderPath);
  if (!(await dir.exists())) {
    return (wallpapers: wallpapers, earliestDate: null);
  }
  final (
    dirList,
    acfInfoList,
  ) = await (Future.wait([dir.list().toList(), getAcfInfo()])).then(
    (results) =>
        (results[0] as List<FileSystemEntity>, results[1] as List<AcfInfo>),
  );
  DateTime? earliestDate;
  // 创建一个Map以便快速查找AcfInfo
  Map<String, AcfInfo> acfInfoMap = {};
  for (var acfInfo in acfInfoList) {
    acfInfoMap[acfInfo.id] = acfInfo;
  }
  // Directories only, in original order.
  final folders = dirList
      .whereType<Directory>()
      .where(
        (Directory folder) =>
            !WallpaperFiles.isLibraryRepairStage(path.basename(folder.path)),
      )
      .toList();
  // Batched, or a large library opens too many file handles at once.
  const int batchSize = 24;
  for (int i = 0; i < folders.length; i += batchSize) {
    final batch = folders.skip(i).take(batchSize);
    final parsed = await Future.wait(
      batch.map((folder) => _parseWallpaperFolder(folder, acfInfoMap)),
    );
    for (final wallpaper in parsed) {
      if (wallpaper == null) continue; // skip missing/corrupt entries
      wallpapers.add(wallpaper);
      if (earliestDate == null || wallpaper.createTime.isBefore(earliestDate)) {
        earliestDate = wallpaper.createTime;
      }
    }
  }
  return (wallpapers: wallpapers, earliestDate: earliestDate);
}

/// One folder read as a wallpaper, for the details of a backup card, which is a
/// folder name rather than a row of a scanned library.
///
/// Falls back to the folder and its size when project.json will not read: that
/// folder is exactly the one whose details are worth opening, and the backup
/// grid keeps it rather than dropping it the way the extract scan does.
Future<WallpaperInfo> readWallpaperFolder(String folderPath) async {
  final Directory folder = Directory(folderPath);
  final Map<String, AcfInfo> acfInfoMap = <String, AcfInfo>{
    for (final AcfInfo info in await getAcfInfo()) info.id: info,
  };
  final WallpaperInfo? parsed = await _parseWallpaperFolder(folder, acfInfoMap);
  if (parsed != null) return parsed;
  final String name = path.basename(folderPath);
  return WallpaperInfo(
    id: name,
    title: name,
    contentRating: '',
    tags: const <String>[],
    previews: '',
    type: WallpaperType.unknown,
    updateTime: null,
    createTime: (await folder.stat()).changed,
    target: '',
    folder: folderPath,
    // The whole folder, not getSize: there is no project.json to name a file to
    // measure, and the folder is the thing the user is asking about.
    size: await folderBytes(folder),
  );
}

/// Parses one folder's project.json. Null if it is missing or unreadable, which
/// skips the wallpaper rather than aborting the scan.
Future<WallpaperInfo?> _parseWallpaperFolder(
  Directory folder,
  Map<String, AcfInfo> acfInfoMap,
) async {
  String id = path.basename(folder.path);
  File file = File(path.join(folder.path, WallpaperFiles.project));
  if (!await file.exists()) return null;
  try {
    String jsonString = await file.readAsString();
    final jsonMap = json.decode(jsonString);
    // myprojects wallpapers often have no title; fall back to the folder id.
    String title = jsonMap[WallpaperProjectFields.title] ?? id;
    String? contentRating = jsonMap[WallpaperProjectFields.contentRating];
    if (contentRating == null) {
      if (kDebugMode) {
        debugPrint('${tr(AppI10n.logNoContentRating)} ${folder.path}');
      }
      contentRating = '';
    }
    List<String> tags = List<String>.from(
      jsonMap[WallpaperProjectFields.tags] ?? <String>[],
    );
    String? type = jsonMap[WallpaperProjectFields.type];
    if (type == null) {
      if (kDebugMode) {
        debugPrint('${tr(AppI10n.logNoType)} ${folder.path}');
      }
      type = '';
    }
    // May be missing on a self-made wallpaper; the UI shows a placeholder.
    String? imgName = jsonMap[WallpaperProjectFields.preview];
    String previews = imgName == null ? '' : path.join(folder.path, imgName);
    String? target = jsonMap[WallpaperProjectFields.file];
    if (target == null) {
      String temp = path.join(
        folder.path,
        WallpaperDirectories.container,
        WallpaperDirectories.custom,
      );
      target = await Directory(temp).exists() ? temp : '';
    } else if (target.toLowerCase().endsWith('json')) {
      // project.json says scene.json whether the scene is packed or not, so
      // assuming scene.pkg pointed RePKG at a file that wasn't there. With no
      // pkg present, target the folder and copy the unpacked files.
      final bool packed = await File(
        path.join(folder.path, WallpaperFiles.packedScene),
      ).exists();
      target = packed
          ? path.join(folder.path, WallpaperFiles.packedScene)
          : folder.path;
    } else {
      if (target == '') {
        if (kDebugMode) {
          debugPrint('${tr(AppI10n.logEmptyFile)} ${folder.path}');
        }
      }
      target = target == '' ? '' : path.join(folder.path, target);
    }
    int size = 0;
    int? updateTime;
    final fileStat = await file.stat();
    DateTime createTime = fileStat.changed;
    if (acfInfoMap.containsKey(id)) {
      size = acfInfoMap[id]!.size;
      updateTime = acfInfoMap[id]!.time;
    } else {
      if (kDebugMode) debugPrint('$id ${tr(AppI10n.logNoInfo)}');
      size = await getSize(target);
      updateTime = null;
    }
    return WallpaperInfo(
      id: id,
      title: title,
      contentRating: contentRating.toLowerCase(),
      tags: tags,
      previews: previews,
      type: type.toLowerCase(),
      updateTime: updateTime,
      createTime: createTime,
      target: target,
      size: size,
      folder: folder.path,
    );
  } catch (e) {
    // A single failed parse shouldn't abort the whole scan; skip and log it.
    if (kDebugMode) {
      debugPrint('${tr(AppI10n.logParseWallpaperSkipped)} ${folder.path}: $e');
    }
    return null;
  }
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
