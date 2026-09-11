import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:we_repkg/actions/wallpaper_actions.dart';
import 'package:we_repkg/cores/extract.dart';
import 'package:we_repkg/cores/scene_pkg_inspection.dart';
import 'package:we_repkg/utils/json_diff.dart';
import 'package:we_repkg/utils/tool.dart';
import 'package:we_repkg/utils/wallpaper_search.dart';
import 'package:we_repkg/widgets/file_tree_panel.dart';

class _TestSession extends ScenePkgInspectionSession {
  _TestSession(this.temporaryBasePath);
  @override
  final String temporaryBasePath;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('werepkg_paths_');
  });
  tearDown(() async {
    await root.delete(recursive: true);
  });

  test(
    'folder launch preserves CJK, spaces, hash and percent characters',
    () async {
      final folder = await Directory(
        p.join(root.path, '中文 日本語 한국어 🌸 #100%'),
      ).create();
      final urls = <String>[];
      const channel = MethodChannel('plugins.flutter.io/url_launcher');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        urls.add((call.arguments as Map)['url'] as String);
        return true;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      await browserFolder(folder.path);
      expect(urls, hasLength(2));
      for (final url in urls) {
        final uri = Uri.parse(url);
        expect(uri.fragment, isEmpty);
        expect(
          p.equals(p.normalize(uri.toFilePath()), p.normalize(folder.path)),
          isTrue,
        );
      }
    },
  );

  test(
    'extracted files retain Unicode names and contents when published',
    () async {
      final from = await Directory(p.join(root.path, '原本')).create();
      final to = await Directory(p.join(root.path, '出力')).create();
      const relative = '中文/日本語/한국어 🌸.txt';
      final source = File(p.join(from.path, relative));
      await source.parent.create(recursive: true);
      await source.writeAsString('中文 日本語 한국어 🌸');
      expect(
        await moveExtractedInto(
          from.path,
          to.path,
          FileNameClaims(overwrite: false),
        ),
        isNull,
      );
      expect(
        await File(p.join(to.path, relative)).readAsString(),
        '中文 日本語 한국어 🌸',
      );
      expect(renameFolder('中文 日本語 한국어 🌸'), '中文 日本語 한국어 🌸');
      final args = wallpaperExtractArgs(
        target: p.join(root.path, '中文 日本語 한국어', 'scene.pkg'),
        outPath: to.path,
        excludeTexture: false,
        onlySaveImage: false,
        overwrite: false,
        detailedProgress: false,
        newFlags: true,
      );
      expect(args.last, p.join(root.path, '中文 日本語 한국어', 'scene.pkg'));
      expect(args, contains(to.path));
    },
  );

  test(
    'session name truncation never splits a supplementary character',
    () async {
      for (final side in ['left', 'right']) {
        await Directory(p.join(root.path, side)).create();
        await File(
          p.join(root.path, side, 'scene.pkg'),
        ).writeAsString('fixture');
      }
      final session = _TestSession(p.join(root.path, 'sessions'));
      addTearDown(session.dispose);
      // The missing tool fails only after the Unicode session directories are created.
      await expectLater(
        session.inspect(
          tool: p.join(root.path, 'missing-tool.exe'),
          wallpaperName: '${'中' * 47}🌸끝',
          filePath: 'scene.pkg',
          leftFolder: p.join(root.path, 'left'),
          rightFolder: p.join(root.path, 'right'),
        ),
        throwsA(isA<ProcessException>()),
      );
      expect(
        await Directory(session.temporaryBasePath).list().toList(),
        isEmpty,
      );
    },
  );

  test(
    'search and JSON field identities preserve CJK and combining characters',
    () {
      for (final name in ['中文', '日本語', '한국어', '🌸', 'e\u0301']) {
        expect(matchesSearch(title: name, id: '', needle: name), isTrue);
        final changes = compareJsonValues({name: 1}, {name: 2});
        expect(changes.single.before, 1);
        expect(formatJsonFieldPath(changes.single.field), contains(name));
      }
      expect(compareJsonValues({'é': 1}, {'e\u0301': 1}), hasLength(2));
    },
  );

  testWidgets('shared file rows retain CJK and supplementary labels', (
    tester,
  ) async {
    const label = '中文 日本語 한국어 🌸.png';
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: FileTreeRow(
            depth: 0,
            icon: Icons.insert_drive_file,
            label: label,
            foreground: Colors.black,
          ),
        ),
      ),
    );
    expect(find.text(label), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
