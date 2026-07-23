import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:we_repkg/constants/i10n.dart';
import 'package:we_repkg/constants/keys.dart';
import 'package:we_repkg/constants/strings.dart';
import 'package:we_repkg/cores/toast.dart';
import 'package:we_repkg/models/acf.dart';
import 'package:we_repkg/models/enums.dart';
import 'package:we_repkg/models/error.dart';
import 'package:we_repkg/models/wallpaper.dart';
import 'package:we_repkg/provider/system.dart';
import 'package:we_repkg/provider/wallpaper.dart';
import 'package:we_repkg/utils/info.dart';
import 'package:we_repkg/utils/parse_acf.dart';
import 'package:we_repkg/utils/storage.dart';

Future<List<String>> getWindowsDisks() async {
  try {
    // 执行wmic命令获取磁盘信息
    final result = await Process.run('wmic', ['logicaldisk', 'get', 'name']);
    // 解析输出（注意不同系统语言可能需要调整分隔符）
    String output = result.stdout.toString();
    List<String> disks = output
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty && line.contains(':'))
        .toList();
    // 移除标题行（第一行通常是"Name"）
    if (disks.isNotEmpty && disks.first == 'Name') disks.removeAt(0);
    return disks;
  } catch (e) {
    debugPrint('获取磁盘失败: $e');
    return [];
  }
}

Future<String?> getWallpaperPath() async {
  final disks = await getWindowsDisks();
  if (disks.isEmpty) return null;
  // 生成所有可能的壁纸路径
  final tempPaths = _generateWallpaperPaths(disks);
  // 查找存在的壁纸路径
  final wallpaperPath = await _findWallpaperPath(tempPaths);
  // 处理存储逻辑
  await _handleStorageLogic(wallpaperPath);
  return wallpaperPath;
}

/// 生成所有可能的壁纸路径
List<String> _generateWallpaperPaths(List<String> disks) {
  final tempPaths = <String>[];
  // 为第一个磁盘（通常是系统盘）添加特殊路径
  tempPaths.add('${disks.first}${AppStrings.systemDiskWallpaperPath}');
  // 为所有磁盘添加基础路径
  for (final disk in disks) {
    tempPaths.add('$disk${AppStrings.baseWallpaperPath1}');
    tempPaths.add('$disk${AppStrings.baseWallpaperPath2}');
    tempPaths.add('$disk${AppStrings.baseWallpaperPath3}');
  }
  return tempPaths;
}

/// 查找存在的壁纸路径
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
  // 如果没有找到有内容的目录，但有空目录，使用空目录
  wallpaperPath ??= emptyPath;
  return wallpaperPath;
}

/// 处理存储相关的逻辑
Future<void> _handleStorageLogic(String? wallpaperPath) async {
  if (wallpaperPath != null) {
    String? acfPath = getAcfPath(wallpaperPath);
    if (acfPath != null) await StorageUtil.setString(AppKeys.acfPath, acfPath);
    String projectPath = projectDefaultPath(wallpaperPath);
    await StorageUtil.setString(AppKeys.projectPath, projectPath);
  }
}

