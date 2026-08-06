import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:we_repkg/constants/keys.dart';
import 'package:we_repkg/models/enums.dart';
import 'package:we_repkg/provider/system.dart';
import 'package:we_repkg/utils/storage.dart';
import 'package:we_repkg/views/bottom/toggle_input.dart';

const String _workshop = r'C:\Steam\steamapps\workshop\content\431960';
const String _derived =
    r'C:\Steam\steamapps\common\wallpaper_engine\projects\myprojects';

void main() {
  Future<ProviderContainer> show(
    WidgetTester tester,
    Map<String, Object> settings,
  ) async {
    // runAsync, because seeding awaits a real platform-channel reply that the
    // fake clock inside testWidgets never delivers.
    await tester.runAsync(() async {
      SharedPreferences.setMockInitialValues(settings);
      await StorageUtil.init();
    });
    final ProviderContainer container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: Row(children: [ToggleInput()])),
        ),
      ),
    );
    return container;
  }

  String fieldText(WidgetTester tester) =>
      tester.widget<TextField>(find.byType(TextField)).controller!.text;

  // The row is the only place either folder can be set now, so it is also the
  // only place either can be undone.
  testWidgets('project mode resets to the folder beside the library', (
    tester,
  ) async {
    final ProviderContainer container = await show(tester, <String, Object>{
      AppKeys.wallpaperPath: _workshop,
      AppKeys.projectPath: r'C:\scratch\wpetest\project',
      AppKeys.extractType: ExtractType.project.index,
    });
    expect(fieldText(tester), r'C:\scratch\wpetest\project');

    await tester.tap(find.byIcon(Icons.refresh_rounded));
    await tester.pump();

    expect(container.read(projectPathProvider), _derived);
    expect(fieldText(tester), _derived);
  });

  // The export folder has nothing to derive from, so reset clears it and the
  // hint comes back rather than a stale path looking like a choice.
  testWidgets('wallpaper mode clears the export folder for good', (
    tester,
  ) async {
    final ProviderContainer container = await show(tester, <String, Object>{
      AppKeys.exportPath: r'D:\WPE_Extract',
      AppKeys.extractType: ExtractType.wallpaper.index,
    });
    expect(fieldText(tester), r'D:\WPE_Extract');

    await tester.tap(find.byIcon(Icons.refresh_rounded));
    await tester.pump();

    expect(container.read(exportPathProvider), isNull);
    expect(fieldText(tester), isEmpty);
    // Storage too, or the path would be back at the next start. `update(null)`
    // deliberately does not clear it, so this needs its own path through.
    expect(StorageUtil.getString(AppKeys.exportPath), isNull);
  });
}
