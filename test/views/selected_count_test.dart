import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:we_repkg/models/wallpaper.dart';
import 'package:we_repkg/provider/wallpaper.dart';
import 'package:we_repkg/views/bottom/selected_count.dart';

WallpaperInfo make(String id) => WallpaperInfo(
  id: id,
  title: 'Wallpaper $id',
  contentRating: 'everyone',
  tags: const [],
  previews: '',
  type: 'scene',
  updateTime: null,
  createTime: DateTime(2024, 1, 1),
  target: 'scene.pkg',
  folder: 'C:\\wallpapers\\$id',
  size: 0,
);

Future<void> pump(WidgetTester tester, int selected) {
  return tester.pumpWidget(
    ProviderScope(
      overrides: [
        checkedWallpaperListProvider.overrideWithValue([
          for (int i = 0; i < selected; i++) make('$i'),
        ]),
      ],
      child: const MaterialApp(home: Scaffold(body: SelectedCount())),
    ),
  );
}

// The rendered string is easy_localization's, and tr() falls back to the key
// without it, so these cover when the label appears rather than how it reads.
void main() {
  testWidgets('appears once anything is selected', (tester) async {
    await pump(tester, 3);
    expect(find.byType(Text), findsOneWidget);

    await pump(tester, 1);
    expect(find.byType(Text), findsOneWidget);
  });

  testWidgets('says nothing when nothing is selected', (tester) async {
    await pump(tester, 0);

    expect(find.byType(Text), findsNothing);
  });
}
