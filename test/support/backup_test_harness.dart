import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:we_repkg/config/theme.dart';
import 'package:we_repkg/cores/backup.dart';
import 'package:we_repkg/provider/backup.dart';
import 'package:we_repkg/provider/system.dart';
import 'package:we_repkg/utils/backup_diff.dart';
import 'package:we_repkg/utils/backup_tiles.dart';
import 'package:we_repkg/utils/wallpaper_junk.dart';
import 'package:we_repkg/views/backup/backup.dart';

BackupScan scanOf({
  Map<BackupCard, BackupState> cards = const <BackupCard, BackupState>{},
  Map<BackupCard, BackupUpdatePlan> updates =
      const <BackupCard, BackupUpdatePlan>{},
  Map<String, ({bool live, bool backup})>? presence,
  Map<String, ({bool live, bool backup, WallpaperJunkKind kind})> junk =
      const <String, ({bool live, bool backup, WallpaperJunkKind kind})>{},
  List<ReconcileEntry> reconcile = const <ReconcileEntry>[],
  Set<BackupFolder> missing = const <BackupFolder>{},
}) => (
  cards: cards,
  updates: updates,
  presence:
      presence ??
      <String, ({bool live, bool backup})>{
        for (final MapEntry<BackupCard, BackupState> entry in cards.entries)
          entry.key.id: (
            live: entry.value != BackupState.vanished,
            backup: entry.value != BackupState.notBackedUp,
          ),
      },
  junk: junk,
  reconcile: reconcile,
  acfRead: true,
  missing: missing,
);

/// One frame for the futures, one for the animations. Not pumpAndSettle: a
/// pill holding wallpapers glows for as long as it is switched off, so there
/// is nothing to settle.
Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Finder countOf(String label, int count) => find.text('$label $count');

// The tile list is stubbed too, or the grid would go looking for previews
// under the fake root on whatever machine this runs on.
Future<void> showScan(
  WidgetTester tester,
  BackupScan scan, {
  List<BackupTile> tiles = const <BackupTile>[],
  String? workshopPath,
}) => tester.pumpWidget(
  ProviderScope(
    overrides: [
      backupRootProvider.overrideWithValue(r'C:\backup'),
      if (workshopPath != null)
        wallpaperPathProvider.overrideWithValue(workshopPath),
      backupScanProvider.overrideWithValue(AsyncValue<BackupScan>.data(scan)),
      backupTilesProvider.overrideWithValue(
        AsyncValue<List<BackupTile>>.data(tiles),
      ),
      // What the grid draws. Overridden beside the unfiltered list rather
      // than derived from it, so a pumped frame does not have to wait on
      // the search filter's own future.
      backupVisibleTilesProvider.overrideWithValue(
        AsyncValue<List<BackupTile>>.data(tiles),
      ),
    ],
    child: MaterialApp(
      theme: AppTheme.lightTheme,
      home: const Scaffold(body: BackupView()),
    ),
  ),
);
