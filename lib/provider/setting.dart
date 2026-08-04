import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:we_repkg/constants/keys.dart';
import 'package:we_repkg/models/enums.dart';
import 'package:we_repkg/utils/storage.dart';
import 'package:we_repkg/utils/system_memory.dart';

part 'setting.g.dart';

@riverpod
class OnlySaveImage extends _$OnlySaveImage {
  @override
  bool build() => StorageUtil.getNullBool(AppKeys.onlySaveImage) ?? true;
  void update(bool value) async {
    state = value;
    await StorageUtil.setBool(AppKeys.onlySaveImage, value);
  }
}

@riverpod
class ExcludeTexture extends _$ExcludeTexture {
  @override
  bool build() => StorageUtil.getNullBool(AppKeys.excludeTexture) ?? true;
  void update(bool value) async {
    state = value;
    await StorageUtil.setBool(AppKeys.excludeTexture, value);
  }
}

@riverpod
class UseTitleName extends _$UseTitleName {
  @override
  bool build() => StorageUtil.getNullBool(AppKeys.useTitleName) ?? true;
  void update(bool value) async {
    state = value;
    await StorageUtil.setBool(AppKeys.useTitleName, value);
  }
}

@riverpod
class SortAscending extends _$SortAscending {
  @override
  bool build() => StorageUtil.getBool(AppKeys.sortAscending);
  void update() async {
    state = !state;
    await StorageUtil.setBool(AppKeys.sortAscending, state);
  }
}

@riverpod
class WallpaperSortType extends _$WallpaperSortType {
  @override
  SortType build() =>
      SortType.values[StorageUtil.getInt(AppKeys.sortType) ?? 0];
  void update(SortType value) async {
    state = value;
    await StorageUtil.setInt(AppKeys.sortType, value.index);
  }
}

@riverpod
class ReplaceFile extends _$ReplaceFile {
  @override
  bool build() => StorageUtil.getBool(AppKeys.replaceFile);
  void update(bool value) async {
    state = value;
    await StorageUtil.setBool(AppKeys.replaceFile, state);
  }
}

/// The persisted notification choice. Shared with the success toast, which has
/// no `ref` to read the provider through: it is stored by index, so a second
/// copy of this lookup would be free to disagree about the default.
NotificationType storedNotificationType() =>
    NotificationType.values[StorageUtil.getInt(AppKeys.notificationType) ??
        NotificationType.app.index];

@riverpod
class LocalNotificationType extends _$LocalNotificationType {
  @override
  NotificationType build() => storedNotificationType();
  void update(NotificationType value) async {
    state = value;
    await StorageUtil.setInt(AppKeys.notificationType, value.index);
  }
}

@riverpod
class DeleteTransparency extends _$DeleteTransparency {
  @override
  bool build() => StorageUtil.getBool(AppKeys.deleteTransparency);
  void update(bool value) async {
    state = value;
    await StorageUtil.setBool(AppKeys.deleteTransparency, state);
  }
}

@riverpod
class UseProjectPath extends _$UseProjectPath {
  @override
  bool build() => StorageUtil.getBool(AppKeys.useProjectFolder);
  void update(bool value) async {
    state = value;
    await StorageUtil.setBool(AppKeys.useProjectFolder, state);
  }
}

@riverpod
class UseAcfInfo extends _$UseAcfInfo {
  @override
  bool build() => StorageUtil.getNullBool(AppKeys.useAcfInfo) ?? true;
  void update(bool value) async {
    state = value;
    await StorageUtil.setBool(AppKeys.useAcfInfo, state);
  }
}

@riverpod
class UpdateProjectPath extends _$UpdateProjectPath {
  @override
  bool build() => StorageUtil.getNullBool(AppKeys.updateProjectPath) ?? true;
  void update(bool value) async {
    state = value;
    await StorageUtil.setBool(AppKeys.updateProjectPath, state);
  }
}

@riverpod
class UpdateAcfPath extends _$UpdateAcfPath {
  @override
  bool build() => StorageUtil.getNullBool(AppKeys.updateAcfPath) ?? true;
  void update(bool value) async {
    state = value;
    await StorageUtil.setBool(AppKeys.updateAcfPath, state);
  }
}

@riverpod
class MaximizeOpen extends _$MaximizeOpen {
  @override
  bool build() => StorageUtil.getBool(AppKeys.maximizeOpen);
  void update(bool value) async {
    state = value;
    await StorageUtil.setBool(AppKeys.maximizeOpen, state);
  }
}

/// How many wallpapers extract at once.
///
/// Four by default rather than the core count: RePKG is as much disk-bound as
/// CPU-bound, and on a spinning disk more parallelism makes a batch slower.
/// Users on fast NVMe can raise it.
///
/// Eight at the top. A batch takes as long as its slowest wallpaper, so past a
/// handful the extra workers finish early and wait, and the cores each RePKG
/// gets for its own textures are divided by this number: at sixteen every one
/// of them is down to a single thread.
@riverpod
class ExtractConcurrency extends _$ExtractConcurrency {
  static const int min = 1;
  static const int max = 8;
  static const int defaultValue = 4;

  @override
  int build() {
    final stored = StorageUtil.getInt(AppKeys.extractConcurrency);
    return (stored ?? defaultValue).clamp(min, max);
  }

  void update(int value) async {
    state = value.clamp(min, max);
    await StorageUtil.setInt(AppKeys.extractConcurrency, state);
  }
}

/// Total megabytes extraction may hold at once, shared between however many
/// wallpapers run side by side.
///
/// A quarter of the machine by default. Nothing predicts what a wallpaper will
/// cost, so this is a ceiling RePKG is held to rather than an estimate: too low
/// only makes extraction slower, never wrong.
@riverpod
class ExtractMemoryLimit extends _$ExtractMemoryLimit {
  static const int min = 256;
  static const int max = 16384;
  static const int fallback = 1024;

  /// Whole gigabytes read better on a slider than 1536MB does.
  static const int step = 256;

  /// What to suggest on a machine this size, before the user says otherwise.
  static int suggestedFor(int? installedBytes) {
    if (installedBytes == null) return fallback;
    final int quarter = installedBytes ~/ 4 ~/ (1024 * 1024);
    return quarter.clamp(min, max);
  }

  @override
  int build() {
    final stored = StorageUtil.getInt(AppKeys.extractMemoryLimit);
    return (stored ?? suggestedFor(installedMemoryBytes())).clamp(min, max);
  }

  void update(int value) async {
    state = value.clamp(min, max);
    await StorageUtil.setInt(AppKeys.extractMemoryLimit, state);
  }
}
