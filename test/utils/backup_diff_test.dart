import 'package:flutter_test/flutter_test.dart';
import 'package:we_repkg/utils/backup_diff.dart';

void main() {
  // Everything defaults to empty so each test names only the sets it cares
  // about. Ids are the folder names Steam and Wallpaper Engine actually use.
  BackupDiffResult diff({
    Set<String> liveWorkshop = const <String>{},
    Set<String> liveMyProjects = const <String>{},
    Set<String> backupWorkshop = const <String>{},
    Set<String> backupMyProjects = const <String>{},
    Map<String, String> liveWorkshopVersions = const <String, String>{},
    Map<String, String> liveMyProjectsVersions = const <String, String>{},
    Map<String, BackupRecord> records = const <String, BackupRecord>{},
  }) => backupDiff(
    liveWorkshop: liveWorkshop,
    liveMyProjects: liveMyProjects,
    backupWorkshop: backupWorkshop,
    backupMyProjects: backupMyProjects,
    liveWorkshopVersions: liveWorkshopVersions,
    liveMyProjectsVersions: liveMyProjectsVersions,
    records: records,
  );

  Map<BackupCard, BackupState> cards({
    Set<String> liveWorkshop = const <String>{},
    Set<String> liveMyProjects = const <String>{},
    Set<String> backupWorkshop = const <String>{},
    Set<String> backupMyProjects = const <String>{},
    Map<String, String> liveWorkshopVersions = const <String, String>{},
    Map<String, String> liveMyProjectsVersions = const <String, String>{},
    Map<String, BackupRecord> records = const <String, BackupRecord>{},
  }) => diff(
    liveWorkshop: liveWorkshop,
    liveMyProjects: liveMyProjects,
    backupWorkshop: backupWorkshop,
    backupMyProjects: backupMyProjects,
    liveWorkshopVersions: liveWorkshopVersions,
    liveMyProjectsVersions: liveMyProjectsVersions,
    records: records,
  ).cards;

  BackupCard workshop(String name) =>
      BackupCard(WallpaperLibrary.workshop, name);
  BackupCard myProjects(String name) =>
      BackupCard(WallpaperLibrary.myProjects, name);

  // Exhaustive, because the interesting bugs live at the tier boundaries and
  // targeted tests kept covering the Workshop arm of a rule and not the
  // myprojects one. Names read live Workshop, live myprojects, backup Workshop,
  // backup myprojects.
  group('the sixteen presence states', () {
    const String n = '793602574';

    BackupDiffResult shape(bool lw, bool lm, bool bw, bool bm) => diff(
      liveWorkshop: lw ? const <String>{n} : const <String>{},
      liveMyProjects: lm ? const <String>{n} : const <String>{},
      backupWorkshop: bw ? const <String>{n} : const <String>{},
      backupMyProjects: bm ? const <String>{n} : const <String>{},
    );

    void expectCards(
      BackupDiffResult result,
      Map<BackupCard, BackupState> expected,
    ) {
      expect(result.cards, expected);
      expect(result.reconcile, isEmpty);
    }

    void expectReconcile(
      BackupDiffResult result,
      Set<WallpaperLibrary> orphans,
      Set<WallpaperLibrary> needsBackup,
    ) {
      expect(result.cards, isEmpty);
      expect(result.reconcile.single.orphans, orphans);
      expect(result.reconcile.single.needsBackup, needsBackup);
    }

    test('-- -- -- --', () {
      expectCards(
        shape(false, false, false, false),
        <BackupCard, BackupState>{},
      );
    });

    test('-- -- -- BM', () {
      expectCards(shape(false, false, false, true), <BackupCard, BackupState>{
        myProjects(n): BackupState.vanished,
      });
    });

    test('-- -- BW --', () {
      expectCards(shape(false, false, true, false), <BackupCard, BackupState>{
        workshop(n): BackupState.vanished,
      });
    });

    test('-- -- BW BM', () {
      expectCards(shape(false, false, true, true), <BackupCard, BackupState>{
        workshop(n): BackupState.vanished,
        myProjects(n): BackupState.vanished,
      });
    });

    test('-- LM -- --', () {
      expectCards(shape(false, true, false, false), <BackupCard, BackupState>{
        myProjects(n): BackupState.notBackedUp,
      });
    });

    test('-- LM -- BM', () {
      expectCards(shape(false, true, false, true), <BackupCard, BackupState>{
        myProjects(n): BackupState.synced,
      });
    });

    test('-- LM BW --', () {
      expectReconcile(
        shape(false, true, true, false),
        <WallpaperLibrary>{WallpaperLibrary.workshop},
        <WallpaperLibrary>{WallpaperLibrary.myProjects},
      );
    });

    test('-- LM BW BM', () {
      expectReconcile(shape(false, true, true, true), <WallpaperLibrary>{
        WallpaperLibrary.workshop,
      }, <WallpaperLibrary>{});
    });

    test('LW -- -- --', () {
      expectCards(shape(true, false, false, false), <BackupCard, BackupState>{
        workshop(n): BackupState.notBackedUp,
      });
    });

    test('LW -- -- BM', () {
      expectReconcile(
        shape(true, false, false, true),
        <WallpaperLibrary>{WallpaperLibrary.myProjects},
        <WallpaperLibrary>{WallpaperLibrary.workshop},
      );
    });

    test('LW -- BW --', () {
      expectCards(shape(true, false, true, false), <BackupCard, BackupState>{
        workshop(n): BackupState.synced,
      });
    });

    test('LW -- BW BM', () {
      expectReconcile(shape(true, false, true, true), <WallpaperLibrary>{
        WallpaperLibrary.myProjects,
      }, <WallpaperLibrary>{});
    });

    test('LW LM -- --', () {
      expectCards(shape(true, true, false, false), <BackupCard, BackupState>{
        workshop(n): BackupState.notBackedUp,
        myProjects(n): BackupState.notBackedUp,
      });
    });

    test('LW LM -- BM', () {
      expectCards(shape(true, true, false, true), <BackupCard, BackupState>{
        workshop(n): BackupState.notBackedUp,
        myProjects(n): BackupState.synced,
      });
    });

    test('LW LM BW --', () {
      expectCards(shape(true, true, true, false), <BackupCard, BackupState>{
        workshop(n): BackupState.synced,
        myProjects(n): BackupState.notBackedUp,
      });
    });

    test('LW LM BW BM', () {
      expectCards(shape(true, true, true, true), <BackupCard, BackupState>{
        workshop(n): BackupState.synced,
        myProjects(n): BackupState.synced,
      });
    });
  });

  group('tier 1, vanished', () {
    test('a backed-up wallpaper in neither live library has vanished', () {
      final BackupDiffResult result = diff(
        backupWorkshop: const <String>{'793602574'},
      );

      expect(result.cards, <BackupCard, BackupState>{
        workshop('793602574'): BackupState.vanished,
      });
      expect(result.reconcile, isEmpty);
    });

    // Both folders survive in the backup and both can be restored, so neither
    // is folded into the other.
    test('a name backed up under both libraries vanishes as two cards', () {
      expect(
        cards(
          backupWorkshop: const <String>{'793602574'},
          backupMyProjects: const <String>{'793602574'},
        ),
        <BackupCard, BackupState>{
          workshop('793602574'): BackupState.vanished,
          myProjects('793602574'): BackupState.vanished,
        },
      );
    });

    // The tier the whole tab exists for. A record left behind by a since-deleted
    // backup, a stale version, nothing may pull a name out of vanished.
    test('vanished wins over everything else about the name', () {
      final BackupDiffResult result = diff(
        backupWorkshop: const <String>{'793602574'},
        backupMyProjects: const <String>{'793602574'},
        liveWorkshopVersions: const <String, String>{'793602574': 'manifest-9'},
        records: const <String, BackupRecord>{
          'workshop/793602574': BackupRecord(
            backedUpVersion: 'manifest-1',
            dismissedVersion: 'manifest-9',
          ),
        },
      );

      expect(result.cards, <BackupCard, BackupState>{
        workshop('793602574'): BackupState.vanished,
        myProjects('793602574'): BackupState.vanished,
      });
      expect(result.reconcile, isEmpty);
    });

    test('a re-cased backup-only folder keeps its own spelling', () {
      expect(
        cards(backupMyProjects: const <String>{'Cool Wallpaper'}),
        <BackupCard, BackupState>{
          myProjects('Cool Wallpaper'): BackupState.vanished,
        },
      );
    });
  });

  group('tier 2, reconcile', () {
    // The packed original left behind by an unsubscribe. Pooled coverage used
    // to call this synced and hide the leftover from every card.
    test('a backup Workshop copy with the name live only in myprojects', () {
      final BackupDiffResult result = diff(
        liveMyProjects: const <String>{'793602574'},
        backupWorkshop: const <String>{'793602574'},
      );

      expect(result.cards, isEmpty);
      expect(result.reconcile, <ReconcileEntry>[
        const ReconcileEntry(
          name: '793602574',
          states: <WallpaperLibrary, BackupState>{
            WallpaperLibrary.myProjects: BackupState.notBackedUp,
          },
          backupWorkshop: true,
          backupMyProjects: false,
        ),
      ]);
    });

    // The unpacked extraction whose live copy was deleted.
    test('a backup myprojects copy with the name live only in Workshop', () {
      expect(
        diff(
          liveWorkshop: const <String>{'793602574'},
          backupWorkshop: const <String>{'793602574'},
          backupMyProjects: const <String>{'793602574'},
        ).reconcile,
        <ReconcileEntry>[
          const ReconcileEntry(
            name: '793602574',
            states: <WallpaperLibrary, BackupState>{
              WallpaperLibrary.workshop: BackupState.synced,
            },
            backupWorkshop: true,
            backupMyProjects: true,
          ),
        ],
      );
    });

    // The live copy here is backed up in its own library, so without a carried
    // state a republish would go unseen until the user got round to this card.
    test('an entry carries the state of its live copy', () {
      expect(
        diff(
          liveWorkshop: const <String>{'793602574'},
          backupWorkshop: const <String>{'793602574'},
          backupMyProjects: const <String>{'793602574'},
          liveWorkshopVersions: const <String, String>{
            '793602574': 'manifest-2',
          },
          records: const <String, BackupRecord>{
            'workshop/793602574': BackupRecord(backedUpVersion: 'manifest-1'),
          },
        ).reconcile.single.states,
        <WallpaperLibrary, BackupState>{
          WallpaperLibrary.workshop: BackupState.updateAvailable,
        },
      );
    });

    // Two mismatches, one wallpaper, one decision.
    test('a name with two mismatches is one entry', () {
      final List<ReconcileEntry> entries = diff(
        liveMyProjects: const <String>{'793602574'},
        backupWorkshop: const <String>{'793602574'},
      ).reconcile;

      expect(entries, hasLength(1));
      expect(entries.single.orphans, <WallpaperLibrary>{
        WallpaperLibrary.workshop,
      });
      expect(entries.single.needsBackup, <WallpaperLibrary>{
        WallpaperLibrary.myProjects,
      });
    });

    // AC 18: a reconcile name is out of the grid entirely, so it cannot show up
    // twice offering unrelated actions.
    test('a reconciling name produces no card', () {
      expect(
        cards(
          liveWorkshop: const <String>{'793602574'},
          backupWorkshop: const <String>{'793602574'},
          backupMyProjects: const <String>{'793602574'},
        ),
        isEmpty,
      );
    });

    // Only the orphan sends a name here. A live wallpaper nobody has backed up
    // yet is ordinary business.
    test('a live wallpaper with no backup at all is not a reconcile', () {
      expect(
        diff(
          liveWorkshop: const <String>{'793602574'},
          liveMyProjects: const <String>{'793602574'},
        ).reconcile,
        isEmpty,
      );
    });

    test('a name matched in both libraries is not a reconcile', () {
      expect(
        diff(
          liveWorkshop: const <String>{'793602574'},
          liveMyProjects: const <String>{'793602574'},
          backupWorkshop: const <String>{'793602574'},
          backupMyProjects: const <String>{'793602574'},
        ).reconcile,
        isEmpty,
      );
    });

    test('an entry takes the live spelling', () {
      expect(
        diff(
          liveMyProjects: const <String>{'Cool Wallpaper'},
          backupWorkshop: const <String>{'cool wallpaper'},
        ).reconcile.single.name,
        'Cool Wallpaper',
      );
    });
  });

  group('tier 3, ordinary cards', () {
    test('a live wallpaper in neither backup folder needs backing up', () {
      expect(
        cards(liveWorkshop: const <String>{'793602574'}),
        <BackupCard, BackupState>{
          workshop('793602574'): BackupState.notBackedUp,
        },
      );
    });

    test('a live wallpaper its own backup library holds is synced', () {
      expect(
        cards(
          liveWorkshop: const <String>{'793602574'},
          backupWorkshop: const <String>{'793602574'},
        ),
        <BackupCard, BackupState>{workshop('793602574'): BackupState.synced},
      );
    });

    // Coverage is never pooled. The other library's backup holds a different
    // wallpaper under the same name, so it vouches for nothing.
    test('the other backup library never covers a card', () {
      expect(
        cards(
          liveWorkshop: const <String>{'793602574'},
          liveMyProjects: const <String>{'793602574'},
          backupWorkshop: const <String>{'793602574'},
        ),
        <BackupCard, BackupState>{
          workshop('793602574'): BackupState.synced,
          myProjects('793602574'): BackupState.notBackedUp,
        },
      );
    });

    test('a live version differing from the backed-up one is an update', () {
      expect(
        cards(
          liveWorkshop: const <String>{'793602574'},
          backupWorkshop: const <String>{'793602574'},
          liveWorkshopVersions: const <String, String>{
            '793602574': 'manifest-2',
          },
          records: const <String, BackupRecord>{
            'workshop/793602574': BackupRecord(backedUpVersion: 'manifest-1'),
          },
        ),
        <BackupCard, BackupState>{
          workshop('793602574'): BackupState.updateAvailable,
        },
      );
    });

    test('an update the user dismissed is not offered again', () {
      expect(
        cards(
          liveWorkshop: const <String>{'793602574'},
          backupWorkshop: const <String>{'793602574'},
          liveWorkshopVersions: const <String, String>{
            '793602574': 'manifest-2',
          },
          records: const <String, BackupRecord>{
            'workshop/793602574': BackupRecord(
              backedUpVersion: 'manifest-1',
              dismissedVersion: 'manifest-2',
            ),
          },
        ),
        <BackupCard, BackupState>{
          workshop('793602574'): BackupState.updateDismissed,
        },
      );
    });

    // Dismissal is against a version, not against the wallpaper, so the next
    // republish surfaces it again with nothing to re-arm.
    test('a wallpaper republished after a dismissal comes back', () {
      expect(
        cards(
          liveWorkshop: const <String>{'793602574'},
          backupWorkshop: const <String>{'793602574'},
          liveWorkshopVersions: const <String, String>{
            '793602574': 'manifest-3',
          },
          records: const <String, BackupRecord>{
            'workshop/793602574': BackupRecord(
              backedUpVersion: 'manifest-1',
              dismissedVersion: 'manifest-2',
            ),
          },
        ),
        <BackupCard, BackupState>{
          workshop('793602574'): BackupState.updateAvailable,
        },
      );
    });

    // A folder the user copied into the backup by hand has no recorded version.
    // Nothing can be compared, so it is left alone rather than called stale.
    test('a backup with no recorded version is left alone', () {
      expect(
        cards(
          liveWorkshop: const <String>{'793602574'},
          backupWorkshop: const <String>{'793602574'},
          liveWorkshopVersions: const <String, String>{
            '793602574': 'manifest-1',
          },
        ),
        <BackupCard, BackupState>{workshop('793602574'): BackupState.synced},
      );
    });

    // An unreadable ACF leaves every Workshop item with no live version. The
    // guard has to catch that before the dismissed comparison, or `null ==
    // null` would file the whole library under dismissed.
    test('a wallpaper with no live version is left alone', () {
      expect(
        cards(
          liveWorkshop: const <String>{'793602574'},
          backupWorkshop: const <String>{'793602574'},
          records: const <String, BackupRecord>{
            'workshop/793602574': BackupRecord(
              backedUpVersion: 'manifest-1',
              dismissedVersion: 'manifest-2',
            ),
          },
        ),
        <BackupCard, BackupState>{workshop('793602574'): BackupState.synced},
      );
    });

    // The record travels with the backup drive and the copy it describes can be
    // deleted from under it. Coverage is the folder listing, never the record,
    // or a wallpaper deleted in Explorer would read as backed up forever.
    test('a record with no backup copy behind it is not coverage', () {
      expect(
        cards(
          liveWorkshop: const <String>{'793602574'},
          liveWorkshopVersions: const <String, String>{
            '793602574': 'manifest-1',
          },
          records: const <String, BackupRecord>{
            'workshop/793602574': BackupRecord(backedUpVersion: 'manifest-1'),
          },
        ),
        <BackupCard, BackupState>{
          workshop('793602574'): BackupState.notBackedUp,
        },
      );
    });

    // Windows treats the two spellings as one folder, and myprojects names come
    // from wallpaper titles, so they are not all safely numeric.
    test('a re-cased folder is one wallpaper, under the live spelling', () {
      expect(
        cards(
          liveMyProjects: const <String>{'Cool Wallpaper'},
          backupMyProjects: const <String>{'cool wallpaper'},
        ),
        <BackupCard, BackupState>{
          myProjects('Cool Wallpaper'): BackupState.synced,
        },
      );
    });

    // `id` lowercases what it writes, so an odd-cased key comes from a
    // hand-edited file or an older one. It still has to match.
    test('a re-cased record still finds its wallpaper', () {
      expect(
        cards(
          liveMyProjects: const <String>{'Cool Wallpaper'},
          backupMyProjects: const <String>{'Cool Wallpaper'},
          liveMyProjectsVersions: const <String, String>{
            'Cool Wallpaper': 'digest-2',
          },
          records: const <String, BackupRecord>{
            'myprojects/Cool Wallpaper': BackupRecord(
              backedUpVersion: 'digest-1',
            ),
          },
        ),
        <BackupCard, BackupState>{
          myProjects('Cool Wallpaper'): BackupState.updateAvailable,
        },
      );
    });
  });

  group('a name live in both libraries', () {
    // The author unpacks a Workshop wallpaper into myprojects and edits it, so
    // the two folders hold different content under one name.
    test('is two cards', () {
      expect(
        cards(
          liveWorkshop: const <String>{'793602574'},
          liveMyProjects: const <String>{'793602574'},
        ),
        <BackupCard, BackupState>{
          workshop('793602574'): BackupState.notBackedUp,
          myProjects('793602574'): BackupState.notBackedUp,
        },
      );
    });

    test('tracks a version per card', () {
      expect(
        cards(
          liveWorkshop: const <String>{'793602574'},
          liveMyProjects: const <String>{'793602574'},
          backupWorkshop: const <String>{'793602574'},
          backupMyProjects: const <String>{'793602574'},
          liveWorkshopVersions: const <String, String>{
            '793602574': 'manifest-1',
          },
          liveMyProjectsVersions: const <String, String>{
            '793602574': 'digest-2',
          },
          records: const <String, BackupRecord>{
            'workshop/793602574': BackupRecord(backedUpVersion: 'manifest-1'),
            'myprojects/793602574': BackupRecord(backedUpVersion: 'digest-1'),
          },
        ),
        <BackupCard, BackupState>{
          workshop('793602574'): BackupState.synced,
          myProjects('793602574'): BackupState.updateAvailable,
        },
      );
    });

    // Dismissing on one card must not quiet the other. Dismissed on the
    // myprojects side, so a card reading the wrong record cannot land on the
    // expected answer by accident.
    test('dismisses per card', () {
      expect(
        cards(
          liveWorkshop: const <String>{'793602574'},
          liveMyProjects: const <String>{'793602574'},
          backupWorkshop: const <String>{'793602574'},
          backupMyProjects: const <String>{'793602574'},
          liveWorkshopVersions: const <String, String>{
            '793602574': 'manifest-2',
          },
          liveMyProjectsVersions: const <String, String>{
            '793602574': 'digest-2',
          },
          records: const <String, BackupRecord>{
            'workshop/793602574': BackupRecord(backedUpVersion: 'manifest-1'),
            'myprojects/793602574': BackupRecord(
              backedUpVersion: 'digest-1',
              dismissedVersion: 'digest-2',
            ),
          },
        ),
        <BackupCard, BackupState>{
          workshop('793602574'): BackupState.updateAvailable,
          myProjects('793602574'): BackupState.updateDismissed,
        },
      );
    });
  });

  test('a card ids itself by library and name', () {
    expect(myProjects('793602574').id, 'myprojects/793602574');
    expect(workshop('793602574').id, 'workshop/793602574');
    expect(workshop('793602574'), isNot(myProjects('793602574')));
  });

  // Re-casing a folder has to update its record, not write a second one beside
  // it, or which of the two the differ compares against comes down to the order
  // the JSON happened to encode.
  test('a re-cased card ids the same', () {
    expect(myProjects('Cool Wallpaper').id, myProjects('cool wallpaper').id);
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

  group('countByState', () {
    test('counts each state', () {
      expect(
        countByState(const <BackupState>[
          BackupState.synced,
          BackupState.vanished,
          BackupState.synced,
        ]),
        <BackupState, int>{
          BackupState.synced: 2,
          BackupState.notBackedUp: 0,
          BackupState.vanished: 1,
          BackupState.updateAvailable: 0,
          BackupState.updateDismissed: 0,
        },
      );
    });

    // Zero-filled, so a caller can list every state without a null check and a
    // state nobody has hits still shows its own row.
    test('gives an empty library a zero for every state', () {
      expect(countByState(const <BackupState>[]).values, everyElement(0));
      expect(countByState(const <BackupState>[]), hasLength(5));
    });
  });
}
