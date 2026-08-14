import 'dart:math' as math;

import 'package:bot_toast/bot_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:we_repkg/config/theme.dart';
import 'package:we_repkg/config/theme_extensions.dart';
import 'package:we_repkg/constants/i10n.dart';
import 'package:we_repkg/constants/nums.dart';
import 'package:we_repkg/cores/integrity_scan.dart';
import 'package:we_repkg/provider/integrity.dart';
import 'package:we_repkg/provider/system.dart';
import 'package:we_repkg/utils/storage.dart';
import 'package:we_repkg/cores/integrity_rules.dart';
import 'package:we_repkg/views/backup/integrity.dart';
import 'package:we_repkg/views/backup/integrity_repair_action.dart';
import 'package:we_repkg/widgets/count_pill.dart';

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

  Future<void> show(
    WidgetTester tester,
    IntegrityReport report, {
    IntegrityRepairHandler? onRepair,
    List<ResolvedIntegrityIssue> resolved = const <ResolvedIntegrityIssue>[],
  }) async {
    final ProviderContainer container = ProviderContainer(
      overrides: [
        backupRootProvider.overrideWithValue(r'C:\backup'),
        integrityScanProvider.overrideWithValue(
          AsyncValue<IntegrityReport>.data(report),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.read(integrityResolvedProvider.notifier).addAll(resolved);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          builder: BotToastInit(),
          navigatorObservers: <NavigatorObserver>[BotToastNavigatorObserver()],
          home: Scaffold(body: IntegrityView(onRepair: onRepair)),
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

  testWidgets('a row opens only from its folder button', (tester) async {
    await show(tester, (
      findings: <IntegrityFinding>[
        finding(
          IntegrityRoot.liveWorkshop,
          'aaa',
          IntegrityVerdict.shaderCacheOnly,
        ),
      ],
      scanned: const <IntegrityRoot, int>{IntegrityRoot.liveWorkshop: 1},
      missing: const <IntegrityRoot>{},
    ));

    expect(
      find.ancestor(of: find.text('aaa'), matching: find.byType(InkWell)),
      findsNothing,
    );
    expect(find.byIcon(Icons.folder_open_rounded), findsOneWidget);
  });

  testWidgets('the summary explanation is as readable as the advice', (
    tester,
  ) async {
    await show(tester, (
      findings: <IntegrityFinding>[
        finding(
          IntegrityRoot.liveWorkshop,
          'aaa',
          IntegrityVerdict.shaderCacheOnly,
        ),
      ],
      scanned: const <IntegrityRoot, int>{IntegrityRoot.liveWorkshop: 1},
      missing: const <IntegrityRoot>{},
    ));

    final Text summary = tester.widget<Text>(find.text(AppI10n.integrityAbout));
    final Text advice = tester.widget<Text>(
      find.text(AppI10n.integrityAdviceShaderCacheOnly),
    );
    expect(
      summary.style!.fontSize,
      greaterThanOrEqualTo(advice.style!.fontSize!),
    );
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

  // Repairs appear only where the app can act without guessing. They use the
  // same word; the confirmation explains what each one does.
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

    testWidgets('a leftover shader cache can be recycled', (tester) async {
      await only(tester, IntegrityVerdict.shaderCacheOnly);

      expect(find.byIcon(Icons.build_outlined), findsNWidgets(2));
      expect(find.text(AppI10n.integrityFixAll), findsOneWidget);
    });

    testWidgets('shader cleanup explains OK and Cancel before changing disk', (
      tester,
    ) async {
      await only(tester, IntegrityVerdict.shaderCacheOnly);

      await tester.tap(find.byIcon(Icons.build_outlined).last);
      await tester.pumpAndSettle();

      expect(find.text(AppI10n.integrityFixCacheOne), findsOneWidget);
      expect(find.text(AppI10n.integrityFixFolderLabel), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (Widget widget) =>
              widget is Text &&
              widget.style?.fontFamily == 'Consolas' &&
              widget.data?.replaceAll('\u200B', '') ==
                  '${AppI10n.homeLibraryWorkshop}\\aaa',
        ),
        findsOneWidget,
      );
      expect(find.text(AppI10n.ok), findsOneWidget);
      expect(find.text(AppI10n.cancel), findsOneWidget);
      expect(find.byIcon(Icons.delete_outline_rounded), findsOneWidget);

      await tester.tap(find.text(AppI10n.cancel));
      await tester.pumpAndSettle();
      expect(find.text(AppI10n.integrityFixCacheOne), findsNothing);
    });

    testWidgets('group shader cleanup explains its exact Recycle Bin scope', (
      tester,
    ) async {
      await show(tester, (
        findings: <IntegrityFinding>[
          finding(
            IntegrityRoot.liveWorkshop,
            'live-a',
            IntegrityVerdict.shaderCacheOnly,
          ),
          finding(
            IntegrityRoot.liveWorkshop,
            'live-b',
            IntegrityVerdict.shaderCacheOnly,
          ),
        ],
        scanned: const <IntegrityRoot, int>{IntegrityRoot.liveWorkshop: 2},
        missing: const <IntegrityRoot>{},
      ));

      await tester.tap(find.text(AppI10n.integrityFixAll));
      await tester.pumpAndSettle();

      expect(find.text(AppI10n.integrityFixCacheMany), findsOneWidget);
      expect(find.text(AppI10n.ok), findsOneWidget);
      expect(find.text(AppI10n.cancel), findsOneWidget);

      await tester.tap(find.text(AppI10n.cancel));
      await tester.pumpAndSettle();
      expect(find.text(AppI10n.integrityFixCacheMany), findsNothing);
    });

    testWidgets('a media-only folder offers repair choices', (tester) async {
      await only(tester, IntegrityVerdict.mediaOnly);

      expect(find.byIcon(Icons.build_outlined), findsNWidgets(2));

      await tester.tap(find.byIcon(Icons.build_outlined).last);
      await tester.pumpAndSettle();
      final Finder cancel = find.widgetWithText(OutlinedButton, AppI10n.cancel);
      final Finder create = find.widgetWithText(
        OutlinedButton,
        AppI10n.integrityFixMediaCreate,
      );
      final Finder recycle = find.widgetWithText(
        FilledButton,
        AppI10n.integrityFixMediaRecycle,
      );
      expect(
        tester.getCenter(cancel).dy,
        greaterThan(
          math.max(tester.getCenter(create).dy, tester.getCenter(recycle).dy),
        ),
      );
      expect(
        find.ancestor(of: create, matching: find.byType(Expanded)),
        findsNothing,
      );
      expect(
        find.ancestor(of: recycle, matching: find.byType(Expanded)),
        findsNothing,
      );
      expect(
        find.ancestor(of: cancel, matching: find.byType(Expanded)),
        findsNothing,
      );
      expect(find.byIcon(Icons.add_circle_outline_rounded), findsOneWidget);
      expect(find.byIcon(Icons.delete_outline_rounded), findsOneWidget);
      expect(find.byIcon(Icons.auto_fix_high_rounded), findsOneWidget);

      await tester.tap(create);
      await tester.pumpAndSettle();
      expect(find.text(AppI10n.integrityFixMediaCreateOne), findsOneWidget);
      expect(find.text(AppI10n.ok), findsOneWidget);
      expect(find.text(AppI10n.cancel), findsOneWidget);
      expect(find.byIcon(Icons.auto_fix_high_rounded), findsOneWidget);

      await tester.tap(find.text(AppI10n.cancel));
      await tester.pumpAndSettle();
    });

    testWidgets('media recycling has its own final confirmation', (
      tester,
    ) async {
      await only(tester, IntegrityVerdict.mediaOnly);

      await tester.tap(find.byIcon(Icons.build_outlined).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppI10n.integrityFixMediaRecycle));
      await tester.pumpAndSettle();

      expect(find.text(AppI10n.integrityFixMediaRecycleOne), findsOneWidget);
      expect(find.text(AppI10n.ok), findsOneWidget);
      expect(find.text(AppI10n.cancel), findsOneWidget);
      expect(find.byIcon(Icons.delete_outline_rounded), findsOneWidget);
      await tester.tap(find.text(AppI10n.cancel));
      await tester.pumpAndSettle();
    });

    testWidgets('missing files and damaged descriptions can be resolved', (
      tester,
    ) async {
      await only(tester, IntegrityVerdict.payloadMissing);
      expect(find.byIcon(Icons.build_outlined), findsNWidgets(2));

      await only(tester, IntegrityVerdict.projectUnreadable);
      expect(find.byIcon(Icons.build_outlined), findsNWidgets(2));
    });

    testWidgets('missing-file confirmation shows the exact transfer', (
      tester,
    ) async {
      await show(tester, (
        findings: <IntegrityFinding>[
          finding(
            IntegrityRoot.liveMyProjects,
            'aaa',
            IntegrityVerdict.payloadMissing,
            missing: 'clip.mp4',
          ),
        ],
        scanned: const <IntegrityRoot, int>{IntegrityRoot.liveMyProjects: 1},
        missing: const <IntegrityRoot>{},
      ));

      await tester.tap(find.byIcon(Icons.build_outlined).last);
      await tester.pumpAndSettle();

      Finder detail(String value) => find.byWidgetPredicate(
        (Widget widget) =>
            widget is Text &&
            widget.style?.fontFamily == 'Consolas' &&
            widget.data?.replaceAll('\u200B', '') == value,
      );
      expect(find.text(AppI10n.integrityFixMissingFileLabel), findsOneWidget);
      expect(find.text(AppI10n.integrityFixFromLabel), findsOneWidget);
      expect(find.text(AppI10n.integrityFixToLabel), findsOneWidget);
      expect(detail('clip.mp4'), findsOneWidget);
      expect(
        detail(
          '${AppI10n.navBackup}\\${AppI10n.homeLibraryMyProjects}'
          r'\aaa\clip.mp4',
        ),
        findsOneWidget,
      );
      expect(
        detail('${AppI10n.homeLibraryMyProjects}\\aaa\\clip.mp4'),
        findsOneWidget,
      );
      final Finder missingFilePill = find.ancestor(
        of: detail('clip.mp4'),
        matching: find.byWidgetPredicate(
          (Widget widget) =>
              widget is Container &&
              widget.decoration is BoxDecoration &&
              (widget.decoration! as BoxDecoration).borderRadius ==
                  LayoutNums.pill,
        ),
      );
      expect(missingFilePill, findsOneWidget);
      final BoxDecoration decoration =
          tester.widget<Container>(missingFilePill).decoration!
              as BoxDecoration;
      expect(
        decoration.color,
        AppTheme.lightTheme.actionButtons.primaryBackground,
      );
      final Text missingFile = tester.widget<Text>(detail('clip.mp4'));
      expect(
        missingFile.style?.fontSize,
        Theme.of(
          tester.element(detail('clip.mp4')),
        ).textTheme.bodyMedium?.fontSize,
      );
      expect(missingFile.style?.fontWeight, FontWeight.w500);
      await tester.tap(find.text(AppI10n.cancel));
      await tester.pumpAndSettle();
    });
  });

  testWidgets('issue pills keep a visible tinted surface', (tester) async {
    await show(tester, (
      findings: <IntegrityFinding>[
        finding(
          IntegrityRoot.liveWorkshop,
          'aaa',
          IntegrityVerdict.shaderCacheOnly,
        ),
      ],
      scanned: const <IntegrityRoot, int>{IntegrityRoot.liveWorkshop: 1},
      missing: const <IntegrityRoot>{},
    ));

    final Iterable<Material> surfaces = tester.widgetList<Material>(
      find.descendant(
        of: find.byType(CountPill),
        matching: find.byType(Material),
      ),
    );
    expect(surfaces, isNotEmpty);
    expect(
      surfaces.every((Material material) => material.color!.a > 0),
      isTrue,
    );
  });

  testWidgets('the Resolved pill shows successful work from this app run', (
    tester,
  ) async {
    final IntegrityFinding completed = finding(
      IntegrityRoot.liveMyProjects,
      'completed',
      IntegrityVerdict.unpackedSceneNoProject,
    );
    await show(
      tester,
      (
        findings: <IntegrityFinding>[
          finding(
            IntegrityRoot.liveWorkshop,
            'current',
            IntegrityVerdict.shaderCacheOnly,
          ),
        ],
        scanned: const <IntegrityRoot, int>{IntegrityRoot.liveWorkshop: 2},
        missing: const <IntegrityRoot>{},
      ),
      resolved: <ResolvedIntegrityIssue>[
        (finding: completed, resolution: IntegrityResolution.createdProject),
      ],
    );

    await tester.tap(find.text('${AppI10n.integrityResolved} 1'));
    await tester.pump();

    expect(
      find.text(AppI10n.integrityResolutionCreatedProject),
      findsOneWidget,
    );
    expect(find.text(AppI10n.integrityResolvedAdvice), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_outline_rounded), findsOneWidget);
    expect(find.byIcon(Icons.build_outlined), findsNothing);
    expect(find.byIcon(Icons.folder_open_rounded), findsNothing);
  });

  testWidgets('group Resolve targets only its displayed library', (
    tester,
  ) async {
    List<IntegrityFinding>? received;
    IntegrityRepair? receivedRepair;
    await show(
      tester,
      (
        findings: <IntegrityFinding>[
          finding(
            IntegrityRoot.liveWorkshop,
            'live-a',
            IntegrityVerdict.shaderCacheOnly,
          ),
          finding(
            IntegrityRoot.liveWorkshop,
            'live-b',
            IntegrityVerdict.shaderCacheOnly,
          ),
          finding(
            IntegrityRoot.backupWorkshop,
            'backup-a',
            IntegrityVerdict.shaderCacheOnly,
          ),
        ],
        scanned: const <IntegrityRoot, int>{IntegrityRoot.liveWorkshop: 3},
        missing: const <IntegrityRoot>{},
      ),
      onRepair:
          (
            BuildContext context,
            IntegrityRepair repair,
            List<IntegrityFinding> targets,
          ) async {
            receivedRepair = repair;
            received = targets;
          },
    );

    await tester.tap(find.text(AppI10n.integrityFixAll).first);
    await tester.pump();

    expect(received, hasLength(2));
    expect(receivedRepair, IntegrityRepair.recycleShaderCache);
    expect(
      received!.map((IntegrityFinding finding) => finding.root).toSet(),
      <IntegrityRoot>{IntegrityRoot.liveWorkshop},
    );
  });

  testWidgets('row Resolve targets only that folder', (tester) async {
    List<IntegrityFinding>? received;
    IntegrityRepair? receivedRepair;
    await show(
      tester,
      (
        findings: <IntegrityFinding>[
          finding(
            IntegrityRoot.liveWorkshop,
            'live-a',
            IntegrityVerdict.shaderCacheOnly,
          ),
          finding(
            IntegrityRoot.liveWorkshop,
            'live-b',
            IntegrityVerdict.shaderCacheOnly,
          ),
        ],
        scanned: const <IntegrityRoot, int>{IntegrityRoot.liveWorkshop: 2},
        missing: const <IntegrityRoot>{},
      ),
      onRepair:
          (
            BuildContext context,
            IntegrityRepair repair,
            List<IntegrityFinding> targets,
          ) async {
            receivedRepair = repair;
            received = targets;
          },
    );

    await tester.tap(find.byIcon(Icons.build_outlined).last);
    await tester.pump();

    expect(received, hasLength(1));
    expect(receivedRepair, IntegrityRepair.recycleShaderCache);
    expect(received!.single.name, 'live-b');
  });

  testWidgets('the selected issue explains itself once above every library', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await show(tester, (
      findings: <IntegrityFinding>[
        finding(
          IntegrityRoot.liveWorkshop,
          'live',
          IntegrityVerdict.shaderCacheOnly,
        ),
        finding(
          IntegrityRoot.backupWorkshop,
          'backup',
          IntegrityVerdict.shaderCacheOnly,
        ),
      ],
      scanned: const <IntegrityRoot, int>{IntegrityRoot.liveWorkshop: 2},
      missing: const <IntegrityRoot>{},
    ));

    final Finder advice = find.text(AppI10n.integrityAdviceShaderCacheOnly);
    expect(advice, findsOneWidget);
    final Rect heading = tester.getRect(
      find.text(AppI10n.integrityRootLiveWorkshop),
    );
    final Rect note = tester.getRect(advice);
    expect(note.bottom, lessThanOrEqualTo(heading.top));
    expect(tester.takeException(), isNull);
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
