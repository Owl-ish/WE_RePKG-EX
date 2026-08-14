import 'dart:io';

import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:we_repkg/config/theme.dart';
import 'package:we_repkg/constants/i10n.dart';
import 'package:we_repkg/cores/backup.dart';
import 'package:we_repkg/models/enums.dart';
import 'package:we_repkg/provider/backup.dart';
import 'package:we_repkg/provider/filter.dart';
import 'package:we_repkg/provider/navigation.dart';
import 'package:we_repkg/provider/system.dart';
import 'package:we_repkg/provider/wallpaper.dart';
import 'package:we_repkg/utils/backup_diff.dart';
import 'package:we_repkg/utils/backup_tiles.dart';
import 'package:we_repkg/utils/storage.dart';
import 'package:we_repkg/views/backup/backup.dart';
import 'package:we_repkg/views/backup/backup_tile.dart';
import 'package:we_repkg/views/backup/integrity.dart';
import 'package:we_repkg/widgets/app_icon_button.dart';
import 'package:we_repkg/widgets/folder_input.dart';
import 'package:we_repkg/widgets/selection_tint.dart';

class StubPicker extends FileSelectorPlatform {
  StubPicker(this.answer);
  final String? answer;

  @override
  Future<String?> getDirectoryPath({
    String? initialDirectory,
    String? confirmButtonText,
  }) async => answer;
}

CardFace faceOf(String title) =>
    (title: title, preview: '', type: '', rating: '', modified: null);

