import 'package:flutter_test/flutter_test.dart';
import 'package:we_repkg/cores/context_menu.dart';
import 'package:we_repkg/models/wallpaper.dart';

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

void main() {
  final a = make('1');
  final b = make('2');
  final c = make('3');

  test('acts on the whole selection when the wallpaper is in it', () {
    expect(menuTargets([a, b], a), [a, b]);
    expect(menuTargets([a, b], b), [a, b]);
  });

  test('acts on the wallpaper alone when it is outside the selection', () {
    expect(menuTargets([a, b], c), [c]);
  });

  test('one selected wallpaper behaves the same as none', () {
    expect(menuTargets([a], a), [a]);
    expect(menuTargets([a], b), [b]);
    expect(menuTargets([], b), [b]);
  });
}
