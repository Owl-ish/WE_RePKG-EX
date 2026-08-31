import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:we_repkg/config/theme.dart';
import 'package:we_repkg/constants/i10n.dart';
import 'package:we_repkg/cores/backup.dart';
import 'package:we_repkg/utils/backup_diff.dart';
import 'package:we_repkg/utils/backup_tiles.dart';
import 'package:we_repkg/views/backup/backup_tile.dart';
import 'package:we_repkg/views/backup/details/issue_details.dart';
import 'package:we_repkg/views/content/detail_dialog.dart';
import 'package:we_repkg/widgets/file_tree_panel.dart';

void main() {
  testWidgets('duplicate live comparison waits for Compare Files', (
    tester,
  ) async {
    final Completer<FolderFileComparison?> result =
        Completer<FolderFileComparison?>();
    int loads = 0;
    Future<FolderFileComparison?> loadComparison() {
      loads++;
      return result.future;
    }

    const ReconcileEntry entry = ReconcileEntry(
      name: 'double-live',
      reason: BackupReconcileReason.duplicateLiveCopies,
      states: <WallpaperLibrary, BackupState>{
        WallpaperLibrary.workshop: BackupState.synced,
        WallpaperLibrary.myProjects: BackupState.synced,
      },
      backupWorkshop: false,
      backupMyProjects: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: SizedBox(
            width: 360,
            height: 300,
            child: ReconcileDetailContent(
              entry: entry,
              foreground: Colors.black,
              focused: false,
              needsFocus: false,
              workshopLiveFolder: r'C:\workshop\double-live',
              myProjectsLiveFolder: r'C:\myprojects\double-live',
              workshopBackupFolder: null,
              myProjectsBackupFolder: null,
              loadDuplicateLiveChanges: loadComparison,
            ),
          ),
        ),
      ),
    );

    final Finder compare = find.byKey(
      const ValueKey<String>('backup-reconcile-expand-live-differences'),
    );
    expect(compare, findsOneWidget);
    expect(loads, 0);
    expect(
      find.byKey(
        const ValueKey<String>('backup-duplicate-live-comparison-progress'),
      ),
      findsNothing,
    );

    await tester.tap(compare);
    await tester.pump();

    expect(loads, 1);
    expect(
      find.byKey(
        const ValueKey<String>('backup-duplicate-live-comparison-progress'),
      ),
      findsOneWidget,
    );

    result.complete((
      changes: (
        modified: <String>['scene.pkg'],
        onlyFirst: <String>['workshop-only.txt'],
        onlySecond: <String>['myprojects-only.txt'],
      ),
      matching: <String>['project.json'],
    ));
    await tester.pump();
    await tester.pump();

    expect(loads, 1);
    expect(
      find.byKey(const ValueKey<String>('backup-duplicate-live-file-tree')),
      findsOneWidget,
    );
    expect(find.text('workshop-only.txt'), findsOneWidget);
    expect(find.text('myprojects-only.txt'), findsOneWidget);
    final FileTreeGroup workshopGroup = tester.widget<FileTreeGroup>(
      find.ancestor(
        of: find.text('workshop-only.txt'),
        matching: find.byType(FileTreeGroup),
      ),
    );
    final FileTreeGroup myProjectsGroup = tester.widget<FileTreeGroup>(
      find.ancestor(
        of: find.text('myprojects-only.txt'),
        matching: find.byType(FileTreeGroup),
      ),
    );
    expect(workshopGroup.title.toLowerCase(), contains('workshop'));
    expect(myProjectsGroup.title.toLowerCase(), contains('myprojects'));
  });

  testWidgets('duplicate live comparison lists files proven identical', (
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

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: SizedBox(
            width: 360,
            height: 300,
            child: ReconcileDetailContent(
              entry: entry,
              foreground: Colors.black,
              focused: false,
              needsFocus: false,
              workshopLiveFolder: r'C:\workshop\same-double-live',
              myProjectsLiveFolder: r'C:\myprojects\same-double-live',
              workshopBackupFolder: null,
              myProjectsBackupFolder: null,
              loadDuplicateLiveChanges: () async => (
                changes: (
                  modified: <String>[],
                  onlyFirst: <String>[],
                  onlySecond: <String>[],
                ),
                matching: <String>['project.json', 'scene.pkg'],
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(
      find.byKey(
        const ValueKey<String>('backup-reconcile-expand-live-differences'),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(
      find.byKey(
        const ValueKey<String>('backup-duplicate-live-matching-files'),
      ),
      findsOneWidget,
    );
    expect(find.textContaining('✓ project.json'), findsOneWidget);
    expect(find.textContaining('✓ scene.pkg'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('backup-duplicate-live-file-tree')),
      findsNothing,
    );
  });

  testWidgets('duplicate live tile wires both folders into comparison', (
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
      '${workshopRoot.path}${Platform.pathSeparator}double-live-wiring',
    )..createSync();
    final Directory myProjects = Directory(
      '${myProjectsRoot.path}${Platform.pathSeparator}double-live-wiring',
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
        name: 'double-live-wiring',
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

    final Finder compare = find.byKey(
      const ValueKey<String>('backup-reconcile-expand-live-differences'),
    );
    for (
      int attempt = 0;
      attempt < 40 && compare.evaluate().isEmpty;
      attempt++
    ) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 25));
      });
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(compare, findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('backup-duplicate-live-file-tree')),
      findsNothing,
    );

    await tester.tap(compare);
    await tester.pump();
    final Finder tree = find.byKey(
      const ValueKey<String>('backup-duplicate-live-file-tree'),
    );
    for (int attempt = 0; attempt < 40 && tree.evaluate().isEmpty; attempt++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 25));
      });
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(tree, findsOneWidget);
    expect(find.text('workshop-only.txt'), findsOneWidget);
    expect(find.text('myprojects-only.txt'), findsOneWidget);
    expect(tester.takeException(), isNull);
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
      expect(
        find.descendant(
          of: expandPrompt,
          matching: find.text(AppI10n.backupDetailCompareFilesHint),
        ),
        findsOneWidget,
      );
      expect(tester.getSize(expandPrompt).height, greaterThanOrEqualTo(48));
      final WallpaperDetailDialog detailDialog = tester.widget(
        find.byType(WallpaperDetailDialog),
      );
      expect(detailDialog.layout.maxHeight, 560);
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
        reason: 'metadata should keep its natural height above dense details',
      );
      expect(
        find.byKey(const ValueKey<String>('backup-reconcile-detail-scroll')),
        findsNothing,
      );

      final double previewBefore = tester.getSize(previewPane).width;
      final double panelBefore = tester.getSize(panelPane).width;
      final double totalBefore = previewBefore + panelBefore;
      final Size dialogBefore = tester.getSize(find.byType(Dialog));

      await tester.tap(
        find.byKey(const ValueKey<String>('wallpaper-detail-extra-focus-hint')),
      );
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
        reason: 'pane expansion must not reveal caller-owned work',
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

  testWidgets('small reconcile differences stay expanded without focus mode', (
    tester,
  ) async {
    final Directory folder = Directory.systemTemp.createTempSync(
      'we_repkg_reconcile_small_detail',
    );
    addTearDown(() {
      if (folder.existsSync()) folder.deleteSync(recursive: true);
    });
    File(
      '${folder.path}${Platform.pathSeparator}placeholder.txt',
    ).writeAsStringSync('different');

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
  });
}
