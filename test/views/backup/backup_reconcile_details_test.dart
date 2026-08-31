import 'dart:async';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:we_repkg/config/theme.dart';
import 'package:we_repkg/constants/i10n.dart';
import 'package:we_repkg/cores/backup.dart';
import 'package:we_repkg/provider/system.dart';
import 'package:we_repkg/utils/backup_diff.dart';
import 'package:we_repkg/utils/backup_tiles.dart';
import 'package:we_repkg/views/backup/backup_tile.dart';
import 'package:we_repkg/views/backup/details/content_details.dart';
import 'package:we_repkg/views/backup/details/issue_details.dart';
import 'package:we_repkg/views/content/detail_dialog.dart';
import 'package:we_repkg/widgets/file_tree_panel.dart';
import 'package:we_repkg/widgets/input_controls.dart';

void main() {
  testWidgets('duplicate live details expose every detected location', (
    tester,
  ) async {
    Future<FolderFileComparison?> loadComparison() async => null;

    const ReconcileEntry entry = ReconcileEntry(
      name: 'double-live',
      reason: BackupReconcileReason.duplicateLiveCopies,
      states: <WallpaperLibrary, BackupState>{
        WallpaperLibrary.workshop: BackupState.synced,
        WallpaperLibrary.myProjects: BackupState.synced,
      },
      backupWorkshop: true,
      backupMyProjects: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              height: 230,
              child: ReconcileDetailContent(
                entry: entry,
                foreground: Colors.black,
                focused: false,
                needsFocus: false,
                workshopLiveFolder: r'C:\workshop\431960\double-live',
                myProjectsLiveFolder:
                    r'C:\wallpaper_engine\projects\myprojects\double-live',
                workshopBackupFolder: r'C:\backup\431960\double-live',
                myProjectsBackupFolder: null,
                rePKGPath: null,
                loadDuplicateLiveChanges: loadComparison,
              ),
            ),
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey<String>('backup-reconcile-live-workshop')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('backup-reconcile-live-myprojects')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('backup-reconcile-backup-workshop')),
      findsOneWidget,
    );
    expect(find.text(r'C:\workshop\431960\double-live'), findsOneWidget);
    expect(
      find.text(r'C:\wallpaper_engine\projects\myprojects\double-live'),
      findsOneWidget,
    );
    expect(find.text(r'C:\backup\431960\double-live'), findsOneWidget);
    expect(find.byType(PathActionBox), findsNWidgets(3));
    for (final PathActionBox box in tester.widgetList<PathActionBox>(
      find.byType(PathActionBox),
    )) {
      expect(box.compact, isTrue);
    }
    expect(find.byIcon(Icons.copy_rounded), findsNWidgets(3));
    expect(find.byIcon(Icons.folder_open_rounded), findsNWidgets(3));
    final SingleChildScrollView scroll = tester.widget<SingleChildScrollView>(
      find.byType(SingleChildScrollView),
    );
    expect(scroll.padding, const EdgeInsets.only(right: 10));
    final Finder detailScrollbars = find.descendant(
      of: find.byType(ReconcileDetailContent),
      matching: find.byType(Scrollbar),
    );
    expect(detailScrollbars, findsOneWidget);
    final Scrollbar scrollbar = tester.widget<Scrollbar>(detailScrollbars);
    expect(scrollbar.thumbVisibility, isTrue);
    expect(
      scroll.controller!.position.maxScrollExtent,
      greaterThan(0),
      reason: 'overflowing location evidence should advertise that it scrolls',
    );
    final Finder comparePrompt = find.byKey(
      const ValueKey<String>('backup-reconcile-expand-live-differences'),
    );
    expect(comparePrompt, findsOneWidget);
    expect(
      find.descendant(
        of: comparePrompt,
        matching: find.text(AppI10n.backupDetailCompareFiles),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: comparePrompt,
        matching: find.text(AppI10n.backupDetailCompareFilesHint),
      ),
      findsOneWidget,
    );
    final Rect detailRect = tester.getRect(find.byType(ReconcileDetailContent));
    final Rect promptRect = tester.getRect(comparePrompt);
    expect(
      promptRect.bottom,
      lessThanOrEqualTo(detailRect.bottom + .5),
      reason: 'Compare Files must stay visible below a three-location list',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'duplicate live comparison stays idle until Compare Files is pressed',
    (tester) async {
      final Completer<FolderFileComparison?> comparison =
          Completer<FolderFileComparison?>();
      int loads = 0;
      Future<FolderFileComparison?> loadComparison() {
        loads++;
        return comparison.future;
      }

      const ReconcileEntry entry = ReconcileEntry(
        name: 'pending-double-live',
        reason: BackupReconcileReason.duplicateLiveCopies,
        states: <WallpaperLibrary, BackupState>{
          WallpaperLibrary.workshop: BackupState.synced,
          WallpaperLibrary.myProjects: BackupState.synced,
        },
        backupWorkshop: false,
        backupMyProjects: false,
      );

      Widget detail({required bool focused}) => MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            height: 230,
            child: ReconcileDetailContent(
              entry: entry,
              foreground: Colors.black,
              focused: focused,
              needsFocus: false,
              workshopLiveFolder: r'C:\workshop\pending-double-live',
              myProjectsLiveFolder: r'C:\myprojects\pending-double-live',
              workshopBackupFolder: null,
              myProjectsBackupFolder: null,
              rePKGPath: null,
              loadDuplicateLiveChanges: loadComparison,
            ),
          ),
        ),
      );

      await tester.pumpWidget(detail(focused: false));

      expect(loads, 0);
      expect(
        find.byKey(
          const ValueKey<String>('backup-duplicate-live-comparison-progress'),
        ),
        findsNothing,
      );
      final Finder comparePrompt = find.byKey(
        const ValueKey<String>('backup-reconcile-expand-live-differences'),
      );
      expect(comparePrompt, findsOneWidget);
      expect(
        find.descendant(
          of: comparePrompt,
          matching: find.text(AppI10n.backupDetailCompareFiles),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: comparePrompt,
          matching: find.text(AppI10n.backupDetailCompareFilesHint),
        ),
        findsOneWidget,
      );

      await tester.pumpWidget(detail(focused: true));
      await tester.pump();

      expect(
        loads,
        0,
        reason: 'expanding the right pane alone must not start comparison',
      );
      expect(comparePrompt, findsOneWidget);
      expect(
        find.byKey(
          const ValueKey<String>('backup-duplicate-live-comparison-progress'),
        ),
        findsNothing,
      );

      await tester.tap(comparePrompt);
      await tester.pump();

      expect(loads, 1);
      expect(
        find.byKey(
          const ValueKey<String>('backup-duplicate-live-comparison-progress'),
        ),
        findsOneWidget,
      );

      comparison.complete((
        changes: (
          modified: <String>['scene.pkg'],
          onlyFirst: <String>[],
          onlySecond: <String>[],
        ),
        matching: <String>['project.json'],
      ));
      await tester.pump();
      await tester.pump();

      expect(loads, 1);
      expect(
        find.byKey(
          const ValueKey<String>('backup-duplicate-live-comparison-progress'),
        ),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('backup-duplicate-live-file-tree')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('duplicate live identical comparison lists matching files', (
    tester,
  ) async {
    const ReconcileEntry entry = ReconcileEntry(
      name: 'same-double-live',
      reason: BackupReconcileReason.duplicateLiveCopies,
      states: <WallpaperLibrary, BackupState>{
        WallpaperLibrary.workshop: BackupState.synced,
        WallpaperLibrary.myProjects: BackupState.synced,
      },
      backupWorkshop: false,
      backupMyProjects: false,
    );

    Future<FolderFileComparison?> loadComparison() async => (
      changes: (
        modified: <String>[],
        onlyFirst: <String>[],
        onlySecond: <String>[],
      ),
      matching: <String>['project.json', 'preview.jpg', 'scene.pkg'],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            height: 280,
            child: ReconcileDetailContent(
              entry: entry,
              foreground: Colors.black,
              focused: true,
              needsFocus: false,
              workshopLiveFolder: r'C:\workshop\same-double-live',
              myProjectsLiveFolder: r'C:\myprojects\same-double-live',
              workshopBackupFolder: null,
              myProjectsBackupFolder: null,
              rePKGPath: null,
              loadDuplicateLiveChanges: loadComparison,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final Finder comparePrompt = find.byKey(
      const ValueKey<String>('backup-reconcile-expand-live-differences'),
    );
    expect(comparePrompt, findsOneWidget);

    await tester.tap(comparePrompt);
    await tester.pump();
    await tester.pump();

    expect(
      find.byKey(
        const ValueKey<String>('backup-duplicate-live-matching-files'),
      ),
      findsOneWidget,
    );
    expect(find.text(AppI10n.backupDetailMatchingFiles), findsOneWidget);
    expect(find.text('✓ project.json'), findsOneWidget);
    expect(find.text('✓ preview.jpg'), findsOneWidget);
    expect(find.text('✓ scene.pkg'), findsOneWidget);
    expect(find.text(AppI10n.backupDetailSame), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reconcile context menu exposes every detected location', (
    tester,
  ) async {
    const ReconcileTile tile = (
      entry: ReconcileEntry(
        name: 'double-live',
        reason: BackupReconcileReason.duplicateLiveCopies,
        states: <WallpaperLibrary, BackupState>{
          WallpaperLibrary.workshop: BackupState.synced,
          WallpaperLibrary.myProjects: BackupState.synced,
        },
        backupWorkshop: true,
        backupMyProjects: false,
      ),
      face: null,
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: Center(
              child: ReconcileTileView(
                width: 180,
                tile: tile,
                folders: const (
                  live: r'C:\workshop\431960\double-live',
                  backup: r'C:\backup\431960\double-live',
                ),
                backupRoot: r'C:\backup',
                liveWorkshopRoot: r'C:\workshop\431960',
                liveMyProjectsRoot: r'C:\wallpaper_engine\projects\myprojects',
                onTap: () {},
              ),
            ),
          ),
        ),
      ),
    );

    final Finder tileFinder = find.byType(ReconcileTileView);
    final TestGesture secondary = await tester.startGesture(
      tester.getCenter(tileFinder),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryButton,
    );
    await secondary.up();
    await tester.pumpAndSettle();

    expect(find.text(AppI10n.backupOpenWorkshopLiveFolder), findsOneWidget);
    expect(find.text(AppI10n.backupOpenMyProjectsLiveFolder), findsOneWidget);
    expect(find.text(AppI10n.backupOpenWorkshopBackupFolder), findsOneWidget);
    expect(find.text(AppI10n.backupOpenMyProjectsBackupFolder), findsNothing);
    expect(find.text(AppI10n.backupOpenLiveFolder), findsNothing);
    expect(find.text(AppI10n.backupOpenBackupFolder), findsNothing);
  });

  testWidgets('reconcile tile surfaces every known issue badge', (
    tester,
  ) async {
    const ReconcileTile tile = (
      entry: ReconcileEntry(
        name: 'multi-issue',
        reason: BackupReconcileReason.duplicateLiveCopies,
        additionalReasons: <BackupReconcileReason>{
          BackupReconcileReason.conflictingBackupCopies,
        },
        states: <WallpaperLibrary, BackupState>{
          WallpaperLibrary.workshop: BackupState.synced,
          WallpaperLibrary.myProjects: BackupState.updateAvailable,
        },
        backupWorkshop: true,
        backupMyProjects: true,
      ),
      face: null,
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: Center(
              child: ReconcileTileView(
                width: 180,
                tile: tile,
                folders: const (live: null, backup: null),
                onTap: () {},
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text(AppI10n.backupTileDuplicateLive), findsOneWidget);
    expect(find.text(AppI10n.backupTileBackupsConflict), findsOneWidget);
    expect(find.text(AppI10n.backupStateUpdateAvailable), findsOneWidget);
    expect(find.text(AppI10n.backupStateSynced), findsNothing);
  });

  testWidgets('reconcile details surface hidden ordinary attention states', (
    tester,
  ) async {
    const ReconcileEntry entry = ReconcileEntry(
      name: 'attention-state',
      reason: BackupReconcileReason.duplicateLiveCopies,
      states: <WallpaperLibrary, BackupState>{
        WallpaperLibrary.workshop: BackupState.synced,
        WallpaperLibrary.myProjects: BackupState.updateAvailable,
      },
      backupWorkshop: true,
      backupMyProjects: false,
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 340,
            height: 260,
            child: ReconcileDetailContent(
              entry: entry,
              foreground: Colors.black,
              focused: false,
              needsFocus: false,
              workshopLiveFolder: r'C:\workshop\attention-state',
              myProjectsLiveFolder: r'C:\myprojects\attention-state',
              workshopBackupFolder: r'C:\backup\attention-state',
              myProjectsBackupFolder: null,
              rePKGPath: null,
            ),
          ),
        ),
      ),
    );

    expect(
      find.textContaining(AppI10n.backupStateUpdateAvailable),
      findsOneWidget,
    );
    expect(find.textContaining(AppI10n.backupStateSynced), findsNothing);
  });

  testWidgets('duplicate live comparison starts only from Compare Files', (
    tester,
  ) async {
    final Directory root = Directory.systemTemp.createTempSync(
      'we_repkg_duplicate_live_detail',
    );
    addTearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });
    final Directory workshopRoot = Directory(
      '${root.path}${Platform.pathSeparator}workshop',
    )..createSync();
    final Directory myProjectsRoot = Directory(
      '${root.path}${Platform.pathSeparator}myprojects',
    )..createSync();
    final Directory workshop = Directory(
      '${workshopRoot.path}${Platform.pathSeparator}double-live-diff',
    )..createSync();
    final Directory myProjects = Directory(
      '${myProjectsRoot.path}${Platform.pathSeparator}double-live-diff',
    )..createSync();
    for (final Directory folder in <Directory>[workshop, myProjects]) {
      File(
        '${folder.path}${Platform.pathSeparator}project.json',
      ).writeAsStringSync('{"title":"Duplicate","type":"scene"}');
      File(
        '${folder.path}${Platform.pathSeparator}scene.pkg',
      ).writeAsStringSync('same');
    }

    const ReconcileTile tile = (
      entry: ReconcileEntry(
        name: 'double-live-diff',
        reason: BackupReconcileReason.duplicateLiveCopies,
        states: <WallpaperLibrary, BackupState>{
          WallpaperLibrary.workshop: BackupState.synced,
          WallpaperLibrary.myProjects: BackupState.synced,
        },
        backupWorkshop: false,
        backupMyProjects: false,
      ),
      face: null,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [toolPathProvider.overrideWithValue(null)],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: Center(
              child: ReconcileTileView(
                width: 180,
                tile: tile,
                folders: (live: workshop.path, backup: null),
                liveWorkshopRoot: workshopRoot.path,
                liveMyProjectsRoot: myProjectsRoot.path,
                onTap: () {},
              ),
            ),
          ),
        ),
      ),
    );

    // Change the second live copy only after the tile exists. The grid and
    // ordinary detail opening must stay cheap; the explicit differences click
    // below is the first point allowed to start exact recursive comparison.
    File(
      '${myProjects.path}${Platform.pathSeparator}scene.pkg',
    ).writeAsStringSync('diff');
    File(
      '${workshop.path}${Platform.pathSeparator}workshop-only.txt',
    ).writeAsStringSync('left');
    File(
      '${myProjects.path}${Platform.pathSeparator}myprojects-only.txt',
    ).writeAsStringSync('right');

    final Finder tileFinder = find.byType(ReconcileTileView);
    await tester.tap(tileFinder);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(tileFinder);

    final Finder focusTarget = find.byKey(
      const ValueKey<String>('wallpaper-detail-extra-focus-target'),
    );
    for (
      int attempt = 0;
      attempt < 60 && focusTarget.evaluate().isEmpty;
      attempt++
    ) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 25));
      });
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(focusTarget, findsOneWidget);
    expect(
      find.byKey(
        const ValueKey<String>('backup-reconcile-expand-live-differences'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('wallpaper-detail-extra-focus-hint')),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey<String>('backup-duplicate-live-comparison-progress'),
      ),
      findsNothing,
      reason: 'opening Duplicate Live details must not start the file scan',
    );
    expect(
      find.byKey(const ValueKey<String>('backup-duplicate-live-file-tree')),
      findsNothing,
    );

    final Finder comparePrompt = find.byKey(
      const ValueKey<String>('backup-reconcile-expand-live-differences'),
    );

    await tester.tap(focusTarget);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));

    expect(
      comparePrompt,
      findsOneWidget,
      reason: 'expanding the pane must not consume the explicit compare action',
    );
    expect(
      find.byKey(
        const ValueKey<String>('backup-duplicate-live-comparison-progress'),
      ),
      findsNothing,
      reason: 'blank-pane expansion must not start recursive comparison',
    );
    expect(
      find.byKey(const ValueKey<String>('backup-duplicate-live-file-tree')),
      findsNothing,
    );

    await tester.tap(comparePrompt);
    await tester.pump();

    final Finder tree = find.byKey(
      const ValueKey<String>('backup-duplicate-live-detail-scroll'),
    );
    for (int attempt = 0; attempt < 60 && tree.evaluate().isEmpty; attempt++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 25));
      });
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(tree, findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('backup-scene-pkg-inspect')),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey<String>(
          'backup-manual-compare-duplicate-live-workshop::workshop-only.txt',
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey<String>(
          'backup-manual-compare-duplicate-live-myprojects::myprojects-only.txt',
        ),
      ),
      findsOneWidget,
    );
    final FileTreeRouteBanner route = tester.widget(
      find.byType(FileTreeRouteBanner),
    );
    expect(route.source, endsWith('/ double-live-diff'));
    expect(route.source.toLowerCase(), contains('workshop'));
    expect(route.destination, endsWith('/ double-live-diff'));
    expect(route.destination.toLowerCase(), contains('myprojects'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('conflicting backup details expose only detected backup paths', (
    tester,
  ) async {
    const ReconcileEntry entry = ReconcileEntry(
      name: 'double-backup',
      reason: BackupReconcileReason.conflictingBackupCopies,
      states: <WallpaperLibrary, BackupState>{
        WallpaperLibrary.workshop: BackupState.synced,
      },
      backupWorkshop: true,
      backupMyProjects: true,
      backupDifference: BackupCopyDifference(
        differentSize: <String>['project.json'],
      ),
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ReconcileDetailContent(
            entry: entry,
            foreground: Colors.black,
            focused: false,
            needsFocus: true,
            workshopLiveFolder: r'C:\workshop\431960\double-backup',
            myProjectsLiveFolder: null,
            workshopBackupFolder: r'C:\backup\Workshop\double-backup',
            myProjectsBackupFolder: r'C:\backup\MyProjects\double-backup',
            rePKGPath: null,
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey<String>('backup-reconcile-backup-workshop')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('backup-reconcile-backup-myprojects')),
      findsOneWidget,
    );
    expect(find.text(r'C:\backup\Workshop\double-backup'), findsOneWidget);
    expect(find.text(r'C:\backup\MyProjects\double-backup'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('backup-reconcile-live-workshop')),
      findsNothing,
    );
  });

  testWidgets('comparison unavailable shows only detected locations', (
    tester,
  ) async {
    const ReconcileEntry entry = ReconcileEntry(
      name: 'comparison-failed',
      reason: BackupReconcileReason.comparisonUnavailable,
      states: <WallpaperLibrary, BackupState>{
        WallpaperLibrary.myProjects: BackupState.updateAvailable,
      },
      backupWorkshop: true,
      backupMyProjects: false,
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ReconcileDetailContent(
            entry: entry,
            foreground: Colors.black,
            focused: false,
            needsFocus: false,
            workshopLiveFolder: null,
            myProjectsLiveFolder: r'C:\live\MyProjects\comparison-failed',
            workshopBackupFolder: r'C:\backup\Workshop\comparison-failed',
            myProjectsBackupFolder: null,
            rePKGPath: null,
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey<String>('backup-reconcile-live-myprojects')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('backup-reconcile-backup-workshop')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('backup-reconcile-live-workshop')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('backup-reconcile-backup-myprojects')),
      findsNothing,
    );
  });

  testWidgets(
    'reconcile details focus the file pane without resizing the dialog',
    (tester) async {
      final Directory folder = Directory.systemTemp.createTempSync(
        'we_repkg_reconcile_detail',
      );
      addTearDown(() {
        if (folder.existsSync()) folder.deleteSync(recursive: true);
      });
      File(
        '${folder.path}${Platform.pathSeparator}placeholder.txt',
      ).writeAsStringSync('different');

      const ReconcileTile tile = (
        entry: ReconcileEntry(
          name: 'conflict',
          reason: BackupReconcileReason.conflictingBackupCopies,
          states: <WallpaperLibrary, BackupState>{
            WallpaperLibrary.workshop: BackupState.synced,
          },
          backupWorkshop: true,
          backupMyProjects: true,
          backupDifference: BackupCopyDifference(
            differentSize: <String>['project.json'],
            onlyWorkshop: <String>['effects\\a.json'],
            onlyMyProjects: <String>['materials\\b.json'],
          ),
        ),
        face: null,
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: Scaffold(
              body: Center(
                child: ReconcileTileView(
                  width: 180,
                  tile: tile,
                  folders: (live: folder.path, backup: null),
                  onTap: () {},
                ),
              ),
            ),
          ),
        ),
      );

      final Finder tileFinder = find.byType(ReconcileTileView);
      await tester.tap(tileFinder);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(tileFinder);

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

      final Finder focusTarget = find.byKey(
        const ValueKey<String>('wallpaper-detail-extra-focus-target'),
      );
      final Finder previewPane = find.byKey(
        const ValueKey<String>('wallpaper-detail-preview-pane'),
      );
      final Finder panelPane = find.byKey(
        const ValueKey<String>('wallpaper-detail-panel-pane'),
      );
      expect(await waitFor(focusTarget), isTrue);
      expect(
        find.byKey(const ValueKey<String>('wallpaper-detail-extra-focus-hint')),
        findsOneWidget,
      );
      final Finder expandPrompt = find.byKey(
        const ValueKey<String>('backup-reconcile-expand-differences'),
      );
      expect(expandPrompt, findsOneWidget);
      expect(
        find.descendant(
          of: expandPrompt,
          matching: find.text(AppI10n.backupDetailCompareFiles),
        ),
        findsOneWidget,
      );
      final Semantics expandSemantics = tester.widget<Semantics>(
        find
            .descendant(of: expandPrompt, matching: find.byType(Semantics))
            .first,
      );
      expect(expandSemantics.properties.button, isTrue);
      expect(
        expandSemantics.properties.label,
        contains(AppI10n.backupDetailCompareFilesHint),
      );
      expect(tester.getSize(expandPrompt).height, greaterThanOrEqualTo(48));
      expect(
        tester.getSize(expandPrompt).height,
        lessThan(120),
        reason: 'the shared expand prompt must not stretch into a detail pane',
      );
      final WallpaperDetailDialog detailDialog = tester.widget(
        find.byType(WallpaperDetailDialog),
      );
      final Finder metadata = find.byKey(
        const ValueKey<String>('wallpaper-detail-metadata'),
      );
      expect(metadata, findsOneWidget);
      expect(
        find.ancestor(
          of: metadata,
          matching: find.byType(SingleChildScrollView),
        ),
        findsNothing,
        reason:
            'preview-backed details should give metadata its natural height instead of overlaying a scrollbar on copy controls',
      );
      const DetailDialogLayout sharedLayout = DetailDialogLayout();
      expect(detailDialog.layout.panelWidth, sharedLayout.panelWidth);
      expect(
        find.byKey(const ValueKey<String>('backup-reconcile-detail-scroll')),
        findsNothing,
      );

      final double previewBefore = tester.getSize(previewPane).width;
      final double panelBefore = tester.getSize(panelPane).width;
      final double totalBefore = previewBefore + panelBefore;
      final Size dialogBefore = tester.getSize(find.byType(Dialog));

      await tester.tap(focusTarget);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 220));

      final double previewFocused = tester.getSize(previewPane).width;
      final double panelFocused = tester.getSize(panelPane).width;
      final Size dialogFocused = tester.getSize(find.byType(Dialog));
      expect(
        find.byKey(
          const ValueKey<String>('backup-reconcile-expand-differences'),
        ),
        findsOneWidget,
        reason: 'expanding the pane alone must not open comparison results',
      );
      expect(
        find.byKey(const ValueKey<String>('backup-reconcile-detail-scroll')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('wallpaper-detail-extra-focus-hint')),
        findsNothing,
      );
      expect(previewFocused, lessThan(previewBefore));
      expect(previewFocused, lessThanOrEqualTo(100));
      expect(panelFocused, greaterThan(panelBefore));
      expect(previewFocused + panelFocused, closeTo(totalBefore, .5));
      expect(dialogFocused.width, closeTo(dialogBefore.width, .5));
      expect(dialogFocused.height, closeTo(dialogBefore.height, .5));

      await tester.tap(expandPrompt);
      await tester.pump();
      expect(
        find.byKey(
          const ValueKey<String>('backup-reconcile-expand-differences'),
        ),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('backup-reconcile-detail-scroll')),
        findsOneWidget,
      );

      await tester.tap(previewPane);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 220));

      expect(tester.getSize(previewPane).width, closeTo(previewBefore, .5));
      expect(tester.getSize(panelPane).width, closeTo(panelBefore, .5));
    },
  );

  testWidgets('reconcile file tree exposes shared manual comparison', (
    tester,
  ) async {
    final Directory root = Directory.systemTemp.createTempSync(
      'we_repkg_reconcile_compare',
    );
    addTearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });
    final Directory workshop = Directory(
      '${root.path}${Platform.pathSeparator}workshop',
    )..createSync();
    final Directory myProjects = Directory(
      '${root.path}${Platform.pathSeparator}myprojects',
    )..createSync();
    File(
      '${workshop.path}${Platform.pathSeparator}left.txt',
    ).writeAsStringSync('left');
    File(
      '${myProjects.path}${Platform.pathSeparator}right.txt',
    ).writeAsStringSync('right');

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: BackupDifferenceFileTree(
            wallpaperName: 'conflict',
            difference: const BackupCopyDifference(
              onlyWorkshop: <String>['left.txt'],
              onlyMyProjects: <String>['right.txt'],
            ),
            workshopBackupFolder: workshop.path,
            myProjectsBackupFolder: myProjects.path,
            rePKGPath: null,
            foreground: Colors.black,
          ),
        ),
      ),
    );
    await tester.pump();

    final Finder count = find.byKey(
      const ValueKey<String>('backup-reconcile-manual-compare-count'),
    );
    expect(count, findsOneWidget);
    expect(tester.widget<Text>(count).data, '0 / 2');
    expect(
      find.byKey(
        const ValueKey<String>(
          'backup-manual-compare-reconcile-workshop::left.txt',
        ),
      ),
      findsOneWidget,
    );
    final Finder leftRow = find.byKey(
      const ValueKey<String>(
        'backup-manual-compare-reconcile-workshop::left.txt',
      ),
    );
    final Finder rightRow = find.byKey(
      const ValueKey<String>(
        'backup-manual-compare-reconcile-myprojects::right.txt',
      ),
    );
    expect(leftRow, findsOneWidget);
    expect(rightRow, findsOneWidget);
    expect(tester.widget<FileTreeRow>(leftRow).contextActions, hasLength(1));
    expect(
      tester.widget<FileTreeRow>(leftRow).contextActions.single.enabled,
      isFalse,
    );

    await tester.tap(leftRow);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.tap(rightRow);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    expect(tester.widget<Text>(count).data, '2 / 2');
    expect(
      tester.widget<FileTreeRow>(leftRow).contextActions.single.enabled,
      isTrue,
    );
    expect(
      tester.widget<FileTreeRow>(rightRow).contextActions.single.enabled,
      isTrue,
    );
  });

  testWidgets('small reconcile differences stay expanded without focus mode', (
    tester,
  ) async {
    final Directory root = Directory.systemTemp.createTempSync(
      'we_repkg_reconcile_small_detail',
    );
    addTearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });
    final Directory live = Directory(
      '${root.path}${Platform.pathSeparator}live',
    )..createSync();
    File(
      '${live.path}${Platform.pathSeparator}placeholder.txt',
    ).writeAsStringSync('different');
    final Directory workshopBackup = Directory(
      '${backupWorkshopPath(root.path)!}${Platform.pathSeparator}small-conflict',
    )..createSync(recursive: true);
    final Directory myProjectsBackup = Directory(
      '${backupMyProjectsPath(root.path)!}${Platform.pathSeparator}small-conflict',
    )..createSync(recursive: true);
    File(
      '${workshopBackup.path}${Platform.pathSeparator}project.json',
    ).writeAsStringSync('{"title":"Conflict","version":1}');
    File(
      '${myProjectsBackup.path}${Platform.pathSeparator}project.json',
    ).writeAsStringSync('{"title":"Conflict","version":20}');

    const ReconcileTile tile = (
      entry: ReconcileEntry(
        name: 'small-conflict',
        reason: BackupReconcileReason.conflictingBackupCopies,
        states: <WallpaperLibrary, BackupState>{
          WallpaperLibrary.workshop: BackupState.synced,
        },
        backupWorkshop: true,
        backupMyProjects: true,
        backupDifference: BackupCopyDifference(
          differentSize: <String>['project.json'],
        ),
      ),
      face: null,
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: Center(
              child: ReconcileTileView(
                width: 180,
                tile: tile,
                folders: (live: live.path, backup: null),
                backupRoot: root.path,
                onTap: () {},
              ),
            ),
          ),
        ),
      ),
    );

    final Finder tileFinder = find.byType(ReconcileTileView);
    await tester.tap(tileFinder);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(tileFinder);
    for (int attempt = 0; attempt < 40; attempt++) {
      if (find
          .byKey(const ValueKey<String>('backup-reconcile-detail-scroll'))
          .evaluate()
          .isNotEmpty) {
        break;
      }
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 25));
      });
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(
      find.byKey(const ValueKey<String>('backup-reconcile-detail-scroll')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('backup-reconcile-expand-differences')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('wallpaper-detail-extra-focus-target')),
      findsNothing,
    );
    final Finder versionJson = find.byKey(
      const ValueKey<String>('backup-json-project.json'),
    );
    expect(versionJson, findsOneWidget);
    await tester.tap(versionJson);
    for (int attempt = 0; attempt < 40; attempt++) {
      if (find.text('version').evaluate().isNotEmpty) break;
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 25));
      });
      await tester.pump(const Duration(milliseconds: 50));
    }
    final FileTreeRouteBanner reconcileRoute = tester.widget(
      find.byType(FileTreeRouteBanner),
    );
    expect(reconcileRoute.source, endsWith('/ small-conflict'));
    expect(reconcileRoute.source.toLowerCase(), contains('backup'));
    expect(reconcileRoute.source.toLowerCase(), contains('workshop'));
    expect(reconcileRoute.destination, endsWith('/ small-conflict'));
    expect(reconcileRoute.destination.toLowerCase(), contains('backup'));
    expect(reconcileRoute.destination.toLowerCase(), contains('myprojects'));
    expect(find.text('version'), findsOneWidget);
    expect(find.text('1  →  20'), findsOneWidget);
  });
}
