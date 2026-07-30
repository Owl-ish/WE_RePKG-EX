import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:we_repkg/provider/setting.dart';
import 'package:we_repkg/utils/storage.dart';
import 'package:we_repkg/views/setting/concurrency_slider.dart';

// The estimate reads the machine's memory over FFI. A throw there would take the
// whole settings page with it, and no other test builds this widget.
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

  testWidgets('builds and reports what the setting costs', (tester) async {
    await pump(tester, 4);

    expect(tester.takeException(), isNull);
    expect(find.byType(Slider), findsOneWidget);
    // Label, tip, value, and the estimate underneath.
    expect(find.byType(Text), findsNWidgets(4));
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
