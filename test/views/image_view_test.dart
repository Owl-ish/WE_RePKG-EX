import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:we_repkg/models/wallpaper.dart';
import 'package:we_repkg/views/content/image.dart';

WallpaperInfo make({String previews = ''}) => WallpaperInfo(
  id: '1',
  title: 'Wallpaper',
  contentRating: 'everyone',
  tags: const [],
  previews: previews,
  type: 'scene',
  updateTime: null,
  createTime: DateTime(2024, 1, 1),
  target: 'scene.pkg',
  folder: r'C:\wallpapers\1',
  size: 0,
);

// A tile whose preview has not loaded is the common case while scrolling or
// searching, and it is the one that threw when the placeholder fill was
// dropped without dropping the clip that needed it.
void main() {
  testWidgets('builds with no preview to show yet', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ImageView(size: 180, wallpaper: make())),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.byType(ImageView), findsOneWidget);
  });

  testWidgets('builds with a hover scale animation attached', (tester) async {
    final AnimationController controller = AnimationController(
      vsync: tester,
      duration: const Duration(milliseconds: 100),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ImageView(size: 180, wallpaper: make(), scale: controller),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
  });
}
