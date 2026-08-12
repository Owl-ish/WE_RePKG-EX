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
    if (_has(entries, 'scene.pkg')) {
      return IntegrityVerdict.packedSceneNoProject;
    }
    if (_has(entries, 'scene.json')) {
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
    return _has(entries, 'scene.pkg') || _has(entries, file);
  }
  if (_has(entries, file)) return true;
  // A hand-made wallpaper can name `clip.mp4` and keep the media in a `clip`
  // folder beside it. Two of the user's did, and counting them as broken was a
  // false alarm worth not repeating.
  final int dot = file.lastIndexOf('.');
  final String stem = dot <= 0 ? file : file.substring(0, dot);
  return entries.any((FolderEntry e) => e.isDirectory && _same(e.name, stem));
}

/// What Steam leaves when it removes an unsubscribed wallpaper: the folder
/// stands, because Wallpaper Engine wrote the cache in it rather than
/// downloading it. The backup tab drops these too, so the rule lives here once.
bool holdsOnlyRebuiltShaders(List<FolderEntry> entries) =>
    entries.isNotEmpty &&
    entries.every((FolderEntry e) => e.isDirectory && _same(e.name, 'shaders'));

bool _has(List<FolderEntry> entries, String name) =>
    entries.any((FolderEntry e) => _same(e.name, name));

// Windows sees one folder whatever the case, so the comparison has to too.
bool _same(String a, String b) => a.toLowerCase() == b.toLowerCase();
