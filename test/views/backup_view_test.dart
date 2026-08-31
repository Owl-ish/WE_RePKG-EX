import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:we_repkg/config/theme.dart';
import 'package:we_repkg/config/theme_extensions.dart';
import 'package:we_repkg/constants/i10n.dart';
import 'package:we_repkg/cores/backup.dart';
import 'package:we_repkg/models/enums.dart';
import 'package:we_repkg/provider/backup.dart';
import 'package:we_repkg/provider/navigation.dart';
import 'package:we_repkg/provider/system.dart';
import 'package:we_repkg/utils/backup_diff.dart';
import 'package:we_repkg/utils/backup_tiles.dart';
import 'package:we_repkg/utils/storage.dart';
import 'package:we_repkg/utils/wallpaper_junk.dart';
import 'package:we_repkg/views/backup/backup.dart';
import 'package:we_repkg/views/backup/backup_action_ui.dart';
import 'package:we_repkg/views/backup/backup_tile.dart';
import 'package:we_repkg/views/backup/integrity.dart';
import 'package:we_repkg/widgets/app_icon_button.dart';
import 'package:we_repkg/widgets/input_controls.dart';
import 'package:we_repkg/widgets/folder_input.dart';
import 'package:we_repkg/widgets/issue_note.dart';
import 'package:we_repkg/widgets/selection_grid.dart';
import 'package:we_repkg/widgets/tile_overlays.dart';