Future<List<WallpaperInfo>> getAllFile(WidgetRef ref) async {
  // Capture notifiers synchronously up front: switching folders triggers a
  // state change that unmounts the widget owning `ref`, and touching `ref`
  // after the scan (await) would throw "Using ref when widget is unmounted".
  final wallpaperPathNotifier = ref.read(wallpaperPathProvider.notifier);
  final CurrentState currentState = ref.read(currentStateProvider.notifier);
  String? wallpaperPath = ref.read(wallpaperPathProvider);
  if (wallpaperPath == null) {
    wallpaperPath = await getWallpaperPath();
    wallpaperPathNotifier.update(wallpaperPath);
  }
  currentState.update(RunState.initial);
  List<WallpaperInfo> wallpapers = [];
  try {
    wallpapers = await getAllWallpaper(ref, wallpaperPath);
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
  Map<String, dynamic> content = await parseAcf(acfPath);
  if (content.isEmpty) return acfInfoList;
  acfInfoList = convertToAcfInfoList(content); // 转换为AcfInfo对象列表
  return acfInfoList;
}

Future<List<WallpaperInfo>> getAllWallpaper(
  WidgetRef ref,
  String? folderPath,
) async {
  if (folderPath == null) return [];
  // Capture the notifier synchronously; the scan (workshop folders can be slow)
  // may finish after the widget that owns `ref` has been unmounted.
  final earliestTimeNotifier = ref.read(earliestTimeProvider.notifier);
  List<WallpaperInfo> wallpapers = [];
  Directory dir = Directory(folderPath);
  if (!(await dir.exists())) return [];
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
  // Only directory entries, kept in original order (Future.wait returns
  // results in input order).
  final folders = dirList.whereType<Directory>().toList();
  // Bounded concurrency: parse project.json in parallel batches to avoid
  // opening too many file handles at once.
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
  if (earliestDate != null) {
    String earliestDateStr = earliestDate.toString().substring(0, 10);
    earliestTimeNotifier.update(earliestDateStr);
  }
  return wallpapers;
}

/// Parses a single wallpaper folder's project.json into a [WallpaperInfo].
/// Returns null (skipping the item, without aborting the whole scan) when the
/// project.json is missing or fails to parse.
Future<WallpaperInfo?> _parseWallpaperFolder(
  Directory folder,
  Map<String, AcfInfo> acfInfoMap,
) async {
  String id = path.basename(folder.path);
  File file = File('${folder.path}\\project.json');
  if (!await file.exists()) return null;
  try {
    String jsonString = await file.readAsString();
    final jsonMap = json.decode(jsonString);
    // User-created wallpapers (myprojects) may have a project.json without a
    // title; fall back to the folder id.
    String title = jsonMap['title'] ?? id;
    String? contentRating = jsonMap['contentrating'];
    if (contentRating == null) {
      debugPrint('没有分级: ${folder.path}');
      contentRating = '';
    }
    List<String> tags = List<String>.from(jsonMap['tags'] ?? []);
    String? type = jsonMap['type'];
    if (type == null) {
      debugPrint('没有类型: ${folder.path}');
      type = '';
    }
    // preview may be missing (e.g. a self-made wallpaper with no preview yet);
    // leave it empty and the UI shows a placeholder.
    String? imgName = jsonMap['preview'];
    String previews = imgName == null ? '' : '${folder.path}\\$imgName';
    String? target = jsonMap['file'];
    if (target == null) {
      String temp = '${folder.path}\\directories\\customdirectory';
      target = await Directory(temp).exists() ? temp : '';
    } else {
      if (target.endsWith('json')) target = 'scene.pkg';
      if (target == '') debugPrint('空文件：${folder.path}');
      target = target == '' ? '' : '${folder.path}\\$target';
    }
    int size = 0;
    int? updateTime;
    final fileStat = await file.stat();
    DateTime createTime = fileStat.changed;
    if (acfInfoMap.containsKey(id)) {
      size = acfInfoMap[id]!.size;
      updateTime = acfInfoMap[id]!.time;
    } else {
      debugPrint('$id 没有获取到信息');
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
    debugPrint('解析壁纸失败，已跳过 ${folder.path}: $e');
    return null;
  }
}

Future<void> refreshWallpaper(WidgetRef ref) async {
  // Capture the notifier before awaiting so a refresh can't crash if the
  // widget owning `ref` is unmounted mid-scan.
  final wallpaperListNotifier = ref.read(wallpaperListProvider.notifier);
  wallpaperListNotifier.clear();
  List<WallpaperInfo> wallpapers = await getAllFile(ref);
  wallpaperListNotifier.addAll(wallpapers);
}
