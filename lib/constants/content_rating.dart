/// Wallpaper Engine age ratings as they appear in a project.json `contentrating`
/// field, lowercased to match [WallpaperInfo.contentRating].
///
/// Not `ratingsex` / `ratingviolence`. Those are the finer-grained descriptors
/// (none / mild / full / adult) Wallpaper Engine combines to derive this value;
/// they are absent on roughly a fifth of workshop items and do not map onto the
/// three age levels.
class ContentRating {
  static const String everyone = 'everyone';
  static const String questionable = 'questionable';
  static const String mature = 'mature';
}
