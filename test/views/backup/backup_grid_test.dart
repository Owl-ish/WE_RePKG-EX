import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:we_repkg/config/theme.dart';
import 'package:we_repkg/constants/i10n.dart';
import 'package:we_repkg/constants/nums.dart';
import 'package:we_repkg/cores/backup.dart';
import 'package:we_repkg/models/enums.dart';
import 'package:we_repkg/provider/backup.dart';
import 'package:we_repkg/provider/filter.dart';
import 'package:we_repkg/provider/navigation.dart';
import 'package:we_repkg/provider/system.dart';
import 'package:we_repkg/utils/backup_diff.dart';
import 'package:we_repkg/utils/backup_tiles.dart';
import 'package:we_repkg/utils/storage.dart';
import 'package:we_repkg/views/backup/backup.dart';
import 'package:we_repkg/views/backup/backup_tile.dart';
import 'package:we_repkg/views/backup/integrity.dart';
import 'package:we_repkg/views/states/no_results.dart';
import 'package:we_repkg/widgets/count_pill.dart';
import 'package:we_repkg/widgets/selection_grid.dart';
import 'package:we_repkg/widgets/tile_overlays.dart';

import '../../support/backup_test_harness.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await StorageUtil.init();
  });

  // Through the real providers, so what is drawn is the pipeline's answer
  // rather than a stub's.
  group('pills', () {
    late ProviderContainer container;

    Future<void> pumpPills(
      WidgetTester tester, {
      List<BackupTile> tiles = const <BackupTile>[],
      List<ReconcileTile> reconcile = const <ReconcileTile>[],
      Map<BackupCard, BackupState>? scanCards,
      Map<BackupCard, BackupUpdatePlan> updates =
          const <BackupCard, BackupUpdatePlan>{},
      Set<BackupCard> ignoredUpdates = const <BackupCard>{},
      Map<String, ({bool live, bool backup})>? presence,
      bool entrance = false,
    }) async {
      container = ProviderContainer(
        overrides: [
          backupRootProvider.overrideWithValue(r'C:\backup'),
          backupScanProvider.overrideWithValue(
            AsyncValue<BackupScan>.data(
              scanOf(
                cards:
                    scanCards ??
                    <BackupCard, BackupState>{
                      for (final BackupTile tile in tiles)
                        tile.card: tile.state,
                    },
                updates: updates,
                ignoredUpdates: ignoredUpdates,
                presence: presence,
                reconcile: <ReconcileEntry>[
                  for (final ReconcileTile tile in reconcile) tile.entry,
                ],
              ),
            ),
          ),
          backupTilesProvider.overrideWith((Ref ref) => tiles),
          backupReconcileTilesProvider.overrideWith((Ref ref) => reconcile),
        ],
      );
      addTearDown(container.dispose);
      if (entrance) {
        container
            .read(currentSectionProvider.notifier)
            .update(NavSection.backup);
      }
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const Scaffold(body: BackupView()),
          ),
        ),
      );
      await settle(tester);
    }

    List<BackupTile> three() => <BackupTile>[
      (
        card: const BackupCard(WallpaperLibrary.workshop, 'fresh'),
        state: BackupState.notBackedUp,
        face: null,
      ),
      (
        card: const BackupCard(WallpaperLibrary.workshop, 'gone'),
        state: BackupState.vanished,
        face: null,
      ),
      (
        card: const BackupCard(WallpaperLibrary.workshop, 'safe'),
        state: BackupState.synced,
        face: null,
      ),
    ];

    ReconcileTile conflict() => (
      entry: const ReconcileEntry(
        name: 'muddled',
        reason: BackupReconcileReason.conflictingBackupCopies,
        states: <WallpaperLibrary, BackupState>{
          WallpaperLibrary.myProjects: BackupState.synced,
        },
        backupWorkshop: true,
        backupMyProjects: true,
        backupDifference: BackupCopyDifference(
          differentSize: <String>['project.json'],
          onlyWorkshop: <String>['workshop-only.txt'],
          onlyMyProjects: <String>['myprojects-only.txt'],
        ),
      ),
      face: null,
    );

    ReconcileTile duplicateLive() => (
      entry: const ReconcileEntry(
        name: 'double-live',
        reason: BackupReconcileReason.duplicateLiveCopies,
        states: <WallpaperLibrary, BackupState>{
          WallpaperLibrary.workshop: BackupState.synced,
          WallpaperLibrary.myProjects: BackupState.synced,
        },
        backupWorkshop: true,
        backupMyProjects: true,
      ),
      face: null,
    );

    Future<void> tapPill(WidgetTester tester, String label, int count) async {
      await tester.tap(find.text('$label $count'));
      await settle(tester);
    }

    testWidgets('ignored updates use the shared Ignored pill and grid', (
      tester,
    ) async {
      const BackupCard card = BackupCard(
        WallpaperLibrary.workshop,
        'ignored-update',
      );
      await pumpPills(
        tester,
        tiles: const <BackupTile>[
          (card: card, state: BackupState.updateDismissed, face: null),
        ],
        scanCards: const <BackupCard, BackupState>{},
        ignoredUpdates: <BackupCard>{card},
        reconcile: <ReconcileTile>[conflict()],
      );

      final Iterable<CountPill> pills = tester.widgetList<CountPill>(
        find.byType(CountPill),
      );
      expect(
        pills.where(
          (CountPill pill) => pill.label == AppI10n.backupStateUpdateDismissed,
        ),
        isEmpty,
      );
      expect(countOf(AppI10n.backupIgnored, 1), findsOneWidget);
      expect(container.read(backupStateFilterProvider).reconcile, isTrue);

      await tapPill(tester, AppI10n.backupIgnored, 1);

      expect(container.read(backupStateFilterProvider).ignored, isTrue);
      expect(
        find.byKey(const ValueKey<String>('backup-ignored-grid')),
        findsOneWidget,
      );
      expect(find.text('ignored-update'), findsOneWidget);
    });

    Finder arrivingTiles() => find.descendant(
      of: find.byType(SelectionGrid),
      matching: find.byType(SlideTransition),
    );

    // SelectionGrid calls forward() from a post-frame callback. The first
    // frame after that establishes the ticker's start timestamp at t=0; only
    // later timed pumps advance the animation. This helper models that real
    // lifecycle instead of assuming one large pump both starts and finishes it.
    Future<void> finishEntrance(WidgetTester tester) async {
      await tester.pump();
      // Pump just past the nominal endpoint. At exactly 900ms the controller
      // can report 1.0 before its completed status has fired, leaving the
      // transition wrappers in the tree until time advances again.
      await tester.pump(gridEntranceDuration + const Duration(milliseconds: 1));
      // Completion removes the transition wrappers via setState.
      await tester.pump();
    }

    // The one state with an obvious next step. The rest glow for themselves.
    testWidgets('the grid opens on the wallpapers that are not backed up', (
      tester,
    ) async {
      await pumpPills(tester, tiles: three());

      expect(find.byType(BackupTileView), findsOneWidget);
      expect(find.text('fresh'), findsOneWidget);
    });

    testWidgets('picking a pill filters cached details without loading', (
      tester,
    ) async {
      await pumpPills(tester, tiles: three());

      await tester.tap(find.text('${AppI10n.backupStateVanished} 1'));
      await tester.pump();

      expect(find.text(AppI10n.backupReadingDetails), findsNothing);
      expect(find.text('gone'), findsOneWidget);
      expect(find.text('fresh'), findsNothing);
    });

    testWidgets('switching state pills does not replay or reflow the grid', (
      tester,
    ) async {
      await pumpPills(tester, tiles: three());
      final Rect atRest = tester.getRect(find.byType(BackupTileView));

      await tester.tap(find.text('${AppI10n.backupStateVanished} 1'));
      await tester.pump(const Duration(milliseconds: 100));

      expect(arrivingTiles(), findsNothing);
      expect(tester.getRect(find.byType(BackupTileView)), atRest);
    });

    testWidgets('switching to Empty/Junk does not replay the entrance', (
      tester,
    ) async {
      await pumpPills(
        tester,
        tiles: <BackupTile>[
          (
            card: const BackupCard(WallpaperLibrary.workshop, 'fresh'),
            state: BackupState.notBackedUp,
            face: null,
          ),
          (
            card: const BackupCard(WallpaperLibrary.workshop, 'junk'),
            state: BackupState.emptyBackup,
            face: null,
          ),
        ],
      );

      await tester.tap(find.text('${AppI10n.backupStateEmptyBackup} 1'));
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        find.descendant(
          of: find.byKey(const ValueKey<String>('backup-junk-grid')),
          matching: find.byType(SlideTransition),
        ),
        findsNothing,
      );
    });

    testWidgets('the selected status border stays subtle', (tester) async {
      await pumpPills(tester, tiles: three());

      final Finder selected = find.ancestor(
        of: find.text('${AppI10n.backupStateNotBackedUp} 1'),
        matching: find.byType(CountPill),
      );
      final Container surface = tester
          .widgetList<Container>(
            find.descendant(of: selected, matching: find.byType(Container)),
          )
          .singleWhere(
            (Container container) =>
                container.decoration is BoxDecoration &&
                (container.decoration! as BoxDecoration).borderRadius ==
                    LayoutNums.pill,
          );
      final Border border =
          (surface.decoration! as BoxDecoration).border! as Border;
      expect(border.top.color.a, closeTo(.55, .001));
    });

    testWidgets('an inactive pill has a clearly visible slow pulse', (
      tester,
    ) async {
      await pumpPills(tester, tiles: three());
      final Finder pill = find.ancestor(
        of: find.text('${AppI10n.backupStateVanished} 1'),
        matching: find.byType(CountPill),
      );
      double fill() => tester
          .widgetList<Material>(
            find.descendant(of: pill, matching: find.byType(Material)),
          )
          .first
          .color!
          .a;
      double glow() {
        final DecoratedBox surface = tester.widget<DecoratedBox>(
          find.descendant(
            of: pill,
            matching: find.byWidgetPredicate((Widget widget) {
              if (widget is! DecoratedBox ||
                  widget.decoration is! BoxDecoration) {
                return false;
              }
              return (widget.decoration as BoxDecoration)
                      .boxShadow
                      ?.isNotEmpty ??
                  false;
            }),
          ),
        );
        return (surface.decoration as BoxDecoration).boxShadow!.single.color.a;
      }

      final double rising = fill();
      final double risingGlow = glow();
      await tester.pump(const Duration(milliseconds: 450));

      expect(fill(), greaterThan(rising + .03));
      expect(glow(), greaterThan(risingGlow + .03));
    });

    testWidgets('Empty/Junk explains the issue once below the pills', (
      tester,
    ) async {
      final List<BackupTile> tiles = <BackupTile>[
        (
          card: const BackupCard(WallpaperLibrary.workshop, 'junk-a'),
          state: BackupState.emptyBackup,
          face: null,
        ),
        (
          card: const BackupCard(WallpaperLibrary.myProjects, 'junk-b'),
          state: BackupState.emptyBackup,
          face: null,
        ),
      ];
      await pumpPills(tester, tiles: tiles);

      final Finder note = find.byKey(
        const ValueKey<String>('backup-junk-note-empty'),
      );
      expect(note, findsOneWidget);
      expect(
        tester
            .widgetList<RichText>(
              find.descendant(of: note, matching: find.byType(RichText)),
            )
            .map((RichText text) => text.text.toPlainText())
            .join(),
        contains(AppI10n.backupJunkEmptyAbout),
      );
      expect(
        find.descendant(
          of: note,
          matching: find.byIcon(Icons.info_outline_rounded),
        ),
        findsOneWidget,
      );
    });

    // On a library with nothing to back up that pill is dead, and opening on
    // it puts a "no results" grid in front of wallpapers that have vanished.
    testWidgets('a library with nothing to back up opens on the worst state '
        'that holds something', (tester) async {
      await pumpPills(
        tester,
        tiles: three()
            .where((BackupTile tile) => tile.state != BackupState.notBackedUp)
            .toList(),
      );

      expect(find.text('gone'), findsOneWidget);
      expect(find.byType(NoResultsView), findsNothing);
    });

    // A rescan that empties the selected state moves the filter to the next
    // populated state. This test is only about that filter decision; the
    // animation replay has its own test below.
    testWidgets('a rescan moves off a state it has emptied', (tester) async {
      List<BackupTile> tiles = three();
      container = ProviderContainer(
        overrides: [
          backupRootProvider.overrideWithValue(r'C:\backup'),
          backupScanProvider.overrideWith(
            (Ref ref) => scanOf(
              cards: <BackupCard, BackupState>{
                for (final BackupTile tile in tiles) tile.card: tile.state,
              },
            ),
          ),
          backupTilesProvider.overrideWith((Ref ref) => tiles),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const Scaffold(body: BackupView()),
          ),
        ),
      );
      await settle(tester);
      expect(find.text('fresh'), findsOneWidget);

      tiles = three()
          .where((BackupTile tile) => tile.state != BackupState.notBackedUp)
          .toList();
      container.invalidate(backupScanProvider);
      container.invalidate(backupTilesProvider);
      await settle(tester);

      expect(find.text('gone'), findsOneWidget);
      expect(
        container.read(backupStateFilterProvider).state,
        BackupState.vanished,
      );
    });

    testWidgets('a completed rescan replays the Backup wave once', (
      tester,
    ) async {
      final List<BackupTile> tiles = three();
      container = ProviderContainer(
        overrides: [
          backupRootProvider.overrideWithValue(r'C:\backup'),
          backupScanProvider.overrideWith(
            (Ref ref) => scanOf(
              cards: <BackupCard, BackupState>{
                for (final BackupTile tile in tiles) tile.card: tile.state,
              },
            ),
          ),
          backupTilesProvider.overrideWith((Ref ref) => tiles),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const Scaffold(body: BackupView()),
          ),
        ),
      );
      await settle(tester);
      expect(arrivingTiles(), findsNothing);

      // Same visible result, new completed scan. A rescan is an explicit
      // replay trigger even when nothing moved between the two snapshots.
      container.invalidate(backupScanProvider);
      await settle(tester);
      expect(arrivingTiles(), findsWidgets);

      await finishEntrance(tester);
      expect(arrivingTiles(), findsNothing);
      await tester.pump(const Duration(milliseconds: 400));
      expect(arrivingTiles(), findsNothing);
    });

    testWidgets('entering Backup plays the tile wave once', (tester) async {
      await pumpPills(tester, tiles: three(), entrance: true);

      expect(arrivingTiles(), findsWidgets);

      await finishEntrance(tester);
      expect(arrivingTiles(), findsNothing);
      await tester.pump(const Duration(milliseconds: 400));
      expect(arrivingTiles(), findsNothing);
    });

    testWidgets('returning from Integrity replays the Backup wave once', (
      tester,
    ) async {
      await pumpPills(tester, tiles: three());
      expect(arrivingTiles(), findsNothing);

      await tester.tap(find.text(AppI10n.backupTabIntegrity));
      await settle(tester);
      expect(find.byType(IntegrityView), findsOneWidget);

      await tester.tap(find.text(AppI10n.backupTabBackup));
      await tester.pump();
      expect(arrivingTiles(), findsWidgets);

      await finishEntrance(tester);
      expect(arrivingTiles(), findsNothing);
      await tester.pump(const Duration(milliseconds: 400));
      expect(arrivingTiles(), findsNothing);
    });

    testWidgets('entering Backup animates Empty/Junk too', (tester) async {
      final List<BackupTile> junk = <BackupTile>[
        (
          card: const BackupCard(WallpaperLibrary.workshop, 'junk-a'),
          state: BackupState.emptyBackup,
          face: null,
        ),
        (
          card: const BackupCard(WallpaperLibrary.workshop, 'junk-b'),
          state: BackupState.emptyBackup,
          face: null,
        ),
      ];
      await pumpPills(tester, tiles: junk, entrance: true);

      final Finder arriving = find.descendant(
        of: find.byKey(const ValueKey<String>('backup-junk-grid')),
        matching: find.byType(SlideTransition),
      );
      expect(arriving, findsWidgets);

      await finishEntrance(tester);
      expect(arriving, findsNothing);
    });

    // They behave as tabs: one at a time, and the grid is never left empty
    // because everything was switched off.
    testWidgets('picking a pill shows that state alone', (tester) async {
      await pumpPills(tester, tiles: three());

      await tapPill(tester, AppI10n.backupStateVanished, 1);

      expect(find.byType(BackupTileView), findsOneWidget);
      expect(find.text('gone'), findsOneWidget);
      expect(find.text(AppI10n.backupAboutVanished), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('backup-state-note-vanished')),
        findsOneWidget,
      );
    });

    // A selected state with no remaining cards is display state, not an
    // actionable pill; clicking its zero-count control must stay disabled.
    testWidgets('a pill holding nothing is not a live control', (tester) async {
      await pumpPills(tester, tiles: three());
      container
          .read(backupStateFilterProvider.notifier)
          .show(BackupState.emptyBackup);
      await settle(tester);

      expect(find.byType(NoResultsView), findsOneWidget);
      expect(
        tester
            .widget<InkWell>(
              find
                  .ancestor(
                    of: find.text('${AppI10n.backupStateEmptyBackup} 0'),
                    matching: find.byType(InkWell),
                  )
                  .first,
            )
            .onTap,
        isNull,
      );
    });

    testWidgets('picking the pill already showing changes nothing', (
      tester,
    ) async {
      await pumpPills(tester, tiles: three());

      await tapPill(tester, AppI10n.backupStateNotBackedUp, 1);

      expect(find.byType(BackupTileView), findsOneWidget);
      expect(find.text('fresh'), findsOneWidget);
    });

    testWidgets('Update / Sync tiles show update, sync, or both', (
      tester,
    ) async {
      const BackupCard updateCard = BackupCard(
        WallpaperLibrary.workshop,
        'content-update',
      );
      const BackupCard syncCard = BackupCard(
        WallpaperLibrary.workshop,
        'placement-sync',
      );
      const BackupCard bothCard = BackupCard(
        WallpaperLibrary.myProjects,
        'content-and-placement',
      );
      await pumpPills(
        tester,
        tiles: const <BackupTile>[
          (card: updateCard, state: BackupState.updateAvailable, face: null),
          (card: syncCard, state: BackupState.updateAvailable, face: null),
          (card: bothCard, state: BackupState.updateAvailable, face: null),
        ],
        updates: <BackupCard, BackupUpdatePlan>{
          updateCard: const BackupUpdatePlan(updateContent: true),
          syncCard: const BackupUpdatePlan(
            sync: BackupSyncPlan(
              kind: BackupSyncKind.relocate,
              from: WallpaperLibrary.myProjects,
              to: WallpaperLibrary.workshop,
            ),
          ),
          bothCard: const BackupUpdatePlan(
            updateContent: true,
            sync: BackupSyncPlan(
              kind: BackupSyncKind.relocate,
              from: WallpaperLibrary.workshop,
              to: WallpaperLibrary.myProjects,
            ),
          ),
        },
      );

      expect(find.byType(TileBadgeStrip), findsNWidgets(3));
      expect(find.text(AppI10n.backupTileUpdate), findsNWidgets(2));
      expect(find.text(AppI10n.backupTileSync), findsNWidgets(2));
    });

    // Reconcile groups stay separate even when the second group is off-screen.
    testWidgets('the reconcile pill groups tiles by reason', (tester) async {
      await pumpPills(
        tester,
        tiles: three(),
        reconcile: <ReconcileTile>[conflict(), duplicateLive()],
      );

      await tapPill(tester, AppI10n.backupReconcile, 2);

      final Finder reconcileGrid = find.byKey(
        const ValueKey<String>('backup-reconcile-grid'),
      );
      expect(reconcileGrid, findsOneWidget);
      expect(
        tester.widget<SelectionGrid>(reconcileGrid).sections,
        hasLength(2),
        reason: 'Reconcile should use the shared grouped grid engine',
      );
      expect(find.byType(BackupTileView), findsNothing);
      expect(find.text('double-live'), findsOneWidget);
      expect(find.text(AppI10n.backupTileReconcile), findsNothing);
      expect(find.text(AppI10n.backupTileDuplicateLive), findsOneWidget);
      expect(
        find.textContaining(AppI10n.backupReconcileDuplicateLiveTitle),
        findsOneWidget,
      );
      expect(
        find.byKey(
          const ValueKey<String>('backup-reconcile-note-duplicateLiveCopies'),
        ),
        findsOneWidget,
      );
      final Finder duplicateHeader = find.ancestor(
        of: find.byKey(
          const ValueKey<String>('backup-reconcile-note-duplicateLiveCopies'),
        ),
        matching: find.byType(SliverPersistentHeader),
      );
      expect(duplicateHeader, findsOneWidget);
      expect(
        tester.widget<SliverPersistentHeader>(duplicateHeader).pinned,
        isTrue,
      );
      expect(
        find.ancestor(
          of: duplicateHeader,
          matching: find.byType(SliverMainAxisGroup),
        ),
        findsOneWidget,
      );

      await tester.drag(reconcileGrid, const Offset(0, -600));
      await settle(tester);

      expect(find.text('muddled'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey<String>('reconcile/muddled')),
          matching: find.byType(TileBadgeStrip),
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining(AppI10n.backupReconcileConflictingBackupsTitle),
        findsOneWidget,
      );
      expect(
        find.byKey(
          const ValueKey<String>(
            'backup-reconcile-note-conflictingBackupCopies',
          ),
        ),
        findsOneWidget,
      );
    });

    // They all read as off while it has the grid, so lighting one has to mean
    // "show me that state".
    testWidgets('a state pill takes the grid back from reconcile', (
      tester,
    ) async {
      await pumpPills(
        tester,
        tiles: three(),
        reconcile: <ReconcileTile>[conflict()],
      );
      await tapPill(tester, AppI10n.backupReconcile, 1);

      await tapPill(tester, AppI10n.backupStateSynced, 1);

      expect(find.byType(ReconcileTileView), findsNothing);
      expect(find.text('safe'), findsOneWidget);
      expect(find.text('gone'), findsNothing);
    });

    // A tile out of view can be neither seen nor cleared.
    testWidgets('narrowing the grid deselects what it hides', (tester) async {
      await pumpPills(tester, tiles: three());
      container.read(backupSelectionProvider.notifier).setExactly({
        'workshop/fresh',
      });
      await tester.pump();

      await tapPill(tester, AppI10n.backupStateVanished, 1);

      expect(container.read(backupSelectionProvider), isEmpty);
    });

    // They are the summary of what is on disk; narrowing is a way of looking
    // at it, not a change to it.
    testWidgets('the counts stay whole-library while a pill narrows it', (
      tester,
    ) async {
      await pumpPills(tester, tiles: three());

      await tapPill(tester, AppI10n.backupStateVanished, 1);

      expect(countOf(AppI10n.backupStateVanished, 1), findsOneWidget);
      expect(countOf(AppI10n.backupStateSynced, 1), findsOneWidget);
    });

    // The pruning has to know which list is on screen, or it drops every
    // reconcile tile the moment anything moves.
    testWidgets('a selected reconcile tile survives a narrowing', (
      tester,
    ) async {
      await pumpPills(
        tester,
        tiles: three(),
        reconcile: <ReconcileTile>[conflict()],
      );
      await tapPill(tester, AppI10n.backupReconcile, 1);

      await tester.tap(find.byType(ReconcileTileView));
      await tester.pump(kDoubleTapTimeout);
      expect(container.read(backupSelectionProvider), {'reconcile/muddled'});

      // Still a match, so nothing should be dropped.
      container.read(backupSearchProvider.notifier).update('mud');
      await settle(tester);

      expect(container.read(backupSelectionProvider), {'reconcile/muddled'});
      expect(find.byType(ReconcileTileView), findsOneWidget);
    });

    // Wired to nothing they would look right and do nothing.
    testWidgets('the order controls reach the grid', (tester) async {
      final DateTime old = DateTime(2024);
      final DateTime recent = DateTime(2026);
      await pumpPills(
        tester,
        tiles: <BackupTile>[
          (
            card: const BackupCard(WallpaperLibrary.workshop, 'alpha'),
            state: BackupState.notBackedUp,
            face: (
              title: 'alpha',
              preview: '',
              type: '',
              rating: '',
              modified: old,
            ),
          ),
          (
            card: const BackupCard(WallpaperLibrary.workshop, 'beta'),
            state: BackupState.notBackedUp,
            face: (
              title: 'beta',
              preview: '',
              type: '',
              rating: '',
              modified: recent,
            ),
          ),
        ],
      );

      List<String> drawn() => tester
          .widgetList<BackupTileView>(find.byType(BackupTileView))
          .map((BackupTileView t) => t.tile.card.name)
          .toList();

      expect(drawn(), <String>['alpha', 'beta']);

      container
          .read(backupSortOrderProvider.notifier)
          .update(BackupSortType.date);
      await settle(tester);
      expect(drawn(), <String>['beta', 'alpha'], reason: 'newest first');

      container.read(backupSortAscendingProvider.notifier).update();
      await settle(tester);
      expect(drawn(), <String>['alpha', 'beta']);
    });

    // One menu, both grids. On a default filter it would silently do nothing
    // here.
    testWidgets('the extract tab\'s filter reaches this grid', (tester) async {
      await pumpPills(
        tester,
        tiles: <BackupTile>[
          (
            card: const BackupCard(WallpaperLibrary.workshop, 'clip'),
            state: BackupState.notBackedUp,
            face: (
              title: 'clip',
              preview: '',
              type: 'video',
              rating: '',
              modified: null,
            ),
          ),
        ],
      );
      expect(find.byType(BackupTileView), findsOneWidget);

      container.read(filterStateProvider.notifier).updateHideVideo(true);
      await settle(tester);

      expect(find.byType(BackupTileView), findsNothing);
      expect(
        countOf(AppI10n.backupStateNotBackedUp, 1),
        findsOneWidget,
        reason: 'the counts are what is on disk, not what is on screen',
      );
    });
  });
}
