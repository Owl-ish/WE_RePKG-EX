import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:we_repkg/constants/keys.dart';
import 'package:we_repkg/provider/setting.dart';
import 'package:we_repkg/utils/storage.dart';
import 'package:we_repkg/views/setting/setting_slider.dart';

// Slider asserts its value sits inside min..max, so a stored value the range no
// longer covers would first show up as a blank settings page.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Out here, or awaiting the prefs channel inside testWidgets hands the wait to
  // the fake clock and the test hangs instead of failing.
  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await StorageUtil.init();
  });

  // Both wirings as setting_config_group builds them.
  Widget concurrencySlider() => Consumer(
    builder: (context, ref, _) => SettingSlider(
      label: 'Concurrency',
      tip: 'How many at once',
      value: ref.watch(extractConcurrencyProvider),
      min: ExtractConcurrency.min,
      max: ExtractConcurrency.max,
      onChanged: (v) => ref.read(extractConcurrencyProvider.notifier).update(v),
    ),
  );

  Widget memoryLimitSlider() => Consumer(
    builder: (context, ref, _) => SettingSlider(
      label: 'Memory limit',
      tip: 'Ceiling for a batch',
      value: ref.watch(extractMemoryLimitProvider),
      min: ExtractMemoryLimit.min,
      max: ExtractMemoryLimit.max,
      step: ExtractMemoryLimit.step,
      unit: ' MB',
      onChanged: (v) => ref.read(extractMemoryLimitProvider.notifier).update(v),
    ),
  );

  // One container per test: disposing two of them schedules timers that outlive
  // the last frame. Seeding goes through the notifier rather than prefs, so
  // nothing awaits a method channel inside the fake clock.
  Future<ProviderContainer> pump(
    WidgetTester tester,
    Widget slider, {
    void Function(ProviderContainer container)? seed,
  }) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    seed?.call(container);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: Scaffold(body: slider)),
      ),
    );
    // Riverpod schedules its propagation on a zero length timer, which outlives
    // the test unless it is let run.
    await tester.pump(const Duration(milliseconds: 1));
    return container;
  }

  group('concurrency', () {
    testWidgets('builds', (tester) async {
      await pump(
        tester,
        concurrencySlider(),
        seed: (c) => c.read(extractConcurrencyProvider.notifier).update(4),
      );

      expect(tester.takeException(), isNull);
      expect(find.byType(Slider), findsOneWidget);
      // Label, tip, and the value.
      expect(find.byType(Text), findsNWidgets(3));
    });

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
        final container = await pump(tester, concurrencySlider());

        expect(tester.takeException(), isNull);
        expect(
          container.read(extractConcurrencyProvider),
          ExtractConcurrency.max,
        );
      });
    });

    for (final int value in <int>[
      ExtractConcurrency.min,
      ExtractConcurrency.max,
    ]) {
      testWidgets('survives concurrency $value', (tester) async {
        await pump(
          tester,
          concurrencySlider(),
          seed: (c) =>
              c.read(extractConcurrencyProvider.notifier).update(value),
        );

        expect(tester.takeException(), isNull);
        expect(find.byType(Slider), findsOneWidget);
      });
    }
  });

  group('memory limit', () {
    testWidgets('builds, and carries its unit', (tester) async {
      await pump(
        tester,
        memoryLimitSlider(),
        seed: (c) => c.read(extractMemoryLimitProvider.notifier).update(2048),
      );

      expect(tester.takeException(), isNull);
      expect(find.byType(Slider), findsOneWidget);
      expect(find.text('2048 MB'), findsOneWidget);
    });

    // A value stored before the range existed, or edited by hand, must not throw
    // the assertion Slider makes about value being inside min..max.
    group('a stored value outside the range', () {
      setUp(() async {
        SharedPreferences.setMockInitialValues(<String, Object>{
          AppKeys.extractMemoryLimit: ExtractMemoryLimit.max * 4,
        });
        await StorageUtil.init();
      });

      testWidgets('still draws, pulled back to the top of the range', (
        tester,
      ) async {
        final container = await pump(tester, memoryLimitSlider());

        expect(tester.takeException(), isNull);
        expect(
          container.read(extractMemoryLimitProvider),
          ExtractMemoryLimit.max,
        );
      });
    });

    for (final int value in <int>[
      ExtractMemoryLimit.min,
      ExtractMemoryLimit.max,
    ]) {
      testWidgets('survives a limit of $value', (tester) async {
        await pump(
          tester,
          memoryLimitSlider(),
          seed: (c) =>
              c.read(extractMemoryLimitProvider.notifier).update(value),
        );

        expect(tester.takeException(), isNull);
      });
    }
  });
}
