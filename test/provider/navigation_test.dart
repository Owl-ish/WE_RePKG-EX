import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:we_repkg/models/enums.dart';
import 'package:we_repkg/provider/navigation.dart';

void main() {
  group('section entrance replay', () {
    test('changing area requests one entrance for the area being entered', () {
      final ProviderContainer container = ProviderContainer();
      addTearDown(container.dispose);

      final CurrentSection navigation = container.read(
        currentSectionProvider.notifier,
      );
      navigation.update(NavSection.backup);

      expect(container.read(currentSectionProvider), NavSection.backup);
      expect(navigation.consumeEntrance(NavSection.backup), isTrue);
      expect(navigation.consumeEntrance(NavSection.backup), isFalse);
      expect(navigation.consumeEntrance(NavSection.extract), isFalse);
    });

    test('reselecting the current area does not request another entrance', () {
      final ProviderContainer container = ProviderContainer();
      addTearDown(container.dispose);

      final CurrentSection navigation = container.read(
        currentSectionProvider.notifier,
      );
      navigation.update(NavSection.extract);

      expect(navigation.consumeEntrance(NavSection.extract), isFalse);
    });

    test('an explicit Extract replay survives while Backup is showing', () {
      final ProviderContainer container = ProviderContainer();
      addTearDown(container.dispose);

      final CurrentSection navigation = container.read(
        currentSectionProvider.notifier,
      );
      navigation.update(NavSection.backup);
      // Clear the navigation-triggered Backup entrance. The path-change request
      // below is independent and must wait for Extract to consume it later.
      expect(navigation.consumeEntrance(NavSection.backup), isTrue);

      navigation.requestEntrance(NavSection.extract);

      expect(container.read(currentSectionProvider), NavSection.backup);
      expect(navigation.consumeEntrance(NavSection.extract), isTrue);
      expect(navigation.consumeEntrance(NavSection.extract), isFalse);
    });

    test('multiple requests for the same area coalesce into one replay', () {
      final ProviderContainer container = ProviderContainer();
      addTearDown(container.dispose);

      final CurrentSection navigation = container.read(
        currentSectionProvider.notifier,
      );
      navigation
        ..requestEntrance(NavSection.extract)
        ..requestEntrance(NavSection.extract);

      expect(navigation.consumeEntrance(NavSection.extract), isTrue);
      expect(navigation.consumeEntrance(NavSection.extract), isFalse);
    });

    test('extract is first, since the areas are listed in order', () {
      expect(NavSection.values, <NavSection>[
        NavSection.extract,
        NavSection.backup,
      ]);
    });
  });

  group('Backup subtab entrance replay', () {
    test('returning from Integrity requests Backup exactly once', () {
      final ProviderContainer container = ProviderContainer();
      addTearDown(container.dispose);

      final CurrentBackupTab tabs = container.read(
        currentBackupTabProvider.notifier,
      );
      tabs.update(BackupTab.integrity);
      expect(tabs.consumeEntrance(BackupTab.backup), isFalse);

      tabs.update(BackupTab.backup);

      expect(tabs.consumeEntrance(BackupTab.backup), isTrue);
      expect(tabs.consumeEntrance(BackupTab.backup), isFalse);
    });

    test('reselecting Backup does not request another entrance', () {
      final ProviderContainer container = ProviderContainer();
      addTearDown(container.dispose);

      final CurrentBackupTab tabs = container.read(
        currentBackupTabProvider.notifier,
      );
      tabs.update(BackupTab.backup);

      expect(tabs.consumeEntrance(BackupTab.backup), isFalse);
    });
  });
}
