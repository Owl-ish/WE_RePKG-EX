import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:we_repkg/models/wallpaper.dart';
import 'package:we_repkg/views/content/detail_dialog.dart';

WallpaperInfo _wallpaper(String id) => WallpaperInfo(
  id: id,
  title: id,
  contentRating: '',
  tags: const <String>[],
  previews: '',
  type: 'Scene',
  updateTime: null,
  createTime: DateTime(2024),
  target: '',
  folder: id,
  size: 0,
);

void main() {
  testWidgets('one navigator opens one wallpaper detail route at a time', (
    tester,
  ) async {
    late BuildContext context;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Builder(
            builder: (BuildContext value) {
              context = value;
              return const SizedBox();
            },
          ),
        ),
      ),
    );

    final Future<void> first = showWallpaperDetail(
      context,
      _wallpaper('first'),
      actions: const <DetailAction>[],
      includePreview: false,
    );
    final Future<void> blocked = showWallpaperDetail(
      context,
      _wallpaper('blocked'),
      actions: const <DetailAction>[],
      includePreview: false,
    );
    await tester.pumpAndSettle();

    expect(find.byType(WallpaperDetailDialog), findsOneWidget);
    expect(
      tester
          .widget<WallpaperDetailDialog>(find.byType(WallpaperDetailDialog))
          .wallpaper
          .id,
      'first',
    );
    await blocked;

    Navigator.of(context, rootNavigator: true).pop();
    await tester.pumpAndSettle();
    await first;

    final Future<void> reopened = showWallpaperDetail(
      context,
      _wallpaper('reopened'),
      actions: const <DetailAction>[],
      includePreview: false,
    );
    await tester.pumpAndSettle();

    expect(find.byType(WallpaperDetailDialog), findsOneWidget);
    expect(
      tester
          .widget<WallpaperDetailDialog>(find.byType(WallpaperDetailDialog))
          .wallpaper
          .id,
      'reopened',
    );

    Navigator.of(context, rootNavigator: true).pop();
    await tester.pumpAndSettle();
    await reopened;
  });
}
