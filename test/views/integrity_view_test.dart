import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:we_repkg/config/theme.dart';
import 'package:we_repkg/constants/i10n.dart';
import 'package:we_repkg/cores/integrity_scan.dart';
import 'package:we_repkg/provider/integrity.dart';
import 'package:we_repkg/utils/storage.dart';
import 'package:we_repkg/cores/integrity_rules.dart';
import 'package:we_repkg/views/backup/integrity.dart';

IntegrityFinding finding(
  IntegrityRoot root,
  String name,
  IntegrityVerdict verdict, {
  String? missing,
}) => (
  root: root,
  name: name,
  verdict: verdict,
  bytes: 2048,
  folder: 'C:\\$name',
  missing: missing,
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

  testWidgets('a finding is named and sized', (tester) async {
    await show(tester, (
      findings: <IntegrityFinding>[
        finding(
          IntegrityRoot.backupWorkshop,
          '3675770605',
          IntegrityVerdict.payloadMissing,
          missing: 'scene.pkg',
        ),
      ],
      scanned: const <IntegrityRoot, int>{IntegrityRoot.backupWorkshop: 1},
      missing: const <IntegrityRoot>{},
    ));

    expect(find.text('3675770605'), findsOneWidget);
    expect(find.text('2.00KB'), findsOneWidget);
    // The name itself comes from the scan, which integrity_scan_test covers:
    // tr() here returns the key rather than filling the placeholder in.
    expect(
      find.text(AppI10n.integrityMissingFile),
      findsOneWidget,
      reason: 'a row that names no missing file leaves the user guessing',
    );
    expect(
      find.textContaining(AppI10n.integrityVerdictPayloadMissing),
      findsOneWidget,
    );
    expect(find.text(AppI10n.integrityClean), findsNothing);
  });

  // The tab is read from the top down, and a count of folders alone says
  // nothing about whether the user has anything to do.
  testWidgets('the summary says whether anything needs a look', (tester) async {
    await show(tester, (
      findings: <IntegrityFinding>[
        finding(IntegrityRoot.liveWorkshop, 'aaa', IntegrityVerdict.mediaOnly),
      ],
      scanned: const <IntegrityRoot, int>{IntegrityRoot.liveWorkshop: 9},
      missing: const <IntegrityRoot>{},
    ));

    expect(find.text(AppI10n.integrityFound), findsOneWidget);
    expect(find.text(AppI10n.integrityFoundNothing), findsNothing);

    await show(tester, (
      findings: const <IntegrityFinding>[],
      scanned: const <IntegrityRoot, int>{IntegrityRoot.liveWorkshop: 9},
      missing: const <IntegrityRoot>{},
    ));

    expect(find.text(AppI10n.integrityFoundNothing), findsOneWidget);
  });

  // One heading per library, not one per row and not one for the lot.
  testWidgets('a heading starts each library, once', (tester) async {
    await show(tester, (
      findings: <IntegrityFinding>[
        finding(IntegrityRoot.liveWorkshop, 'aaa', IntegrityVerdict.mediaOnly),
        finding(IntegrityRoot.liveWorkshop, 'bbb', IntegrityVerdict.mediaOnly),
        finding(
          IntegrityRoot.backupWorkshop,
          'ddd',
          IntegrityVerdict.mediaOnly,
        ),
      ],
      scanned: const <IntegrityRoot, int>{IntegrityRoot.liveWorkshop: 3},
      missing: const <IntegrityRoot>{},
    ));

    expect(find.text(AppI10n.integrityRootLiveWorkshop), findsOneWidget);
    expect(find.text(AppI10n.integrityRootBackupWorkshop), findsOneWidget);
    expect(find.text('bbb'), findsOneWidget);
  });

  group('the concern pills', () {
    IntegrityReport mixed() => (
      findings: <IntegrityFinding>[
        finding(IntegrityRoot.liveWorkshop, 'aaa', IntegrityVerdict.mediaOnly),
        finding(
          IntegrityRoot.liveWorkshop,
          'ccc',
          IntegrityVerdict.payloadMissing,
        ),
      ],
      scanned: const <IntegrityRoot, int>{IntegrityRoot.liveWorkshop: 2},
      missing: const <IntegrityRoot>{},
    );

    // A folder whose payload is missing is the one worth opening first, so the
    // tab lands there rather than on whatever sorts first.
    testWidgets('the tab opens on the worst concern found', (tester) async {
      await show(tester, mixed());

      expect(find.text('ccc'), findsOneWidget);
      expect(find.text('aaa'), findsNothing);
      expect(
        find.text(AppI10n.integrityAdvicePayloadMissing),
        findsOneWidget,
        reason: 'the verdict alone does not say what to do about it',
      );
    });

    // One at a time, the way the backup pills behave.
    testWidgets('picking one shows that concern alone', (tester) async {
      await show(tester, mixed());

      await tester.tap(find.text('${AppI10n.integrityVerdictMediaOnly} 1'));
      await tester.pump();

      expect(find.text('aaa'), findsOneWidget);
      expect(find.text('ccc'), findsNothing);
      expect(find.text(AppI10n.integrityAdviceMediaOnly), findsOneWidget);
    });

    // A row of zeroes is a list of things that did not happen, and it was most
    // of the pills on a healthy library.
    testWidgets('a concern with nothing in it is not shown at all', (
      tester,
    ) async {
      await show(tester, mixed());

      expect(
        find.textContaining(AppI10n.integrityVerdictShaderCacheOnly),
        findsNothing,
      );
      expect(
        find.text('${AppI10n.integrityVerdictMediaOnly} 1'),
        findsOneWidget,
      );
    });
  });

  // Only two concerns can be put right without guessing at the wallpaper, and
  // offering a repair for the others would be offering to lose one. Both say
  // the same word: what they do is the confirmation's to explain.
  group('the repair buttons', () {
    Future<void> only(WidgetTester tester, IntegrityVerdict verdict) =>
        show(tester, (
          findings: <IntegrityFinding>[
            finding(IntegrityRoot.liveWorkshop, 'aaa', verdict),
          ],
          scanned: const <IntegrityRoot, int>{IntegrityRoot.liveWorkshop: 1},
          missing: const <IntegrityRoot>{},
        ));

    testWidgets('a packed wallpaper with no project.json can be resolved', (
      tester,
    ) async {
      await only(tester, IntegrityVerdict.packedSceneNoProject);

      // One on the row, one on the library heading: these arrive in dozens and
      // all want the same answer.
      expect(find.byIcon(Icons.build_outlined), findsNWidgets(2));
      expect(find.text(AppI10n.integrityFixAll), findsOneWidget);
    });

    testWidgets('an unpacked one is offered the same button', (tester) async {
      await only(tester, IntegrityVerdict.unpackedSceneNoProject);

      expect(find.byIcon(Icons.build_outlined), findsNWidgets(2));
    });

    testWidgets('a concern with nothing safe to do offers no repair', (
      tester,
    ) async {
      await only(tester, IntegrityVerdict.mediaOnly);

      expect(find.byIcon(Icons.build_outlined), findsNothing);
      expect(find.text(AppI10n.integrityFixAll), findsNothing);
    });
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