BackupScan scanOf({
  Map<BackupCard, BackupState> cards = const <BackupCard, BackupState>{},
  List<ReconcileEntry> reconcile = const <ReconcileEntry>[],
  Set<BackupFolder> missing = const <BackupFolder>{},
}) => (
  cards: cards,
  reconcile: reconcile,
  acfRead: true,
  missing: missing,
  seeds: const <String, String>{},
);

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await StorageUtil.init();
  });

  Future<ProviderContainer> show(WidgetTester tester) async {
    // The scan is stubbed even here, or setting a root would send the real one
    // at whatever this machine has on disk.
    final ProviderContainer container = ProviderContainer(
      overrides: [
        backupScanProvider.overrideWithValue(
          AsyncValue<BackupScan>.data(scanOf()),
        ),
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
    return container;
  }

  /// One frame for the futures, one for the animations. Not pumpAndSettle: a
  /// pill holding wallpapers glows for as long as it is switched off, so there
  /// is nothing to settle.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  String fieldText(WidgetTester tester) =>
      tester.widget<TextField>(find.byType(TextField)).controller!.text;

  // The segmented control keys its children from 1 while the enum indexes from
  // 0, so the off-by-one is only ever a click away from a RangeError.
  testWidgets('the second segment opens the integrity check', (tester) async {
    final ProviderContainer container = await show(tester);

    expect(find.byType(IntegrityView), findsNothing);

    await tester.tap(find.text(AppI10n.backupTabIntegrity));
    await tester.pumpAndSettle();

    expect(container.read(currentBackupTabProvider), BackupTab.integrity);
    expect(find.byType(IntegrityView), findsOneWidget);
  });

  // The tab has to be usable on its own. Without this the only way to set a
  // backup root is to know it lives in the settings card.
  testWidgets('the tab offers a picker when no root is set', (tester) async {
    await show(tester);

    expect(find.byType(FolderInput), findsOneWidget);
    expect(fieldText(tester), isEmpty);
    // tr() returns the raw key here, no localisation is loaded under test.
    expect(find.text(AppI10n.backupNoRoot), findsOneWidget);
  });

  // A root is what the tab needs to say anything, so picking one has to swap
  // the empty state out on the spot rather than at the next restart.
  testWidgets('picking from the tab sets the root', (tester) async {
    FileSelectorPlatform.instance = StubPicker(r'C:\backup');
    final ProviderContainer container = await show(tester);

    await tester.tap(find.byType(AppIconButton));
    await tester.pump();

    expect(container.read(backupRootProvider), r'C:\backup');
    expect(find.byType(FolderInput), findsNothing);
  });

  testWidgets('cancelling the picker leaves the tab unset', (tester) async {
    FileSelectorPlatform.instance = StubPicker(null);
    final ProviderContainer container = await show(tester);

    await tester.tap(find.byType(AppIconButton));
    await tester.pump();

    expect(container.read(backupRootProvider), isNull);
    expect(fieldText(tester), isEmpty);
  });

  group('with a root set', () {
    // The tile list is stubbed too, or the grid would go looking for previews
    // under the fake root on whatever machine this runs on.
    Future<void> showScan(
      WidgetTester tester,
      BackupScan scan, {
      List<BackupTile> tiles = const <BackupTile>[],
    }) => tester.pumpWidget(
      ProviderScope(
        overrides: [
          backupRootProvider.overrideWithValue(r'C:\backup'),
          backupScanProvider.overrideWithValue(
            AsyncValue<BackupScan>.data(scan),
          ),
          backupTilesProvider.overrideWithValue(
            AsyncValue<List<BackupTile>>.data(tiles),
          ),
          // What the grid draws. Overridden beside the unfiltered list rather
          // than derived from it, so a pumped frame does not have to wait on
          // the search filter's own future.
          backupVisibleTilesProvider.overrideWithValue(
            AsyncValue<List<BackupTile>>.data(tiles),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(body: BackupView()),
        ),
      ),
    );

    Finder countOf(String label, int count) => find.text('$label $count');

    testWidgets('every state gets a count, including the empty ones', (
      tester,
    ) async {
      await showScan(
        tester,
        scanOf(
          cards: <BackupCard, BackupState>{
            const BackupCard(WallpaperLibrary.workshop, '793602574'):
                BackupState.vanished,
            const BackupCard(WallpaperLibrary.workshop, '833227004'):
                BackupState.synced,
            const BackupCard(WallpaperLibrary.myProjects, 'alpha'):
                BackupState.synced,
          },
        ),
      );

      expect(countOf(AppI10n.backupStateVanished, 1), findsOneWidget);
      expect(countOf(AppI10n.backupStateSynced, 2), findsOneWidget);
      expect(countOf(AppI10n.backupStateNotBackedUp, 0), findsOneWidget);
      expect(countOf(AppI10n.backupStateUpdateAvailable, 0), findsOneWidget);
      expect(countOf(AppI10n.backupStateUpdateDismissed, 0), findsOneWidget);
      expect(countOf(AppI10n.backupStateEmptyBackup, 0), findsOneWidget);
      expect(countOf(AppI10n.backupReconcile, 0), findsOneWidget);
    });

    // A wallpaper in both libraries is two tiles, and the badge is the only
    // thing telling them apart.
    testWidgets('a tile is drawn per card, named and badged', (tester) async {
      await showScan(
        tester,
        scanOf(),
        tiles: <BackupTile>[
          (
            card: const BackupCard(WallpaperLibrary.workshop, '793602574'),
            state: BackupState.vanished,
            face: faceOf('Neon Alley'),
          ),
          (
            card: const BackupCard(WallpaperLibrary.myProjects, 'Neon Alley'),
            state: BackupState.synced,
            face: faceOf('Neon Alley'),
          ),
        ],
      );

      expect(find.byType(BackupTileView), findsNWidgets(2));
      expect(find.text('Neon Alley'), findsNWidgets(2));
      // The badge carries the label alone; the counts above pair theirs with a
      // number, so these match the tiles and nothing else.
      expect(find.text(AppI10n.backupStateVanished), findsOneWidget);
      expect(find.text(AppI10n.backupStateSynced), findsOneWidget);
      expect(find.text(AppI10n.homeLibraryWorkshop), findsOneWidget);
      expect(find.text(AppI10n.homeLibraryMyProjects), findsOneWidget);
    });

    // A folder with no readable project.json still occupies the backup, and it
    // is exactly the one the integrity tab exists to point at.
    testWidgets('a card with nothing to read falls back to the folder name', (
      tester,
    ) async {
      await showScan(
        tester,
        scanOf(),
        tiles: <BackupTile>[
          (
            card: const BackupCard(WallpaperLibrary.workshop, '793602574'),
            state: BackupState.notBackedUp,
            face: null,
          ),
        ],
      );

      expect(find.text('793602574'), findsOneWidget);
    });

    group('selection', () {
      late ProviderContainer container;

      /// Tiles named so a range reads clearly. Built through a variable rather
      /// than overridden with a fixed value, so a test can take one away and
      /// ask the grid for the list again.
      List<BackupTile> named(List<String> names) => <BackupTile>[
        for (final String name in names)
          (
            card: BackupCard(WallpaperLibrary.workshop, name),
            state: BackupState.vanished,
            face: null,
          ),
      ];

      late List<BackupTile> tiles;

      Future<void> pump(WidgetTester tester) async {
        tiles = named(<String>['a', 'b', 'c', 'd']);
        container = ProviderContainer(
          overrides: [
            backupRootProvider.overrideWithValue(r'C:\backup'),
            backupScanProvider.overrideWithValue(
              AsyncValue<BackupScan>.data(scanOf()),
            ),
            backupTilesProvider.overrideWith((Ref ref) => tiles),
            backupVisibleTilesProvider.overrideWith((Ref ref) => tiles),
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
      }

      /// Long enough after the last one to count as its own click, and long
      /// enough to see off the double tap recogniser's timers.
      Future<void> click(
        WidgetTester tester,
        int index, {
        LogicalKeyboardKey? modifier,
      }) async {
        if (modifier != null) await tester.sendKeyDownEvent(modifier);
        await tester.tap(find.byType(BackupTileView).at(index));
        await tester.pump(kDoubleTapTimeout);
        if (modifier != null) await tester.sendKeyUpEvent(modifier);
      }

      Set<String> selected() => container.read(backupSelectionProvider);

      // Clicking a tile has to reach this grid's own selection, not the extract
      // tab's, or the two would tick each other's wallpapers.
      testWidgets('a plain click takes that tile alone', (tester) async {
        await pump(tester);

        await click(tester, 0);
        expect(selected(), {'workshop/a'});

        await click(tester, 2);
        expect(selected(), {
          'workshop/c',
        }, reason: 'a plain click replaces rather than adds');
        expect(
          container.read(checkedIdsProvider),
          isEmpty,
          reason: 'the extract tab keeps its own selection',
        );
      });

      // Without this the tint is the only thing the user has to go on, and a
      // watch on the whole set would light every tile at once.
      testWidgets('only the clicked tile is tinted', (tester) async {
        await pump(tester);
        expect(find.byKey(SelectionTint.tintKey), findsNothing);

        await click(tester, 1);

        expect(find.byKey(SelectionTint.tintKey), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(BackupTileView).at(1),
            matching: find.byKey(SelectionTint.tintKey),
          ),
          findsOneWidget,
        );
      });

      testWidgets('ctrl adds, and clicking again takes it back off', (
        tester,
      ) async {
        await pump(tester);

        await click(tester, 0);
        await click(tester, 2, modifier: LogicalKeyboardKey.controlLeft);
        expect(selected(), {'workshop/a', 'workshop/c'});

        await click(tester, 0, modifier: LogicalKeyboardKey.controlLeft);
        expect(selected(), {'workshop/c'});
      });

      // So a tile can be deselected without aiming at anything small.
      testWidgets('clicking the only selected tile clears it', (tester) async {
        await pump(tester);

        await click(tester, 1);
        await click(tester, 1);

        expect(selected(), isEmpty);
      });

      // Acting on the second click would clear what the first selected and
      // leave the details open over a blanked tile. No pause between the two
      // here, which is what makes them one double click.
      testWidgets('a double click leaves the tile selected', (tester) async {
        await pump(tester);

        await tester.tap(find.byType(BackupTileView).at(1));
        await tester.pump(kDoubleTapTimeout ~/ 3);
        await tester.tap(find.byType(BackupTileView).at(1));
        await tester.pump(kDoubleTapTimeout);

        expect(selected(), {'workshop/b'});
        // The details the double click asked for open over a folder that is not
        // there, which is fine and is not what this is about; settling here
        // keeps its route and its timers out of the next test.
        await tester.pumpAndSettle();
      });

      // Clicking past the tiles is how a selection is put down without hunting
      // for the one tile that would clear it.
      testWidgets('clicking an empty part of the grid clears the selection', (
        tester,
      ) async {
        await pump(tester);
        await click(tester, 0);
        expect(selected(), isNotEmpty);

        // Below the four tiles, which sit along the top of the viewport, and
        // off to the left of the scroll-to-bottom zone.
        await tester.tapAt(const Offset(120, 520));
        await tester.pump(kDoubleTapTimeout);

        expect(selected(), isEmpty);
      });

      // Same button, same empty spot: whether the mouse twitched past the drag
      // threshold used to decide whether the selection survived.
      testWidgets('a drag over empty space clears the selection too', (
        tester,
      ) async {
        await pump(tester);
        await click(tester, 0);

        await tester.dragFrom(const Offset(120, 520), const Offset(60, 40));
        await tester.pump(kDoubleTapTimeout);

        expect(selected(), isEmpty);
      });

      // The anchor outlived the selection, so a shift click after clearing
      // reached back to a tile nothing was selected from.
      testWidgets('shift after clearing starts from the top', (tester) async {
        await pump(tester);
        await click(tester, 3);

        await tester.tapAt(const Offset(120, 520));
        await tester.pump(kDoubleTapTimeout);
        await click(tester, 1, modifier: LogicalKeyboardKey.shiftLeft);

        expect(selected(), {'workshop/a', 'workshop/b'});
      });

      // The anchor is an id, not a position, so re-ordering the grid cannot
      // leave it pointing at whatever took that place.
      testWidgets('shift reaches back to the same tile after a re-order', (
        tester,
      ) async {
        await pump(tester);
        // Anchored on 'd', which is not the tile the fallback would pick: that
        // is the last selected one in list order, and after the re-order below
        // it is 'a' at the other end.
        await click(tester, 0, modifier: LogicalKeyboardKey.controlLeft);
        await click(tester, 3, modifier: LogicalKeyboardKey.controlLeft);

        tiles = named(<String>['d', 'c', 'b', 'a']);
        container.invalidate(backupTilesProvider);
        container.invalidate(backupVisibleTilesProvider);
        await tester.pumpAndSettle();

        await click(tester, 2, modifier: LogicalKeyboardKey.shiftLeft);

        expect(
          selected(),
          {'workshop/d', 'workshop/c', 'workshop/b'},
          reason: 'from the anchor at d, not from the last selected at a',
        );
      });

      // Its own anchor, held in this grid rather than in the app-wide setting
      // the extract grid uses, or the two would reach into each other's list.
      testWidgets('shift reaches back to the last click', (tester) async {
        await pump(tester);

        await click(tester, 3, modifier: LogicalKeyboardKey.controlLeft);
        await click(tester, 1, modifier: LogicalKeyboardKey.controlLeft);
        expect(selected(), {'workshop/b', 'workshop/d'});

        // From the anchor at 1, not from the last selected tile at 3.
        await click(tester, 2, modifier: LogicalKeyboardKey.shiftLeft);
        expect(selected(), {'workshop/b', 'workshop/c'});
      });

      // A marquee sets no anchor, so shift after one has to find its own start.
      testWidgets('shift with no anchor reaches from the last selected', (
        tester,
      ) async {
        await pump(tester);
        container.read(backupSelectionProvider.notifier).setExactly({
          'workshop/b',
        });
        await tester.pump();

        await click(tester, 3, modifier: LogicalKeyboardKey.shiftLeft);

        expect(selected(), {'workshop/b', 'workshop/c', 'workshop/d'});
      });

      // A rescan can drop a card. Left behind, its id is invisible: no tile
      // draws it and no click can clear it, but Delete would still act on it.
      testWidgets('a card that leaves the grid leaves the selection', (
        tester,
      ) async {
        await pump(tester);
        await click(tester, 0);
        await click(tester, 2, modifier: LogicalKeyboardKey.controlLeft);
        expect(selected(), {'workshop/a', 'workshop/c'});

        tiles = named(<String>['a', 'b', 'd']);
        container.invalidate(backupTilesProvider);
        container.invalidate(backupVisibleTilesProvider);
        await tester.pump();

        expect(selected(), {'workshop/a'});
      });
    });

    // Through the real providers, so what is drawn is the pipeline's answer
    // rather than a stub's.
    group('pills', () {
      late ProviderContainer container;

      Future<void> pumpPills(
        WidgetTester tester, {
        List<BackupTile> tiles = const <BackupTile>[],
        List<ReconcileTile> reconcile = const <ReconcileTile>[],
      }) async {
        container = ProviderContainer(
          overrides: [
            backupRootProvider.overrideWithValue(r'C:\backup'),
            backupScanProvider.overrideWithValue(
              AsyncValue<BackupScan>.data(
                scanOf(
                  cards: <BackupCard, BackupState>{
                    for (final BackupTile tile in tiles) tile.card: tile.state,
                  },
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

      ReconcileTile orphan() => (
        entry: const ReconcileEntry(
          name: 'muddled',
          states: <WallpaperLibrary, BackupState>{
            WallpaperLibrary.myProjects: BackupState.synced,
          },
          backupWorkshop: true,
          backupMyProjects: false,
        ),
        face: null,
      );

      Future<void> tapPill(WidgetTester tester, String label, int count) async {
        await tester.tap(find.text('$label $count'));
        await settle(tester);
      }

      // The one state with an obvious next step. The rest glow for themselves.
      testWidgets('the grid opens on the wallpapers that are not backed up', (
        tester,
      ) async {
        await pumpPills(tester, tiles: three());

        expect(find.byType(BackupTileView), findsOneWidget);
        expect(find.text('fresh'), findsOneWidget);
      });

      testWidgets('a pill switched on brings its wallpapers back', (
        tester,
      ) async {
        await pumpPills(tester, tiles: three());

        await tapPill(tester, AppI10n.backupStateVanished, 1);

        expect(find.byType(BackupTileView), findsNWidgets(2));
      });

      testWidgets('a pill switched off takes its wallpapers away', (
        tester,
      ) async {
        await pumpPills(tester, tiles: three());

        await tapPill(tester, AppI10n.backupStateNotBackedUp, 1);

        expect(find.byType(BackupTileView), findsNothing);
      });

      // Not a filter beside the others: a question about a name rather than a
      // state of a card, so it takes the grid over.
      testWidgets('the reconcile pill swaps the grid over', (tester) async {
        await pumpPills(
          tester,
          tiles: three(),
          reconcile: <ReconcileTile>[orphan()],
        );

        await tapPill(tester, AppI10n.backupReconcile, 1);

        expect(find.byType(ReconcileTileView), findsOneWidget);
        expect(find.byType(BackupTileView), findsNothing);
        expect(find.text('muddled'), findsOneWidget);
      });

      // They all read as off while it has the grid, so lighting one has to mean
      // "show me that state".
      testWidgets('a state pill takes the grid back from reconcile', (
        tester,
      ) async {
        await pumpPills(
          tester,
          tiles: three(),
          reconcile: <ReconcileTile>[orphan()],
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

        await tapPill(tester, AppI10n.backupStateNotBackedUp, 1);

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
          reconcile: <ReconcileTile>[orphan()],
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

      // Off the way it came on: the state pills keep what they had, so the grid
      // lands back where it left rather than empty.
      testWidgets('the reconcile pill puts the grid back', (tester) async {
        await pumpPills(
          tester,
          tiles: three(),
          reconcile: <ReconcileTile>[orphan()],
        );
        await tapPill(tester, AppI10n.backupReconcile, 1);

        await tapPill(tester, AppI10n.backupReconcile, 1);

        expect(find.byType(ReconcileTileView), findsNothing);
        expect(find.text('fresh'), findsOneWidget);
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
      testWidgets('the extract tab\'s filter reaches this grid', (
        tester,
      ) async {
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

    // Reconcile entries are not cards, so they are counted apart or the tab
    // would report nothing about the names waiting to be sorted out.
    testWidgets('reconcile entries carry their own count', (tester) async {
      await showScan(
        tester,
        scanOf(
          reconcile: const <ReconcileEntry>[
            ReconcileEntry(
              name: '793602574',
              states: <WallpaperLibrary, BackupState>{
                WallpaperLibrary.myProjects: BackupState.synced,
              },
              backupWorkshop: true,
              backupMyProjects: true,
            ),
          ],
        ),
      );

      expect(countOf(AppI10n.backupReconcile, 1), findsOneWidget);
    });

    // A folder the scan could not read does not make the counts incomplete, it
    // makes them wrong: a missing live library turns every backup folder into a
    // vanished card. Showing them anyway is the failure this whole tab exists
    // to prevent.
    testWidgets('an unreadable folder replaces the counts, not joins them', (
      tester,
    ) async {
      await showScan(
        tester,
        scanOf(
          missing: const <BackupFolder>{BackupFolder.liveMyProjects},
          cards: <BackupCard, BackupState>{
            const BackupCard(WallpaperLibrary.workshop, '793602574'):
                BackupState.vanished,
          },
        ),
      );

      expect(find.text(AppI10n.backupMissingFolders), findsOneWidget);
      expect(find.text(AppI10n.backupStateVanished), findsNothing);
      expect(find.byIcon(Icons.refresh_rounded), findsNothing);
    });

    testWidgets('each missing folder is named, and only the missing ones', (
      tester,
    ) async {
      await showScan(
        tester,
        scanOf(
          missing: const <BackupFolder>{
            BackupFolder.liveWorkshop,
            BackupFolder.backupRoot,
          },
        ),
      );

      // The path comes with the label, so the row says which folder it looked
      // in rather than only that one was wrong.
      expect(
        find.textContaining(AppI10n.backupFolderLiveWorkshop),
        findsOneWidget,
      );
      expect(
        find.textContaining(AppI10n.backupFolderBackupRoot),
        findsOneWidget,
      );
      expect(
        find.textContaining(AppI10n.backupFolderLiveMyProjects),
        findsNothing,
      );
    });

    // The only visible signal that a library could not be read at all.
    testWidgets('a failed scan says so rather than showing nothing', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            backupRootProvider.overrideWithValue(r'C:\backup'),
            backupScanProvider.overrideWithValue(
              AsyncValue<BackupScan>.error(
                const FileSystemException('access denied'),
                StackTrace.empty,
              ),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const Scaffold(body: BackupView()),
          ),
        ),
      );

      expect(find.textContaining(AppI10n.backupScanFailed), findsOneWidget);
    });

    // The kept-alive scan does not notice the filesystem moving under it, so
    // this button is the only way to ask for fresh numbers.
    testWidgets('rescan runs the comparison again', (tester) async {
      int builds = 0;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            backupRootProvider.overrideWithValue(r'C:\backup'),
            backupScanProvider.overrideWith((Ref ref) {
              builds++;
              return scanOf();
            }),
          ],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const Scaffold(body: BackupView()),
          ),
        ),
      );
      await tester.pump();
      expect(builds, 1);

      await tester.tap(find.byIcon(Icons.refresh_rounded));
      await tester.pump();

      expect(builds, 2);
    });
  });
}