import '../support/backup_test_harness.dart';

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

  String fieldText(WidgetTester tester) =>
      tester.widget<TextField>(find.byType(TextField)).controller!.text;

  // A rescan puts the whole tab back to waiting, and a bare spinner there says
  // nothing about a job that takes ten seconds.
  testWidgets('overflowing tile badges animate only while hovered', (
    tester,
  ) async {
    const String label = 'Comparison unavailable';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 64,
              child: TileBadgeStrip(
                badges: <TileBadgeData>[
                  TileBadgeData(text: label, colour: Colors.red),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    final Finder strip = find.byType(TileBadgeStrip);
    expect(
      find.descendant(of: strip, matching: find.byType(AnimatedBuilder)),
      findsNothing,
      reason:
          'overflowing badges should stay idle during ordinary grid scrolling',
    );

    final Finder hoverRegion = find
        .ancestor(of: find.text(label), matching: find.byType(MouseRegion))
        .first;
    final TestGesture mouse = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
    );
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(hoverRegion));
    await tester.pump();

    expect(
      find.descendant(of: strip, matching: find.byType(AnimatedBuilder)),
      findsOneWidget,
    );
    expect(
      tester.takeException(),
      isNull,
      reason: 'hovering an overflowing badge must keep finite layout bounds',
    );

    await mouse.moveTo(const Offset(0, 0));
    await tester.pump();
    expect(
      find.descendant(of: strip, matching: find.byType(AnimatedBuilder)),
      findsNothing,
      reason: 'leaving the badge should stop its scrolling animation',
    );
    await mouse.removePointer();
  });

  testWidgets('tile badges respect accessibility text scaling', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: const Scaffold(
          body: SizedBox(
            width: 64,
            child: TileBadgeStrip(
              badges: <TileBadgeData>[
                TileBadgeData(
                  text: 'Comparison unavailable',
                  colour: Colors.red,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    expect(tester.getSize(find.byType(TileBadgeStrip)).height, greaterThan(18));
    expect(tester.takeException(), isNull);
  });

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

  testWidgets('read-only paths stay compact and scroll horizontally', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: const Scaffold(
          body: SizedBox(
            width: 180,
            child: ReadOnlyPathBox(
              path:
                  r'Backup Workshop\very\long\nested\wallpaper\path\1234567890',
            ),
          ),
        ),
      ),
    );

    expect(tester.getSize(find.byType(ReadOnlyPathBox)).height, 28);
    final SelectableText pathText = tester.widget<SelectableText>(
      find.descendant(
        of: find.byType(ReadOnlyPathBox),
        matching: find.byType(SelectableText),
      ),
    );
    expect(pathText.style?.fontSize, 12);
    final SingleChildScrollView scroller = tester.widget(
      find.descendant(
        of: find.byType(ReadOnlyPathBox),
        matching: find.byType(SingleChildScrollView),
      ),
    );
    expect(scroller.scrollDirection, Axis.horizontal);
    expect(find.byType(Scrollbar), findsOneWidget);
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
      expect(countOf(AppI10n.backupStateEmptyBackup, 0), findsOneWidget);
      expect(countOf(AppI10n.backupReconcile, 0), findsOneWidget);
      expect(countOf(AppI10n.backupIgnored, 0), findsOneWidget);
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

    testWidgets('a reconcile tile shows every reason and warning state', (
      tester,
    ) async {
      const ReconcileEntry entry = ReconcileEntry(
        name: '3707191336',
        reason: BackupReconcileReason.duplicateLiveCopies,
        additionalReasons: <BackupReconcileReason>{
          BackupReconcileReason.conflictingBackupCopies,
        },
        states: <WallpaperLibrary, BackupState>{
          WallpaperLibrary.workshop: BackupState.updateAvailable,
          WallpaperLibrary.myProjects: BackupState.notBackedUp,
        },
        backupWorkshop: true,
        backupMyProjects: true,
      );
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: Scaffold(
              body: ReconcileTileView(
                width: 220,
                tile: (entry: entry, face: null),
                folders: (live: r'C:\live\3707191336', backup: null),
                onTap: () {},
              ),
            ),
          ),
        ),
      );

      expect(find.text(AppI10n.backupTileDuplicateLive), findsOneWidget);
      expect(find.text(AppI10n.backupTileBackupsConflict), findsOneWidget);
      expect(find.text(AppI10n.backupStateUpdateAvailable), findsOneWidget);
      expect(find.text(AppI10n.backupStateNotBackedUp), findsOneWidget);
    });

    testWidgets(
      'tile actions stay visible without repeating per-tile animation',
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

        final Finder tile = find.byType(BackupTileView);
        final Finder tileAction = find.byKey(
          ValueKey<String>('backup-tile-action-${card.id}'),
        );
        final Finder tileActionScale = find.byKey(
          ValueKey<String>('backup-tile-action-scale-${card.id}'),
        );
        expect(
          tileAction,
          findsOneWidget,
          reason: 'the tile action should be mounted before pointer hover',
        );
        expect(
          find.descendant(of: tile, matching: find.byType(BackupActionGlow)),
          findsNothing,
          reason: 'always-visible tile actions must not own repeating tickers',
        );
        final TestGesture mouse = await tester.createGesture(
          kind: PointerDeviceKind.mouse,
        );
        await mouse.addPointer(location: Offset.zero);
        expect(tester.widget<AnimatedScale>(tileActionScale).scale, 1);
        await mouse.moveTo(tester.getCenter(tileAction));
        await tester.pump(const Duration(milliseconds: 110));
        expect(
          tileAction,
          findsOneWidget,
          reason:
              'hovering must not control whether the tile action is mounted',
        );
        expect(
          tester.widget<AnimatedScale>(tileActionScale).scale,
          1.10,
          reason: 'the action should respond visually only to direct hover',
        );
        await mouse.moveTo(const Offset(0, 0));
        await tester.pump(const Duration(milliseconds: 110));
        expect(
          tileAction,
          findsOneWidget,
          reason: 'leaving hover must not hide or unmount the tile action',
        );
        expect(tester.widget<AnimatedScale>(tileActionScale).scale, 1);
        await mouse.removePointer();

        final Finder bulkGlow = find.byKey(
          const ValueKey<String>('backup-all-action-glow'),
        );
        expect(bulkGlow, findsOneWidget);
        final Finder bulkWrapper = find.ancestor(
          of: bulkGlow,
          matching: find.byType(BackupActionGlow),
        );
        final BackupActionGlow bulk = tester.widget<BackupActionGlow>(
          bulkWrapper,
        );
        expect(bulk.enabled, isTrue);
        expect(bulk.scale, 1);

        final BuildContext bulkContext = tester.element(bulkWrapper);
        expect(
          bulk.colour,
          backupStateLook(bulkContext, BackupState.vanished).colour,
        );

        final IconButton button = tester.widget<IconButton>(tileAction);
        expect(button.tooltip, isNull);
        expect(button.style?.animationDuration, Duration.zero);
        expect(button.style?.splashFactory, NoSplash.splashFactory);
        final Icon icon = button.icon as Icon;
        expect(icon.color, isNotNull);
        expect(icon.semanticLabel, AppI10n.backupActionRestore);
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
      expect(
        tester.widget<SelectionGrid>(junkGrid).sections,
        hasLength(2),
        reason: 'Empty/Junk should use the shared grouped grid engine',
      );

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
          matching: find.byType(SliverPersistentHeader),
        );
        expect(groupHeader, findsOneWidget);
        expect(
          tester.widget<SliverPersistentHeader>(groupHeader).pinned,
          isTrue,
        );
        expect(
          find.ancestor(
            of: groupHeader,
            matching: find.byType(SliverMainAxisGroup),
          ),
          findsOneWidget,
        );

        final Finder actionHost = find.byKey(
          ValueKey<String>('backup-junk-action-${kind.name}'),
        );
        final Finder actionGlow = find.descendant(
          of: actionHost,
          matching: find.byKey(
            const ValueKey<String>('backup-all-action-glow'),
          ),
        );
        final Finder actionLabel = find.descendant(
          of: actionHost,
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
          tester.getRect(junkGrid).overlaps(tester.getRect(issueNote)),
          isTrue,
          reason: 'the sticky header keeps its own callout visible',
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
        final Finder issueNoteHost = find.byKey(
          const ValueKey<String>('backup-junk-note-empty'),
        );
        final Finder issueNote = find.descendant(
          of: issueNoteHost,
          matching: find.byType(IssueNote),
        );
        final Finder groupHeader = find.ancestor(
          of: issueNoteHost,
          matching: find.byType(SliverPersistentHeader),
        );
        final Finder actionGlow = find.descendant(
          of: find.byKey(const ValueKey<String>('backup-junk-action-empty')),
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
        expect(issueNoteHost, findsOneWidget);
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

    test('Backup action labels stay compact in both translations', () {
      final Map<String, dynamic> english =
          jsonDecode(File('assets/translations/en-US.json').readAsStringSync())
              as Map<String, dynamic>;
      final Map<String, dynamic> chinese =
          jsonDecode(File('assets/translations/zh-CN.json').readAsStringSync())
              as Map<String, dynamic>;

      expect(english['backup']['junk']['emptyTitle'], 'Empty Folders');
      expect(english['backup']['state']['updateAvailable'], 'Update / Sync');
      expect(english['backup']['action']['update'], 'Update / Sync');
      expect(english['backup']['action']['showAgain'], 'Show Again');
      expect(
        english['backup']['action']['recycleAll'],
        'Recycle Bin All ({count})',
      );
      expect(english['backup']['action']['backUpAll'], 'Backup All ({count})');
      expect(
        english['backup']['action']['updateAll'],
        'Update / Sync All ({count})',
      );
      expect(
        english['backup']['action']['restoreAll'],
        'Restore All ({count})',
      );
      expect(
        english['backup']['action']['showAgainAll'],
        'Show Again All ({count})',
      );
      expect(chinese['backup']['junk']['emptyTitle'], '空文件夹');
      expect(chinese['backup']['state']['updateAvailable'], '更新 / 同步');
      expect(chinese['backup']['action']['showAgain'], '再次显示');
      expect(chinese['backup']['action']['recycleAll'], '全部移到回收站（{count}）');
      expect(english['backup']['ignored'], 'Ignored');
      expect(
        english['backup']['reconcileReason']['duplicateLiveTitle'],
        'Duplicate live copies',
      );
      expect(
        english['backup']['reconcileReason']['duplicateLiveAbout'],
        'This wallpaper exists in both Live {location1} and {location2} folders. '
        'Please remove one if they are identical, or ignore this detection.',
      );
      expect(
        english['backup']['reconcileReason']['conflictingBackupsTitle'],
        'Conflicting backup copies',
      );
      expect(english['backup']['tile']['reconcile'], 'Reconcile');
      expect(
        english['backup']['detail']['syncWillMove'],
        'Sync - Will move this wallpaper folder',
      );
      expect(
        english['backup']['detail']['updateToLive'],
        'Updates this backup to mirror the live wallpaper location.',
      );
      expect(english['backup']['detail']['fileChanges'], 'File changes');
      expect(
        english['backup']['detail']['expandFileChanges'],
        'Click to expand and inspect changed files',
      );
      expect(english['backup']['detail']['modified'], 'Modified Files');
      expect(english['backup']['detail']['addedFiles'], 'Added Files');
      expect(english['backup']['detail']['removedFiles'], 'Removed Files');
      expect(english['backup']['detail']['willRemove'], 'This will be removed');
      expect(english['backup']['detail']['willKeep'], 'This will be kept');
      expect(
        english['backup']['detail']['inWorkshopBackup'],
        'In Workshop backup',
      );
      expect(
        english['backup']['detail']['inMyProjectsBackup'],
        'In MyProjects backup',
      );
      expect(english['backup']['detail']['inWorkshopLive'], 'In Workshop live');
      expect(
        english['backup']['detail']['inMyProjectsLive'],
        'In MyProjects live',
      );
      expect(english['backup']['detail']['copyFolderPath'], 'Copy folder path');
      expect(
        english['backup']['about']['vanished'],
        'These wallpapers exist only in backup. No live copy is found in the libraries.',
      );
      expect(chinese['backup']['tile']['reconcile'], '需要处理');
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

    // Reconcile entries are not cards, so they are counted apart or the tab
    // would report nothing about the names waiting to be sorted out.
    testWidgets('reconcile entries carry their own count', (tester) async {
      await showScan(
        tester,
        scanOf(
          reconcile: const <ReconcileEntry>[
            ReconcileEntry(
              name: '793602574',
              reason: BackupReconcileReason.conflictingBackupCopies,
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
