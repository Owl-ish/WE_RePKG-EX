import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:we_repkg/models/enums.dart';
import 'package:we_repkg/provider/navigation.dart';

void main() {
  group('Extract entrance replay', () {
    test('is a one-shot request that survives a change of area', () {
      final ProviderContainer container = ProviderContainer();
      addTearDown(container.dispose);

      final CurrentSection notifier = container.read(
        currentSectionProvider.notifier,
      );
      // A wallpaper path changed from the settings card while Backup was
      // showing. The request has to still be waiting on the way back.
      notifier.update(NavSection.backup);
      notifier.requestExtractEntrance();

      expect(container.read(currentSectionProvider), NavSection.backup);
      expect(notifier.consumeExtractEntrance(), isTrue);
      expect(notifier.consumeExtractEntrance(), isFalse);
    });

    test('extract is first, since the areas are listed in order', () {
      expect(NavSection.values, <NavSection>[
        NavSection.extract,
        NavSection.backup,
      ]);
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
