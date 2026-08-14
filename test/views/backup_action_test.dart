import 'package:bot_toast/bot_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:we_repkg/constants/i10n.dart';
import 'package:we_repkg/config/theme.dart';
import 'package:we_repkg/cores/backup.dart';
import 'package:we_repkg/cores/backup_action.dart';
import 'package:we_repkg/provider/backup.dart';
import 'package:we_repkg/provider/system.dart';
import 'package:we_repkg/utils/backup_diff.dart';
import 'package:we_repkg/utils/backup_tiles.dart';
import 'package:we_repkg/utils/storage.dart';
import 'package:we_repkg/views/backup/backup.dart';
import 'package:we_repkg/views/backup/backup_action.dart';
import 'package:we_repkg/widgets/count_pill.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await StorageUtil.init();
  });

  Future<BuildContext> show(WidgetTester tester) async {
    late BuildContext context;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          builder: BotToastInit(),
          navigatorObservers: <NavigatorObserver>[BotToastNavigatorObserver()],
          home: Builder(
            builder: (BuildContext value) {
              context = value;
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    return context;
  }

  testWidgets('Cancel leaves the backup action untouched', (tester) async {
    final BuildContext context = await show(tester);
    int calls = 0;
    final Future<void> action = applyBackupAction(
      context,
      BackupAction.backUp,
      const <BackupCard>[BackupCard(WallpaperLibrary.workshop, 'demo')],
      runAction: (BackupAction action, List<BackupCard> cards) async {
        calls++;
        return (changed: true, error: null);
      },
    );
    await tester.pumpAndSettle();

    expect(find.text(AppI10n.backupActionBackUpOne), findsOneWidget);
    await tester.tap(find.text(AppI10n.cancel));
    await tester.pumpAndSettle();
    await action;

    expect(calls, 0);
  });

  testWidgets('same-name vanished cards are restored as one target', (
    tester,
  ) async {
    final BuildContext context = await show(tester);
    final List<List<BackupCard>> received = <List<BackupCard>>[];
    final Future<void> action = applyBackupAction(
      context,
      BackupAction.restore,
      const <BackupCard>[
        BackupCard(WallpaperLibrary.workshop, 'same'),
        BackupCard(WallpaperLibrary.myProjects, 'same'),
      ],
      runAction: (BackupAction action, List<BackupCard> cards) async {
        received.add(cards);
        return (changed: true, error: null);
      },
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppI10n.backupActionRestore));
    await tester.pumpAndSettle();
    await action;

    expect(received, hasLength(1));
    expect(received.single, hasLength(2));
  });

  testWidgets('an actionable pill shows both all and wallpaper controls', (
    tester,
  ) async {
    const BackupCard card = BackupCard(WallpaperLibrary.workshop, 'demo');
    final BackupScan scan = (
      cards: <BackupCard, BackupState>{card: BackupState.notBackedUp},
      presence: <String, ({bool live, bool backup})>{
        card.id: (live: true, backup: false),
      },
      reconcile: <ReconcileEntry>[],
      acfRead: true,
      missing: <BackupFolder>{},
    );
    const BackupTile tile = (
      card: card,
      state: BackupState.notBackedUp,
      face: null,
    );
    final ProviderContainer container = ProviderContainer(
      overrides: [
        backupRootProvider.overrideWithValue(r'C:\backup'),
        backupScanProvider.overrideWithValue(AsyncValue<BackupScan>.data(scan)),
        backupTilesProvider.overrideWithValue(
          const AsyncValue<List<BackupTile>>.data(<BackupTile>[tile]),
        ),
        backupVisibleTilesProvider.overrideWithValue(
          const AsyncValue<List<BackupTile>>.data(<BackupTile>[tile]),
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
    await tester.pump();

    final Finder action = find.byKey(
      const ValueKey<String>('backup-all-action-glow'),
    );
    expect(action, findsOneWidget);
    expect(
      tester.getCenter(action).dx,
      greaterThan(tester.getCenter(find.byType(CountPill).first).dx),
    );
    expect(
      tester.getCenter(action).dy,
      greaterThan(tester.getCenter(find.byType(CountPill).first).dy),
    );
    final BoxDecoration glow =
        tester.widget<DecoratedBox>(action).decoration as BoxDecoration;
    expect(glow.boxShadow, hasLength(2));
    expect(glow.boxShadow!.last.blurRadius, greaterThan(10));
    expect(find.byTooltip(AppI10n.backupActionBackUp), findsOneWidget);
  });
}
