import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:we_repkg/cores/wallpaper.dart';
import 'package:we_repkg/utils/storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;

  setUp(() async {
    // Empty prefs so getAcfInfo() short-circuits to an empty ACF list.
    SharedPreferences.setMockInitialValues({});
    await StorageUtil.init();
    tmp = Directory.systemTemp.createTempSync('we_repkg_scan');
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  Directory makeWallpaper(String id, {String? projectJson}) {
    final dir = Directory(p.join(tmp.path, id))..createSync();
    if (projectJson != null) {
      File(p.join(dir.path, 'project.json')).writeAsStringSync(projectJson);
    }
    return dir;
  }

  String project({
    String? title,
    String type = 'scene',
    String? preview,
    String file = 'scene.pkg',
  }) {
    final map = <String, dynamic>{'type': type, 'file': file};
    if (title != null) map['title'] = title;
    if (preview != null) map['preview'] = preview;
    return jsonEncode(map);
  }

  group('scanWallpapers', () {
    test('null path returns empty', () async {
      final r = await scanWallpapers(null);
      expect(r.wallpapers, isEmpty);
      expect(r.earliestDate, isNull);
    });

    test('nonexistent path returns empty', () async {
      final r = await scanWallpapers(p.join(tmp.path, 'nope'));
      expect(r.wallpapers, isEmpty);
      expect(r.earliestDate, isNull);
    });

    test('parses valid wallpaper folders', () async {
      makeWallpaper('111', projectJson: project(title: 'Alpha'));
      makeWallpaper(
        '222',
        projectJson: project(title: 'Beta', type: 'video'),
      );
      final r = await scanWallpapers(tmp.path);
      expect(r.wallpapers.length, 2);
      final byId = {for (final w in r.wallpapers) w.id: w};
      expect(byId['111']!.title, 'Alpha');
      expect(byId['111']!.type, 'scene');
      expect(byId['222']!.type, 'video');
      expect(r.earliestDate, isNotNull);
    });

    test('folder without project.json is skipped', () async {
      makeWallpaper('111', projectJson: project(title: 'Alpha'));
      makeWallpaper('222'); // no project.json
      final r = await scanWallpapers(tmp.path);
      expect(r.wallpapers.map((w) => w.id), ['111']);
    });

    test('malformed project.json is skipped; others still load', () async {
      makeWallpaper('good', projectJson: project(title: 'Good'));
      makeWallpaper('bad', projectJson: '{ not valid json ');
      final r = await scanWallpapers(tmp.path);
      expect(r.wallpapers.map((w) => w.id), ['good']);
    });

    test(
      'missing title falls back to folder id; missing preview is empty',
      () async {
        makeWallpaper('333', projectJson: project()); // no title, no preview
        final r = await scanWallpapers(tmp.path);
        expect(r.wallpapers.length, 1);
        expect(r.wallpapers.first.title, '333');
        expect(r.wallpapers.first.previews, '');
      },
    );
  });
}
