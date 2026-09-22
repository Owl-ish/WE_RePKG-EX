import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:we_repkg/config/theme.dart';
import 'package:we_repkg/constants/i10n.dart';
import 'package:we_repkg/cores/backup.dart';
import 'package:we_repkg/views/backup/details/backup_file_browser.dart';
import 'package:we_repkg/views/backup/details/content_details.dart';
import 'package:we_repkg/widgets/file_tree_panel.dart';

Future<void> _waitFor(WidgetTester tester, Finder finder) async {
  for (int attempt = 0; attempt < 80 && finder.evaluate().isEmpty; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 25)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(finder, findsWidgets);
}

void main() {
  for (final bool dark in <bool>[false, true]) {
    for (final double width in <double>[600, 1100]) {
      testWidgets('paired Update aligns and links rows at $width dark=$dark', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(Size(width, 700));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final BackupUpdateSelection selection = BackupUpdateSelection(
          Future.value((
            modified: <String>[
              for (int i = 0; i < 35; i++)
                '文件夹/${i.toString().padLeft(2, '0')}.txt',
            ],
            onlyLive: <String>['added.txt'],
            onlyBackup: <String>['removed.txt'],
          )),
        );
        addTearDown(selection.dispose);
        await tester.pumpWidget(
          MaterialApp(
            theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
            home: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
              child: Material(
                child: UpdateFileChanges(
                  wallpaperName: 'paired',
                  liveFolder: r'C:\fixture-live',
                  backupFolder: r'C:\fixture-backup',
                  sourceLabel: 'Live',
                  destinationLabel: 'Backup',
                  rePKGPath: null,
                  foreground: dark ? Colors.white : Colors.black,
                  selection: selection,
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump();
        expect(tester.takeException(), isNull);
        if (Platform.isWindows) {
          expect(find.byType(Tooltip), findsNothing);
        }
        expect(find.text(AppI10n.backupMissingLive), findsOneWidget);
        expect(find.text(AppI10n.backupMissingBackup), findsOneWidget);
        final Finder left = find.byKey(
          const ValueKey<String>('update-row-live-文件夹/00.txt'),
        );
        final Finder right = find.byKey(
          const ValueKey<String>('update-row-backup-文件夹/00.txt'),
        );
        final Finder compare = find.byKey(
          const ValueKey<String>('update-pair-compare-文件夹/00.txt'),
        );
        final FileTreeRow modifiedRow = tester.widget<FileTreeRow>(
          find.descendant(of: right, matching: find.byType(FileTreeRow)),
        );
        expect(modifiedRow.contextActions, hasLength(1));
        expect(modifiedRow.contextActions.single.enabled, isTrue);
        expect(
          tester.getCenter(left).dy,
          closeTo(tester.getCenter(right).dy, .1),
        );
        expect(
          tester.getCenter(compare).dy,
          closeTo(tester.getCenter(right).dy, .1),
        );
        await tester.tap(find.byKey(const ValueKey('file-tree-collapse-all')));
        await tester.pump();
        expect(left, findsNothing);
        expect(right, findsNothing);
        await tester.tap(find.byKey(const ValueKey('file-tree-expand-all')));
        await tester.pump();
        expect(left, findsOneWidget);
        expect(right, findsOneWidget);
        ScrollController controller(String side) => tester
            .widget<FileTreeScrollView>(
              find.byKey(ValueKey<String>('update-paired-$side')),
            )
            .verticalController!;
        final ScrollController live = controller('live');
        final ScrollController backup = controller('backup');
        final Finder rail = find.byKey(
          const ValueKey<String>('update-compare-rail'),
        );
        final ScrollController railController = tester
            .widget<SingleChildScrollView>(rail)
            .controller!;
        expect(tester.getSize(rail).width, 32);
        expect(
          find.descendant(of: rail, matching: find.byType(Scrollbar)),
          findsNothing,
        );
        live.jumpTo(160);
        await tester.pump();
        expect(backup.offset, closeTo(live.offset, .1));
        expect(railController.offset, closeTo(live.offset, .1));
        backup.jumpTo(220);
        await tester.pump();
        expect(live.offset, closeTo(backup.offset, .1));
        await tester.tap(
          find.byKey(const ValueKey<String>('update-link-scrolling')),
        );
        await tester.pump();
        live.jumpTo(80);
        await tester.pump();
        expect(backup.offset, closeTo(220, .1));
        expect(railController.offset, closeTo(80, .1));
        await tester.tap(
          find.byKey(const ValueKey<String>('update-link-scrolling')),
        );
        await tester.pump();
        expect(backup.offset, closeTo(80, .1));
        live.jumpTo(live.position.maxScrollExtent);
        await tester.pump();
        expect(railController.offset, closeTo(live.offset, .1));
        expect(
          tester
              .getCenter(
                find.byKey(
                  const ValueKey<String>('update-pair-compare-文件夹/34.txt'),
                ),
              )
              .dy,
          closeTo(
            tester
                .getCenter(
                  find.byKey(
                    const ValueKey<String>('update-row-backup-文件夹/34.txt'),
                  ),
                )
                .dy,
            .1,
          ),
        );
        live.jumpTo(0);
        await tester.pump();
        await tester.tap(
          find.byKey(const ValueKey<String>('update-folder-live-文件夹')),
        );
        await tester.pump();
        expect(left, findsNothing);
        expect(right, findsNothing);
        expect(compare, findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }
  }

  testWidgets(
    'Update browser shares copy and removal choices with its caller',
    (tester) async {
      final Directory root = Directory.systemTemp.createTempSync(
        'browser_choices_',
      );
      addTearDown(() => root.deleteSync(recursive: true));
      final BackupUpdateSelection selection = BackupUpdateSelection(
        Future.value((
          modified: <String>[],
          onlyLive: <String>['added.txt'],
          onlyBackup: <String>['removed.txt'],
        )),
      );
      addTearDown(selection.dispose);
      selection.setCopySelected('added.txt', false);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: BackupFileBrowser(
            wallpaperName: 'choices',
            liveFolder: root.path,
            backupFolder: root.path,
            updateSelection: selection,
          ),
        ),
      );
      expect(find.byType(UpdateFileChanges), findsNothing);
      await tester.tap(find.text(AppI10n.backupDetailCompareFiles));
      await tester.pump();
      await tester.pump();
      final Finder updateView = find.byType(UpdateFileChanges);
      expect(updateView, findsOneWidget);
      expect(
        tester.widget<UpdateFileChanges>(updateView).selection,
        same(selection),
      );
      expect(find.text(AppI10n.backupTileUpdate), findsNothing);
      expect(find.text(AppI10n.backupLiveSource), findsOneWidget);
      expect(find.text(AppI10n.backupBackupDestination), findsOneWidget);

      final Finder acceptCopy = find.byKey(
        const ValueKey<String>('backup-update-accept-added.txt'),
      );
      await tester.ensureVisible(acceptCopy);
      await tester.tap(acceptCopy);
      expect(selection.copySelected('added.txt'), isTrue);
      final Finder keepBackup = find.byKey(
        const ValueKey<String>('backup-update-reject-removed.txt'),
      );
      await tester.ensureVisible(keepBackup);
      await tester.tap(keepBackup);
      expect(selection.deletionSelected('removed.txt'), isFalse);
      final BackupSelectiveUpdatePlan plan = (await selection.buildPlan())!;
      expect(plan.keptBackupFiles, contains('removed.txt'));
      expect(plan.skippedCopies, isEmpty);

      await tester.tap(find.text(AppI10n.backupBrowseFiles));
      await tester.pump();
      selection.setCopySelected('added.txt', false);
      await tester.tap(find.text(AppI10n.backupDetailCompareFiles));
      await tester.pump();
      expect(selection.copySelected('added.txt'), isFalse);
      await tester.pumpWidget(const SizedBox());
      selection.setCopySelected('added.txt', true);
      expect(selection.copySelected('added.txt'), isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  for (final bool liveOnly in <bool>[false, true]) {
    testWidgets('browser supports only ${liveOnly ? "live" : "backup"} files', (
      tester,
    ) async {
      final Directory root = Directory.systemTemp.createTempSync(
        'browser_single_',
      );
      addTearDown(() => root.deleteSync(recursive: true));
      File('${root.path}/file.txt').writeAsStringSync('contents');
      await tester.pumpWidget(
        MaterialApp(
          home: BackupFileBrowser(
            wallpaperName: 'single',
            liveFolder: liveOnly ? root.path : null,
            backupFolder: liveOnly ? null : root.path,
          ),
        ),
      );
      await _waitFor(tester, find.text('file.txt'));
      expect(find.byType(FileTreePanel), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('backup-browser-link-scrolling')),
        findsNothing,
      );
      expect(find.text(AppI10n.backupDetailCompareFiles), findsNothing);
      expect(
        find.text(
          liveOnly
              ? AppI10n.backupOpenLiveFolder
              : AppI10n.backupOpenBackupFolder,
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('browser links unequal folder scrolls and retains expansion', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1100, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final Directory root = Directory.systemTemp.createTempSync('browser_link_');
    addTearDown(() => root.deleteSync(recursive: true));
    final Directory live = Directory('${root.path}/live')..createSync();
    final Directory backup = Directory('${root.path}/backup')..createSync();
    final Directory nested = Directory('${live.path}/nested')..createSync();
    File('${nested.path}/child.txt').writeAsStringSync('nested');
    for (int i = 0; i < 45; i++) {
      File(
        '${live.path}/日本語中文한국어_${i.toString().padLeft(2, '0')}.txt',
      ).writeAsStringSync('live');
    }
    for (int i = 0; i < 30; i++) {
      File('${backup.path}/backup_$i.txt').writeAsStringSync('backup');
    }
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.windows),
        home: BackupFileBrowser(
          wallpaperName: 'scroll',
          liveFolder: live.path,
          backupFolder: backup.path,
        ),
      ),
    );
    await _waitFor(tester, find.text('child.txt'));
    final List<FileTreePanel> panes = tester
        .widgetList<FileTreePanel>(find.byType(FileTreePanel))
        .toList();
    final ScrollController left = panes[0].verticalController!;
    final ScrollController right = panes[1].verticalController!;
    expect(right.position.maxScrollExtent, greaterThan(100));
    expect(
      left.position.maxScrollExtent,
      greaterThan(right.position.maxScrollExtent),
    );
    left.jumpTo(left.position.maxScrollExtent);
    await tester.pump();
    expect(right.offset, closeTo(right.position.maxScrollExtent, .1));
    expect(left.offset, closeTo(left.position.maxScrollExtent, .1));
    await tester.tap(
      find.byKey(const ValueKey<String>('backup-browser-link-scrolling')),
    );
    await tester.pump();
    right.jumpTo(0);
    await tester.pump();
    expect(left.offset, greaterThan(0));
    left.jumpTo(60);
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey<String>('backup-browser-link-scrolling')),
    );
    await tester.pump();
    expect(right.offset, closeTo(60, .1));
    right.jumpTo(100);
    await tester.pump();
    expect(left.offset, closeTo(100, .1));
    left.jumpTo(0);
    await tester.pump();
    await tester.tap(find.text('nested'));
    await tester.pump();
    expect(find.text('child.txt'), findsNothing);
    await tester.tap(find.text(AppI10n.backupDetailCompareFiles));
    await _waitFor(
      tester,
      find.byKey(const ValueKey<String>('backup-update-file-tree')),
    );
    await tester.tap(find.text(AppI10n.backupBrowseFiles));
    await tester.pump();
    expect(find.text('child.txt'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  testWidgets('browser tolerates no available folder locations', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: BackupFileBrowser(
          wallpaperName: 'unavailable',
          liveFolder: null,
          backupFolder: null,
        ),
      ),
    );
    expect(find.byType(FileTreePanel), findsNothing);
    expect(find.text(AppI10n.backupDetailCompareFiles), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'comparison uses the paired tree for matching and unavailable folders',
    (tester) async {
      final Directory root = Directory.systemTemp.createTempSync(
        'browser_matching_',
      );
      addTearDown(() => root.deleteSync(recursive: true));
      final Directory live = Directory('${root.path}/live')..createSync();
      final Directory backup = Directory('${root.path}/backup')..createSync();
      File('${live.path}/same.txt').writeAsStringSync('same');
      File('${backup.path}/same.txt').writeAsStringSync('same');
      for (final bool available in <bool>[true, false]) {
        await tester.pumpWidget(
          MaterialApp(
            home: BackupFileBrowser(
              key: ValueKey<bool>(available),
              wallpaperName: 'matching',
              liveFolder: live.path,
              backupFolder: available ? backup.path : '${root.path}/missing',
            ),
          ),
        );
        await tester.tap(find.text(AppI10n.backupDetailCompareFiles));
        await _waitFor(
          tester,
          available
              ? find.byKey(const ValueKey<String>('backup-update-file-tree'))
              : find.text(AppI10n.backupDetailFileComparisonUnavailable),
        );
        if (available) {
          expect(find.text('same.txt'), findsNWidgets(2));
          expect(
            find.byKey(const ValueKey<String>('update-pair-compare-same.txt')),
            findsOneWidget,
          );
        }
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final bool dark in <bool>[false, true]) {
    for (final double width in <double>[600, 1200]) {
      testWidgets('browser fits $width wide in ${dark ? "dark" : "light"}', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(Size(width, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final Directory root = Directory.systemTemp.createTempSync('browser_');
        addTearDown(() => root.deleteSync(recursive: true));
        final Directory live = Directory('${root.path}/live')..createSync();
        final Directory backup = Directory('${root.path}/backup')..createSync();
        File('${live.path}/中文.png').writeAsStringSync('live');
        File('${backup.path}/中文.png').writeAsStringSync('backup');
        await tester.pumpWidget(
          MaterialApp(
            theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(1.5)),
              child: child!,
            ),
            home: BackupFileBrowser(
              wallpaperName: '日本語 한국어 中文',
              liveFolder: live.path,
              backupFolder: backup.path,
            ),
          ),
        );
        await _waitFor(tester, find.text('中文.png'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byType(FileTreePanel), findsNWidgets(2));
        expect(
          find.byKey(const ValueKey<String>('backup-update-file-tree')),
          findsNothing,
        );
        await tester.tap(find.text(AppI10n.backupDetailCompareFiles));
        await _waitFor(
          tester,
          find.byKey(const ValueKey<String>('backup-update-file-tree')),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(
          find.byKey(const ValueKey<String>('backup-update-file-tree')),
          findsOneWidget,
        );
        await tester.tap(find.text(AppI10n.backupBrowseFiles));
        await tester.pumpAndSettle();
        expect(find.byType(FileTreePanel), findsNWidgets(2));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }
  }

  testWidgets('shared comparison prompts wrap their full guidance', (
    tester,
  ) async {
    for (final String title in <String>[
      'File changes',
      'Compare Files',
      '比较文件',
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: 200,
              child: BackupDetailExpandPrompt(
                title: title,
                subtitle:
                    'Click to expand and inspect changed files in this wallpaper',
                foreground: Colors.black,
                onPressed: () {},
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      final Text guidance = tester.widget<Text>(
        find.text(
          'Click to expand and inspect changed files in this wallpaper',
        ),
      );
      expect(guidance.maxLines, isNull);
      expect(guidance.overflow, isNull);
    }
  });
}
