import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:we_repkg/constants/keys.dart';
import 'package:we_repkg/models/enums.dart';
import 'package:we_repkg/utils/backup_diff.dart';
import 'package:we_repkg/utils/storage.dart';
import 'package:we_repkg/views/states/empty.dart';

const String _workshop = r'C:\Steam\steamapps\workshop\content\431960';
const String _myProjects =
    r'C:\Steam\steamapps\common\wallpaper_engine\projects\myprojects';

void main() {
  Future<void> show(WidgetTester tester, WallpaperLibrary library) async {
    // runAsync, because seeding awaits a real platform-channel reply that the
    // fake clock inside testWidgets never delivers.
    await tester.runAsync(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        AppKeys.wallpaperPath: _workshop,
        AppKeys.myProjectsLibrary: _myProjects,
        AppKeys.currentLibrary: library.index,
      });
      await StorageUtil.init();
    });
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(body: EmptyView(runState: RunState.empty)),
        ),
      ),
    );
  }

  String fieldText(WidgetTester tester) =>
      tester.widget<TextField>(find.byType(TextField)).controller!.text;

  testWidgets('the empty state offers the workshop library', (tester) async {
    await show(tester, WallpaperLibrary.workshop);
    expect(fieldText(tester), _workshop);
  });

  // Offering the Workshop box while the grid is on myprojects would repoint the
  // wrong library, and the ACF and extraction paths are re-derived from it.
  testWidgets('the empty state offers the myprojects library', (tester) async {
    await show(tester, WallpaperLibrary.myProjects);
    expect(fieldText(tester), _myProjects);
  });
}
