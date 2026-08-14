/// Whether a wallpaper matches what was typed in a search box.
///
/// Title and folder name both: a Workshop link or a folder on disk gives you
/// the id and never the title, and a myprojects folder can be named something
/// its title no longer says. One rule, so the two grids cannot drift apart on
/// what a search means.
///
/// [needle] must already be lowercased, since a caller filtering a few thousand
/// wallpapers folds it once rather than per wallpaper.
bool matchesSearch({
  required String title,
  required String id,
  required String needle,
}) =>
    needle.isEmpty ||
    title.toLowerCase().contains(needle) ||
    id.toLowerCase().contains(needle);
