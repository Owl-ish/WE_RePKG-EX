import 'dart:convert';
import 'dart:io';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:we_repkg/cores/backup.dart';
import 'package:we_repkg/src/rust/api/simple.dart' as native;
import 'package:we_repkg/src/rust/frb_generated.dart';
import 'package:we_repkg/utils/backup_diff.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Opt in with a freshly built DLL; ordinary tests exercise the Dart fallback.
  final dll = Platform.environment['WEREPKG_NATIVE_TEST_DLL'];
  group(
    'native scan parity',
    skip: dll == null ? 'Native DLL not supplied' : false,
    () {
      late Directory root;
      late String live;
      late String backup;
      late Map<String, CopyStanding> dartStandings;
      late Map<String, String> dartVersions;
      String? linkFailure;
      final names = <String>{
        '中文',
        '日本語',
        '한국어',
        'accent',
        'sigma',
        'sigma-final',
        'dotted',
        'supplementary',
      };

      setUpAll(() async {
        root = await Directory.systemTemp.createTemp('werepkg_unicode_');
        live = p.join(root.path, '原本');
        backup = p.join(root.path, 'バックアップ');
        for (final name in names) {
          final upper = switch (name) {
            'accent' => 'Ä.PNG',
            'sigma' => 'ΟΣ.PNG',
            'sigma-final' => 'ΟΣ',
            'dotted' => 'İ.PNG',
            'supplementary' => '\u{10400}.PNG',
            _ => '$name 图像🌸.png',
          };
          for (final side in [live, backup]) {
            final folder = Directory(p.join(side, name));
            await folder.create(recursive: true);
            await File(
              p.join(folder.path, side == live ? upper : upper.toLowerCase()),
            ).writeAsString('中文 日本語 한국어 🌸');
            await File(
              p.join(folder.path, 'project.json'),
            ).writeAsString(jsonEncode({'title': name}));
          }
        }
        final tokenFolder = Directory(p.join(live, '排序'));
        await tokenFolder.create();
        for (final name in [
          '\u{10000}.txt',
          '\uE000.txt',
          '中文.txt',
          '日本語.txt',
          '한국어.txt',
        ]) {
          await File(p.join(tokenFolder.path, name)).writeAsString(name);
        }
        try {
          await Link(p.join(live, '链接')).create(tokenFolder.path);
          await Link(
            p.join(tokenFolder.path, '연결.txt'),
          ).create(p.join(live, '中文', 'project.json'));
          await Link(p.join(live, '中文', '素材リンク')).create(tokenFolder.path);
          await Link(
            p.join(tokenFolder.path, 'broken.txt'),
          ).create(p.join(root.path, 'missing.txt'));
        } on FileSystemException catch (error) {
          linkFailure = '$error';
        }
        dartStandings = await copyStandings(
          livePath: live,
          backupPath: backup,
          recursive: true,
          shared: names,
          compare: names,
        );
        dartVersions = await folderVersions(live);
        await RustLib.init(externalLibrary: ExternalLibrary.open(dll!));
      });
      tearDownAll(() async {
        await root.delete(recursive: true);
      });

      test('Unicode filename case matches the Dart comparator', () async {
        expect(dartStandings.values, everyElement(CopyStanding.covers));
        expect(
          await native.compareBackupFoldersRust(
            liveRoot: live,
            backupRoot: backup,
            folderNames: names.toList(),
            workers: 2,
          ),
          {for (final name in names) name: true},
        );
        expect(
          await copyStandings(
            livePath: live,
            backupPath: backup,
            recursive: true,
            shared: names,
            compare: names,
          ),
          dartStandings,
        );
      });
      test('version tokens use the same Unicode ordering', () async {
        final direct = await native.myProjectsInventoryRust(
          root: live,
          ignoredPrefixes: [],
          workers: 2,
        );
        expect(direct['排序'], dartVersions['排序']);
        final actual = await folderVersions(live);
        expect(actual['排序'], dartVersions['排序']);
      });
      test('read-only inventory includes linked folders and files', () async {
        if (linkFailure != null) {
          markTestSkipped('Link creation unavailable: $linkFailure');
          return;
        }
        final actual = await folderVersions(live);
        expect(actual['链接'], dartVersions['链接']);
        expect(actual['排序'], contains('연결.txt|'));
        expect(actual['排序'], isNot(contains('broken.txt')));
        final reads = await native.readIntegrityFoldersRust(
          root: live,
          folderNames: ['中文'],
          workers: 1,
        );
        expect(
          reads['中文']!.entries
              .singleWhere((entry) => entry.name == '素材リンク')
              .isDirectory,
          isTrue,
        );
      });
      test('project readers preserve CJK names and UTF-8 JSON', () async {
        final projects = await native.readWallpaperProjectsRust(
          root: live,
          folderNames: names.toList(),
          workers: 2,
        );
        for (final name in names) {
          expect(jsonDecode(projects[name]!.json), {'title': name});
          expect(
            projects[name]!.changedMicros.round(),
            (await File(
              p.join(live, name, 'project.json'),
            ).stat()).changed.microsecondsSinceEpoch,
          );
        }
        final folders = await native.readIntegrityFoldersRust(
          root: live,
          folderNames: ['中文', '日本語', '한국어'],
          workers: 2,
        );
        for (final name in ['中文', '日本語', '한국어']) {
          expect(
            folders[name]!.entries.map((e) => e.name),
            contains('$name 图像🌸.png'),
          );
        }
      });
    },
  );
}
