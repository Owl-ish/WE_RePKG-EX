class WallpaperFilter {
  final bool hideScene;
  final bool hideVideo;
  final bool hideWeb;
  final bool hideApp;
  final bool hideUnknown;
  final bool hideEveryone;
  final bool hideQuestionable;
  final bool hideMature;

  WallpaperFilter({
    required this.hideScene,
    required this.hideVideo,
    required this.hideWeb,
    required this.hideApp,
    required this.hideUnknown,
    required this.hideEveryone,
    required this.hideQuestionable,
    required this.hideMature,
  });

  /// Nothing filtered out: every type and every age rating is showing. Drives
  /// whether the menu's reset action has anything left to do.
  bool get nothingHidden =>
      !hideScene &&
      !hideVideo &&
      !hideWeb &&
      !hideApp &&
      !hideUnknown &&
      !hideEveryone &&
      !hideQuestionable &&
      !hideMature;

  WallpaperFilter copyWith({
    bool? hideScene,
    bool? hideVideo,
    bool? hideWeb,
    bool? hideApp,
    bool? hideUnknown,
    bool? hideEveryone,
    bool? hideQuestionable,
    bool? hideMature,
  }) {
    return WallpaperFilter(
      hideScene: hideScene ?? this.hideScene,
      hideVideo: hideVideo ?? this.hideVideo,
      hideWeb: hideWeb ?? this.hideWeb,
      hideApp: hideApp ?? this.hideApp,
      hideUnknown: hideUnknown ?? this.hideUnknown,
      hideEveryone: hideEveryone ?? this.hideEveryone,
      hideQuestionable: hideQuestionable ?? this.hideQuestionable,
      hideMature: hideMature ?? this.hideMature,
    );
  }
}
