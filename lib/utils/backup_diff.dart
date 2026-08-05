/// Where a wallpaper stands between the live libraries and the backup.
enum BackupState {
  /// Backed up and current, or backed up at a version nothing can compare.
  synced,
  notBackedUp,

  /// In the backup and in neither live library. Steam removes a delisted
  /// wallpaper without saying so, which is the case this whole tab exists for.
  vanished,
  updateAvailable,
  updateDismissed,
}

/// What the backup holds for one wallpaper, and which update was waved off.
///
/// Versions are opaque: Steam's manifest for a Workshop item, a size and mtime
/// digest for a myprojects one. Comparing them needs no idea which is which.
class BackupRecord {
  const BackupRecord({this.backedUpVersion, this.dismissedVersion});

  final String? backedUpVersion;
  final String? dismissedVersion;
}

/// A file sitting directly in a wallpaper folder.
class FileStamp {
  const FileStamp({
    required this.name,
    required this.size,
    required this.modified,
  });

  final String name;
  final int size;
  final DateTime modified;
}

/// Version token for a myprojects wallpaper, which has no ACF to ask.
///
/// Only the files directly in the folder count. `project.json` and the scene
/// definition live there, so an edit to the wallpaper shows up; swapping an
/// unpacked asset in a subfolder without touching the scene does not. Listing
/// order varies, so sort before joining. Windows forbids `|` in a filename,
/// which is what keeps the join unambiguous.
String? folderVersion(Iterable<FileStamp> topLevelFiles) {
  final List<FileStamp> files = topLevelFiles.toList()
    ..sort((FileStamp a, FileStamp b) => a.name.compareTo(b.name));
  if (files.isEmpty) return null;
  return files
      .map(
        (FileStamp f) =>
            '${f.name}|${f.size}|${f.modified.millisecondsSinceEpoch}',
      )
      .join(';');
}

/// Where every wallpaper stands, keyed by folder name.
///
/// Each side is the union of its two libraries, so a wallpaper counts as backed
/// up when either backup folder holds it. Extraction moves output into
/// myprojects, which puts many Workshop items there legitimately.
///
/// The keys span live and backup together, so the result names wallpapers the
/// live grid has never seen. Those are the vanished ones, and they are the
/// point of the tab.
Map<String, BackupState> backupStates({
  required Set<String> liveWorkshop,
  required Set<String> liveMyProjects,
  required Set<String> backupWorkshop,
  required Set<String> backupMyProjects,
  required Map<String, String> liveVersions,
  required Map<String, BackupRecord> records,
}) {
  final Map<String, String> live = _namesByKey(liveWorkshop, liveMyProjects);
  final Map<String, String> backup = _namesByKey(
    backupWorkshop,
    backupMyProjects,
  );
  final Map<String, String> versions = _keyed(liveVersions);
  final Map<String, BackupRecord> byKey = _keyed(records);

  final Map<String, BackupState> result = <String, BackupState>{};
  live.forEach((String key, String name) {
    result[name] = backup.containsKey(key)
        ? _coveredState(versions[key], byKey[key])
        : BackupState.notBackedUp;
  });
  backup.forEach((String key, String name) {
    if (!live.containsKey(key)) result[name] = BackupState.vanished;
  });
  return result;
}

/// Both libraries under one lowercased key, since Windows sees `A` and `a` as
/// one folder. Workshop wins the spelling when a name appears in both.
Map<String, String> _namesByKey(Set<String> workshop, Set<String> myProjects) {
  final Map<String, String> names = <String, String>{};
  for (final String name in workshop) {
    names[name.toLowerCase()] = name;
  }
  for (final String name in myProjects) {
    names.putIfAbsent(name.toLowerCase(), () => name);
  }
  return names;
}

Map<String, V> _keyed<V>(Map<String, V> byName) => <String, V>{
  for (final MapEntry<String, V> entry in byName.entries)
    entry.key.toLowerCase(): entry.value,
};

/// State of a wallpaper the backup already covers.
///
/// Either version missing means nothing can be compared, so the wallpaper is
/// left alone. The two cases are not the same, though: no recorded version is a
/// folder copied into the backup by hand, while no live version means the ACF
/// could not be read. The caller warns about that one rather than letting a
/// whole library quietly read as current.
BackupState _coveredState(String? liveVersion, BackupRecord? record) {
  final String? backedUp = record?.backedUpVersion;
  if (liveVersion == null || backedUp == null) return BackupState.synced;
  if (liveVersion == backedUp) return BackupState.synced;
  if (liveVersion == record?.dismissedVersion) {
    return BackupState.updateDismissed;
  }
  return BackupState.updateAvailable;
}
