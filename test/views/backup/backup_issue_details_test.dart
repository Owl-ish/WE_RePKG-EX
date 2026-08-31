import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:we_repkg/config/theme_extensions.dart';
import 'package:we_repkg/constants/i10n.dart';
import 'package:we_repkg/utils/backup_diff.dart';
import 'package:we_repkg/utils/backup_tiles.dart';
import 'package:we_repkg/utils/storage.dart';
import 'package:we_repkg/utils/wallpaper_junk.dart';
import 'package:we_repkg/views/backup/backup_tile.dart';
import 'package:we_repkg/views/backup/details/issue_details.dart';
import 'package:we_repkg/widgets/file_tree_panel.dart';

import '../../support/backup_test_harness.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await StorageUtil.init();
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
      final bool usesSharedGroupHeader =
          hasTree &&
          find
              .descendant(
                of: treeFinder,
                matching: find.byType(FileTreeGroupHeader),
              )
              .evaluate()
              .isNotEmpty;
      final Finder rootHeader = find.descendant(
        of: treeFinder,
        matching: find.byType(FileTreeGroupHeader),
      );
      final Finder rootFolderIcon = find.descendant(
        of: rootHeader,
        matching: find.byIcon(Icons.folder_open_rounded),
      );
      final Color? rootFolderColour = rootFolderIcon.evaluate().isEmpty
          ? null
          : tester.widget<Icon>(rootFolderIcon.first).color;
      final Color workshopColour = Theme.of(
        tester.element(treeFinder),
      ).status.note;
      final bool showedNestedFolder =
          hasTree && await waitFor(find.text('blobssm40'));
      final bool showedFile = hasTree && await waitFor(find.text('cache.dxs'));
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
      expect(usesSharedGroupHeader, isTrue);
      expect(rootFolderColour, workshopColour);
      expect(showedNestedFolder, isTrue);
      expect(showedFile, isTrue);
      expect(hasVerticalTreeScroll, isTrue);
      expect(hasHorizontalTreeScroll, isTrue);
      expect(treeScrollbarCount, 2);
    },
  );

  testWidgets('Reconcile details show every reason, warning, and folder', (
    tester,
  ) async {
    const ReconcileEntry entry = ReconcileEntry(
      name: '3707191336',
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
    );
    const List<String> folders = <String>[
      r'C:\live\workshop\3707191336',
      r'C:\live\myprojects\3707191336',
      r'C:\backup\workshop\3707191336',
      r'C:\backup\myprojects\3707191336',
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 900,
            height: 520,
            child: ReconcileDetailContent(
              entry: entry,
              foreground: Colors.black,
              focused: false,
              needsFocus: false,
              workshopLiveFolder: folders[0],
              myProjectsLiveFolder: folders[1],
              workshopBackupFolder: folders[2],
              myProjectsBackupFolder: folders[3],
            ),
          ),
        ),
      ),
    );

    expect(
      find.text('• ${AppI10n.backupReconcileConflictingBackupsAbout}'),
      findsOneWidget,
    );
    expect(
      find.text('• ${AppI10n.backupStateUpdateAvailable}'),
      findsOneWidget,
    );
    for (final String folder in folders) {
      expect(find.text(folder), findsOneWidget);
    }
  });
}
