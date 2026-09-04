import 'dart:io';

import 'package:bot_toast/bot_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:we_repkg/constants/i10n.dart';
import 'package:we_repkg/cores/backup.dart';
import 'package:we_repkg/models/enums.dart';
import 'package:we_repkg/provider/backup.dart';
import 'package:we_repkg/provider/system.dart';
import 'package:we_repkg/provider/wallpaper.dart';
import 'package:we_repkg/utils/backup_diff.dart';
import 'package:we_repkg/utils/storage.dart';
import 'package:we_repkg/actions/backup_actions.dart';

void main() {
  late Directory temporary;
  late String backupRoot;
  late String projects;
  late String workshop;
  late ProviderContainer container;
  int scanReads = 0;
  const card = BackupCard(WallpaperLibrary.myProjects, 'demo');
  const BackupScan emptyScan = (
    cards: {},
    updates: {},
    ignoredUpdates: {},
    presence: {},
    junk: {},
    reconcile: [],
    acfRead: true,
    missing: {},
  );

  setUp(() async {
    temporary = Directory.systemTemp.createTempSync('werepkg-backup-actions-');
    backupRoot = path.join(temporary.path, 'backup');
    projects = path.join(temporary.path, 'projects');
    workshop = path.join(temporary.path, 'workshop');
    for (final root in [backupRoot, projects, workshop]) {
      Directory(root).createSync();
    }
    SharedPreferences.setMockInitialValues({});
    await StorageUtil.initWithoutFile();
    scanReads = 0;
    container = ProviderContainer(
      overrides: [
        backupRootProvider.overrideWithValue(backupRoot),
        myProjectsLibraryProvider.overrideWithValue(projects),
        wallpaperPathProvider.overrideWithValue(workshop),
        acfPathProvider.overrideWithValue(null),
        backupScanProvider.overrideWith((ref) async {
          scanReads++;
          return emptyScan;
        }),
        // Selection pruning is unrelated to action completion. Keep this card
        // visible so only the action under test can clear the selection.
        backupVisibleIdsProvider.overrideWithValue(AsyncData({card.id})),
      ],
    );
  });

  tearDown(() {
    container.dispose();
    temporary.deleteSync(recursive: true);
  });

  File write(String folder, String name, String text) =>
      File(path.join(folder, name))
        ..createSync(recursive: true)
        ..writeAsStringSync(text);

  Future<BuildContext> host(WidgetTester tester) async {
    late BuildContext context;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          builder: BotToastInit(),
          navigatorObservers: [BotToastNavigatorObserver()],
          home: Builder(
            builder: (value) {
              context = value;
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    await container.read(backupScanProvider.future);
    container.read(backupSelectionProvider.notifier).setExactly({card.id});
    await tester.pump();
    return context;
  }

  Future<void> finish(
    WidgetTester tester,
    Future<void> Function() start,
    String label,
  ) async {
    late Future<void> action;
    // Start the operation in the real async zone so file reads can complete
    // after confirmation; only the dialog animation uses the fake clock.
    await tester.runAsync(() async {
      action = start();
    });
    await tester.pumpAndSettle();
    await tester.tap(find.text(label));
    // BotToast removes the confirmation on frames after the closing animation.
    // Await its actual removal before waiting on I/O; waiting on the action
    // earlier would prevent the frames that let the action start.
    for (
      int frame = 0;
      frame < 10 && find.text(label).evaluate().isNotEmpty;
      frame++
    ) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text(label), findsNothing);
    await tester.runAsync(() => action.timeout(const Duration(seconds: 10)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
  }

  Future<void> expectRefresh({required bool changed}) async {
    await container.read(backupScanProvider.future);
    expect(scanReads, changed ? 2 : 1);
    expect(
      container.read(backupSelectionProvider),
      changed ? isEmpty : {card.id},
    );
  }

  Future<void> dismissToasts(WidgetTester tester) async {
    BotToast.cleanAll();
    await tester.pumpAndSettle();
  }

  for (final mode in ['back up', 'full update', 'selective update']) {
    testWidgets('$mode reaches the real file worker and refreshes Backup', (
      tester,
    ) async {
      final live = path.join(projects, card.name);
      final backup = path.join(backupMyProjectsPath(backupRoot)!, card.name);
      write(live, 'project.json', '{}');
      final source = write(live, 'scene.json', 'new contents');
      final target = write(backup, 'scene.json', 'old');
      final residue = write(backup, 'legacy.txt', 'keep if not a full update');
      final context = await host(tester);
      final selective = mode == 'selective update';
      final action = mode == 'back up'
          ? BackupAction.backUp
          : BackupAction.update;
      final selection = selective
          ? BackupSelectiveUpdatePlan(
              expectedChanges: (
                modified: ['scene.json'],
                onlyLive: ['project.json'],
                onlyBackup: ['legacy.txt'],
              ),
              keptBackupFiles: {'legacy.txt'},
            )
          : null;

      await finish(
        tester,
        () => applyBackupAction(context, action, [
          card,
        ], selectiveUpdate: selection),
        action == BackupAction.backUp
            ? AppI10n.backupActionBackUp
            : AppI10n.backupActionUpdate,
      );

      expect(target.readAsStringSync(), 'new contents');
      expect(source.readAsStringSync(), 'new contents');
      expect(residue.existsSync(), mode != 'full update');
      final records = await tester.runAsync(
        () => readBackupRecords(backupRoot),
      );
      expect(
        records?[card.id]?.backedUpVersion,
        selective ? isNull : isNotNull,
      );
      await expectRefresh(changed: true);
      await dismissToasts(tester);
    });
  }

  testWidgets(
    'cancelled Back up leaves files, selection and cached scan alone',
    (tester) async {
      write(path.join(projects, card.name), 'project.json', '{}');
      final context = await host(tester);
      await finish(
        tester,
        () => applyBackupAction(context, BackupAction.backUp, [card]),
        AppI10n.cancel,
      );
      expect(
        Directory(backupMyProjectsPath(backupRoot)!).existsSync(),
        isFalse,
      );
      await expectRefresh(changed: false);
      await dismissToasts(tester);
    },
  );

  testWidgets('missing source reports the failure without clearing selection', (
    tester,
  ) async {
    final context = await host(tester);
    await finish(
      tester,
      () => applyBackupAction(context, BackupAction.backUp, [card]),
      AppI10n.backupActionBackUp,
    );
    expect(
      find.textContaining(AppI10n.backupActionSourceMissing),
      findsOneWidget,
    );
    expect(Directory(backupMyProjectsPath(backupRoot)!).existsSync(), isFalse);
    await expectRefresh(changed: false);
    await dismissToasts(tester);
  });

  testWidgets(
    'partial failure still refreshes Backup and clears its selection',
    (tester) async {
      final context = await host(tester);
      await finish(
        tester,
        () => applyBackupAction(
          context,
          BackupAction.update,
          [card],
          runAction: (_, _) async =>
              (changed: true, error: 'source changed during copy'),
        ),
        AppI10n.backupActionUpdate,
      );
      expect(find.textContaining('source changed during copy'), findsOneWidget);
      expect(find.textContaining(AppI10n.backupActionDone), findsNothing);
      await expectRefresh(changed: true);
      await dismissToasts(tester);
    },
  );

  testWidgets('Restore publishes to MyProjects and resets its loaded state', (
    tester,
  ) async {
    final source = write(
      path.join(backupWorkshopPath(backupRoot)!, card.name),
      'scene.pkg',
      'package',
    );
    final context = await host(tester);
    container
        .read(currentLibraryProvider.notifier)
        .update(WallpaperLibrary.myProjects);
    container.read(currentStateProvider.notifier).update(RunState.complete);
    container.read(checkedIdsProvider.notifier).setExactly({'old-selection'});

    await finish(
      tester,
      () => applyBackupAction(context, BackupAction.restore, [
        BackupCard(WallpaperLibrary.workshop, card.name),
      ]),
      AppI10n.backupActionRestore,
    );

    expect(
      File(path.join(projects, card.name, 'scene.pkg')).readAsStringSync(),
      'package',
    );
    expect(source.readAsStringSync(), 'package');
    expect(Directory(path.join(workshop, card.name)).existsSync(), isFalse);
    expect(container.read(currentStateProvider), RunState.initial);
    expect(container.read(checkedIdsProvider), isEmpty);
    await expectRefresh(changed: true);
    await dismissToasts(tester);
  });

  testWidgets('Ignore and Show Again preserve the backup version and files', (
    tester,
  ) async {
    final source = write(path.join(projects, card.name), 'project.json', '{}');
    await tester.runAsync(
      () => writeBackupRecords(backupRoot, {
        card.id: const BackupRecord(backedUpVersion: 'saved-baseline'),
      }),
    );
    final context = await host(tester);
    await finish(
      tester,
      () => applyBackupAction(context, BackupAction.ignoreUpdate, [card]),
      AppI10n.backupActionIgnore,
    );
    final ignored = await tester.runAsync(() => readBackupRecords(backupRoot));
    expect(ignored?[card.id]?.dismissedVersion, isNotNull);
    expect(ignored?[card.id]?.backedUpVersion, 'saved-baseline');
    await expectRefresh(changed: true);
    await dismissToasts(tester);

    await finish(
      tester,
      () => applyBackupAction(context, BackupAction.showUpdateAgain, [card]),
      AppI10n.backupActionShowAgain,
    );
    final shown = await tester.runAsync(() => readBackupRecords(backupRoot));
    expect(shown?[card.id]?.dismissedVersion, isNull);
    expect(shown?[card.id]?.backedUpVersion, 'saved-baseline');
    expect(source.readAsStringSync(), '{}');
    await dismissToasts(tester);
  });

  testWidgets(
    'Reconcile ignores eligible reasons and restores them individually or together',
    (tester) async {
      const duplicate = BackupReconcileReason.duplicateLiveCopies;
      const conflict = BackupReconcileReason.conflictingBackupCopies;
      const unavailable = BackupReconcileReason.comparisonUnavailable;
      const entry = ReconcileEntry(
        name: 'demo',
        reason: duplicate,
        states: {},
        backupWorkshop: true,
        backupMyProjects: true,
        additionalReasons: {conflict, unavailable},
        issueFingerprints: {
          duplicate: 'live-evidence',
          conflict: 'backup-evidence',
          unavailable: 'not-ignorable',
        },
      );
      final context = await host(tester);
      await finish(
        tester,
        () => ignoreReconcileDetections(context, entry),
        AppI10n.backupActionIgnore,
      );
      final ignored = await tester.runAsync(
        () => readBackupRecords(backupRoot),
      );
      expect(
        ignored?[reconcileIgnoreRecordId('demo')]?.ignoredReconcileIssues,
        {duplicate: 'live-evidence', conflict: 'backup-evidence'},
      );
      await expectRefresh(changed: true);
      await dismissToasts(tester);

      await finish(
        tester,
        () => showReconcileDetectionAgain(context, entry, duplicate),
        AppI10n.backupActionShowAgain,
      );
      final remaining = await tester.runAsync(
        () => readBackupRecords(backupRoot),
      );
      expect(
        remaining?[reconcileIgnoreRecordId('demo')]?.ignoredReconcileIssues,
        {conflict: 'backup-evidence'},
      );
      await dismissToasts(tester);

      await tester.runAsync(
        () => writeBackupRecords(backupRoot, {
          ...remaining!,
          card.id: const BackupRecord(
            backedUpVersion: 'saved',
            dismissedVersion: 'ignored',
          ),
        }),
      );
      final BackupScan scan = (
        cards: {},
        updates: {},
        ignoredUpdates: {card},
        presence: {},
        junk: {},
        reconcile: [
          const ReconcileEntry(
            name: 'demo',
            reason: conflict,
            states: {},
            backupWorkshop: true,
            backupMyProjects: true,
            ignoredReasons: {conflict},
          ),
        ],
        acfRead: true,
        missing: {},
      );
      await finish(
        tester,
        () => showAllIgnoredDetections(context, scan),
        AppI10n.backupActionShowAgain,
      );
      final shown = await tester.runAsync(() => readBackupRecords(backupRoot));
      expect(shown?.containsKey(reconcileIgnoreRecordId('demo')), isFalse);
      expect(shown?[card.id]?.dismissedVersion, isNull);
      expect(shown?[card.id]?.backedUpVersion, 'saved');
      await dismissToasts(tester);
    },
  );

  testWidgets('Recycle refuses healthy folders without removing files', (
    tester,
  ) async {
    final source = write(path.join(projects, card.name), 'project.json', '{}');
    final target = write(
      path.join(backupMyProjectsPath(backupRoot)!, card.name),
      'project.json',
      '{}',
    );
    final context = await host(tester);
    await finish(
      tester,
      () => applyBackupAction(context, BackupAction.recycleJunk, [card]),
      AppI10n.backupActionRecycle,
    );
    expect(source.readAsStringSync(), '{}');
    expect(target.readAsStringSync(), '{}');
    await expectRefresh(changed: false);
    await dismissToasts(tester);
  });
}
