import 'package:flutter_test/flutter_test.dart';
import 'package:we_repkg/utils/backup_diff.dart';

void main() {
  // Everything defaults to empty so each test names only the sets it cares
  // about. Ids are the folder names Steam and Wallpaper Engine actually use.
  Map<String, BackupState> states({
    Set<String> liveWorkshop = const <String>{},
    Set<String> liveMyProjects = const <String>{},
    Set<String> backupWorkshop = const <String>{},
    Set<String> backupMyProjects = const <String>{},
    Map<String, String> liveVersions = const <String, String>{},
    Map<String, BackupRecord> records = const <String, BackupRecord>{},
  }) => backupStates(
    liveWorkshop: liveWorkshop,
    liveMyProjects: liveMyProjects,
    backupWorkshop: backupWorkshop,
    backupMyProjects: backupMyProjects,
    liveVersions: liveVersions,
    records: records,
  );

  test('a live wallpaper in neither backup folder needs backing up', () {
    expect(
      states(liveWorkshop: const <String>{'793602574'}),
      <String, BackupState>{'793602574': BackupState.notBackedUp},
    );
  });

  test('a backed-up wallpaper in neither live library has vanished', () {
    expect(
      states(backupWorkshop: const <String>{'793602574'}),
      <String, BackupState>{'793602574': BackupState.vanished},
    );
  });

  // Extraction moves output into myprojects, so the copy that covers a Workshop
  // wallpaper often sits in the other library. Comparing each library only
  // against its counterpart called 223 of the author's wallpapers unbacked.
  test('a Workshop wallpaper backed up under myprojects is covered', () {
    expect(
      states(
        liveWorkshop: const <String>{'793602574'},
        backupMyProjects: const <String>{'793602574'},
      ),
      <String, BackupState>{'793602574': BackupState.synced},
    );
  });

  test('a live version differing from the backed-up one is an update', () {
    expect(
      states(
        liveWorkshop: const <String>{'793602574'},
        backupWorkshop: const <String>{'793602574'},
        liveVersions: const <String, String>{'793602574': 'manifest-2'},
        records: const <String, BackupRecord>{
          '793602574': BackupRecord(backedUpVersion: 'manifest-1'),
        },
      ),
      <String, BackupState>{'793602574': BackupState.updateAvailable},
    );
  });

  test('an update the user dismissed is not offered again', () {
    expect(
      states(
        liveWorkshop: const <String>{'793602574'},
        backupWorkshop: const <String>{'793602574'},
        liveVersions: const <String, String>{'793602574': 'manifest-2'},
        records: const <String, BackupRecord>{
          '793602574': BackupRecord(
            backedUpVersion: 'manifest-1',
            dismissedVersion: 'manifest-2',
          ),
        },
      ),
      <String, BackupState>{'793602574': BackupState.updateDismissed},
    );
  });

  // Dismissal is against a version, not against the wallpaper, so the next
  // republish surfaces it again with nothing to re-arm.
  test('a wallpaper republished after a dismissal comes back', () {
    expect(
      states(
        liveWorkshop: const <String>{'793602574'},
        backupWorkshop: const <String>{'793602574'},
        liveVersions: const <String, String>{'793602574': 'manifest-3'},
        records: const <String, BackupRecord>{
          '793602574': BackupRecord(
            backedUpVersion: 'manifest-1',
            dismissedVersion: 'manifest-2',
          ),
        },
      ),
      <String, BackupState>{'793602574': BackupState.updateAvailable},
    );
  });

  // A folder the user copied into the backup by hand has no recorded version.
  // Nothing can be compared, so it is left alone rather than called stale.
  test('a backup with no recorded version is left alone', () {
    expect(
      states(
        liveWorkshop: const <String>{'793602574'},
        backupWorkshop: const <String>{'793602574'},
        liveVersions: const <String, String>{'793602574': 'manifest-1'},
      ),
      <String, BackupState>{'793602574': BackupState.synced},
    );
  });

  // Windows treats the two spellings as one folder, and myprojects names come
  // from wallpaper titles, so they are not all safely numeric.
  test('a re-cased folder is one wallpaper, under the live spelling', () {
    expect(
      states(
        liveMyProjects: const <String>{'Cool Wallpaper'},
        backupMyProjects: const <String>{'cool wallpaper'},
      ),
      <String, BackupState>{'Cool Wallpaper': BackupState.synced},
    );
  });

  test('a re-cased backup-only folder keeps its own spelling', () {
    expect(
      states(backupMyProjects: const <String>{'Cool Wallpaper'}),
      <String, BackupState>{'Cool Wallpaper': BackupState.vanished},
    );
  });

  group('folderVersion', () {
    FileStamp stamp(String name, int size, int epoch) => FileStamp(
      name: name,
      size: size,
      modified: DateTime.fromMillisecondsSinceEpoch(epoch * 1000, isUtc: true),
    );

    test('a changed size changes the token', () {
      expect(
        folderVersion(<FileStamp>[stamp('project.json', 100, 1700000000)]),
        isNot(
          folderVersion(<FileStamp>[stamp('project.json', 101, 1700000000)]),
        ),
      );
    });

    // Packing and unpacking swaps scene.json for scene.pkg at the same size,
    // which is the change the token most needs to catch.
    test('a renamed file changes the token', () {
      expect(
        folderVersion(<FileStamp>[stamp('scene.json', 100, 1700000000)]),
        isNot(folderVersion(<FileStamp>[stamp('scene.pkg', 100, 1700000000)])),
      );
    });

    test('a changed mtime changes the token', () {
      expect(
        folderVersion(<FileStamp>[stamp('scene.json', 100, 1700000000)]),
        isNot(folderVersion(<FileStamp>[stamp('scene.json', 100, 1700000001)])),
      );
    });

    test('an added file changes the token', () {
      expect(
        folderVersion(<FileStamp>[stamp('project.json', 100, 1700000000)]),
        isNot(
          folderVersion(<FileStamp>[
            stamp('project.json', 100, 1700000000),
            stamp('preview.jpg', 50, 1700000000),
          ]),
        ),
      );
    });

    // Directory listings come back in whatever order the filesystem feels like,
    // and a reordering is not a change.
    test('listing order does not change the token', () {
      final List<FileStamp> files = <FileStamp>[
        stamp('project.json', 100, 1700000000),
        stamp('scene.json', 200, 1700000001),
        stamp('preview.jpg', 50, 1700000002),
      ];
      expect(folderVersion(files), folderVersion(files.reversed));
    });

    test('a folder with no top-level files has no token', () {
      expect(folderVersion(const <FileStamp>[]), isNull);
    });
  });
}
