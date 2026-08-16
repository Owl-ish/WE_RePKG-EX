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
import 'package:we_repkg/utils/wallpaper_junk.dart';
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
      junk: <String, ({bool live, bool backup, WallpaperJunkKind kind})>{},
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
    expect(find.byTooltip(AppI10n.backupActionBackUp), findsOneWidget);
  });
  testWidgets('BackupActionGlow animates the halo independently of its child', (
    tester,
  ) async {
    const Color accent = Color(0xFF2F76B8);
    const Color childFill = Color(0xFFF4F6F8);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Row(
            children: <Widget>[
              BackupActionGlow(
                colour: accent,
                enabled: true,
                borderRadius: BorderRadius.all(Radius.circular(20)),
                glowKey: ValueKey<String>('full-action-glow'),
                child: Material(
                  key: ValueKey<String>('full-action-child'),
                  color: childFill,
                  child: SizedBox(width: 80, height: 32),
                ),
              ),
              BackupActionGlow(
                colour: accent,
                enabled: true,
                borderRadius: BorderRadius.all(Radius.circular(999)),
                glowKey: ValueKey<String>('compact-action-glow'),
                scale: .7,
                child: Material(
                  color: childFill,
                  shape: CircleBorder(),
                  child: SizedBox(width: 34, height: 34),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    BoxDecoration decoration(String key) =>
        tester
                .widget<DecoratedBox>(find.byKey(ValueKey<String>(key)))
                .decoration
            as BoxDecoration;

    List<BoxShadow> shadows(String key) => decoration(key).boxShadow!;

    // A newly mounted action starts with no halo. This verifies the resting
    // surface independently from the pulse itself.
    expect(shadows('full-action-glow'), hasLength(2));
    expect(
      shadows(
        'full-action-glow',
      ).every((BoxShadow shadow) => shadow.color.a == 0),
      isTrue,
    );
    expect(
      tester
          .widget<Material>(
            find.byKey(const ValueKey<String>('full-action-child')),
          )
          .color,
      childFill,
    );

    // Half of the 2.2 s cosine period is the exact pulse peak. Testing the
    // shared component directly avoids lazy-grid mount timing entirely.
    await tester.pump(const Duration(milliseconds: 1100));

    final List<BoxShadow> full = shadows('full-action-glow');
    final List<BoxShadow> compact = shadows('compact-action-glow');
    expect(full, hasLength(2));
    expect(compact, hasLength(2));

    double maxAlpha(List<BoxShadow> value) => value
        .map((BoxShadow shadow) => shadow.color.a)
        .reduce((double a, double b) => a > b ? a : b);
    double maxBlur(List<BoxShadow> value) => value
        .map((BoxShadow shadow) => shadow.blurRadius)
        .reduce((double a, double b) => a > b ? a : b);
    double maxSpread(List<BoxShadow> value) => value
        .map((BoxShadow shadow) => shadow.spreadRadius)
        .reduce((double a, double b) => a > b ? a : b);

    expect(maxAlpha(full), closeTo(.22, .01));
    expect(maxBlur(full), closeTo(20, .1));
    expect(maxSpread(full), closeTo(2, .1));
    expect(maxAlpha(compact), closeTo(.22, .01));
    expect(maxBlur(compact), closeTo(14, .1));
    expect(maxSpread(compact), closeTo(1.4, .1));
    for (final BoxShadow shadow in <BoxShadow>[...full, ...compact]) {
      expect(
        shadow.color.toARGB32() & 0x00FFFFFF,
        accent.toARGB32() & 0x00FFFFFF,
      );
    }
  });
}
