import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:we_repkg/constants/i10n.dart';
import 'package:we_repkg/constants/keys.dart';
import 'package:we_repkg/provider/system.dart';
import 'package:we_repkg/utils/storage.dart';
import 'package:we_repkg/views/backup/backup.dart';
import 'package:we_repkg/widgets/app_icon_button.dart';
import 'package:we_repkg/widgets/folder_input.dart';

class StubPicker extends FileSelectorPlatform {
  StubPicker(this.answer);
  final String? answer;

  @override
  Future<String?> getDirectoryPath({
    String? initialDirectory,
    String? confirmButtonText,
  }) async => answer;
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await StorageUtil.init();
  });

  Future<ProviderContainer> show(WidgetTester tester) async {
    final ProviderContainer container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: BackupView())),
      ),
    );
    return container;
  }

  String fieldText(WidgetTester tester) =>
      tester.widget<TextField>(find.byType(TextField)).controller!.text;

  // The tab has to be usable on its own. Without this the only way to set a
  // backup root is to know it lives in the settings card.
  testWidgets('the tab offers a picker when no root is set', (tester) async {
    await show(tester);

    expect(find.byType(FolderInput), findsOneWidget);
    expect(fieldText(tester), isEmpty);
    // tr() returns the raw key here, no localisation is loaded under test.
    expect(find.text(AppI10n.backupNoRoot), findsOneWidget);
  });

  testWidgets('picking from the tab sets the root', (tester) async {
    FileSelectorPlatform.instance = StubPicker(r'C:\backup');
    final ProviderContainer container = await show(tester);

    await tester.tap(find.byType(AppIconButton));
    await tester.pump();

    expect(container.read(backupRootProvider), r'C:\backup');
    expect(fieldText(tester), r'C:\backup');
    expect(find.text(AppI10n.backupComingSoon), findsOneWidget);
  });

  testWidgets('cancelling the picker leaves the tab unset', (tester) async {
    FileSelectorPlatform.instance = StubPicker(null);
    final ProviderContainer container = await show(tester);

    await tester.tap(find.byType(AppIconButton));
    await tester.pump();

    expect(container.read(backupRootProvider), isNull);
    expect(fieldText(tester), isEmpty);
  });

  // Cancelling used to blank the row on screen while storage kept the old
  // path, so the app looked like it had forgotten the setting until a restart.
  testWidgets('cancelling the picker keeps a root already set', (tester) async {
    // runAsync, because seeding awaits a real platform-channel reply that the
    // fake clock inside testWidgets never delivers.
    await tester.runAsync(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        AppKeys.backupRoot: r'C:\backup',
      });
      await StorageUtil.init();
    });
    FileSelectorPlatform.instance = StubPicker(null);
    final ProviderContainer container = await show(tester);

    await tester.tap(find.byType(AppIconButton));
    await tester.pump();

    expect(container.read(backupRootProvider), r'C:\backup');
    expect(fieldText(tester), r'C:\backup');
  });
}
