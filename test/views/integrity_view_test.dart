import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:we_repkg/config/theme.dart';
import 'package:we_repkg/constants/i10n.dart';
import 'package:we_repkg/cores/integrity.dart';
import 'package:we_repkg/provider/integrity.dart';
import 'package:we_repkg/utils/storage.dart';
import 'package:we_repkg/utils/wallpaper_integrity.dart';
import 'package:we_repkg/views/backup/integrity.dart';

IntegrityFinding finding(
  IntegrityRoot root,
  String name,
  IntegrityVerdict verdict,
) => (
  root: root,
  name: name,
  verdict: verdict,
  bytes: 2048,
  folder: 'C:\\$name',
);

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await StorageUtil.init();
  });

  Future<void> show(WidgetTester tester, IntegrityReport report) async {
    final ProviderContainer container = ProviderContainer(
      overrides: [
        integrityScanProvider.overrideWithValue(
          AsyncValue<IntegrityReport>.data(report),
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(body: IntegrityView()),
        ),
      ),
    );
  }

  // An empty list reads as "did not run", which is the one thing a check like
  // this must never imply.
  testWidgets('a clean library says so rather than showing nothing', (
    tester,
  ) async {
    await show(tester, (
      findings: const <IntegrityFinding>[],
      scanned: const <IntegrityRoot, int>{IntegrityRoot.liveWorkshop: 12},
      missing: const <IntegrityRoot>{},
    ));

    expect(find.text(AppI10n.integrityClean), findsOneWidget);
  });

  testWidgets('a finding is named, sized and grouped by root and verdict', (
    tester,
  ) async {
    await show(tester, (
      findings: <IntegrityFinding>[
        finding(
          IntegrityRoot.backupWorkshop,
          '3675770605',
          IntegrityVerdict.payloadMissing,
        ),
      ],
      scanned: const <IntegrityRoot, int>{IntegrityRoot.backupWorkshop: 1},
      missing: const <IntegrityRoot>{},
    ));

    expect(find.text('3675770605'), findsOneWidget);
    expect(find.text('2.00KB'), findsOneWidget);
    expect(
      find.textContaining(AppI10n.integrityVerdictPayloadMissing),
      findsOneWidget,
    );
    expect(find.text(AppI10n.integrityClean), findsNothing);
  });

  // One heading per root and verdict, not one per row and not one for the lot.
  testWidgets('a heading starts each root and each verdict, once', (
    tester,
  ) async {
    await show(tester, (
      findings: <IntegrityFinding>[
        finding(IntegrityRoot.liveWorkshop, 'aaa', IntegrityVerdict.mediaOnly),
        finding(IntegrityRoot.liveWorkshop, 'bbb', IntegrityVerdict.mediaOnly),
        finding(
          IntegrityRoot.liveWorkshop,
          'ccc',
          IntegrityVerdict.payloadMissing,
        ),
        finding(
          IntegrityRoot.backupWorkshop,
          'ddd',
          IntegrityVerdict.mediaOnly,
        ),
      ],
      scanned: const <IntegrityRoot, int>{IntegrityRoot.liveWorkshop: 4},
      missing: const <IntegrityRoot>{},
    ));

    // Two rows under one heading, so three headings for four findings.
    expect(
      find.textContaining(AppI10n.integrityVerdictMediaOnly),
      findsNWidgets(2),
    );
    expect(
      find.textContaining(AppI10n.integrityVerdictPayloadMissing),
      findsOneWidget,
    );
    expect(find.text('bbb'), findsOneWidget);
  });

  // Nothing read is not a clean bill of health. Saying so over four unreadable
  // roots is the one lie this view must not tell.
  testWidgets('nothing read is not reported as clean', (tester) async {
    await show(tester, (
      findings: const <IntegrityFinding>[],
      scanned: const <IntegrityRoot, int>{},
      missing: const <IntegrityRoot>{
        IntegrityRoot.liveWorkshop,
        IntegrityRoot.liveMyProjects,
        IntegrityRoot.backupWorkshop,
        IntegrityRoot.backupMyProjects,
      },
    ));

    expect(find.text(AppI10n.integrityClean), findsNothing);
    expect(find.text(AppI10n.integrityMissingRoots), findsOneWidget);
  });

  // A root nobody could open is not a clean root, and the check has to say
  // which one rather than quietly reporting on three of four.
  testWidgets('an unreadable root is named alongside the findings', (
    tester,
  ) async {
    await show(tester, (
      findings: const <IntegrityFinding>[],
      scanned: const <IntegrityRoot, int>{IntegrityRoot.liveWorkshop: 3},
      missing: const <IntegrityRoot>{IntegrityRoot.backupMyProjects},
    ));

    expect(find.text(AppI10n.integrityMissingRoots), findsOneWidget);
    expect(find.text(AppI10n.integrityRootBackupMyProjects), findsOneWidget);
    expect(find.text(AppI10n.integrityRootLiveWorkshop), findsNothing);
  });
}
