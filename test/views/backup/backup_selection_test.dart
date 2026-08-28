import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:we_repkg/config/theme.dart';
import 'package:we_repkg/cores/backup.dart';
import 'package:we_repkg/provider/backup.dart';
import 'package:we_repkg/provider/system.dart';
import 'package:we_repkg/provider/wallpaper.dart';
import 'package:we_repkg/utils/backup_diff.dart';
import 'package:we_repkg/utils/backup_tiles.dart';
import 'package:we_repkg/utils/storage.dart';
import 'package:we_repkg/views/backup/backup.dart';
import 'package:we_repkg/views/backup/backup_tile.dart';
import 'package:we_repkg/widgets/selection_grid.dart';
import 'package:we_repkg/widgets/tile_overlays.dart';

import '../../support/backup_test_harness.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await StorageUtil.init();
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

    Future<void> pump(
      WidgetTester tester, {
      List<String> names = const <String>['a', 'b', 'c', 'd'],
    }) async {
      tiles = named(names);
      container = ProviderContainer(
        overrides: [
          backupRootProvider.overrideWithValue(r'C:\backup'),
          backupScanProvider.overrideWithValue(
            AsyncValue<BackupScan>.data(scanOf()),
          ),
          backupTilesProvider.overrideWith((Ref ref) => tiles),
          backupVisibleTilesProvider.overrideWith(
            (Ref ref) => AsyncValue<List<BackupTile>>.data(tiles),
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

    Offset emptyGridPoint(WidgetTester tester) {
      final Rect grid = tester.getRect(find.byType(SelectionGrid));
      final Rect lastTile = tester.getRect(find.byType(BackupTileView).last);
      final Offset point = Offset(grid.left + 40, lastTile.bottom + 20);
      expect(
        grid.contains(point),
        isTrue,
        reason: 'the selection test needs empty grid space below the tiles',
      );
      return point;
    }

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
      expect(
        find.descendant(
          of: find.byKey(SelectionTint.tintKey),
          matching: find.byIcon(Icons.check_rounded),
        ),
        findsOneWidget,
        reason: 'the tick says which tiles are picked at a glance',
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
      // Do not use pumpAndSettle here. Backup actions deliberately keep a
      // pulse running, so there is no settled frame to wait for.
      await tester.pump(const Duration(milliseconds: 400));
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
      await tester.tapAt(emptyGridPoint(tester));
      await tester.pump(kDoubleTapTimeout);

      expect(selected(), isEmpty);
    });

    // Empty-space clearing must be the same whether the pointer stays a click
    // or crosses the drag threshold.
    testWidgets('a drag over empty space clears the selection too', (
      tester,
    ) async {
      await pump(tester);
      await click(tester, 0);

      await tester.dragFrom(emptyGridPoint(tester), const Offset(60, 40));
      await tester.pump(kDoubleTapTimeout);

      expect(selected(), isEmpty);
    });

    // The anchor outlived the selection, so a shift click after clearing
    // reached back to a tile nothing was selected from.
    testWidgets('shift after clearing starts from the top', (tester) async {
      await pump(tester);
      await click(tester, 3);

      await tester.tapAt(emptyGridPoint(tester));
      await tester.pump(kDoubleTapTimeout);
      await click(tester, 1, modifier: LogicalKeyboardKey.shiftLeft);

      expect(selected(), {'workshop/a', 'workshop/b'});
    });

    // Backup shares the grid reflow behavior, so a sort change should animate
    // existing tiles to their new cells rather than snapping them.
    testWidgets('a re-order slides the tiles rather than snapping them', (
      tester,
    ) async {
      await pump(tester);
      // Out of the entrance, which starts a frame after the grid appears, so
      // what moves below is the reflow.
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      final Rect before = tester.getRect(find.byType(BackupTileView).first);

      tiles = named(<String>['d', 'c', 'b', 'a']);
      container.invalidate(backupTilesProvider);
      container.invalidate(backupVisibleTilesProvider);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));

      final Rect moving = tester.getRect(find.byType(BackupTileView).first);
      expect(moving, isNot(before), reason: 'still on its way');

      await tester.pump(const Duration(milliseconds: 400));

      expect(tester.getRect(find.byType(BackupTileView).first), before);
    });

    // Typing a search term moves a few tiles one place and the rest of them
    // half the library. Sliding the short movers while the long ones fade is
    // what read as the animation firing at random.
    testWidgets('a list that moves a long way fades all of it, not some', (
      tester,
    ) async {
      final List<String> many = <String>[for (int i = 0; i < 40; i++) 'w$i'];
      await pump(tester, names: many);
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      final Offset resting = tester
          .getRect(find.byType(BackupTileView).at(1))
          .center;

      // Every tile shifts one place, and the last one is carried to the
      // front, which is further than a slide can read as movement.
      tiles = named(<String>[many.last, ...many.take(many.length - 1)]);
      container.invalidate(backupTilesProvider);
      container.invalidate(backupVisibleTilesProvider);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));

      final Finder shortMover = find.byType(BackupTileView).at(1);
      expect(
        tester.getRect(shortMover).center,
        resting,
        reason: 'it grows into place rather than sliding one cell',
      );
      expect(
        tester
            .widget<Opacity>(
              find
                  .ancestor(of: shortMover, matching: find.byType(Opacity))
                  .first,
            )
            .opacity,
        lessThan(1),
      );
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
      await settle(tester);

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

    testWidgets('ctrl+shift adds the anchor range', (tester) async {
      await pump(tester);
      await click(tester, 0, modifier: LogicalKeyboardKey.controlLeft);
      await click(tester, 3, modifier: LogicalKeyboardKey.controlLeft);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      addTearDown(() => tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft));
      await click(tester, 1, modifier: LogicalKeyboardKey.shiftLeft);

      expect(selected(), {
        'workshop/a',
        'workshop/b',
        'workshop/c',
        'workshop/d',
      });
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
      await settle(tester);

      expect(selected(), {'workshop/a'});
    });
  });
}
