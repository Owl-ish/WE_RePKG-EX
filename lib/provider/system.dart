import 'package:easy_localization/easy_localization.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:we_repkg/constants/i10n.dart';
import 'package:we_repkg/constants/keys.dart';
import 'package:we_repkg/models/enums.dart';
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

@Riverpod(keepAlive: true)
class ExportPath extends _$ExportPath {
  @override
  String? build() => StorageUtil.getString(AppKeys.exportPath);
  void update(String? value) async {
    state = value;
    if (state == null) return;
    await StorageUtil.setString(AppKeys.exportPath, value!);
  }
}

@Riverpod(keepAlive: true)
class ToolVersion extends _$ToolVersion {
  @override
  String? build() => StorageUtil.getString(AppKeys.toolVersion);
  void update(String? value) async {
    state = value;
    await StorageUtil.setString(AppKeys.toolVersion, value!);
  }
}

@Riverpod(keepAlive: true)
class EarliestTime extends _$EarliestTime {
  @override
  String? build() => null;
  Future<void> update(String? value) async {
    state = value;
    if (state == null) {
      await StorageUtil.remove(AppKeys.earliestDate);
    } else {
      await StorageUtil.setString(AppKeys.earliestDate, state!);
    }
  }
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
class CurrentLanguage extends _$CurrentLanguage {
  @override
  LanguageType? build() => null;
  void update(LanguageType value) => state = value;
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
