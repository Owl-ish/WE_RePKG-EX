import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:we_repkg/provider/setting.dart';
import 'package:we_repkg/utils/storage.dart';
import 'package:we_repkg/views/setting/memory_limit_slider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Out here, or awaiting the prefs channel inside testWidgets hands the wait to
  // the fake clock and the test hangs instead of failing.
  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await StorageUtil.init();
  });

  Future<ProviderContainer> pump(WidgetTester tester, int limit) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(extractMemoryLimitProvider.notifier).update(limit);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: MemoryLimitSlider())),
      ),
    );
    // Riverpod schedules its propagation on a zero length timer.
    await tester.pump(const Duration(milliseconds: 1));
    return container;
  }

  testWidgets('builds', (tester) async {
    await pump(tester, 2048);

    expect(tester.takeException(), isNull);
    expect(find.byType(Slider), findsOneWidget);
    expect(find.text('2048 MB'), findsOneWidget);
  });

  // A value stored before the range existed, or edited by hand, must not throw
  // the assertion Slider makes about value being inside min..max.
  testWidgets('a stored value outside the range still draws', (tester) async {
    final container = await pump(tester, ExtractMemoryLimit.max);
    expect(tester.takeException(), isNull);
    expect(
      container.read(extractMemoryLimitProvider),
      lessThanOrEqualTo(ExtractMemoryLimit.max),
    );
  });

  for (final int value in <int>[
    ExtractMemoryLimit.min,
    ExtractMemoryLimit.max,
  ]) {
    testWidgets('survives a limit of $value', (tester) async {
      await pump(tester, value);
      expect(tester.takeException(), isNull);
    });
  }
}
