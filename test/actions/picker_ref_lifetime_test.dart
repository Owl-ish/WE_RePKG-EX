import 'dart:async';

import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:we_repkg/actions/path_actions.dart';
import 'package:we_repkg/provider/system.dart';
import 'package:we_repkg/utils/storage.dart';

/// Keeps the picker pending until the test supplies an answer.
class HeldPicker extends FileSelectorPlatform {
  final Completer<String?> answer = Completer<String?>();

  @override
  Future<String?> getDirectoryPath({
    String? initialDirectory,
    String? confirmButtonText,
  }) => answer.future;
}

class Host extends ConsumerWidget {
  const Host({super.key, required this.onRef});
  final void Function(WidgetRef ref) onRef;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    onRef(ref);
    return const SizedBox();
  }
}

void main() {
  late HeldPicker picker;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await StorageUtil.init();
    picker = HeldPicker();
    FileSelectorPlatform.instance = picker;
  });

  // Unmount the page before resolving the picker to expose reads through a disposed ref.
  testWidgets('a folder chosen after the page closed is still kept', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    late WidgetRef captured;

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: Host(onRef: (r) => captured = r)),
      ),
    );

    final Future<bool> pending = setExportPath(captured);

    // The user navigates away while the picker is still up.
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SizedBox()),
      ),
    );

    picker.answer.complete(r'C:\chosen');
    // Resolve the picker outside the widget test's fake clock.
    expect(await tester.runAsync(() => pending), isTrue);
    expect(container.read(exportPathProvider), r'C:\chosen');
  });

  testWidgets('a backup root chosen after the page closed is still kept', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    late WidgetRef captured;

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: Host(onRef: (r) => captured = r)),
      ),
    );

    final Future<void> pending = setBackupRoot(captured);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SizedBox()),
      ),
    );

    picker.answer.complete(r'C:\backup');
    await tester.runAsync(() => pending);

    expect(container.read(backupRootProvider), r'C:\backup');
  });

  testWidgets('cancelling the picker keeps a root already set', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    late WidgetRef captured;

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: Host(onRef: (r) => captured = r)),
      ),
    );
    container.read(backupRootProvider.notifier).update(r'C:\backup');

    final Future<void> pending = setBackupRoot(captured);
    picker.answer.complete(null);
    await tester.runAsync(() => pending);

    expect(container.read(backupRootProvider), r'C:\backup');
  });

  testWidgets('cancelling the backup root picker leaves it unset', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    late WidgetRef captured;

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: Host(onRef: (r) => captured = r)),
      ),
    );

    final Future<void> pending = setBackupRoot(captured);
    picker.answer.complete(null);
    await tester.runAsync(() => pending);

    expect(container.read(backupRootProvider), isNull);
  });

  testWidgets('cancelling the picker leaves the path alone', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    late WidgetRef captured;

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: Host(onRef: (r) => captured = r)),
      ),
    );

    final Future<bool> pending = setProjectPath(captured);
    picker.answer.complete(null);

    expect(await tester.runAsync(() => pending), isFalse);
  });
}
