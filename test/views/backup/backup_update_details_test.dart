import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:we_repkg/config/theme.dart';
import 'package:we_repkg/constants/i10n.dart';
import 'package:we_repkg/cores/backup.dart';
import 'package:we_repkg/utils/backup_diff.dart';
import 'package:we_repkg/views/backup/backup_tile.dart';
import 'package:we_repkg/views/backup/details/content_details.dart';
import 'package:we_repkg/widgets/file_tree_panel.dart';

void main() {
  testWidgets('normal Backup tiles expose Update file inspection', (
    WidgetTester tester,
  ) async {
    final Directory root = Directory.systemTemp.createTempSync(
      'we_repkg_update_tile',
    );
    addTearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });
    const BackupCard card = BackupCard(WallpaperLibrary.workshop, 'updated');
    final Directory live = Directory(
      '${root.path}${Platform.pathSeparator}live${Platform.pathSeparator}${card.name}',
    )..createSync(recursive: true);
    final String backupLibrary = backupWorkshopPath(root.path)!;
    final Directory backup = Directory(
      '$backupLibrary${Platform.pathSeparator}${card.name}',
    )..createSync(recursive: true);
    File(
      '${live.path}${Platform.pathSeparator}project.json',
    ).writeAsStringSync('{"title":"Updated","type":"scene"}');
    File(
      '${backup.path}${Platform.pathSeparator}project.json',
    ).writeAsStringSync('{"title":"Old","type":"scene"}');

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: Center(
              child: BackupTileView(
                width: 180,
                tile: const (
                  card: card,
                  state: BackupState.updateAvailable,
                  face: null,
                ),
                folders: (live: live.path, backup: backup.path),
                updatePlan: const BackupUpdatePlan(updateContent: true),
                backupRoot: root.path,
                onTap: () {},
              ),
            ),
          ),
        ),
      ),
    );

    final Finder tile = find.byType(BackupTileView);
    await tester.tap(tile);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(tile);
    final Finder prompt = find.byKey(
      const ValueKey<String>('backup-update-expand-file-changes'),
    );
    for (
      int attempt = 0;
      attempt < 40 && prompt.evaluate().isEmpty;
      attempt++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(prompt, findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('backup-update-file-tree')),
      findsNothing,
    );
  });

  testWidgets('Update file inspection starts only after explicit expansion', (
    WidgetTester tester,
  ) async {
    final Completer<BackupFileChanges?> comparison =
        Completer<BackupFileChanges?>();
    final BackupUpdateSelection selection = BackupUpdateSelection(
      comparison.future,
    );
    addTearDown(selection.dispose);
    bool focused = false;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: SizedBox(
            width: 520,
            height: 420,
            child: StatefulBuilder(
              builder: (BuildContext context, StateSetter setState) =>
                  UpdatePlanDetailContent(
                    plan: const BackupUpdatePlan(updateContent: true),
                    card: const BackupCard(
                      WallpaperLibrary.workshop,
                      'updated',
                    ),
                    liveFolder: 'live',
                    backupFolder: 'backup',
                    foreground: Colors.white,
                    focused: focused,
                    needsFocus: true,
                    selection: selection,
                    onRequestFocus: () => setState(() => focused = true),
                  ),
            ),
          ),
        ),
      ),
    );

    final Finder prompt = find.byKey(
      const ValueKey<String>('backup-update-expand-file-changes'),
    );
    expect(prompt, findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('backup-update-file-tree')),
      findsNothing,
    );
    await tester.tap(prompt);
    await tester.pump();

    expect(find.text(AppI10n.backupDetailComparingFiles), findsOneWidget);

    comparison.complete((
      modified: <String>['project.json'],
      onlyLive: <String>['materials/new.tex'],
      onlyBackup: <String>['legacy.txt'],
    ));
    await tester.pump();

    final Finder tree = find.byKey(
      const ValueKey<String>('backup-update-file-tree'),
    );
    expect(tree, findsOneWidget);
    expect(
      find.descendant(of: tree, matching: find.byType(FileTreeGroupHeader)),
      findsNWidgets(3),
    );
    expect(find.text('project.json'), findsOneWidget);
    expect(find.text('materials  ›  new.tex'), findsOneWidget);
    expect(find.text('legacy.txt'), findsOneWidget);
    expect(find.byType(FileTreeCompareBar), findsOneWidget);
  });

  testWidgets('Update choices keep rejected copies and backup-only files', (
    WidgetTester tester,
  ) async {
    final BackupUpdateSelection selection = BackupUpdateSelection(
      Future<BackupFileChanges?>.value((
        modified: <String>['project.json'],
        onlyLive: <String>['materials/new.tex'],
        onlyBackup: <String>['legacy.txt'],
      )),
    );
    addTearDown(selection.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: SizedBox(
            width: 520,
            height: 420,
            child: UpdatePlanDetailContent(
              plan: const BackupUpdatePlan(updateContent: true),
              card: const BackupCard(WallpaperLibrary.workshop, 'updated'),
              liveFolder: 'live',
              backupFolder: 'backup',
              foreground: Colors.white,
              focused: true,
              needsFocus: true,
              selection: selection,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(FileTreeRowChoice), findsNWidgets(6));
    await tester.tap(
      find.byKey(const ValueKey<String>('backup-update-group-reject-modified')),
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('backup-update-reject-legacy.txt')),
    );
    await tester.pump();

    final BackupSelectiveUpdatePlan plan = (await selection.buildPlan())!;
    expect(plan.skippedCopies, const <String>{'project.json'});
    expect(plan.keptBackupFiles, const <String>{'legacy.txt'});
    expect(find.text(AppI10n.backupDetailWillKeep), findsOneWidget);
  });

  testWidgets('Update file inspection distinguishes empty and unavailable', (
    WidgetTester tester,
  ) async {
    final List<BackupUpdateSelection> selections = <BackupUpdateSelection>[];
    addTearDown(() {
      for (final BackupUpdateSelection selection in selections) {
        selection.dispose();
      }
    });

    Future<void> show(Future<BackupFileChanges?> result) {
      final BackupUpdateSelection selection = BackupUpdateSelection(result);
      selections.add(selection);
      return tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: SizedBox(
              width: 520,
              height: 420,
              child: UpdatePlanDetailContent(
                plan: const BackupUpdatePlan(updateContent: true),
                card: const BackupCard(WallpaperLibrary.workshop, 'updated'),
                liveFolder: 'live',
                backupFolder: 'backup',
                foreground: Colors.white,
                focused: true,
                needsFocus: true,
                selection: selection,
              ),
            ),
          ),
        ),
      );
    }

    await show(
      Future<BackupFileChanges?>.value((
        modified: <String>[],
        onlyLive: <String>[],
        onlyBackup: <String>[],
      )),
    );
    await tester.pump();
    expect(find.text(AppI10n.backupDetailNoFileDifferences), findsOneWidget);

    await show(Future<BackupFileChanges?>.value(null));
    await tester.pump();
    expect(
      find.text(AppI10n.backupDetailFileComparisonUnavailable),
      findsOneWidget,
    );
  });
}
