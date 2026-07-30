import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as path;
import 'package:we_repkg/models/wallpaper.dart';
import 'package:we_repkg/provider/wallpaper.dart';
import 'package:we_repkg/views/states/loading.dart';

WallpaperInfo make(String id, String previews) => WallpaperInfo(
  id: id,
  title: 'Wallpaper $id',
  contentRating: 'everyone',
  tags: const [],
  previews: previews,
  type: 'scene',
  updateTime: null,
  createTime: DateTime(2024, 1, 1),
  target: 'scene.pkg',
  folder: 'C:\\wallpapers\\$id',
  size: 0,
);

void main() {
  late Directory dir;
  late String preview;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('we_repkg_loading');
    // A real file, so the preview resolves rather than reporting an image error
    // over the top of the assertions below.
    preview = path.join(dir.path, 'preview.png');
    File(preview).writeAsBytesSync(
      img.encodePng(img.Image(width: 4, height: 4, numChannels: 3)),
    );
  });
  tearDown(() => dir.deleteSync(recursive: true));

  double progressOf(WidgetTester tester) => tester
      .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
      .value!;

  // A single wallpaper is the detail dialog's first button and the commonest
  // action in the app. The displayed wallpaper never changes across such a run,
  // so a progress bar driven only by that change never moves.
  testWidgets('the bar advances on a one wallpaper run', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final WallpaperInfo only = make('1', preview);
    container.read(processingWallpaperProvider.notifier).update(only);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: Scaffold(body: LoadingView([only]))),
      ),
    );
    await tester.pump();
    expect(progressOf(tester), 0);

    container.read(currentIndexProvider.notifier).increment();
    await tester.pump();
    // Past the 500ms the controller animates over.
    await tester.pump(const Duration(milliseconds: 600));

    expect(progressOf(tester), closeTo(1, 0.001));
  });

  testWidgets('the bar still advances across a batch', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final List<WallpaperInfo> list = [
      for (int i = 0; i < 4; i++) make('$i', preview),
    ];
    container.read(processingWallpaperProvider.notifier).update(list.first);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: Scaffold(body: LoadingView(list))),
      ),
    );
    await tester.pump();

    // Two finish while the preview stays on the wallpaper a worker picked up
    // first, which is what a batch running four at once looks like.
    container.read(currentIndexProvider.notifier).increment();
    container.read(currentIndexProvider.notifier).increment();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(progressOf(tester), closeTo(0.5, 0.001));
  });
}
