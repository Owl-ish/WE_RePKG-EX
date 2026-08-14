import 'package:we_repkg/constants/content_rating.dart';
import 'package:we_repkg/constants/wallpaper_type.dart';
import 'package:we_repkg/models/filter.dart';

/// Whether a wallpaper survives the type and age-rating boxes. One menu serves
/// both grids, so one rule does too.
///
/// Both values are `project.json`'s own, lowercased. Empty strings are what a
/// folder with no readable file has, and put it where the extract grid puts the
/// same folder: unknown type, all ages.
bool passesWallpaperFilter({
  required String type,
  required String rating,
  required WallpaperFilter filter,
}) {
  // Anything not mature or questionable counts as all ages, so a wallpaper with
  // a missing or unknown rating cannot hide from all three checkboxes.
  if (rating == ContentRating.mature) {
    if (filter.hideMature) return false;
  } else if (rating == ContentRating.questionable) {
    if (filter.hideQuestionable) return false;
  } else if (filter.hideEveryone) {
    return false;
  }
  if (filter.hideScene && type == WallpaperType.scene) return false;
  if (filter.hideVideo && type == WallpaperType.video) return false;
  if (filter.hideWeb && type == WallpaperType.web) return false;
  if (filter.hideApp && type == WallpaperType.application) return false;
  if (filter.hideUnknown && type == WallpaperType.unknown) return false;
  return true;
}
