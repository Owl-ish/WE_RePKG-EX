import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:we_repkg/constants/keys.dart';
import 'package:we_repkg/models/filter.dart';
import 'package:we_repkg/utils/storage.dart';

part 'filter.g.dart';

@riverpod
class FilterState extends _$FilterState {
  /// Every box the reset action clears, in menu order.
  static const List<String> _hideKeys = [
    AppKeys.hideScene,
    AppKeys.hideVideo,
    AppKeys.hideWeb,
    AppKeys.hideApp,
    AppKeys.hideUnknown,
    AppKeys.hideEveryone,
    AppKeys.hideQuestionable,
    AppKeys.hideMature,
  ];

  @override
  WallpaperFilter build() {
    final (bool everyone, bool questionable, bool mature) = _ratingFlags();
    return WallpaperFilter(
      hideScene: StorageUtil.getBool(AppKeys.hideScene),
      hideVideo: StorageUtil.getBool(AppKeys.hideVideo),
      // Every type shows by default. These two defaulted to hidden from the
      // original project, when web and application wallpapers could not be
      // extracted at all; v1.5 made them extract as a folder copy, so hiding
      // them now conceals types the app supports.
      hideWeb: StorageUtil.getBool(AppKeys.hideWeb),
      hideApp: StorageUtil.getBool(AppKeys.hideApp),
      hideUnknown: StorageUtil.getBool(AppKeys.hideUnknown),
      hideEveryone: everyone,
      hideQuestionable: questionable,
      hideMature: mature,
    );
  }

  /// Reads the three age-rating flags, seeding them from the pre-1.6 three-way
  /// [AppKeys.matureState] the first time so an upgrade keeps the user's choice.
  ///
  /// The seeded values are written back immediately. Deriving them on every load
  /// instead would break as soon as the user touched one box: writing a single
  /// key would make this look migrated while the other two silently reset.
  static (bool, bool, bool) _ratingFlags() {
    final bool migrated =
        StorageUtil.getNullBool(AppKeys.hideEveryone) != null ||
        StorageUtil.getNullBool(AppKeys.hideQuestionable) != null ||
        StorageUtil.getNullBool(AppKeys.hideMature) != null;
    if (migrated) {
      return (
        StorageUtil.getBool(AppKeys.hideEveryone),
        StorageUtil.getBool(AppKeys.hideQuestionable),
        StorageUtil.getBool(AppKeys.hideMature),
      );
    }
    final (bool, bool, bool) seed = switch (StorageUtil.getInt(
      AppKeys.matureState,
    )) {
      1 => (false, false, true), // hide mature
      2 => (true, true, false), // only mature
      _ => (false, false, false), // show everything
    };
    StorageUtil.setBool(AppKeys.hideEveryone, seed.$1);
    StorageUtil.setBool(AppKeys.hideQuestionable, seed.$2);
    StorageUtil.setBool(AppKeys.hideMature, seed.$3);
    return seed;
  }

  /// Shows every type and every age rating again.
  void reset() async {
    state = WallpaperFilter(
      hideScene: false,
      hideVideo: false,
      hideWeb: false,
      hideApp: false,
      hideUnknown: false,
      hideEveryone: false,
      hideQuestionable: false,
      hideMature: false,
    );
    for (final String key in _hideKeys) {
      await StorageUtil.setBool(key, false);
    }
  }

  void updateHideScene(bool hidden) async => await _setHidden(
    AppKeys.hideScene,
    hidden,
    state.copyWith(hideScene: hidden),
  );

  void updateHideVideo(bool hidden) async => await _setHidden(
    AppKeys.hideVideo,
    hidden,
    state.copyWith(hideVideo: hidden),
  );

  void updateHideWeb(bool hidden) async => await _setHidden(
    AppKeys.hideWeb,
    hidden,
    state.copyWith(hideWeb: hidden),
  );

  void updateHideApp(bool hidden) async => await _setHidden(
    AppKeys.hideApp,
    hidden,
    state.copyWith(hideApp: hidden),
  );

  void updateHideUnknown(bool hidden) async => await _setHidden(
    AppKeys.hideUnknown,
    hidden,
    state.copyWith(hideUnknown: hidden),
  );

  void updateHideEveryone(bool hidden) async => await _setHidden(
    AppKeys.hideEveryone,
    hidden,
    state.copyWith(hideEveryone: hidden),
  );

  void updateHideQuestionable(bool hidden) async => await _setHidden(
    AppKeys.hideQuestionable,
    hidden,
    state.copyWith(hideQuestionable: hidden),
  );

  void updateHideMature(bool hidden) async => await _setHidden(
    AppKeys.hideMature,
    hidden,
    state.copyWith(hideMature: hidden),
  );

  Future<void> _setHidden(String key, bool hidden, WallpaperFilter next) async {
    state = next;
    await StorageUtil.setBool(key, hidden);
  }
}
