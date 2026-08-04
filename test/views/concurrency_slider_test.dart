import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:we_repkg/constants/keys.dart';
import 'package:we_repkg/provider/setting.dart';
import 'package:we_repkg/utils/storage.dart';
import 'package:we_repkg/views/setting/concurrency_slider.dart';

// Slider asserts its value sits inside min..max, and no other test builds this
// widget, so a stored value the range no longer covers would first show up as a
// blank settings page.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Out here, or awaiting the prefs channel inside testWidgets hands the wait to
  // the fake clock and the test hangs instead of failing.
  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await StorageUtil.init();
  });

  Future<void> pump(WidgetTester tester, int concurrency) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(extractConcurrencyProvider.notifier).update(concurrency);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: ConcurrencySlider())),
      ),
    );
    // Riverpod schedules its propagation on a zero length timer, which outlives
    // the test unless it is let run.
    await tester.pump(const Duration(milliseconds: 1));
  }

  // The range used to reach 16, so anyone who moved the slider up before this
  // has a stored value the Slider would now assert on. Seeded through prefs
  // because the notifier clamps on the way in and could never store one.
  group('a value stored under the old wider range', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        AppKeys.extractConcurrency: 16,
      });
      await StorageUtil.init();
    });

    testWidgets('still draws, pulled back to the top of the range', (
      tester,
    ) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: ConcurrencySlider())),
        ),
      );
      await tester.pump(const Duration(milliseconds: 1));

      expect(tester.takeException(), isNull);
      expect(
        container.read(extractConcurrencyProvider),
        ExtractConcurrency.max,
      );
    });
  });

  testWidgets('builds', (tester) async {
    await pump(tester, 4);

    expect(tester.takeException(), isNull);
    expect(find.byType(Slider), findsOneWidget);
    // Label, tip, and the value.
    expect(find.byType(Text), findsNWidgets(3));
  });

  // One container per test: disposing two of them schedules timers that outlive
  // the last frame.
  for (final int value in <int>[
    ExtractConcurrency.min,
    ExtractConcurrency.max,
  ]) {
    testWidgets('survives concurrency $value', (tester) async {
      await pump(tester, value);

      expect(tester.takeException(), isNull);
      expect(find.byType(Slider), findsOneWidget);
    });
  }
}
