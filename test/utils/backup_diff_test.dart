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
    Map<String, CopyStanding> crossWorkshopStanding = nothingCompared,
    Map<String, CopyStanding> crossMyProjectsStanding = nothingCompared,
    Map<String, BackupRecord> records = const <String, BackupRecord>{},
    Set<String> equivalentBackupCopies = const <String>{},
    Set<String> unavailableBackupComparisons = const <String>{},
    Map<String, BackupCopyDifference> backupCopyDifferences =
        const <String, BackupCopyDifference>{},
    Set<String> unavailableContentComparisons = const <String>{},
  }) => backupDiff(
    liveWorkshop: liveWorkshop,
    liveMyProjects: liveMyProjects,
    backupWorkshop: backupWorkshop,
    backupMyProjects: backupMyProjects,
    liveWorkshopVersions: liveWorkshopVersions,
    liveMyProjectsVersions: liveMyProjectsVersions,
    workshopStanding: workshopStanding,
    myProjectsStanding: myProjectsStanding,
    crossWorkshopStanding: crossWorkshopStanding,
    crossMyProjectsStanding: crossMyProjectsStanding,
    records: records,
    equivalentBackupCopies: equivalentBackupCopies,
    unavailableBackupComparisons: unavailableBackupComparisons,
    backupCopyDifferences: backupCopyDifferences,
    unavailableContentComparisons: unavailableContentComparisons,
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
    Map<String, CopyStanding> crossWorkshopStanding = nothingCompared,
    Map<String, CopyStanding> crossMyProjectsStanding = nothingCompared,
    Map<String, BackupRecord> records = const <String, BackupRecord>{},
    Set<String> equivalentBackupCopies = const <String>{},
    Set<String> unavailableBackupComparisons = const <String>{},
    Set<String> unavailableContentComparisons = const <String>{},
  }) => diff(
    liveWorkshop: liveWorkshop,
    liveMyProjects: liveMyProjects,
    backupWorkshop: backupWorkshop,
    backupMyProjects: backupMyProjects,
    liveWorkshopVersions: liveWorkshopVersions,
    liveMyProjectsVersions: liveMyProjectsVersions,
    workshopStanding: workshopStanding,
    myProjectsStanding: myProjectsStanding,
    crossWorkshopStanding: crossWorkshopStanding,
    crossMyProjectsStanding: crossMyProjectsStanding,
    records: records,
    equivalentBackupCopies: equivalentBackupCopies,
    unavailableBackupComparisons: unavailableBackupComparisons,
    unavailableContentComparisons: unavailableContentComparisons,
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
      expectCards(shape(false, true, true, false), <BackupCard, BackupState>{
        myProjects(n): BackupState.updateAvailable,
      });
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
      expectCards(shape(true, false, false, true), <BackupCard, BackupState>{
        workshop(n): BackupState.updateAvailable,
      });
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
      expectReconcile(
        shape(true, true, false, false),
        <WallpaperLibrary>{},
        <WallpaperLibrary>{
          WallpaperLibrary.workshop,
          WallpaperLibrary.myProjects,
        },
      );
    });

    test('LW LM -- BM', () {
      expectReconcile(
        shape(true, true, false, true),
        <WallpaperLibrary>{},
        <WallpaperLibrary>{},
      );
    });

    test('LW LM BW --', () {
      expectReconcile(
        shape(true, true, true, false),
        <WallpaperLibrary>{},
        <WallpaperLibrary>{},
      );
    });

    test('LW LM BW BM', () {
      expectReconcile(
        shape(true, true, true, true),
        <WallpaperLibrary>{},
        <WallpaperLibrary>{},
      );
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

  group('central backup rules', () {
    test('duplicate live copies name their reconcile reason', () {
      final BackupRuleDecision decision = backupRule(
        liveWorkshop: true,
        liveMyProjects: true,
        backupWorkshop: false,
        backupMyProjects: true,
      );
      expect(decision.kind, BackupRuleKind.reconcile);
      expect(
        decision.reconcileReason,
        BackupReconcileReason.duplicateLiveCopies,
      );
    });

    test('reconcile collects every already-known ambiguity', () {
      final BackupRuleDecision decision = backupRule(
        liveWorkshop: true,
        liveMyProjects: true,
        backupWorkshop: true,
        backupMyProjects: true,
        backupCopiesCompared: true,
      );

      expect(decision.kind, BackupRuleKind.reconcile);
      expect(
        decision.reconcileReason,
        BackupReconcileReason.duplicateLiveCopies,
      );
      expect(decision.reconcileReasons, <BackupReconcileReason>{
        BackupReconcileReason.duplicateLiveCopies,
        BackupReconcileReason.conflictingBackupCopies,
      });
    });

    test('different duplicate backups name their reconcile reason', () {
      final BackupRuleDecision decision = backupRule(
        liveWorkshop: true,
        liveMyProjects: false,
        backupWorkshop: true,
        backupMyProjects: true,
      );
      expect(decision.kind, BackupRuleKind.reconcile);
      expect(
        decision.reconcileReason,
        BackupReconcileReason.conflictingBackupCopies,
      );
    });

    test('equivalent duplicate backups are deterministic structure sync', () {
      final BackupRuleDecision decision = backupRule(
        liveWorkshop: true,
        liveMyProjects: false,
        backupWorkshop: true,
        backupMyProjects: true,
        backupCopiesEquivalent: true,
      );
      expect(decision.kind, BackupRuleKind.structureSync);
      expect(decision.reconcileReason, isNull);
    });

    test('an unavailable duplicate-backup comparison stays ambiguous', () {
      final BackupRuleDecision decision = backupRule(
        liveWorkshop: true,
        liveMyProjects: false,
        backupWorkshop: true,
        backupMyProjects: true,
        backupComparisonUnavailable: true,
      );
      expect(decision.kind, BackupRuleKind.reconcile);
      expect(
        decision.reconcileReason,
        BackupReconcileReason.comparisonUnavailable,
      );
    });

    test('an unavailable required content comparison stays ambiguous', () {
      final BackupRuleDecision decision = backupRule(
        liveWorkshop: false,
        liveMyProjects: true,
        backupWorkshop: false,
        backupMyProjects: true,
        contentComparisonUnavailable: true,
      );
      expect(decision.kind, BackupRuleKind.reconcile);
      expect(
        decision.reconcileReason,
        BackupReconcileReason.comparisonUnavailable,
      );
    });

    test('wrong placement does not require a content comparison', () {
      final BackupRuleDecision decision = backupRule(
        liveWorkshop: false,
        liveMyProjects: true,
        backupWorkshop: true,
        backupMyProjects: false,
        contentComparisonUnavailable: true,
      );
      expect(decision.kind, BackupRuleKind.structureSync);
      expect(decision.reconcileReason, isNull);
    });
  });

  group('tier 2, reconcile', () {
    // Backup protection is pooled across both backup trees. A lone copy under
    // the opposite tree is protected but structurally out of sync, so it
    // belongs to Update / Sync rather than Reconcile.
    test('an opposite-tree backup is update/sync, not reconcile', () {
      final BackupDiffResult result = diff(
        liveMyProjects: const <String>{'793602574'},
        backupWorkshop: const <String>{'793602574'},
      );

      expect(result.cards, <BackupCard, BackupState>{
        myProjects('793602574'): BackupState.updateAvailable,
      });
      expect(result.reconcile, isEmpty);
    });

    test('wrong placement can require both update and sync', () {
      const BackupCard card = BackupCard(WallpaperLibrary.myProjects, 'alpha');
      final BackupDiffResult result = diff(
        liveMyProjects: const <String>{'alpha'},
        backupWorkshop: const <String>{'alpha'},
        crossMyProjectsStanding: standing('alpha', CopyStanding.behind),
      );

      expect(
        result.updates[card],
        const BackupUpdatePlan(
          updateContent: true,
          sync: BackupSyncPlan(
            kind: BackupSyncKind.relocate,
            from: WallpaperLibrary.workshop,
            to: WallpaperLibrary.myProjects,
          ),
        ),
      );
    });

    test('current wrong-side backup is sync only', () {
      const BackupCard card = BackupCard(WallpaperLibrary.myProjects, 'alpha');
      final BackupDiffResult result = diff(
        liveMyProjects: const <String>{'alpha'},
        backupWorkshop: const <String>{'alpha'},
        crossMyProjectsStanding: standing('alpha', CopyStanding.covers),
      );

      expect(
        result.updates[card],
        const BackupUpdatePlan(
          sync: BackupSyncPlan(
            kind: BackupSyncKind.relocate,
            from: WallpaperLibrary.workshop,
            to: WallpaperLibrary.myProjects,
          ),
        ),
      );
    });

    test('equivalent duplicate backups are structure sync, not reconcile', () {
      final BackupDiffResult result = diff(
        liveWorkshop: const <String>{'793602574'},
        backupWorkshop: const <String>{'793602574'},
        backupMyProjects: const <String>{'793602574'},
        equivalentBackupCopies: const <String>{'793602574'},
      );

      expect(result.cards, <BackupCard, BackupState>{
        workshop('793602574'): BackupState.updateAvailable,
      });
      expect(result.reconcile, isEmpty);
    });

    test('different duplicate backups still require reconcile', () {
      final BackupDiffResult result = diff(
        liveWorkshop: const <String>{'793602574'},
        backupWorkshop: const <String>{'793602574'},
        backupMyProjects: const <String>{'793602574'},
      );

      expect(result.cards, isEmpty);
      expect(result.reconcile, hasLength(1));
    });

    test(
      'an unavailable duplicate-backup comparison names the uncertainty',
      () {
        final BackupDiffResult result = diff(
          liveWorkshop: const <String>{'793602574'},
          backupWorkshop: const <String>{'793602574'},
          backupMyProjects: const <String>{'793602574'},
          unavailableBackupComparisons: const <String>{'793602574'},
        );

        expect(result.cards, isEmpty);
        expect(
          result.reconcile.single.reason,
          BackupReconcileReason.comparisonUnavailable,
        );
      },
    );

    test('an unavailable myprojects comparison never reads as synced', () {
      final BackupDiffResult result = diff(
        liveMyProjects: const <String>{'alpha'},
        backupMyProjects: const <String>{'alpha'},
        unavailableContentComparisons: const <String>{'myprojects/alpha'},
      );

      expect(result.cards, isEmpty);
      expect(
        result.reconcile.single.reason,
        BackupReconcileReason.comparisonUnavailable,
      );
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
            reason: BackupReconcileReason.conflictingBackupCopies,
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

    test('wrong backup structure does not read as synced', () {
      final BackupDiffResult result = diff(
        liveWorkshop: const <String>{'793602574'},
        backupMyProjects: const <String>{'793602574'},
      );

      expect(result.cards, <BackupCard, BackupState>{
        workshop('793602574'): BackupState.updateAvailable,
      });
      expect(result.reconcile, isEmpty);
    });

    // Reconcile owns the ambiguous name exclusively, so the normal grid cannot
    // expose a second action for the same wallpaper.
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

    test('duplicate live copies reconcile even with no backup', () {
      final BackupDiffResult result = diff(
        liveWorkshop: const <String>{'793602574'},
        liveMyProjects: const <String>{'793602574'},
      );

      expect(result.cards, isEmpty);
      expect(result.reconcile, <ReconcileEntry>[
        const ReconcileEntry(
          name: '793602574',
          reason: BackupReconcileReason.duplicateLiveCopies,
          states: <WallpaperLibrary, BackupState>{
            WallpaperLibrary.workshop: BackupState.notBackedUp,
            WallpaperLibrary.myProjects: BackupState.notBackedUp,
          },
          backupWorkshop: false,
          backupMyProjects: false,
        ),
      ]);
      expect(result.reconcile.single.needsBackup, <WallpaperLibrary>{
        WallpaperLibrary.workshop,
        WallpaperLibrary.myProjects,
      });
    });

    test('duplicate live copies reconcile even with both backups', () {
      final BackupDiffResult result = diff(
        liveWorkshop: const <String>{'793602574'},
        liveMyProjects: const <String>{'793602574'},
        backupWorkshop: const <String>{'793602574'},
        backupMyProjects: const <String>{'793602574'},
      );

      expect(result.cards, isEmpty);
      expect(result.reconcile.single.states, <WallpaperLibrary, BackupState>{
        WallpaperLibrary.workshop: BackupState.synced,
        WallpaperLibrary.myProjects: BackupState.synced,
      });
      expect(result.reconcile.single.needsBackup, isEmpty);
    });

    test('duplicate live evidence keeps all detected locations together', () {
      final ReconcileEntry entry = diff(
        liveWorkshop: const <String>{'3707191336'},
        liveMyProjects: const <String>{'3707191336'},
        backupWorkshop: const <String>{'3707191336'},
      ).reconcile.single;

      expect(entry.evidence.requiresUserDecision, isTrue);
      expect(entry.evidence.liveWorkshop, isTrue);
      expect(entry.evidence.liveMyProjects, isTrue);
      expect(entry.evidence.backupWorkshop, isTrue);
      expect(entry.evidence.backupMyProjects, isFalse);
      expect(entry.evidence.reconcileReasons, <BackupReconcileReason>{
        BackupReconcileReason.duplicateLiveCopies,
      });
    });

    test(
      'duplicate live stays reconcile when one live copy differs from the backup',
      () {
        final BackupDiffResult result = diff(
          liveWorkshop: const <String>{'3707191336'},
          liveMyProjects: const <String>{'3707191336'},
          backupWorkshop: const <String>{'3707191336'},
          crossMyProjectsStanding: standing('3707191336', CopyStanding.behind),
        );

        expect(result.cards, isEmpty);
        expect(result.reconcile, hasLength(1));
        expect(
          result.reconcile.single.reason,
          BackupReconcileReason.duplicateLiveCopies,
        );
        expect(result.reconcile.single.states, <WallpaperLibrary, BackupState>{
          WallpaperLibrary.workshop: BackupState.synced,
          WallpaperLibrary.myProjects: BackupState.updateAvailable,
        });
        expect(result.reconcile.single.evidence.attentionStates, <BackupState>{
          BackupState.updateAvailable,
        });
      },
    );

    test(
      'a compared backup conflict stays attached to duplicate live copies',
      () {
        final ReconcileEntry entry = diff(
          liveWorkshop: const <String>{'3707191336'},
          liveMyProjects: const <String>{'3707191336'},
          backupWorkshop: const <String>{'3707191336'},
          backupMyProjects: const <String>{'3707191336'},
          backupCopyDifferences: const <String, BackupCopyDifference>{
            '3707191336': BackupCopyDifference(
              differentSize: <String>['scene.pkg'],
            ),
          },
        ).reconcile.single;

        expect(entry.reason, BackupReconcileReason.duplicateLiveCopies);
        expect(entry.additionalReasons, <BackupReconcileReason>{
          BackupReconcileReason.conflictingBackupCopies,
        });
        expect(entry.evidence.reconcileReasons, <BackupReconcileReason>{
          BackupReconcileReason.duplicateLiveCopies,
          BackupReconcileReason.conflictingBackupCopies,
        });
      },
    );

    test('an opposite-tree card keeps the live spelling', () {
      expect(
        diff(
          liveMyProjects: const <String>{'Cool Wallpaper'},
          backupWorkshop: const <String>{'cool wallpaper'},
        ).cards.keys.single.name,
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

    test('one backup protects both duplicate live copies before reconcile', () {
      final BackupDiffResult result = diff(
        liveWorkshop: const <String>{'793602574'},
        liveMyProjects: const <String>{'793602574'},
        backupWorkshop: const <String>{'793602574'},
      );

      expect(result.cards, isEmpty);
      expect(result.reconcile, hasLength(1));
      expect(result.reconcile.single.states, <WallpaperLibrary, BackupState>{
        WallpaperLibrary.workshop: BackupState.synced,
        WallpaperLibrary.myProjects: BackupState.synced,
      });
      expect(result.reconcile.single.needsBackup, isEmpty);
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

  // Steam's manifest names the live version only, so a hand-made backup with
  // no saved backup operation is compared directly.
  group('workshop without a saved baseline', () {
    const String n = '793602574';

    BackupDiffResult workshopResult({
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
    test('a covering backup is synced', () {
      final BackupDiffResult result = workshopResult(
        standings: standing(n, CopyStanding.covers),
      );

      expect(result.cards[workshop(n)], BackupState.synced);
    });

    test('a backup behind live reports it', () {
      final BackupDiffResult result = workshopResult(
        standings: standing(n, CopyStanding.behind),
      );

      expect(result.cards[workshop(n)], BackupState.updateAvailable);
    });

    // A missing Steam manifest cannot prove a file mismatch is current. Mirror
    // comparison remains authoritative even when no published version exists.
    test('a wallpaper with no manifest still reports a mirror mismatch', () {
      final BackupDiffResult result = workshopResult(
        standings: standing(n, CopyStanding.behind),
        versions: const <String, String>{},
      );

      expect(result.cards[workshop(n)], BackupState.updateAvailable);
    });

    test('a direct mirror mismatch beats a recorded baseline', () {
      final BackupDiffResult result = workshopResult(
        standings: standing(n, CopyStanding.behind),
        records: const <String, BackupRecord>{
          'workshop/$n': BackupRecord(backedUpVersion: 'manifest-1'),
        },
      );

      expect(result.cards[workshop(n)], BackupState.updateAvailable);
    });

    // Nothing compared is not the same as compared and matched.
    test('an uncompared card is left alone', () {
      final BackupDiffResult result = workshopResult();

      expect(result.cards[workshop(n)], BackupState.synced);
    });

    // A cancelled copy leaves the folder there and nothing in it. The record
    // must not answer for it either, or a recorded card could be emptied and go
    // on reading as backed up.
    test('an empty backup folder beats even a recorded baseline', () {
      final BackupDiffResult result = workshopResult(
        standings: standing(n, CopyStanding.empty),
        records: const <String, BackupRecord>{
          'workshop/$n': BackupRecord(backedUpVersion: 'manifest-1'),
        },
      );

      expect(result.cards[workshop(n)], BackupState.emptyBackup);
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

    test('a covering backup is synced', () {
      final BackupDiffResult result = compared(
        standings: standing(n, CopyStanding.covers),
      );

      expect(result.cards[myProjects(n)], BackupState.synced);
    });

    test('a backup behind live is an update, with no record needed', () {
      final BackupDiffResult result = compared(
        standings: standing(n, CopyStanding.behind),
      );

      expect(result.cards[myProjects(n)], BackupState.updateAvailable);
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
  // a state.
  test('a reconcile entry keeps its live state', () {
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
  });

  group('a name live in both libraries', () {
    // Two live copies are one wallpaper-level decision, never two ordinary
    // cards that can quietly drift apart.
    test('is one reconcile entry', () {
      final BackupDiffResult result = diff(
        liveWorkshop: const <String>{'793602574'},
        liveMyProjects: const <String>{'793602574'},
      );

      expect(result.cards, isEmpty);
      expect(result.reconcile, hasLength(1));
      expect(result.reconcile.single.states, <WallpaperLibrary, BackupState>{
        WallpaperLibrary.workshop: BackupState.notBackedUp,
        WallpaperLibrary.myProjects: BackupState.notBackedUp,
      });
    });

    // Each live copy still carries its own update state inside reconciliation.
    test('tracks a version per live copy', () {
      final BackupDiffResult result = diff(
        liveWorkshop: const <String>{'793602574'},
        liveMyProjects: const <String>{'793602574'},
        backupWorkshop: const <String>{'793602574'},
        backupMyProjects: const <String>{'793602574'},
        liveWorkshopVersions: const <String, String>{'793602574': 'manifest-1'},
        myProjectsStanding: standing('793602574', CopyStanding.behind),
        records: const <String, BackupRecord>{
          'workshop/793602574': BackupRecord(backedUpVersion: 'manifest-1'),
        },
      );

      expect(result.cards, isEmpty);
      expect(result.reconcile.single.states, <WallpaperLibrary, BackupState>{
        WallpaperLibrary.workshop: BackupState.synced,
        WallpaperLibrary.myProjects: BackupState.updateAvailable,
      });
    });

    test('dismisses per live copy', () {
      final BackupDiffResult result = diff(
        liveWorkshop: const <String>{'793602574'},
        liveMyProjects: const <String>{'793602574'},
        backupWorkshop: const <String>{'793602574'},
        backupMyProjects: const <String>{'793602574'},
        liveWorkshopVersions: const <String, String>{'793602574': 'manifest-2'},
        liveMyProjectsVersions: const <String, String>{'793602574': 'digest-2'},
        myProjectsStanding: standing('793602574', CopyStanding.behind),
        records: const <String, BackupRecord>{
          'workshop/793602574': BackupRecord(backedUpVersion: 'manifest-1'),
          'myprojects/793602574': BackupRecord(dismissedVersion: 'digest-2'),
        },
      );

      expect(result.cards, isEmpty);
      expect(result.reconcile.single.states, <WallpaperLibrary, BackupState>{
        WallpaperLibrary.workshop: BackupState.updateAvailable,
        WallpaperLibrary.myProjects: BackupState.updateDismissed,
      });
      expect(result.ignoredUpdates, <BackupCard>{myProjects('793602574')});
    });
  });

  test(
    'ignored content update stays in Ignored while required Sync stays active',
    () {
      const String name = '793602574';
      final BackupDiffResult result = diff(
        liveWorkshop: const <String>{name},
        backupMyProjects: const <String>{name},
        liveWorkshopVersions: const <String, String>{name: 'manifest-2'},
        records: const <String, BackupRecord>{
          'workshop/$name': BackupRecord(
            backedUpVersion: 'manifest-1',
            dismissedVersion: 'manifest-2',
          ),
        },
      );
      final BackupCard card = workshop(name);

      expect(result.ignoredUpdates, contains(card));
      expect(result.cards[card], BackupState.updateAvailable);
      expect(result.updates[card]?.updateContent, isFalse);
      expect(result.updates[card]?.needsSync, isTrue);
    },
  );

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

    test('a file that exists only in backup makes the mirror stale', () {
      expect(
        compareCopy(
          live: project,
          backup: <FileEntry>[...project, file('dropped-last-year.tex', 900)],
        ),
        CopyStanding.behind,
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

    // Mirror equality deliberately ignores timestamps because copying may
    // rewrite them; relative path and size are the meaningful comparison here.
    test('a copy made at another time still covers', () {
      expect(compareCopy(live: project, backup: project), CopyStanding.covers);
    });

    // Wallpaper Engine rebuilds shader caches locally, so their absence from a
    // backup must not make otherwise covered content look stale.
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

    // Empty is checked before mirror equality, or an empty backup could be
    // mistaken for a usable mirrored copy.
    test('a backup with no files is empty, not mirrored', () {
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

  group('worstBackupState', () {
    test('takes the worst state with anything in it', () {
      expect(
        worstBackupState(const <BackupState, int>{
          BackupState.vanished: 0,
          BackupState.emptyBackup: 0,
          BackupState.notBackedUp: 0,
          BackupState.updateAvailable: 3,
          BackupState.synced: 900,
        }),
        BackupState.updateAvailable,
      );
    });

    // Nothing to open on, so the tab keeps the state the user came here about
    // rather than landing on whatever sorts first.
    test('falls back to not backed up when every count is zero', () {
      expect(
        worstBackupState(<BackupState, int>{
          for (final BackupState state in BackupState.values) state: 0,
        }),
        BackupState.notBackedUp,
      );
    });
  });

  test('normal pill order leaves ignored updates to the Ignored pill', () {
    expect(backupStateOrder, isNot(contains(BackupState.updateDismissed)));
    expect(
      backupStateOrder.toSet(),
      BackupState.values
          .where((BackupState state) => state != BackupState.updateDismissed)
          .toSet(),
    );
    expect(backupSeverity.keys.toSet(), BackupState.values.toSet());
  });

  group('sortedCards', () {
    // Named against the ranking rather than with it: alphabetically these run
    // backwards, so any two states sharing a rank fall into name order and
    // swap. Naming them in rank order would hide every tie but the first.
    test('puts the states that need attention first', () {
      final List<BackupCard> order = sortedCards(<BackupCard, BackupState>{
        const BackupCard(WallpaperLibrary.workshop, 'a'): BackupState.synced,
        const BackupCard(WallpaperLibrary.workshop, 'b'):
            BackupState.updateDismissed,
        const BackupCard(WallpaperLibrary.workshop, 'c'):
            BackupState.updateAvailable,
        const BackupCard(WallpaperLibrary.workshop, 'd'):
            BackupState.notBackedUp,
        const BackupCard(WallpaperLibrary.workshop, 'e'):
            BackupState.emptyBackup,
        const BackupCard(WallpaperLibrary.workshop, 'f'): BackupState.vanished,
      });

      expect(order.map((BackupCard c) => c.name), <String>[
        'f',
        'e',
        'd',
        'c',
        'b',
        'a',
      ]);
    });

    // The marquee and shift-click index into positions in this list, so two
    // scans of an unchanged library have to agree on it. A directory listing
    // does not.
    // A capital sorts before every lowercase letter in code-point order, so
    // `Beta` is what tells a case-insensitive comparison from a raw one.
    // myprojects folder names are wallpaper titles, so mixed case is normal.
    test('orders by name within a state, ignoring case', () {
      final List<BackupCard> order = sortedCards(<BackupCard, BackupState>{
        const BackupCard(WallpaperLibrary.workshop, 'gamma'):
            BackupState.synced,
        const BackupCard(WallpaperLibrary.workshop, 'Beta'): BackupState.synced,
        const BackupCard(WallpaperLibrary.workshop, 'alpha'):
            BackupState.synced,
      });

      expect(order.map((BackupCard c) => c.name), <String>[
        'alpha',
        'Beta',
        'gamma',
      ]);
    });

    // The sorter can still receive same-name cards from both libraries, so the
    // tie has to break somewhere fixed.
    test('breaks a tied name on the library', () {
      final List<BackupCard> order = sortedCards(<BackupCard, BackupState>{
        const BackupCard(WallpaperLibrary.workshop, 'alpha'):
            BackupState.synced,
        const BackupCard(WallpaperLibrary.myProjects, 'alpha'):
            BackupState.synced,
      });

      expect(order.map((BackupCard c) => c.library), <WallpaperLibrary>[
        WallpaperLibrary.myProjects,
        WallpaperLibrary.workshop,
      ]);
    });
  });
}
