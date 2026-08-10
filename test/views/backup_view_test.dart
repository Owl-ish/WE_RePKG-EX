import 'dart:io';

import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:we_repkg/config/theme.dart';
import 'package:we_repkg/constants/i10n.dart';
import 'package:we_repkg/cores/backup.dart';
import 'package:we_repkg/models/enums.dart';
import 'package:we_repkg/provider/backup.dart';
import 'package:we_repkg/provider/navigation.dart';
import 'package:we_repkg/provider/system.dart';
import 'package:we_repkg/utils/backup_diff.dart';
import 'package:we_repkg/utils/storage.dart';
import 'package:we_repkg/views/backup/backup.dart';
import 'package:we_repkg/views/backup/integrity.dart';
import 'package:we_repkg/widgets/app_icon_button.dart';
import 'package:we_repkg/widgets/folder_input.dart';

class StubPicker extends FileSelectorPlatform {
  StubPicker(this.answer);
  final String? answer;

  @override
  Future<String?> getDirectoryPath({
    String? initialDirectory,
    String? confirmButtonText,
  }) async => answer;
}

BackupScan scanOf({
  Map<BackupCard, BackupState> cards = const <BackupCard, BackupState>{},
  List<ReconcileEntry> reconcile = const <ReconcileEntry>[],
  Set<BackupFolder> missing = const <BackupFolder>{},
}) => (
  cards: cards,
  reconcile: reconcile,
  acfRead: true,
  missing: missing,
  seeds: const <String, String>{},
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

  String fieldText(WidgetTester tester) =>
      tester.widget<TextField>(find.byType(TextField)).controller!.text;

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

  group('with a root set', () {
    Future<void> showScan(WidgetTester tester, BackupScan scan) =>
        tester.pumpWidget(
          ProviderScope(
            overrides: [
              backupRootProvider.overrideWithValue(r'C:\backup'),
              backupScanProvider.overrideWithValue(
                AsyncValue<BackupScan>.data(scan),
              ),
            ],
            child: MaterialApp(
              theme: AppTheme.lightTheme,
              home: const Scaffold(body: BackupView()),
            ),
          ),
        );

    String countBeside(WidgetTester tester, String label) {
      final Finder row = find.ancestor(
        of: find.text(label),
        matching: find.byType(Row),
      );
      return tester
          .widget<Text>(
            find.descendant(of: row, matching: find.byType(Text)).last,
          )
          .data!;
    }

    testWidgets('every state gets a row, including the empty ones', (
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

      expect(countBeside(tester, AppI10n.backupStateVanished), '1');
      expect(countBeside(tester, AppI10n.backupStateSynced), '2');
      expect(countBeside(tester, AppI10n.backupStateNotBackedUp), '0');
      expect(countBeside(tester, AppI10n.backupStateUpdateAvailable), '0');
      expect(countBeside(tester, AppI10n.backupStateUpdateDismissed), '0');
      expect(countBeside(tester, AppI10n.backupReconcile), '0');
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

      expect(countBeside(tester, AppI10n.backupReconcile), '1');
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
