import 'package:flutter_test/flutter_test.dart';
import 'package:we_repkg/utils/backup_diff.dart';

void main() {
  // Everything defaults to empty so each test names only the sets it cares
  // about. Ids are the folder names Steam and Wallpaper Engine actually use.
  const Map<String, CopyStanding> nothingCompared = <String, CopyStanding>{};

  BackupDiffResult diff({
    Set<String> liveWorkshop = const <String>{},
    Set<String> liveMyProjects = const <String>{},
    Set<String> backupWorkshop = const <String>{},
    Set<String> backupMyProjects = const <String>{},
    Map<String, String> liveWorkshopVersions = const <String, String>{},
    Map<String, String> liveMyProjectsVersions = const <String, String>{},
    Map<String, CopyStanding> workshopStanding = nothingCompared,
    Map<String, CopyStanding> myProjectsStanding = nothingCompared,
    Map<String, BackupRecord> records = const <String, BackupRecord>{},
  }) => backupDiff(
    liveWorkshop: liveWorkshop,
    liveMyProjects: liveMyProjects,
    backupWorkshop: backupWorkshop,
    backupMyProjects: backupMyProjects,
    liveWorkshopVersions: liveWorkshopVersions,
    liveMyProjectsVersions: liveMyProjectsVersions,
    workshopStanding: workshopStanding,
    myProjectsStanding: myProjectsStanding,
    records: records,
  );

  Map<BackupCard, BackupState> cards({
    Set<String> liveWorkshop = const <String>{},
    Set<String> liveMyProjects = const <String>{},
    Set<String> backupWorkshop = const <String>{},
    Set<String> backupMyProjects = const <String>{},
    Map<String, String> liveWorkshopVersions = const <String, String>{},
    Map<String, String> liveMyProjectsVersions = const <String, String>{},
    Map<String, CopyStanding> workshopStanding = nothingCompared,
    Map<String, CopyStanding> myProjectsStanding = nothingCompared,
    Map<String, BackupRecord> records = const <String, BackupRecord>{},
  }) => diff(
    liveWorkshop: liveWorkshop,
    liveMyProjects: liveMyProjects,
    backupWorkshop: backupWorkshop,
    backupMyProjects: backupMyProjects,
    liveWorkshopVersions: liveWorkshopVersions,
    liveMyProjectsVersions: liveMyProjectsVersions,
    workshopStanding: workshopStanding,
    myProjectsStanding: myProjectsStanding,
    records: records,
  ).cards;

  /// Named per test, so a card that must not be compared cannot pick one up by
  /// accident.
  Map<String, CopyStanding> standing(String name, CopyStanding value) =>
      <String, CopyStanding>{name: value};

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
    // hand-edited file or an older one. It still has to match. Workshop,
    // because that is the only library holding a baseline.
    test('a re-cased record still finds its wallpaper', () {
      expect(
        cards(
          liveWorkshop: const <String>{'Cool Wallpaper'},
          backupWorkshop: const <String>{'Cool Wallpaper'},
          liveWorkshopVersions: const <String, String>{
            'Cool Wallpaper': 'manifest-2',
          },
          records: const <String, BackupRecord>{
            'workshop/Cool Wallpaper': BackupRecord(
              backedUpVersion: 'manifest-1',
            ),
          },
        ),
        <BackupCard, BackupState>{
          workshop('Cool Wallpaper'): BackupState.updateAvailable,
        },
      );
    });

    // The other half of the same rule: myprojects keeps no baseline, so an
    // odd-cased key there has only the dismissal to find.
    test('a re-cased record still finds a myprojects dismissal', () {
      expect(
        cards(
          liveMyProjects: const <String>{'Cool Wallpaper'},
          backupMyProjects: const <String>{'Cool Wallpaper'},
          myProjectsStanding: standing('Cool Wallpaper', CopyStanding.behind),
          liveMyProjectsVersions: const <String, String>{
            'Cool Wallpaper': 'digest-2',
          },
          records: const <String, BackupRecord>{
            'myprojects/Cool Wallpaper': BackupRecord(
              dismissedVersion: 'digest-2',
            ),
          },
        ),
        <BackupCard, BackupState>{
          myProjects('Cool Wallpaper'): BackupState.updateDismissed,
        },
      );
    });
  });

  // Steam's manifest names the live version only, so a hand-made backup has no
  // baseline until one comparison earns it.
  group('seeding a workshop baseline', () {
    const String n = '793602574';

    BackupDiffResult seeded({
      Map<String, CopyStanding> standings = nothingCompared,
      Map<String, String> versions = const <String, String>{n: 'manifest-1'},
      Map<String, BackupRecord> records = const <String, BackupRecord>{},
    }) => diff(
      liveWorkshop: const <String>{n},
      backupWorkshop: const <String>{n},
      liveWorkshopVersions: versions,
      workshopStanding: standings,
      records: records,
    );

    // The manifest, never a digest of the folder: recording one would leave
    // every later scan comparing a digest against a manifest, so no card would
    // ever match again.
    test('a covering backup records the live manifest', () {
      final BackupDiffResult result = seeded(
        standings: standing(n, CopyStanding.covers),
      );

      expect(result.cards[workshop(n)], BackupState.synced);
      expect(result.seeds, <String, String>{'workshop/$n': 'manifest-1'});
    });

    test('a backup behind live reports it and records nothing', () {
      final BackupDiffResult result = seeded(
        standings: standing(n, CopyStanding.behind),
      );

      expect(result.cards[workshop(n)], BackupState.updateAvailable);
      expect(result.seeds, isEmpty);
    });

    // A folder dropped in by hand has no ACF entry and never will, so flagging
    // it leaves a card nagging forever with no version to dismiss.
    test('a wallpaper with no manifest is left alone and not seeded', () {
      final BackupDiffResult result = seeded(
        standings: standing(n, CopyStanding.behind),
        versions: const <String, String>{},
      );

      expect(result.cards[workshop(n)], BackupState.synced);
      expect(result.seeds, isEmpty);
    });

    // Once the baseline is there the manifests answer the question, which is
    // what lets the scan skip comparing the folders at all.
    test('a recorded baseline wins over the comparison', () {
      final BackupDiffResult result = seeded(
        standings: standing(n, CopyStanding.behind),
        records: const <String, BackupRecord>{
          'workshop/$n': BackupRecord(backedUpVersion: 'manifest-1'),
        },
      );

      expect(result.cards[workshop(n)], BackupState.synced);
      expect(result.seeds, isEmpty);
    });

    // Nothing compared is not the same as compared and matched.
    test('an uncompared card is left alone and not seeded', () {
      final BackupDiffResult result = seeded();

      expect(result.cards[workshop(n)], BackupState.synced);
      expect(result.seeds, isEmpty);
    });

    // A cancelled copy leaves the folder there and nothing in it. The record
    // must not answer for it either, or a seeded card could be emptied and go
    // on reading as backed up.
    test('an empty backup folder beats even a recorded baseline', () {
      final BackupDiffResult result = seeded(
        standings: standing(n, CopyStanding.empty),
        records: const <String, BackupRecord>{
          'workshop/$n': BackupRecord(backedUpVersion: 'manifest-1'),
        },
      );

      expect(result.cards[workshop(n)], BackupState.emptyBackup);
      expect(result.seeds, isEmpty);
    });
  });

  // myprojects has no ACF to ask, so its version is already a fingerprint and
  // the two folders are compared against each other on every scan. A recorded
  // baseline would go stale the moment anything touched the backup outside this
  // app.
  group('myprojects compares the folders directly', () {
    const String n = 'alpha';

    BackupDiffResult compared({
      Map<String, CopyStanding> standings = nothingCompared,
      Map<String, String> versions = const <String, String>{},
      Map<String, BackupRecord> records = const <String, BackupRecord>{},
    }) => diff(
      liveMyProjects: const <String>{n},
      backupMyProjects: const <String>{n},
      liveMyProjectsVersions: versions,
      myProjectsStanding: standings,
      records: records,
    );

    test('a covering backup is synced and earns no baseline', () {
      final BackupDiffResult result = compared(
        standings: standing(n, CopyStanding.covers),
      );

      expect(result.cards[myProjects(n)], BackupState.synced);
      expect(result.seeds, isEmpty);
    });

    test('a backup behind live is an update, with no record needed', () {
      final BackupDiffResult result = compared(
        standings: standing(n, CopyStanding.behind),
      );

      expect(result.cards[myProjects(n)], BackupState.updateAvailable);
      expect(result.seeds, isEmpty);
    });

    test('an empty backup folder is not synced', () {
      final BackupDiffResult result = compared(
        standings: standing(n, CopyStanding.empty),
      );

      expect(result.cards[myProjects(n)], BackupState.emptyBackup);
    });

    // The folders are what decide it, so a leftover baseline from an older
    // records file cannot quiet a wallpaper that really has moved on.
    test('a recorded baseline does not silence a real difference', () {
      final BackupDiffResult result = compared(
        standings: standing(n, CopyStanding.behind),
        versions: const <String, String>{n: 'digest-2'},
        records: const <String, BackupRecord>{
          'myprojects/$n': BackupRecord(backedUpVersion: 'digest-2'),
        },
      );

      expect(result.cards[myProjects(n)], BackupState.updateAvailable);
    });

    test('a dismissal still applies once the folders differ', () {
      final BackupDiffResult result = compared(
        standings: standing(n, CopyStanding.behind),
        versions: const <String, String>{n: 'digest-2'},
        records: const <String, BackupRecord>{
          'myprojects/$n': BackupRecord(dismissedVersion: 'digest-2'),
        },
      );

      expect(result.cards[myProjects(n)], BackupState.updateDismissed);
    });

    // Editing the wallpaper moves its token, so the dismissal stops matching
    // and the card comes back on its own.
    test('an edit after a dismissal brings the card back', () {
      final BackupDiffResult result = compared(
        standings: standing(n, CopyStanding.behind),
        versions: const <String, String>{n: 'digest-3'},
        records: const <String, BackupRecord>{
          'myprojects/$n': BackupRecord(dismissedVersion: 'digest-2'),
        },
      );

      expect(result.cards[myProjects(n)], BackupState.updateAvailable);
    });
  });

  // A wallpaper waiting in reconcile must not go quiet: its live copy still has
  // a state, and that state can still earn a baseline.
  test('a reconcile entry seeds its live copy too', () {
    const String n = '793602574';
    final BackupDiffResult result = diff(
      liveWorkshop: const <String>{n},
      backupWorkshop: const <String>{n},
      backupMyProjects: const <String>{n},
      liveWorkshopVersions: const <String, String>{n: 'manifest-1'},
      workshopStanding: standing(n, CopyStanding.covers),
    );

    expect(result.cards, isEmpty);
    expect(
      result.reconcile.single.states[WallpaperLibrary.workshop],
      BackupState.synced,
    );
    expect(result.seeds, <String, String>{'workshop/$n': 'manifest-1'});
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

    // Each library asks its own question: Workshop compares manifests against
    // its record, myprojects compares the two folders. Both arms are exercised
    // here, so a card reading the other library's answer shows up.
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
          myProjectsStanding: standing('793602574', CopyStanding.behind),
          records: const <String, BackupRecord>{
            'workshop/793602574': BackupRecord(backedUpVersion: 'manifest-1'),
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
          myProjectsStanding: standing('793602574', CopyStanding.behind),
          records: const <String, BackupRecord>{
            'workshop/793602574': BackupRecord(backedUpVersion: 'manifest-1'),
            'myprojects/793602574': BackupRecord(dismissedVersion: 'digest-2'),
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

  group('compareCopy', () {
    FileEntry file(String path, int size) => (path: path, size: size);
    const List<FileEntry> project = <FileEntry>[
      (path: 'project.json', size: 100),
    ];

    test('the same files at the same sizes covers', () {
      expect(compareCopy(live: project, backup: project), CopyStanding.covers);
    });

    test('a live file at a different size is behind', () {
      expect(
        compareCopy(
          live: project,
          backup: <FileEntry>[file('project.json', 101)],
        ),
        CopyStanding.behind,
      );
    });

    test('a live file the backup does not hold is behind', () {
      expect(
        compareCopy(
          live: <FileEntry>[...project, file('scene.pkg', 5)],
          backup: project,
        ),
        CopyStanding.behind,
      );
    });

    // The whole point of the subset rule. Nothing ever deletes from a backup,
    // so a wallpaper edited to drop a file leaves that file there for good;
    // counting it would report an update Back up can never clear, because
    // backing up copies and never removes.
    test('files the backup holds beyond live do not count against it', () {
      expect(
        compareCopy(
          live: project,
          backup: <FileEntry>[...project, file('dropped-last-year.tex', 900)],
        ),
        CopyStanding.covers,
      );
    });

    // Windows sees one path whatever the case, and a backup made by another
    // tool need not have preserved it.
    test('case does not decide it', () {
      expect(
        compareCopy(
          live: <FileEntry>[file(r'Materials\Sky.TEX', 100)],
          backup: <FileEntry>[file(r'materials\sky.tex', 100)],
        ),
        CopyStanding.covers,
      );
    });

    test('separator style does not decide it', () {
      expect(
        compareCopy(
          live: <FileEntry>[file('materials/sky.tex', 100)],
          backup: <FileEntry>[file(r'materials\sky.tex', 100)],
        ),
        CopyStanding.covers,
      );
    });

    // Same name and size in a different folder is a different file.
    test('a file moved between folders is behind', () {
      expect(
        compareCopy(
          live: <FileEntry>[file(r'materials\sky.tex', 100)],
          backup: <FileEntry>[file(r'effects\sky.tex', 100)],
        ),
        CopyStanding.behind,
      );
    });

    // The whole reason this is not folderVersion: copying rewrites every
    // timestamp, and a real backup differed from live on nothing else. There is
    // no timestamp in the input at all, which is the strongest form of this.
    test('a copy made at another time still covers', () {
      expect(compareCopy(live: project, backup: project), CopyStanding.covers);
    });

    // Wallpaper Engine rebuilds these locally, so live grows them and a backup
    // never holds them. Counting them called 1984 of 2162 real backups stale.
    test('rebuilt shaders on the live side do not make it behind', () {
      expect(
        compareCopy(
          live: <FileEntry>[
            ...project,
            file(r'shaders\blobsSM40\cache.bin', 4096),
          ],
          backup: project,
        ),
        CopyStanding.covers,
      );
    });

    test('a backup holding only rebuilt shaders is empty', () {
      expect(
        compareCopy(
          live: project,
          backup: <FileEntry>[file(r'shaders\blobsSM40\cache.bin', 4096)],
        ),
        CopyStanding.empty,
      );
    });

    // Empty is checked before coverage, or a live wallpaper with nothing in it
    // would report as covered by a backup folder holding nothing either.
    test('a backup with no files is empty, not covering', () {
      expect(
        compareCopy(live: project, backup: const <FileEntry>[]),
        CopyStanding.empty,
      );
      expect(
        compareCopy(live: const <FileEntry>[], backup: const <FileEntry>[]),
        CopyStanding.empty,
      );
    });
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
          BackupState.emptyBackup: 0,
        },
      );
    });

    // Zero-filled, so a caller can list every state without a null check and a
    // state nobody has hits still shows its own row. Counted off the enum, so a
    // new state cannot be added without the tab gaining a row for it.
    test('gives an empty library a zero for every state', () {
      expect(countByState(const <BackupState>[]).values, everyElement(0));
      expect(
        countByState(const <BackupState>[]),
        hasLength(BackupState.values.length),
      );
    });
  });
}
