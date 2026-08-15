import 'package:we_repkg/constants/wallpaper_files.dart';

/// One entry directly inside a wallpaper folder.
typedef FolderEntry = ({String name, bool isDirectory});

/// What the caller found when it went looking for `project.json`.
typedef ProjectRead = ({bool present, bool readable, String? file});

/// Whether Wallpaper Engine could load a folder, and if not, what it is
/// instead.
///
/// The project-less verdicts are kept apart on purpose. A packed scene only
/// wants its metadata back, an unpacked one is a project someone can finish, a
/// media-only folder probably cannot be salvaged at all, and a leftover cache
/// has nothing to salvage. One "invalid" label would hide which is which.
enum IntegrityVerdict {
  sound,
  packedSceneNoProject,
  unpackedSceneNoProject,
  mediaOnly,
  payloadMissing,
  projectUnreadable,
  empty,
  shaderCacheOnly,
}

/// The concerns the tab lists, worst first, which is the order the pills sit in
/// and which one the tab opens on.
///
/// [IntegrityVerdict.sound] is not here: the check reports only what it could
/// not load. Neither is [IntegrityVerdict.empty], left out on the user's
/// instruction because the backup tab has a pill for the empty folders that
/// matter, the ones standing in for a backup.
const List<IntegrityVerdict> integrityVerdictOrder = <IntegrityVerdict>[
  IntegrityVerdict.payloadMissing,
  IntegrityVerdict.projectUnreadable,
  IntegrityVerdict.packedSceneNoProject,
  IntegrityVerdict.unpackedSceneNoProject,
  IntegrityVerdict.mediaOnly,
  IntegrityVerdict.shaderCacheOnly,
];

/// How many folders sit under each concern, zero-filled so a caller can draw
/// every pill without checking for null.
Map<IntegrityVerdict, int> verdictCounts(Iterable<IntegrityVerdict> found) {
  final Map<IntegrityVerdict, int> counts = <IntegrityVerdict, int>{
    for (final IntegrityVerdict verdict in integrityVerdictOrder) verdict: 0,
  };
  for (final IntegrityVerdict verdict in found) {
    counts[verdict] = (counts[verdict] ?? 0) + 1;
  }
  return counts;
}

/// The concern the tab is showing: the one picked while it still holds
/// something, and the worst one found until then.
IntegrityVerdict shownVerdict(
  IntegrityVerdict? picked,
  Map<IntegrityVerdict, int> counts,
) => picked != null && (counts[picked] ?? 0) > 0 ? picked : worstFound(counts);

/// The worst concern with anything in it, which is where the tab opens and
/// where it falls back to when a recheck empties the one being shown.
IntegrityVerdict worstFound(Map<IntegrityVerdict, int> counts) =>
    integrityVerdictOrder.firstWhere(
      (IntegrityVerdict verdict) => (counts[verdict] ?? 0) > 0,
      orElse: () => integrityVerdictOrder.first,
    );

/// Sorts one folder by what is inside it.
///
/// Pure: the caller lists the folder and reads the JSON, so the rules can be
/// tested without a temp directory.
IntegrityVerdict classifyFolder({
  required List<FolderEntry> entries,
  required ProjectRead project,
  required bool hasCustomDirectory,
}) {
  if (entries.isEmpty) return IntegrityVerdict.empty;
  if (!project.present) {
    if (holdsOnlyRebuiltShaders(entries)) {
      return IntegrityVerdict.shaderCacheOnly;
    }
    if (holds(entries, WallpaperFiles.packedScene)) {
      return IntegrityVerdict.packedSceneNoProject;
    }
    if (holds(entries, WallpaperFiles.unpackedScene)) {
      return IntegrityVerdict.unpackedSceneNoProject;
    }
    return IntegrityVerdict.mediaOnly;
  }
  if (!project.readable) return IntegrityVerdict.projectUnreadable;
  return _payloadPresent(entries, project.file, hasCustomDirectory)
      ? IntegrityVerdict.sound
      : IntegrityVerdict.payloadMissing;
}

/// Mirrors how `_parseWallpaperFolder` resolves what to extract: the packed and
/// unpacked scene split, the custom directory a null `file` falls back to, and
/// an empty `file` naming nothing at all.
///
/// A name the top-level listing does not hold is not decided here. It can still
/// be a subpath, which the caller resolves against the disk.
bool _payloadPresent(
  List<FolderEntry> entries,
  String? file,
  bool hasCustomDirectory,
) {
  if (file == null) return hasCustomDirectory;
  // An empty `file` is not the null case: the app targets the empty string and
  // never looks for a custom directory, so there is nothing to extract.
  if (file.isEmpty) return false;
  // project.json names scene.json whether the scene is packed or not.
  if (file.toLowerCase().endsWith('json')) {
    return holds(entries, WallpaperFiles.packedScene) || holds(entries, file);
  }
  if (holds(entries, file)) return true;
  // A hand-made wallpaper can name `clip.mp4` and keep the media in a `clip`
  // folder beside it. Two of the user's did, and counting them as broken was a
  // false alarm worth not repeating.
  final int dot = file.lastIndexOf('.');
  final String stem = dot <= 0 ? file : file.substring(0, dot);
  return entries.any(
    (FolderEntry e) => e.isDirectory && sameName(e.name, stem),
  );
}

/// What Steam leaves when it removes an unsubscribed wallpaper: the folder
/// stands, because Wallpaper Engine wrote the cache in it rather than
/// downloading it. The backup tab drops these too, so the rule lives here once.
bool holdsOnlyRebuiltShaders(List<FolderEntry> entries) =>
    entries.isNotEmpty &&
    entries.every(
      (FolderEntry e) =>
          e.isDirectory && sameName(e.name, WallpaperDirectories.shaders),
    );

/// Whether a listing holds [name], whatever case it is written in.
bool holds(List<FolderEntry> entries, String name) =>
    entries.any((FolderEntry e) => sameName(e.name, name));

/// Windows sees one file whatever the case, so the comparison has to too.
bool sameName(String a, String b) => a.toLowerCase() == b.toLowerCase();

/// Whether the fields read by the wallpaper grid have their expected shapes.
bool projectFieldsUsable(Map<String, dynamic> project) {
  bool stringOrAbsent(String key) =>
      project[key] == null || project[key] is String;
  return stringOrAbsent(WallpaperProjectFields.title) &&
      stringOrAbsent(WallpaperProjectFields.contentRating) &&
      stringOrAbsent(WallpaperProjectFields.type) &&
      stringOrAbsent(WallpaperProjectFields.preview) &&
      stringOrAbsent(WallpaperProjectFields.file) &&
      (project[WallpaperProjectFields.tags] == null ||
          project[WallpaperProjectFields.tags] is List);
}
