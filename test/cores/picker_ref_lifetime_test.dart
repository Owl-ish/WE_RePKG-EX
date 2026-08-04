import 'dart:async';

import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:we_repkg/cores/base.dart';
import 'package:we_repkg/provider/system.dart';
import 'package:we_repkg/utils/storage.dart';

/// A folder picker the test opens and closes by hand, standing in for the one
/// the user browses.
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

  // The picker stays open for as long as the user browses, and the settings
  // page can be gone by the time it closes. Reaching back through `ref` then
  // throws "Using ref when a widget is about to or has been unmounted", and the
  // folder the user just chose is dropped on the floor.
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
    // runAsync, because the picker's future settles on the real clock rather
    // than the one pump drives.
    expect(await tester.runAsync(() => pending), isTrue);
    expect(container.read(exportPathProvider), r'C:\chosen');
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
