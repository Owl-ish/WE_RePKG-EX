import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:we_repkg/constants/keys.dart';
import 'package:we_repkg/cores/wallpaper.dart';
import 'package:we_repkg/constants/wallpaper_files.dart';
import 'package:we_repkg/models/wallpaper.dart';
import 'package:we_repkg/provider/system.dart';
import 'package:we_repkg/utils/backup_diff.dart';
import 'package:we_repkg/utils/storage.dart';

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
  late Directory tmp;

  void wallpaper(String library, String name) {
    final Directory folder = Directory(p.join(tmp.path, library, name))
      ..createSync(recursive: true);
    File(
      p.join(folder.path, 'project.json'),
    ).writeAsStringSync('{"title":"$name","type":"scene","file":"scene.pkg"}');
  }

  // Both the temp tree and the prefs are built here, outside the fake clock a
  // testWidgets body runs under, which never delivers a platform-channel reply.
  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('we_repkg_library');
    wallpaper('431960', '793602574');
    wallpaper('431960', '${WallpaperFiles.rescueStagePrefix}123-abc');
    wallpaper('myprojects', 'my own wallpaper');
    SharedPreferences.setMockInitialValues(<String, Object>{
      AppKeys.wallpaperPath: p.join(tmp.path, '431960'),
      AppKeys.myProjectsLibrary: p.join(tmp.path, 'myprojects'),
    });
    await StorageUtil.init();
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  Future<(ProviderContainer, WidgetRef)> host(WidgetTester tester) async {
    final ProviderContainer container = ProviderContainer();
    addTearDown(container.dispose);
    late WidgetRef captured;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: Host(onRef: (WidgetRef r) => captured = r)),
      ),
    );
    return (container, captured);
  }

  // The grid reads one list, so the only thing that can point it at the other
  // library is this choice.
  testWidgets('the library choice picks which folder is scanned', (
    tester,
  ) async {
    final (ProviderContainer container, WidgetRef ref) = await host(tester);

    // runAsync, because the scan is real file IO on the real clock.
    final List<WallpaperInfo> workshop = (await tester.runAsync(
      () => getAllFile(ref),
    ))!;
    expect(workshop.map((WallpaperInfo w) => w.id), <String>['793602574']);

    container
        .read(currentLibraryProvider.notifier)
        .update(WallpaperLibrary.myProjects);
    final List<WallpaperInfo> myProjects = (await tester.runAsync(
      () => getAllFile(ref),
    ))!;

    expect(myProjects.map((WallpaperInfo w) => w.id), <String>[
      'my own wallpaper',
    ]);
  });

  testWidgets('the choice is remembered for the next run', (tester) async {
    final (ProviderContainer container, _) = await host(tester);
    container
        .read(currentLibraryProvider.notifier)
        .update(WallpaperLibrary.myProjects);
    await tester.runAsync(() => pumpEventQueue());

    final ProviderContainer next = ProviderContainer();
    addTearDown(next.dispose);
    expect(next.read(currentLibraryProvider), WallpaperLibrary.myProjects);
  });
}
