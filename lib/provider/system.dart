import 'package:easy_localization/easy_localization.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:we_repkg/constants/i10n.dart';
import 'package:we_repkg/constants/keys.dart';
import 'package:we_repkg/models/enums.dart';
import 'package:we_repkg/utils/backup_diff.dart';
import 'package:we_repkg/utils/info.dart';
import 'package:we_repkg/utils/cancel_token.dart';
import 'package:we_repkg/utils/storage.dart';

part 'system.g.dart';

@Riverpod(keepAlive: true)
class CurrentState extends _$CurrentState {
  @override
  RunState build() => RunState.initial;
  void update(RunState value) => state = value;
}

@Riverpod(keepAlive: true)
class WallpaperPath extends _$WallpaperPath {
  @override
  String? build() => StorageUtil.getString(AppKeys.wallpaperPath);

  void update(String? value) async {
    state = value;
    if (state == null) return;
    await StorageUtil.setString(AppKeys.wallpaperPath, value!);
  }
}

@Riverpod(keepAlive: true)
class ToolPath extends _$ToolPath {
  @override
  String? build() => getToolPath();
  void update(String? value) async {
    state = value;
    if (state == null) return;
    await StorageUtil.setString(AppKeys.toolPath, value!);
  }
}

@Riverpod(keepAlive: true)
class ProjectPath extends _$ProjectPath {
  @override
  String? build() => StorageUtil.getString(AppKeys.projectPath);
  void update(String? value) async {
    state = value;
    if (state == null) return;
    await StorageUtil.setString(AppKeys.projectPath, value!);
  }
}

/// Which library the grid is browsing. Remembered, like the sort and filter.
@Riverpod(keepAlive: true)
class CurrentLibrary extends _$CurrentLibrary {
  @override
  WallpaperLibrary build() =>
      WallpaperLibrary.values[StorageUtil.getInt(AppKeys.currentLibrary) ?? 0];

  void update(WallpaperLibrary value) async {
    state = value;
    await StorageUtil.setInt(AppKeys.currentLibrary, value.index);
  }
}

/// The live myprojects library, the second half of the pair the backup tab
/// compares against the backup.
///
/// Deliberately not [ProjectPath], which is where extraction *writes*. The two
/// shared one setting until 2026-08-05, so pointing extraction at a scratch
/// folder made the backup tab read an empty myprojects library and file all
/// 1341 backed-up folders as vanished or needing reconciliation.
///
/// Falls back to the folder beside the Workshop library, so it fills itself in
/// and follows [WallpaperPath] until the user picks one. [reset] removes the
/// override rather than writing a derived value, or the two would drift apart
/// the next time the library moved.
@Riverpod(keepAlive: true)
class MyProjectsLibrary extends _$MyProjectsLibrary {
  @override
  String? build() {
    final String? stored = StorageUtil.getString(AppKeys.myProjectsLibrary);
    if (stored != null) return stored;
    final String? wallpaperPath = ref.watch(wallpaperPathProvider);
    return wallpaperPath == null ? null : projectDefaultPath(wallpaperPath);
  }

  void update(String value) async {
    state = value;
    await StorageUtil.setString(AppKeys.myProjectsLibrary, value);
  }

  Future<void> reset() async {
    await StorageUtil.remove(AppKeys.myProjectsLibrary);
    ref.invalidateSelf();
  }
}

/// Where the backup tab mirrors both libraries. Null until the user picks one,
/// which reads as nothing being backed up rather than as an error.
///
/// [update] takes a non-null path, unlike the other path notifiers: nothing
/// clears a backup root, and the nullable shape would let a cancelled picker
/// blank the setting on screen while storage kept the old value.
@Riverpod(keepAlive: true)
class BackupRoot extends _$BackupRoot {
  @override
  String? build() => StorageUtil.getString(AppKeys.backupRoot);
  void update(String value) async {
    state = value;
    await StorageUtil.setString(AppKeys.backupRoot, value);
  }
}

@Riverpod(keepAlive: true)
class ExportPath extends _$ExportPath {
  @override
  String? build() => StorageUtil.getString(AppKeys.exportPath);
  void update(String? value) async {
    state = value;
    if (state == null) return;
    await StorageUtil.setString(AppKeys.exportPath, value!);
  }

  /// Back to unset, hint and all. There is no folder to derive this one from,
  /// unlike the project path, so the reset button clears it and the app asks
  /// for a folder again. [update] cannot do this: it ignores null so that a
  /// cancelled picker leaves the setting alone.
  Future<void> clear() async {
    state = null;
    await StorageUtil.remove(AppKeys.exportPath);
  }
}

@Riverpod(keepAlive: true)
class ToolVersion extends _$ToolVersion {
  @override
  Future<String?> build() => readRepkgVersion(ref.watch(toolPathProvider));
}

@Riverpod(keepAlive: true)
class EarliestTime extends _$EarliestTime {
  @override
  String? build() => null;
  void update(String? value) => state = value;
}

@Riverpod(keepAlive: true)
class SearchContent extends _$SearchContent {
  @override
  String build() => '';
  void update(String value) => state = value;
}

@Riverpod(keepAlive: true)
class CurrentTheme extends _$CurrentTheme {
  @override
  ThemeType build() => ThemeType.values[StorageUtil.getInt(AppKeys.theme) ?? 0];
  void update(ThemeType value) async {
    state = value;
    await StorageUtil.setInt(AppKeys.theme, value.index);
  }
}

@Riverpod(keepAlive: true)
class LoadingText extends _$LoadingText {
  @override
  String build() => tr(AppI10n.dialogProcessingWallpaper);

  void update(String value) => state = value;
}

@Riverpod(keepAlive: true)
class CurrentExtractType extends _$CurrentExtractType {
  @override
  ExtractType build() =>
      ExtractType.values[StorageUtil.getInt(AppKeys.extractType) ?? 0];
  void update(ExtractType value) async {
    state = value;
    await StorageUtil.setInt(AppKeys.extractType, value.index);
  }
}

@Riverpod(keepAlive: true)
class AcfPath extends _$AcfPath {
  @override
  String? build() => StorageUtil.getString(AppKeys.acfPath);
  void update(String? value) async {
    state = value;
    if (value == null) return;
    await StorageUtil.setString(AppKeys.acfPath, value);
  }
}

/// The cancel token for the batch currently running, or null when idle. The
/// loading overlay's cancel button reaches the workers through this.
@Riverpod(keepAlive: true)
class ActiveCancelToken extends _$ActiveCancelToken {
  @override
  CancelToken? build() => null;
  void update(CancelToken? value) => state = value;
}
