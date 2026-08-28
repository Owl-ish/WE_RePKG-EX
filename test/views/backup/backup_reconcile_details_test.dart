import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:we_repkg/config/theme.dart';
import 'package:we_repkg/constants/i10n.dart';
import 'package:we_repkg/utils/backup_diff.dart';
import 'package:we_repkg/utils/backup_tiles.dart';
import 'package:we_repkg/views/backup/backup_tile.dart';
import 'package:we_repkg/views/content/detail_dialog.dart';

void main() {
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
      expect(find.text(AppI10n.backupDetailExpandDifferences), findsOneWidget);
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
