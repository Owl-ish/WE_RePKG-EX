import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:we_repkg/config/theme.dart';
import 'package:we_repkg/config/theme_extensions.dart';
import 'package:we_repkg/constants/i10n.dart';
import 'package:we_repkg/constants/nums.dart';
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
import 'package:we_repkg/utils/wallpaper_junk.dart';
import 'package:we_repkg/views/backup/backup.dart';
import 'package:we_repkg/views/backup/backup_action.dart';
import 'package:we_repkg/views/backup/backup_tile.dart';
import 'package:we_repkg/views/backup/integrity.dart';
import 'package:we_repkg/views/states/no_results.dart';
import 'package:we_repkg/widgets/app_icon_button.dart';
import 'package:we_repkg/widgets/count_pill.dart';
import 'package:we_repkg/widgets/folder_input.dart';
import 'package:we_repkg/widgets/selection_grid.dart';
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
  Map<String, ({bool live, bool backup, WallpaperJunkKind kind})> junk =
      const <String, ({bool live, bool backup, WallpaperJunkKind kind})>{},
  List<ReconcileEntry> reconcile = const <ReconcileEntry>[],
  Set<BackupFolder> missing = const <BackupFolder>{},
}) => (
  cards: cards,
  presence: <String, ({bool live, bool backup})>{
    for (final MapEntry<BackupCard, BackupState> entry in cards.entries)
      entry.key.id: (
        live: entry.value != BackupState.vanished,
        backup: entry.value != BackupState.notBackedUp,
      ),
  },
  junk: junk,
  reconcile: reconcile,
  acfRead: true,
  missing: missing,
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

  // A rescan puts the whole tab back to waiting, and a bare spinner there says
  // nothing about a job that takes ten seconds.
  group('while it is working', () {
    Future<void> waiting(
      WidgetTester tester,
      ProviderContainer container,
    ) async {
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
      await tester.pump();
    }

    double? barValue(WidgetTester tester) => tester
        .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
        .value;

    testWidgets('the scan keeps native comparison feedback animated', (
      tester,
    ) async {
      final ProviderContainer container = ProviderContainer(
        overrides: [
          backupRootProvider.overrideWithValue(r'C:\backup'),
          backupScanProvider.overrideWith(
            (Ref ref) => Completer<BackupScan>().future,
          ),
        ],
      );
      await waiting(tester, container);

      expect(find.text(AppI10n.backupScanReading), findsOneWidget);
      expect(
        find.byType(CircularProgressIndicator),
        findsOneWidget,
        reason: 'the animation is above the line, so the line stays put',
      );
      expect(barValue(tester), isNull, reason: 'nothing to count yet');

      container.read(backupScanProgressProvider).value = (
        phase: BackupScanPhase.comparing,
        done: 30,
        total: 120,
      );
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text(AppI10n.backupScanComparing), findsOneWidget);
      expect(
        barValue(tester),
        isNull,
        reason:
            'native comparison completes as one batch, so fake progress would freeze',
      );

      container.read(backupScanProgressProvider).value = (
        phase: BackupScanPhase.finishing,
        done: 120,
        total: 120,
      );
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text(AppI10n.backupScanFinishing), findsOneWidget);
      expect(barValue(tester), isNull);
    });

    // A rescan does not cancel the one running, and both write their progress
    // into the same line.
    testWidgets('the rescan button is off while a scan runs', (tester) async {
      // The second scan is left running, which is the state a user is in the
      // moment they press the button.
      Completer<BackupScan> scan = Completer<BackupScan>()..complete(scanOf());
      final ProviderContainer container = ProviderContainer(
        overrides: [
          backupRootProvider.overrideWithValue(r'C:\backup'),
          backupScanProvider.overrideWith((Ref ref) => scan.future),
        ],
      );
      await waiting(tester, container);

      scan = Completer<BackupScan>();
      container.invalidate(backupScanProvider);
      await tester.pump();

      expect(
        tester
            .widget<AppIconButton>(
              find.widgetWithIcon(AppIconButton, Icons.refresh_rounded),
            )
            .onPressed,
        isNull,
      );
    });

    testWidgets('tile preparation stays in the same loading phase', (
      tester,
    ) async {
      final ProviderContainer container = ProviderContainer(
        overrides: [
          backupRootProvider.overrideWithValue(r'C:\backup'),
          backupScanProvider.overrideWithValue(
            AsyncValue<BackupScan>.data(scanOf()),
          ),
          backupVisibleTilesProvider.overrideWith(
            (Ref ref) => const AsyncValue<List<BackupTile>>.loading(),
          ),
        ],
      );
      await waiting(tester, container);

      expect(find.text(AppI10n.backupPreparingGrid), findsOneWidget);
      expect(find.text(AppI10n.backupReadingDetails), findsNothing);
      expect(find.text(AppI10n.backupReadingDetailsCount), findsNothing);
      expect(barValue(tester), isNull);
    });
  });

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

  testWidgets('opening Integrity does not start the backup scan', (
    tester,
  ) async {
    int builds = 0;
    final ProviderContainer container = ProviderContainer(
      overrides: [
        currentBackupTabProvider.overrideWithValue(BackupTab.integrity),
        backupRootProvider.overrideWithValue(r'C:\backup'),
        backupScanProvider.overrideWith((Ref ref) {
          builds++;
          return scanOf();
        }),
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
    await tester.pump();

    expect(find.byType(IntegrityView), findsOneWidget);
    expect(builds, 0);
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

  testWidgets('finishing a scan does not change a pill during build', (
    WidgetTester tester,
  ) async {
    final Completer<BackupScan> scan = Completer<BackupScan>();
    const BackupTile tile = (
      card: BackupCard(WallpaperLibrary.workshop, 'safe'),
      state: BackupState.synced,
      face: null,
    );
    final ProviderContainer container = ProviderContainer(
      overrides: [
        backupRootProvider.overrideWithValue(r'C:\backup'),
        backupScanProvider.overrideWith((Ref ref) => scan.future),
        backupTilesProvider.overrideWith((Ref ref) => <BackupTile>[tile]),
        backupReconcileTilesProvider.overrideWith(
          (Ref ref) => const <ReconcileTile>[],
        ),
      ],
    );
    addTearDown(container.dispose);
    container.read(backupStateFilterProvider);
    scan.complete(
      scanOf(
        cards: <BackupCard, BackupState>{
          const BackupCard(WallpaperLibrary.workshop, 'safe'):
              BackupState.synced,
        },
      ),
    );
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

    expect(tester.takeException(), isNull);
    expect(container.read(backupStateFilterProvider).state, BackupState.synced);
  });

  group('with a root set', () {
    // The tile list is stubbed too, or the grid would go looking for previews
    // under the fake root on whatever machine this runs on.
    Future<void> showScan(
      WidgetTester tester,
      BackupScan scan, {
      List<BackupTile> tiles = const <BackupTile>[],
      String? workshopPath,
    }) => tester.pumpWidget(
      ProviderScope(
        overrides: [
          backupRootProvider.overrideWithValue(r'C:\backup'),
          if (workshopPath != null)
            wallpaperPathProvider.overrideWithValue(workshopPath),
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

    testWidgets(
      'bulk and circular tile actions use the shared glow treatment',
      (tester) async {
        const BackupCard card = BackupCard(WallpaperLibrary.workshop, 'gone');
        await showScan(
          tester,
          scanOf(cards: <BackupCard, BackupState>{card: BackupState.vanished}),
          tiles: <BackupTile>[
            (card: card, state: BackupState.vanished, face: faceOf('Gone')),
          ],
        );
        await settle(tester);

        final Finder bulkGlow = find.byKey(
          const ValueKey<String>('backup-all-action-glow'),
        );
        final Finder tileGlow = find.byKey(
          const ValueKey<String>('backup-tile-action-glow'),
        );
        expect(bulkGlow, findsOneWidget);
        expect(tileGlow, findsOneWidget);

        final Finder bulkWrapper = find.ancestor(
          of: bulkGlow,
          matching: find.byType(BackupActionGlow),
        );
        final Finder tileWrapper = find.ancestor(
          of: tileGlow,
          matching: find.byType(BackupActionGlow),
        );
        expect(bulkWrapper, findsOneWidget);
        expect(tileWrapper, findsOneWidget);

        final BackupActionGlow bulk = tester.widget<BackupActionGlow>(
          bulkWrapper,
        );
        final BackupActionGlow tile = tester.widget<BackupActionGlow>(
          tileWrapper,
        );
        expect(bulk.enabled, isTrue);
        expect(tile.enabled, isTrue);
        expect(bulk.scale, 1);
        expect(tile.scale, .7);

        final BuildContext bulkContext = tester.element(bulkWrapper);
        expect(
          bulk.colour,
          backupStateLook(bulkContext, BackupState.vanished).colour,
        );

        final Finder circularMaterial = find.descendant(
          of: tileGlow,
          matching: find.byWidgetPredicate(
            (Widget widget) =>
                widget is Material && widget.shape is CircleBorder,
          ),
        );
        final Finder circularButton = find.descendant(
          of: tileGlow,
          matching: find.byType(AppIconButton),
        );
        expect(circularMaterial, findsOneWidget);
        expect(circularButton, findsOneWidget);
        final AppIconButton button = tester.widget<AppIconButton>(
          circularButton,
        );
        expect(button.color, isNotNull);
        expect(tile.colour, button.color);
      },
    );

    testWidgets('Empty/Junk exposes only the folder that needs cleanup', (
      tester,
    ) async {
      const BackupCard card = BackupCard(
        WallpaperLibrary.workshop,
        'junk-live',
      );
      await showScan(
        tester,
        scanOf(
          cards: <BackupCard, BackupState>{card: BackupState.emptyBackup},
          junk:
              const <
                String,
                ({bool live, bool backup, WallpaperJunkKind kind})
              >{
                'workshop/junk-live': (
                  live: true,
                  backup: false,
                  kind: WallpaperJunkKind.empty,
                ),
              },
        ),
        tiles: <BackupTile>[
          (card: card, state: BackupState.emptyBackup, face: null),
        ],
        workshopPath: r'C:\workshop',
      );

      final BackupTileView tile = tester.widget<BackupTileView>(
        find.byType(BackupTileView),
      );
      expect(tile.folders.live, r'C:\workshop\junk-live');
      expect(tile.folders.backup, isNull);
    });

    testWidgets('Empty/Junk groups empty and shader-cache folders separately', (
      tester,
    ) async {
      const BackupCard empty = BackupCard(WallpaperLibrary.workshop, 'empty');
      const BackupCard shader = BackupCard(WallpaperLibrary.workshop, 'shader');
      final List<BackupTile> tiles = <BackupTile>[
        (card: empty, state: BackupState.emptyBackup, face: null),
        (card: shader, state: BackupState.emptyBackup, face: null),
      ];
      await showScan(
        tester,
        scanOf(
          cards: <BackupCard, BackupState>{
            empty: BackupState.emptyBackup,
            shader: BackupState.emptyBackup,
          },
          junk:
              const <
                String,
                ({bool live, bool backup, WallpaperJunkKind kind})
              >{
                'workshop/empty': (
                  live: true,
                  backup: false,
                  kind: WallpaperJunkKind.empty,
                ),
                'workshop/shader': (
                  live: true,
                  backup: false,
                  kind: WallpaperJunkKind.shaderCacheOnly,
                ),
              },
        ),
        tiles: tiles,
        workshopPath: r'C:\workshop',
      );
      await settle(tester);

      final Finder junkGrid = find.byKey(
        const ValueKey<String>('backup-junk-grid'),
      );
      expect(junkGrid, findsOneWidget);

      void expectMountedGroup({
        required WallpaperJunkKind kind,
        required String title,
        required String about,
        required String tileId,
      }) {
        final Finder issueNote = find.byKey(
          ValueKey<String>('backup-junk-note-${kind.name}'),
        );
        final Finder tileFinder = find.byKey(ValueKey<String>(tileId));
        expect(issueNote, findsOneWidget);
        expect(tileFinder, findsOneWidget);

        // Anchor every assertion to this group's own sliver header. A
        // CustomScrollView may unmount the other group's header or tile while
        // scrolling, so global first/second widget positions are not stable.
        final Finder groupHeader = find.ancestor(
          of: issueNote,
          matching: find.byType(SliverToBoxAdapter),
        );
        expect(groupHeader, findsOneWidget);

        final Finder actionGlow = find.descendant(
          of: groupHeader,
          matching: find.byKey(
            const ValueKey<String>('backup-all-action-glow'),
          ),
        );
        final Finder actionLabel = find.descendant(
          of: groupHeader,
          matching: find.text(AppI10n.backupActionRecycleAll),
        );
        final Finder noteTextFinder = find.descendant(
          of: issueNote,
          matching: find.byWidgetPredicate(
            (Widget widget) => widget is Text && widget.textSpan != null,
          ),
        );

        expect(actionGlow, findsOneWidget);
        expect(actionLabel, findsOneWidget);
        expect(noteTextFinder, findsOneWidget);
        final Text noteText = tester.widget<Text>(noteTextFinder);
        expect(noteText.textSpan!.toPlainText(), '$title - $about');
        expect(noteText.maxLines, 2);
        expect(tester.getSize(issueNote).height, lessThanOrEqualTo(48));
        expect(
          tester.getTopLeft(actionLabel).dy,
          lessThan(tester.getTopLeft(issueNote).dy),
        );
        expect(
          tester.getBottomLeft(issueNote).dy,
          lessThan(tester.getTopLeft(tileFinder).dy),
        );
      }

      // Each group is checked only while its own tile is mounted. The second
      // SliverGrid is lazy, so scrolling to it is part of the behavior under
      // test rather than something the assertions should pretend does not
      // exist.
      expectMountedGroup(
        kind: WallpaperJunkKind.empty,
        title: AppI10n.backupJunkEmptyTitle,
        about: AppI10n.backupJunkEmptyAbout,
        tileId: 'workshop/empty',
      );

      await tester.drag(junkGrid, const Offset(0, -600));
      await settle(tester);

      expectMountedGroup(
        kind: WallpaperJunkKind.shaderCacheOnly,
        title: AppI10n.backupJunkShaderTitle,
        about: AppI10n.backupJunkShaderAbout,
        tileId: 'workshop/shader',
      );
    });

    testWidgets(
      'Empty/Junk callouts stay wide and recycle actions match the grid edge',
      (tester) async {
        tester.view.physicalSize = const Size(1440, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        const BackupCard card = BackupCard(WallpaperLibrary.workshop, 'empty');
        await showScan(
          tester,
          scanOf(
            cards: <BackupCard, BackupState>{card: BackupState.emptyBackup},
            junk:
                const <
                  String,
                  ({bool live, bool backup, WallpaperJunkKind kind})
                >{
                  'workshop/empty': (
                    live: true,
                    backup: false,
                    kind: WallpaperJunkKind.empty,
                  ),
                },
          ),
          tiles: const <BackupTile>[
            (card: card, state: BackupState.emptyBackup, face: null),
          ],
          workshopPath: r'C:\workshop',
        );
        await settle(tester);

        final Finder junkGrid = find.byKey(
          const ValueKey<String>('backup-junk-grid'),
        );
        final Finder issueNote = find.byKey(
          const ValueKey<String>('backup-junk-note-empty'),
        );
        final Finder groupHeader = find.ancestor(
          of: issueNote,
          matching: find.byType(SliverToBoxAdapter),
        );
        final Finder actionGlow = find.descendant(
          of: groupHeader,
          matching: find.byKey(
            const ValueKey<String>('backup-all-action-glow'),
          ),
        );
        final Finder actionMaterial = find.descendant(
          of: actionGlow,
          matching: find.byType(Material),
        );
        final Finder actionLabel = find.descendant(
          of: actionGlow,
          matching: find.text(AppI10n.backupActionRecycleAll),
        );

        expect(junkGrid, findsOneWidget);
        expect(groupHeader, findsOneWidget);
        expect(issueNote, findsOneWidget);
        expect(actionGlow, findsOneWidget);
        expect(actionMaterial, findsOneWidget);
        expect(actionLabel, findsOneWidget);

        final double noteWidth = tester.getSize(issueNote).width;
        final double gridWidth = tester.getSize(junkGrid).width;
        expect(noteWidth, greaterThan(1000));
        expect(noteWidth, lessThanOrEqualTo(1100));
        expect(noteWidth, greaterThan(gridWidth * .7));
        expect(noteWidth, lessThan(gridWidth * .82));
        expect(
          tester.getTopLeft(issueNote).dx,
          closeTo(tester.getTopLeft(junkGrid).dx, 1),
        );
        expect(
          tester.getTopRight(actionGlow).dx,
          closeTo(tester.getTopRight(junkGrid).dx, 1),
        );
        expect(
          tester.getBottomLeft(actionGlow).dy,
          lessThan(tester.getTopLeft(issueNote).dy),
        );

        final Finder noteTextFinder = find.descendant(
          of: issueNote,
          matching: find.byWidgetPredicate(
            (Widget widget) => widget is Text && widget.textSpan != null,
          ),
        );
        expect(noteTextFinder, findsOneWidget);
        final Text noteText = tester.widget<Text>(noteTextFinder);
        expect(noteText.maxLines, 2);
        expect(tester.getSize(issueNote).height, lessThanOrEqualTo(48));

        final Material material = tester.widget<Material>(actionMaterial);
        final BuildContext actionContext = tester.element(actionMaterial);
        final ActionButtonTheme actionColors = Theme.of(
          actionContext,
        ).actionButtons;
        expect(material.color, actionColors.destructiveBackground);
        final RoundedRectangleBorder shape =
            material.shape! as RoundedRectangleBorder;
        expect(shape.side.color, actionColors.destructiveBorder);
        expect(shape.side.width, lessThanOrEqualTo(1.1));
        final Text label = tester.widget<Text>(actionLabel);
        expect(label.style?.fontWeight, isNull);
        expect(label.style?.color, actionColors.destructiveForeground);
      },
    );

    test('Empty/Junk labels stay compact in both translations', () {
      final Map<String, dynamic> english =
          jsonDecode(File('assets/translations/en-US.json').readAsStringSync())
              as Map<String, dynamic>;
      final Map<String, dynamic> chinese =
          jsonDecode(File('assets/translations/zh-CN.json').readAsStringSync())
              as Map<String, dynamic>;

      expect(english['backup']['junk']['emptyTitle'], 'Empty Folders');
      expect(
        english['backup']['action']['recycleAll'],
        'Recycle Bin All ({count})',
      );
      expect(chinese['backup']['junk']['emptyTitle'], '空文件夹');
      expect(chinese['backup']['action']['recycleAll'], '全部移到回收站（{count}）');
    });

    testWidgets(
      'double-clicking Empty/Junk keeps rich details and shows its file tree',
      (tester) async {
        // Widget tests run in FakeAsync. Keep real filesystem setup out of
        // that async scheduler or the test can wait forever before the first
        // widget interaction.
        final Directory workshop = Directory.systemTemp.createTempSync(
          'we_repkg_junk_detail',
        );
        addTearDown(() {
          if (workshop.existsSync()) workshop.deleteSync(recursive: true);
        });
        final Directory cache = Directory(
          '${workshop.path}${Platform.pathSeparator}shader'
          '${Platform.pathSeparator}shaders${Platform.pathSeparator}blobssm40',
        );
        cache.createSync(recursive: true);
        File(
          '${cache.path}${Platform.pathSeparator}cache.dxs',
        ).writeAsStringSync('generated shader data');

        const BackupCard card = BackupCard(WallpaperLibrary.workshop, 'shader');
        await showScan(
          tester,
          scanOf(
            cards: <BackupCard, BackupState>{card: BackupState.emptyBackup},
            junk:
                const <
                  String,
                  ({bool live, bool backup, WallpaperJunkKind kind})
                >{
                  'workshop/shader': (
                    live: true,
                    backup: false,
                    kind: WallpaperJunkKind.shaderCacheOnly,
                  ),
                },
          ),
          tiles: const <BackupTile>[
            (card: card, state: BackupState.emptyBackup, face: null),
          ],
          workshopPath: workshop.path,
        );
        await settle(tester);

        final Finder tile = find.byType(BackupTileView);
        await tester.tap(tile);
        await tester.pump(const Duration(milliseconds: 100));
        await tester.tap(tile);

        // The details read and each tree expansion use real filesystem
        // futures. Give those futures short real-async windows, then pump the
        // widget tree. Do not use pumpAndSettle because this screen has an
        // intentional continuous glow animation.
        Future<bool> waitFor(Finder finder) async {
          for (int attempt = 0; attempt < 40; attempt++) {
            if (finder.evaluate().isNotEmpty) return true;
            await tester.runAsync(() async {
              await Future<void>.delayed(const Duration(milliseconds: 25));
            });
            await tester.pump(const Duration(milliseconds: 50));
          }
          return finder.evaluate().isNotEmpty;
        }

        final Finder treeFinder = find.byKey(
          const ValueKey<String>('backup-junk-file-tree'),
        );
        await waitFor(treeFinder);

        final bool hasRichActions = find
            .byKey(const ValueKey<String>('wallpaper-detail-actions'))
            .evaluate()
            .isNotEmpty;
        final bool usedPlainAlert = find
            .byType(AlertDialog)
            .evaluate()
            .isNotEmpty;
        final bool hasExplanation = find
            .text(AppI10n.backupJunkDetailsShader)
            .evaluate()
            .isNotEmpty;
        final bool hasTree = treeFinder.evaluate().isNotEmpty;
        final bool showedNestedFolder =
            hasTree && await waitFor(find.text('blobssm40'));
        final bool showedFile =
            hasTree && await waitFor(find.text('cache.dxs'));
        final List<SingleChildScrollView> treeScrollViews = hasTree
            ? tester
                  .widgetList<SingleChildScrollView>(
                    find.descendant(
                      of: treeFinder,
                      matching: find.byType(SingleChildScrollView),
                    ),
                  )
                  .toList()
            : const <SingleChildScrollView>[];
        final bool hasVerticalTreeScroll = treeScrollViews.any(
          (view) => view.scrollDirection == Axis.vertical,
        );
        final bool hasHorizontalTreeScroll = treeScrollViews.any(
          (view) => view.scrollDirection == Axis.horizontal,
        );
        final int treeScrollbarCount = hasTree
            ? find
                  .descendant(of: treeFinder, matching: find.byType(Scrollbar))
                  .evaluate()
                  .length
            : 0;

        await tester.tap(find.byIcon(Icons.close_rounded));
        await settle(tester);

        expect(hasRichActions, isTrue);
        expect(usedPlainAlert, isFalse);
        expect(hasExplanation, isTrue);
        expect(hasTree, isTrue);
        expect(showedNestedFolder, isTrue);
        expect(showedFile, isTrue);
        expect(hasVerticalTreeScroll, isTrue);
        expect(hasHorizontalTreeScroll, isTrue);
        expect(treeScrollbarCount, 2);
      },
    );

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

      // The extract grid has always carried its tiles to their new cells when
      // the results move. Sharing that means the backup grid does too.
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
        bool entrance = false,
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
        await tester.pump(
          gridEntranceDuration + const Duration(milliseconds: 1),
        );
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
          return (surface.decoration as BoxDecoration)
              .boxShadow!
              .single
              .color
              .a;
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
      });

      // Now that a pill cannot be switched off, one that holds nothing while it
      // holds the grid used to stay lit and clickable and do nothing at all.
      testWidgets('a pill holding nothing is not a live control', (
        tester,
      ) async {
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

      // Not a filter beside the others: a question about a name rather than a
      // state of a card, so it takes the grid over.
      testWidgets('the reconcile pill swaps the grid over', (tester) async {
        await pumpPills(
          tester,
          tiles: three(),
          reconcile: <ReconcileTile>[orphan()],
        );

        expect(
          find.text(AppI10n.backupReconcileAbout),
          findsNothing,
          reason: 'it belongs to the reconcile grid, not to the tab',
        );

        await tapPill(tester, AppI10n.backupReconcile, 1);

        expect(find.byType(ReconcileTileView), findsOneWidget);
        expect(find.byType(BackupTileView), findsNothing);
        expect(find.text('muddled'), findsOneWidget);
        expect(arrivingTiles(), findsNothing);
        // "Needs reconciling" is the one pill whose name does not say what it
        // wants from the user, and the tab is where that has to be answered.
        expect(find.text(AppI10n.backupReconcileAbout), findsOneWidget);
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
