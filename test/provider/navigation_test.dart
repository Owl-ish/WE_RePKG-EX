import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:we_repkg/models/enums.dart';
import 'package:we_repkg/provider/navigation.dart';

void main() {
  group('Extract entrance replay', () {
    test('is a one-shot request and does not navigate away from Settings', () {
      final ProviderContainer container = ProviderContainer();
      addTearDown(container.dispose);

      final CurrentSection notifier = container.read(
        currentSectionProvider.notifier,
      );
      notifier.update(NavSection.settings);
      notifier.requestExtractEntrance();

      expect(container.read(currentSectionProvider), NavSection.settings);
      expect(notifier.consumeExtractEntrance(), isTrue);
      expect(notifier.consumeExtractEntrance(), isFalse);
    });

    test('multiple path changes coalesce into one replay', () {
      final ProviderContainer container = ProviderContainer();
      addTearDown(container.dispose);

      final CurrentSection notifier = container.read(
        currentSectionProvider.notifier,
      );
      notifier
        ..requestExtractEntrance()
        ..requestExtractEntrance();

      expect(notifier.consumeExtractEntrance(), isTrue);
      expect(notifier.consumeExtractEntrance(), isFalse);
    });
  });
}
