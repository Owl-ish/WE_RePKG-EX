import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:we_repkg/cores/integrity_scan.dart';
import 'package:we_repkg/provider/integrity.dart';
import 'package:we_repkg/utils/storage.dart';
import 'package:we_repkg/cores/integrity_rules.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await StorageUtil.init();
  });

  // Nothing is set, so the check reads no roots and comes back empty at once.
  ProviderContainer container() {
    final ProviderContainer c = ProviderContainer();
    addTearDown(c.dispose);
    return c;
  }

  test('nothing is picked until the user picks it', () {
    expect(container().read(integrityShownProvider), isNull);
  });

  // Fix every folder of one concern and its pill empties. Holding the pick
  // would leave the tab on an empty list, and bring it back on the check after.
  test('a recheck forgets which concern was being read', () async {
    final ProviderContainer c = container();
    await c.read(integrityScanProvider.future);
    c.read(integrityShownProvider.notifier).show(IntegrityVerdict.mediaOnly);
    expect(c.read(integrityShownProvider), IntegrityVerdict.mediaOnly);

    c.invalidate(integrityScanProvider);

    expect(c.read(integrityShownProvider), isNull);
  });

  test(
    'resolved issues last for this app run and are not duplicated',
    () async {
      final ProviderContainer c = container();
      await c.read(integrityScanProvider.future);
      const ResolvedIntegrityIssue issue = (
        finding: (
          root: IntegrityRoot.liveMyProjects,
          name: 'demo',
          verdict: IntegrityVerdict.unpackedSceneNoProject,
          bytes: 3,
          folder: r'C:\myprojects\demo',
          missing: null,
        ),
        resolution: IntegrityResolution.createdProject,
      );

      c.read(integrityResolvedProvider.notifier).addAll(
        <ResolvedIntegrityIssue>[issue, issue],
      );
      c.read(integrityResolvedProvider.notifier).show(true);
      c.invalidate(integrityScanProvider);

      expect(c.read(integrityResolvedProvider).issues, <ResolvedIntegrityIssue>[
        issue,
      ]);
    },
  );
}
