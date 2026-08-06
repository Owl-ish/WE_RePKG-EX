import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:we_repkg/constants/keys.dart';
import 'package:we_repkg/provider/system.dart';
import 'package:we_repkg/utils/storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await StorageUtil.init();
  });

  /// A new container every call, which is what makes the reload below a real
  /// test: the second one rebuilds the notifier from storage.
  ProviderContainer freshContainer() {
    final ProviderContainer container = ProviderContainer();
    addTearDown(container.dispose);
    return container;
  }

  // Null and not an error: the whole tab reads as nothing backed up until a
  // root is picked, which is AC 2.
  test('no root is set until the user picks one', () {
    expect(freshContainer().read(backupRootProvider), isNull);
  });

  test(
    'a chosen root reaches storage and comes back on the next run',
    () async {
      freshContainer().read(backupRootProvider.notifier).update(r'C:\backup');
      await pumpEventQueue();

      expect(StorageUtil.getString(AppKeys.backupRoot), r'C:\backup');
      expect(freshContainer().read(backupRootProvider), r'C:\backup');
    },
  );
}
