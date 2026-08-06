import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:we_repkg/cores/integrity.dart';
import 'package:we_repkg/utils/wallpaper_integrity.dart';

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('we_repkg_integrity'));
  tearDown(() => tmp.deleteSync(recursive: true));

  /// Builds one wallpaper folder. [files] maps a name to its contents; a name
  /// ending in `\` makes an empty subfolder instead.
  void wallpaper(String root, String name, Map<String, String> files) {
    final Directory dir = Directory(p.join(tmp.path, root, name))
      ..createSync(recursive: true);
    files.forEach((String file, String content) {
      if (file.endsWith(r'\')) {
        Directory(
          p.join(dir.path, file.substring(0, file.length - 1)),
        ).createSync(recursive: true);
      } else {
        File(p.join(dir.path, file)).writeAsStringSync(content);
      }
    });
  }

  Future<IntegrityReport> scan() => scanIntegrity(
    liveWorkshopPath: p.join(tmp.path, 'live_workshop'),
    liveMyProjectsPath: p.join(tmp.path, 'live_myprojects'),
    backupRoot: p.join(tmp.path, 'backup'),
  );

  const String sceneProject = '{"title":"ok","file":"scene.json"}';

  test(
    'a sound library reports nothing and still counts what it read',
    () async {
      wallpaper('live_workshop', '111', <String, String>{
        'project.json': sceneProject,
        'scene.pkg': 'x',
      });
      Directory(p.join(tmp.path, 'live_myprojects')).createSync();
      Directory(
        p.join(tmp.path, 'backup', '431960'),
      ).createSync(recursive: true);
      Directory(
        p.join(
          tmp.path,
          'backup',
          'wallpaper_engine',
          'projects',
          'myprojects',
        ),
      ).createSync(recursive: true);

      final IntegrityReport report = await scan();

      expect(report.findings, isEmpty);
      expect(report.missing, isEmpty);
      expect(report.scanned[IntegrityRoot.liveWorkshop], 1);
    },
  );

  test('each broken shape is named rather than lumped together', () async {
    wallpaper('live_myprojects', 'bare_pkg', <String, String>{
      'scene.pkg': 'x',
    });
    wallpaper('live_myprojects', 'unpacked', <String, String>{
      'scene.json': '{}',
      r'materials\': '',
    });
    wallpaper('live_myprojects', 'media', <String, String>{'clip.mp4': 'x'});
    wallpaper('live_myprojects', 'no_payload', <String, String>{
      'project.json': '{"file":"gone.mp4"}',
    });
    wallpaper('live_myprojects', 'broken_json', <String, String>{
      'project.json': '{not json',
      'scene.pkg': 'x',
    });
    Directory(p.join(tmp.path, 'live_myprojects', 'nothing')).createSync();

    final IntegrityReport report = await scan();
    final Map<String, IntegrityVerdict> byName = <String, IntegrityVerdict>{
      for (final IntegrityFinding f in report.findings) f.name: f.verdict,
    };

    expect(byName, <String, IntegrityVerdict>{
      'bare_pkg': IntegrityVerdict.packedSceneNoProject,
      'unpacked': IntegrityVerdict.unpackedSceneNoProject,
      'media': IntegrityVerdict.mediaOnly,
      'no_payload': IntegrityVerdict.payloadMissing,
      'broken_json': IntegrityVerdict.projectUnreadable,
      'nothing': IntegrityVerdict.empty,
    });
  });

  // The user's 3675770605: sound in the live library, payload never copied to
  // the backup. Reporting per root is what makes that legible.
  test('the same name is judged separately in each root', () async {
    wallpaper('live_workshop', '3675770605', <String, String>{
      'project.json': '{"file":"clip.mp4"}',
      'clip.mp4': 'the payload',
      'preview.jpg': 'x',
    });
    wallpaper(p.join('backup', '431960'), '3675770605', <String, String>{
      'project.json': '{"file":"clip.mp4"}',
      'preview.jpg': 'x',
    });

    final IntegrityReport report = await scan();

    expect(report.findings, hasLength(1));
    expect(report.findings.single.root, IntegrityRoot.backupWorkshop);
    expect(report.findings.single.verdict, IntegrityVerdict.payloadMissing);
  });

  // project.json can point into a subfolder, which the app resolves by joining
  // the path. Judging it against the top-level listing alone is what made the
  // throwaway version of this check cry wolf twice.
  test('a payload named as a subpath is found', () async {
    wallpaper('live_workshop', 'nested', <String, String>{
      'project.json': r'{"file":"video/clip.mp4"}',
      r'video\': '',
    });
    File(
      p.join(tmp.path, 'live_workshop', 'nested', 'video', 'clip.mp4'),
    ).writeAsStringSync('x');

    expect((await scan()).findings, isEmpty);
  });

  // The app falls back to the custom directory only when `file` is absent. An
  // empty `file` targets the empty string, so there is nothing to extract.
  test('a missing file field falls back to the custom directory', () async {
    wallpaper('live_myprojects', 'custom', <String, String>{
      'project.json': '{"title":"x"}',
    });
    Directory(
      p.join(
        tmp.path,
        'live_myprojects',
        'custom',
        'directories',
        'customdirectory',
      ),
    ).createSync(recursive: true);
    wallpaper('live_myprojects', 'no_custom', <String, String>{
      'project.json': '{"title":"x"}',
    });
    wallpaper('live_myprojects', 'empty_file', <String, String>{
      'project.json': '{"file":""}',
      r'directories\': '',
    });
    Directory(
      p.join(
        tmp.path,
        'live_myprojects',
        'empty_file',
        'directories',
        'customdirectory',
      ),
    ).createSync(recursive: true);

    final Map<String, IntegrityVerdict> byName = <String, IntegrityVerdict>{
      for (final IntegrityFinding f in (await scan()).findings)
        f.name: f.verdict,
    };

    expect(byName, <String, IntegrityVerdict>{
      'no_custom': IntegrityVerdict.payloadMissing,
      'empty_file': IntegrityVerdict.payloadMissing,
    });
  });

  // The grid drops a wallpaper whose project.json has a number where a string
  // belongs. Calling it sound would send someone here to be told nothing is
  // wrong with the wallpaper they cannot see.
  test('a project file the grid could not read is not called sound', () async {
    wallpaper('live_workshop', 'bad_title', <String, String>{
      'project.json': '{"title":5,"file":"clip.mp4"}',
      'clip.mp4': 'x',
    });
    wallpaper('live_workshop', 'bad_tags', <String, String>{
      'project.json': '{"tags":"video","file":"clip.mp4"}',
      'clip.mp4': 'x',
    });

    final IntegrityReport report = await scan();

    expect(report.findings, hasLength(2));
    expect(
      report.findings.map((IntegrityFinding f) => f.verdict),
      everyElement(IntegrityVerdict.projectUnreadable),
    );
  });

  test('a finding carries the size of what is at stake', () async {
    wallpaper('live_myprojects', 'big', <String, String>{
      'payload.mp4': 'x' * 500,
    });

    final IntegrityReport report = await scan();

    expect(report.findings.single.bytes, 500);
  });

  // An unset or absent root is not an empty one, and saying so is what stops a
  // clean bill of health being reported for a folder nobody could open.
  test('a root that cannot be read is named, not counted as empty', () async {
    final IntegrityReport report = await scanIntegrity(
      liveWorkshopPath: p.join(tmp.path, 'not_there'),
      liveMyProjectsPath: null,
      backupRoot: null,
    );

    expect(report.missing, <IntegrityRoot>{
      IntegrityRoot.liveWorkshop,
      IntegrityRoot.liveMyProjects,
      IntegrityRoot.backupWorkshop,
      IntegrityRoot.backupMyProjects,
    });
    expect(report.scanned, isEmpty);
  });
}
