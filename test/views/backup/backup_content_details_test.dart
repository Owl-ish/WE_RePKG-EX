import 'dart:convert';
import 'dart:io';

import 'package:bot_toast/bot_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:we_repkg/config/theme.dart';
import 'package:we_repkg/constants/i10n.dart';
import 'package:we_repkg/cores/backup.dart';
import 'package:we_repkg/provider/system.dart';
import 'package:we_repkg/utils/backup_diff.dart';
import 'package:we_repkg/utils/backup_tiles.dart';
import 'package:we_repkg/utils/storage.dart';
import 'package:we_repkg/views/backup/backup_tile.dart';
import 'package:we_repkg/widgets/file_tree_panel.dart';
import 'package:we_repkg/widgets/input_controls.dart';

import '../../support/backup_test_harness.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await StorageUtil.init();
  });

  testWidgets('Update details compare files lazily and use the shared file tree', (
    tester,
  ) async {
    final Directory root = Directory.systemTemp.createTempSync(
      'we_repkg_update_detail',
    );
    addTearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });
    final Directory workshop = Directory(
      '${root.path}${Platform.pathSeparator}workshop-live',
    )..createSync();
    final String backupLibrary = backupWorkshopPath(root.path)!;
    Directory(backupLibrary).createSync(recursive: true);
    const BackupCard card = BackupCard(WallpaperLibrary.workshop, 'updated');
    final Directory live = Directory(
      '${workshop.path}${Platform.pathSeparator}${card.name}',
    )..createSync();
    final Directory backup = Directory(
      '$backupLibrary${Platform.pathSeparator}${card.name}',
    )..createSync();

    File(
      '${live.path}${Platform.pathSeparator}project.json',
    ).writeAsStringSync('{"title":"Updated","type":"scene"}');
    File(
      '${backup.path}${Platform.pathSeparator}project.json',
    ).writeAsStringSync('{"title":"Old","type":"scene"}');
    File(
      '${live.path}${Platform.pathSeparator}scene.pkg',
    ).writeAsStringSync('new package contents');
    File(
      '${backup.path}${Platform.pathSeparator}scene.pkg',
    ).writeAsStringSync('old');
    final Directory liveEffects = Directory(
      '${live.path}${Platform.pathSeparator}effects',
    )..createSync();
    final Directory backupEffects = Directory(
      '${backup.path}${Platform.pathSeparator}effects',
    )..createSync();
    File(
      '${liveEffects.path}${Platform.pathSeparator}settings.json',
    ).writeAsStringSync('{"strength":2,"enabled":true}');
    File(
      '${backupEffects.path}${Platform.pathSeparator}settings.json',
    ).writeAsStringSync('{"strength":1,"enabled":true}');
    File('${live.path}${Platform.pathSeparator}preview.png').writeAsBytesSync(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0kAAAAFElEQVR4nGP8z8Dwn4GBgYGJAQoAHxcCAk+Uzr4AAAAASUVORK5CYII=',
      ),
    );
    File('${backup.path}${Platform.pathSeparator}preview.png').writeAsBytesSync(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0kAAAAFElEQVR4nGNkYPj/n4GBgYGJAQoAHRkCAjRcHicAAAAASUVORK5CYII=',
      ),
    );
    final Directory liveMaterials = Directory(
      '${live.path}${Platform.pathSeparator}materials',
    )..createSync();
    File(
      '${liveMaterials.path}${Platform.pathSeparator}new.tex',
    ).writeAsStringSync('new texture');
    File(
      '${backup.path}${Platform.pathSeparator}legacy.txt',
    ).writeAsStringSync('kept residue');
    File(
      '${live.path}${Platform.pathSeparator}manual-new.png',
    ).writeAsBytesSync(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0kAAAAFElEQVR4nGP8z8Dwn4GBgYGJAQoAHxcCAk+Uzr4AAAAASUVORK5CYII=',
      ),
    );
    File(
      '${backup.path}${Platform.pathSeparator}manual-old.png',
    ).writeAsBytesSync(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0kAAAAFElEQVR4nGNkYPj/n4GBgYGJAQoAHRkCAjRcHicAAAAASUVORK5CYII=',
      ),
    );

    await showScan(
      tester,
      scanOf(
        cards: <BackupCard, BackupState>{card: BackupState.updateAvailable},
        updates: <BackupCard, BackupUpdatePlan>{
          card: const BackupUpdatePlan(updateContent: true),
        },
        presence: const <String, ({bool live, bool backup})>{
          'workshop/updated': (live: true, backup: true),
        },
      ),
      tiles: const <BackupTile>[
        (card: card, state: BackupState.updateAvailable, face: null),
      ],
      backupRoot: root.path,
      workshopPath: workshop.path,
      withBotToast: true,
    );
    await settle(tester);

    final Finder tile = find.byType(BackupTileView);
    await tester.tap(tile);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(tile);

    final Finder tree = find.byKey(
      const ValueKey<String>('backup-update-file-tree'),
    );
    final Finder expandPrompt = find.byKey(
      const ValueKey<String>('backup-update-expand-file-changes'),
    );
    final Finder focusTarget = find.byKey(
      const ValueKey<String>('wallpaper-detail-extra-focus-target'),
    );
    for (
      int attempt = 0;
      attempt < 40 && expandPrompt.evaluate().isEmpty;
      attempt++
    ) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 25));
      });
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(expandPrompt, findsOneWidget);
    expect(focusTarget, findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('wallpaper-detail-extra-focus-hint')),
      findsOneWidget,
    );
    expect(tree, findsNothing);
    expect(find.text(AppI10n.backupDetailExpandFileChanges), findsOneWidget);

    await tester.ensureVisible(expandPrompt);
    await tester.pump();
    await tester.tap(expandPrompt);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));
    for (int attempt = 0; attempt < 40 && tree.evaluate().isEmpty; attempt++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 25));
      });
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(expandPrompt, findsNothing);
    expect(tree, findsOneWidget);
    expect(
      find.descendant(of: tree, matching: find.byType(FileTreeGroupHeader)),
      findsNWidgets(3),
    );
    expect(
      find.byWidgetPredicate(
        (Widget widget) =>
            widget is FileTreeGroupHeader &&
            widget.title == AppI10n.backupDetailModified,
      ),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (Widget widget) =>
            widget is FileTreeGroupHeader &&
            widget.title == AppI10n.backupDetailAddedFiles,
      ),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (Widget widget) =>
            widget is FileTreeGroupHeader &&
            widget.title == AppI10n.backupDetailRemovedFiles,
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('backup-file-compare-project.json')),
      findsOneWidget,
      reason: 'modified JSON should expose the shared file comparer',
    );
    expect(
      find.byKey(const ValueKey<String>('backup-file-compare-scene.pkg')),
      findsOneWidget,
      reason: 'scene.pkg itself should be comparable before inspection',
    );
    final Finder manualCompareCount = find.byKey(
      const ValueKey<String>('backup-manual-compare-count'),
    );
    expect(tester.widget<Text>(manualCompareCount).data, '0 / 2');
    final Finder newImageRow = find.byKey(
      const ValueKey<String>('backup-manual-compare-live::manual-new.png'),
    );
    final Finder oldImageRow = find.byKey(
      const ValueKey<String>('backup-manual-compare-backup::manual-old.png'),
    );
    expect(newImageRow, findsOneWidget);
    expect(oldImageRow, findsOneWidget);

    await tester.ensureVisible(newImageRow);
    await tester.tap(newImageRow);
    await tester.pump();
    expect(tester.widget<FileTreeRow>(newImageRow).selected, isTrue);
    expect(tester.widget<Text>(manualCompareCount).data, '1 / 2');

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.ensureVisible(oldImageRow);
    await tester.tap(oldImageRow);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(tester.widget<FileTreeRow>(oldImageRow).selected, isTrue);
    expect(tester.widget<Text>(manualCompareCount).data, '2 / 2');

    final Finder manualCompareAction = find.byKey(
      const ValueKey<String>('backup-manual-compare-action'),
    );
    expect(manualCompareAction, findsOneWidget);
    await tester.ensureVisible(manualCompareAction);
    await tester.pump();
    await tester.tap(manualCompareAction);
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('file-image-compare-dialog')),
      findsOneWidget,
    );
    expect(find.byType(InteractiveViewer), findsNWidgets(2));
    expect(
      find.byKey(const ValueKey<String>('file-image-first-zoom-out')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('file-image-first-reset')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('file-image-first-zoom-in')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('file-image-link-views')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('file-image-mode-side-by-side')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('file-image-mode-overlay')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('file-image-mode-blink')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('file-image-mode-difference')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('file-image-mode-overlay')),
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('file-image-overlay-opacity')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('file-image-composite-reset')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('file-image-mode-difference')),
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('file-image-difference-intensity')),
      findsOneWidget,
    );
    final Finder intensityFinder = find.byKey(
      const ValueKey<String>('file-image-difference-intensity'),
    );
    final Slider intensity = tester.widget<Slider>(intensityFinder);
    expect(intensity.value, 4);
    expect(intensity.min, 1);
    expect(intensity.max, 16);
    intensity.onChanged!(8);
    await tester.pump();
    expect(tester.widget<Slider>(intensityFinder).value, 8);
    await tester.tap(
      find.byKey(const ValueKey<String>('file-image-dialog-close')),
    );
    await settle(tester);

    final Finder modifiedGroupReject = find.byKey(
      const ValueKey<String>('backup-update-group-reject-modified'),
    );
    final Finder onlyLiveGroupReject = find.byKey(
      const ValueKey<String>('backup-update-group-reject-only-live'),
    );
    final Finder onlyLiveGroupAccept = find.byKey(
      const ValueKey<String>('backup-update-group-accept-only-live'),
    );
    final Finder onlyBackupGroupReject = find.byKey(
      const ValueKey<String>('backup-update-group-reject-only-backup'),
    );
    final Finder onlyBackupGroupAccept = find.byKey(
      const ValueKey<String>('backup-update-group-accept-only-backup'),
    );
    expect(modifiedGroupReject, findsOneWidget);
    expect(onlyLiveGroupReject, findsOneWidget);
    expect(onlyLiveGroupAccept, findsOneWidget);
    expect(onlyBackupGroupReject, findsOneWidget);
    expect(onlyBackupGroupAccept, findsOneWidget);

    FileTreeRowChoice onlyLiveGroupChoice() {
      final FileTreeGroupHeader header = tester.widget(
        find.byWidgetPredicate(
          (Widget widget) =>
              widget is FileTreeGroupHeader &&
              widget.title == AppI10n.backupDetailAddedFiles,
        ),
      );
      return header.trailing! as FileTreeRowChoice;
    }

    expect(onlyLiveGroupChoice().selected, isTrue);
    await tester.ensureVisible(onlyLiveGroupReject);
    await tester.pump();
    await tester.tap(onlyLiveGroupReject);
    await tester.pump();
    expect(onlyLiveGroupChoice().selected, isFalse);
    await tester.tap(onlyLiveGroupAccept);
    await tester.pump();
    expect(onlyLiveGroupChoice().selected, isTrue);

    await tester.ensureVisible(onlyBackupGroupReject);
    await tester.pump();
    await tester.tap(onlyBackupGroupReject);
    await tester.pump();
    expect(find.text(AppI10n.backupDetailWillKeep), findsNWidgets(2));
    await tester.tap(onlyBackupGroupAccept);
    await tester.pump();
    expect(find.text(AppI10n.backupDetailWillRemove), findsNWidgets(2));

    final FileTreeRouteBanner updateRoute = tester.widget(
      find.byType(FileTreeRouteBanner),
    );
    expect(updateRoute.source, endsWith('/ updated'));
    expect(updateRoute.source.toLowerCase(), contains('workshop'));
    expect(updateRoute.destination, endsWith('/ updated'));
    expect(updateRoute.destination.toLowerCase(), contains('backup'));
    expect(updateRoute.destination.toLowerCase(), contains('workshop'));
    expect(find.text('project.json'), findsOneWidget);
    expect(find.text('effects  ›  settings.json'), findsOneWidget);
    final Finder projectReject = find.byKey(
      const ValueKey<String>('backup-update-reject-project.json'),
    );
    final Finder projectAccept = find.byKey(
      const ValueKey<String>('backup-update-accept-project.json'),
    );
    expect(projectReject, findsOneWidget);
    expect(projectAccept, findsOneWidget);
    expect(
      tester.getCenter(projectReject).dx,
      lessThan(tester.getCenter(projectAccept).dx),
    );
    expect(
      tester.getCenter(projectReject).dx,
      greaterThan(tester.getCenter(find.text('project.json')).dx),
      reason: 'X/check controls belong on the right side of the file row',
    );
    final Finder projectJsonRow = find.byKey(
      const ValueKey<String>('backup-json-project.json'),
    );
    final Element collapsedProjectJsonElement = projectJsonRow
        .evaluate()
        .single;
    final FileTreeRow collapsedProjectJson = tester.widget(projectJsonRow);
    expect(
      collapsedProjectJson.disclosure,
      Icons.keyboard_arrow_right_rounded,
      reason: 'JSON rows should advertise that they start collapsed',
    );
    expect(
      find.text('title'),
      findsNothing,
      reason: 'JSON field diffs stay collapsed until that file is opened',
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey<String>('backup-json-project.json')),
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('backup-json-project.json')),
    );
    await tester.ensureVisible(find.text('effects  ›  settings.json'));
    await tester.tap(find.text('effects  ›  settings.json'));
    for (
      int attempt = 0;
      attempt < 40 && find.text('strength').evaluate().isEmpty;
      attempt++
    ) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 25));
      });
      await tester.pump(const Duration(milliseconds: 50));
    }
    final FileTreeRow expandedProjectJson = tester.widget(projectJsonRow);
    expect(
      identical(collapsedProjectJsonElement, projectJsonRow.evaluate().single),
      isTrue,
      reason:
          'expanding JSON must keep the disclosure row mounted so Windows AX '
          'does not receive a reparented interactive node',
    );
    expect(expandedProjectJson.disclosure, Icons.keyboard_arrow_down_rounded);
    expect(find.text('title'), findsOneWidget);
    expect(find.text('"Old"  →  "Updated"'), findsOneWidget);
    expect(find.text('strength'), findsOneWidget);
    expect(find.text('1  →  2'), findsOneWidget);
    expect(find.text('scene.pkg'), findsOneWidget);
    final Finder imageCompare = find.byKey(
      const ValueKey<String>('backup-image-compare-preview.png'),
    );
    expect(imageCompare, findsOneWidget);
    await tester.ensureVisible(imageCompare);
    await tester.pump();
    await tester.tap(imageCompare);
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('file-image-compare-dialog')),
      findsOneWidget,
    );
    expect(find.byType(InteractiveViewer), findsNWidgets(2));
    for (
      int attempt = 0;
      attempt < 20 && find.textContaining('2 × 2').evaluate().length < 2;
      attempt++
    ) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await tester.pump(const Duration(milliseconds: 30));
    }
    expect(find.textContaining('2 × 2'), findsNWidgets(2));
    expect(find.textContaining('PNG'), findsNWidgets(2));
    await tester.tap(
      find.byKey(const ValueKey<String>('file-image-dialog-close')),
    );
    // showDialog keeps its modal barrier during the reverse transition.
    // Wait that transition out before testing the next real interaction.
    await settle(tester);
    expect(
      find.byKey(const ValueKey<String>('file-image-compare-dialog')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('backup-scene-pkg-inspect')),
      findsOneWidget,
      reason: 'scene.pkg must not be unpacked until the user asks',
    );
    expect(find.text(AppI10n.backupDetailInspectPackageWorking), findsNothing);
    expect(find.text('materials  ›  new.tex'), findsOneWidget);
    expect(find.text('legacy.txt'), findsOneWidget);
    expect(find.text(AppI10n.backupDetailWillRemove), findsNWidgets(2));
    final Finder legacyReject = find.byKey(
      const ValueKey<String>('backup-update-reject-legacy.txt'),
    );
    final Finder legacyAccept = find.byKey(
      const ValueKey<String>('backup-update-accept-legacy.txt'),
    );
    expect(legacyReject, findsOneWidget);
    expect(legacyAccept, findsOneWidget);
    await tester.ensureVisible(legacyReject);
    await tester.pump();
    await tester.tap(legacyReject);
    await tester.pump();
    expect(find.text(AppI10n.backupDetailWillKeep), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('backup-update-accept-scene.pkg')),
      findsOneWidget,
      reason: 'scene.pkg uses the same top-level selection skeleton',
    );

    final Finder inspectPackage = find.byKey(
      const ValueKey<String>('backup-scene-pkg-inspect'),
    );
    await tester.ensureVisible(inspectPackage);
    await tester.pump();
    await tester.tap(inspectPackage);
    final Finder packageConfirmTitle = find.text(
      AppI10n.backupDetailInspectPackageTitle,
    );
    // Preparing the temporary package folder uses real filesystem I/O, so
    // wait for that Future instead of advancing only Flutter's fake clock.
    for (
      int attempt = 0;
      attempt < 40 && packageConfirmTitle.evaluate().isEmpty;
      attempt++
    ) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 25));
      });
      await tester.pump(const Duration(milliseconds: 50));
    }
    try {
      expect(tester.takeException(), isNull);
      expect(
        packageConfirmTitle,
        findsOneWidget,
        reason: 'package extraction needs a second explicit confirmation',
      );
      final Finder pathBox = find.byType(PathActionBox);
      expect(pathBox, findsOneWidget);
      expect(
        find.descendant(of: pathBox, matching: find.byType(SelectableText)),
        findsOneWidget,
        reason: 'the path should also be selectable directly',
      );
      expect(
        find.byIcon(Icons.copy_rounded),
        findsWidgets,
        reason: 'the preflight temp path must be directly copyable',
      );
      expect(
        find.byIcon(Icons.folder_open_rounded),
        findsWidgets,
        reason: 'the preflight temp path must open in Explorer',
      );
    } finally {
      // BotToast is global. Always dismiss the overlay while its host is
      // still mounted, even when an assertion above fails, or its delayed
      // removal can spill into the next widget test.
      final Finder cancel = find.text(AppI10n.cancel);
      if (cancel.evaluate().isNotEmpty) {
        await tester.tap(cancel);
        await settleToast(tester);
      }
    }
    expect(tester.takeException(), isNull);
    expect(
      find.text(AppI10n.backupDetailInspectPackageTitle),
      findsNothing,
      reason: 'the confirmation must be fully removed before teardown',
    );
    expect(
      find.text(AppI10n.backupDetailInspectPackageWorking),
      findsNothing,
      reason: 'cancelling the confirmation must not start RePKG',
    );

    // Prove the global BotToast close callback is finished before its host
    // disappears. Otherwise a later widget test can inherit the exception.
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pump(const Duration(milliseconds: 700));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'scene.pkg inspection starts without returning a Future from setState',
    (tester) async {
      final Directory root = Directory.systemTemp.createTempSync(
        'we_repkg_scene_pkg_setstate',
      );
      addTearDown(() {
        if (root.existsSync()) root.deleteSync(recursive: true);
      });
      final Directory live = Directory(
        '${root.path}${Platform.pathSeparator}live'
        '${Platform.pathSeparator}pkg-test',
      )..createSync(recursive: true);
      final Directory backup = Directory(
        '${backupWorkshopPath(root.path)!}${Platform.pathSeparator}pkg-test',
      )..createSync(recursive: true);
      File(
        '${live.path}${Platform.pathSeparator}project.json',
      ).writeAsStringSync('{"title":"Pkg test","type":"scene"}');
      File(
        '${backup.path}${Platform.pathSeparator}project.json',
      ).writeAsStringSync('{"title":"Pkg test","type":"scene"}');
      File(
        '${live.path}${Platform.pathSeparator}scene.pkg',
      ).writeAsStringSync('new package');
      File(
        '${backup.path}${Platform.pathSeparator}scene.pkg',
      ).writeAsStringSync('old');

      const BackupCard card = BackupCard(WallpaperLibrary.workshop, 'pkg-test');
      await tester.pumpWidget(
        ProviderScope(
          overrides: [toolPathProvider.overrideWithValue(null)],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            builder: BotToastInit(),
            navigatorObservers: <NavigatorObserver>[
              BotToastNavigatorObserver(),
            ],
            home: Scaffold(
              body: Center(
                child: BackupTileView(
                  width: 180,
                  tile: (
                    card: card,
                    state: BackupState.updateAvailable,
                    face: null,
                  ),
                  folders: (live: live.path, backup: backup.path),
                  onTap: () {},
                  onAction: () {},
                  updatePlan: const BackupUpdatePlan(updateContent: true),
                  backupRoot: root.path,
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
      final Finder expand = find.byKey(
        const ValueKey<String>('backup-update-expand-file-changes'),
      );
      for (
        int attempt = 0;
        attempt < 40 && expand.evaluate().isEmpty;
        attempt++
      ) {
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 25));
        });
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(expand, findsOneWidget);
      await tester.ensureVisible(expand);
      await tester.pump();
      await tester.tap(expand);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 220));

      final Finder inspect = find.byKey(
        const ValueKey<String>('backup-scene-pkg-inspect'),
      );
      for (
        int attempt = 0;
        attempt < 40 && inspect.evaluate().isEmpty;
        attempt++
      ) {
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 25));
        });
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(inspect, findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('backup-file-compare-scene.pkg')),
        findsOneWidget,
      );
      final Finder packageContainer = find.byKey(
        const ValueKey<String>('backup-scene-pkg-container-scene.pkg'),
      );
      expect(packageContainer, findsOneWidget);
      expect(tester.widget(packageContainer), isA<KeyedSubtree>());
      expect(
        find.byKey(
          const ValueKey<String>('backup-scene-pkg-semantics-scene.pkg'),
        ),
        findsNothing,
        reason: 'package inspection must not add a nested AX semantics root',
      );
      await tester.ensureVisible(inspect);
      await tester.pump();
      await tester.tap(inspect);
      for (int attempt = 0; attempt < 40; attempt++) {
        if (find
            .text(AppI10n.backupDetailInspectPackageTitle)
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
        find.text(AppI10n.backupDetailInspectPackageTitle),
        findsOneWidget,
      );

      await tester.tap(
        find.widgetWithText(
          FilledButton,
          AppI10n.backupDetailInspectPackageAction,
        ),
      );
      await settleToast(tester);
      for (int attempt = 0; attempt < 40; attempt++) {
        if (find
            .text(AppI10n.backupDetailInspectPackageNoTool)
            .evaluate()
            .isNotEmpty) {
          break;
        }
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 25));
        });
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(tester.takeException(), isNull);
      expect(
        find.text(AppI10n.backupDetailInspectPackageNoTool),
        findsOneWidget,
      );
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pump(const Duration(milliseconds: 700));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Update plus duplicate Sync details fit before file inspection', (
    tester,
  ) async {
    final Directory root = Directory.systemTemp.createTempSync(
      'we_repkg_update_sync_detail',
    );
    addTearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });
    final Directory live = Directory(
      '${root.path}${Platform.pathSeparator}live'
      '${Platform.pathSeparator}combo',
    )..createSync(recursive: true);
    File(
      '${live.path}${Platform.pathSeparator}project.json',
    ).writeAsStringSync('{"title":"Combo","type":"scene"}');
    final Directory backup = Directory(
      '${backupWorkshopPath(root.path)!}${Platform.pathSeparator}combo',
    )..createSync(recursive: true);
    File(
      '${backup.path}${Platform.pathSeparator}project.json',
    ).writeAsStringSync('{"title":"Old","type":"scene"}');

    const BackupCard card = BackupCard(WallpaperLibrary.workshop, 'combo');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [toolPathProvider.overrideWithValue(null)],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: Center(
              child: BackupTileView(
                width: 180,
                tile: (
                  card: card,
                  state: BackupState.updateAvailable,
                  face: null,
                ),
                folders: (live: live.path, backup: backup.path),
                onTap: () {},
                onAction: () {},
                updatePlan: const BackupUpdatePlan(
                  updateContent: true,
                  sync: BackupSyncPlan(
                    kind: BackupSyncKind.removeDuplicate,
                    from: WallpaperLibrary.myProjects,
                    to: WallpaperLibrary.workshop,
                  ),
                ),
                backupRoot: root.path,
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
    final Finder expandPrompt = find.byKey(
      const ValueKey<String>('backup-update-expand-file-changes'),
    );
    for (
      int attempt = 0;
      attempt < 40 && expandPrompt.evaluate().isEmpty;
      attempt++
    ) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 25));
      });
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(expandPrompt, findsOneWidget);
    expect(find.text(AppI10n.backupDetailSyncWillKeep), findsOneWidget);
    expect(find.text(AppI10n.backupDetailSyncWillRemove), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('preview-backed Backup states share the inspector shell', (
    tester,
  ) async {
    final Directory root = Directory.systemTemp.createTempSync(
      'we_repkg_shared_detail_shell',
    );
    addTearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });
    final Directory backup = Directory(
      '${root.path}${Platform.pathSeparator}gone',
    )..createSync();
    File(
      '${backup.path}${Platform.pathSeparator}project.json',
    ).writeAsStringSync('{"title":"Gone","type":"scene"}');
    const BackupCard card = BackupCard(WallpaperLibrary.workshop, 'gone');

    await tester.pumpWidget(
      ProviderScope(
        overrides: [toolPathProvider.overrideWithValue(null)],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: Center(
              child: BackupTileView(
                width: 180,
                tile: (card: card, state: BackupState.vanished, face: null),
                folders: (live: null, backup: backup.path),
                onTap: () {},
                onAction: () {},
                backupRoot: root.path,
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
    final Finder panel = find.byKey(
      const ValueKey<String>('wallpaper-detail-panel-pane'),
    );
    for (int attempt = 0; attempt < 30 && panel.evaluate().isEmpty; attempt++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await tester.pump(const Duration(milliseconds: 40));
    }

    expect(panel, findsOneWidget);
    expect(tester.getSize(panel).width, closeTo(340, .1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Sync-only details center their path block in the detail panel', (
    tester,
  ) async {
    final Directory root = Directory.systemTemp.createTempSync(
      'we_repkg_sync_only_detail',
    );
    addTearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });
    final Directory live = Directory(
      '${root.path}${Platform.pathSeparator}live'
      '${Platform.pathSeparator}sync-only',
    )..createSync(recursive: true);
    File(
      '${live.path}${Platform.pathSeparator}project.json',
    ).writeAsStringSync('{"title":"Sync only","type":"scene"}');

    const BackupCard card = BackupCard(WallpaperLibrary.workshop, 'sync-only');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [toolPathProvider.overrideWithValue(null)],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: Center(
              child: BackupTileView(
                width: 180,
                tile: (
                  card: card,
                  state: BackupState.updateAvailable,
                  face: null,
                ),
                folders: (live: live.path, backup: null),
                onTap: () {},
                onAction: () {},
                updatePlan: const BackupUpdatePlan(
                  sync: BackupSyncPlan(
                    kind: BackupSyncKind.relocate,
                    from: WallpaperLibrary.myProjects,
                    to: WallpaperLibrary.workshop,
                  ),
                ),
                backupRoot: root.path,
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
    final Finder paths = find.byType(ReadOnlyPathBox);
    for (
      int attempt = 0;
      attempt < 40 && paths.evaluate().length < 2;
      attempt++
    ) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 25));
      });
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(paths, findsNWidgets(2));
    // Geometry assertions must wait for the detail entrance transform to finish.
    await settle(tester);
    final Finder syncHeading = find.text(AppI10n.backupDetailSyncWillMove);
    expect(syncHeading, findsOneWidget);
    final Rect syncHeadingBlock = tester.getRect(syncHeading);
    expect(
      tester.getTopLeft(paths.first).dy - syncHeadingBlock.bottom,
      greaterThanOrEqualTo(7.5),
      reason: 'the Sync heading should breathe before the first path box',
    );
    final Rect panel = tester.getRect(
      find.byKey(const ValueKey<String>('wallpaper-detail-panel-pane')),
    );
    final Rect syncContent = tester.getRect(
      find.byKey(const ValueKey<String>('backup-sync-only-content')),
    );
    expect(
      (syncContent.center.dy - panel.center.dy).abs(),
      lessThan(90),
      reason:
          'Sync-only content should stay visually centered, not hug either edge',
    );
    expect(tester.takeException(), isNull);
  });
}
