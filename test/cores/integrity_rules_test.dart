import 'package:flutter_test/flutter_test.dart';
import 'package:we_repkg/cores/integrity_rules.dart';

// Each case is one of the shapes found in the user's real library on
// 2026-08-06, so a regression here is a regression against something that
// actually happened.
void main() {
  IntegrityVerdict verdict(
    List<String> files, {
    List<String> dirs = const <String>[],
    bool project = true,
    bool readable = true,
    String? file,
    bool customDirectory = false,
  }) => classifyFolder(
    entries: <FolderEntry>[
      for (final String f in files) (name: f, isDirectory: false),
      for (final String d in dirs) (name: d, isDirectory: true),
    ],
    project: (present: project, readable: readable, file: file),
    hasCustomDirectory: customDirectory,
  );

  test('a packed scene beside its project file is sound', () {
    expect(
      verdict(<String>[
        'project.json',
        'scene.pkg',
        'preview.jpg',
      ], file: 'scene.json'),
      IntegrityVerdict.sound,
    );
  });

  test('an unpacked scene is sound without a pkg', () {
    expect(
      verdict(
        <String>['project.json', 'scene.json', 'preview.jpg'],
        dirs: <String>['materials', 'models'],
        file: 'scene.json',
      ),
      IntegrityVerdict.sound,
    );
  });

  test('a video is sound when the file it names is there', () {
    expect(
      verdict(<String>[
        'project.json',
        'preview.jpg',
        'STARS-141.mp4',
      ], file: 'STARS-141.mp4'),
      IntegrityVerdict.sound,
    );
  });

  // 3675770605: metadata backed up, the 21MB video never was.
  test('a video wallpaper missing its video is caught', () {
    expect(
      verdict(<String>[
        'project.json',
        'preview.jpg',
      ], file: '[4K] 2B Midnight Bloom.mp4'),
      IntegrityVerdict.payloadMissing,
    );
  });

  // 3373684260 and 3373711195: the file field names a top-level mp4 that is
  // really a folder of them. Reporting these as broken was a false alarm.
  test('media in a folder named after the file counts as present', () {
    expect(
      verdict(
        <String>['project.json', 'preview.jpg'],
        dirs: <String>['白桃少女1110-2'],
        file: '白桃少女1110-2.mp4',
      ),
      IntegrityVerdict.sound,
    );
  });

  // 3294327477: a bare pkg, nothing else. The metadata is what is missing.
  test('a lone scene.pkg is a packed scene with no project file', () {
    expect(
      verdict(<String>['scene.pkg'], project: false),
      IntegrityVerdict.packedSceneNoProject,
    );
  });

  // 1306534790: assets and a scene, no project.json anywhere, live or backup.
  test('a scene.json with no project file is an unpacked scene', () {
    expect(
      verdict(
        <String>['scene.json', 'preview.jpg'],
        dirs: <String>['materials', 'models', 'shaders'],
        project: false,
      ),
      IntegrityVerdict.unpackedSceneNoProject,
    );
  });

  // 3776838872 and 26 others: Steam removed the wallpaper and left the folder,
  // because Wallpaper Engine wrote the cache in it rather than downloading it.
  group('a folder Steam left behind', () {
    test('is named as leftover cache, not as media', () {
      expect(
        verdict(const <String>[], dirs: <String>['shaders'], project: false),
        IntegrityVerdict.shaderCacheOnly,
      );
    });

    test('is media only once something else is in there', () {
      expect(
        verdict(
          const <String>[],
          dirs: <String>['shaders', 'materials'],
          project: false,
        ),
        IntegrityVerdict.mediaOnly,
      );
    });

    // The backup tab reads the same rule to decide what to leave out, and an
    // empty folder is not one of these: it may be a wallpaper mid-download.
    test('an empty folder is not one', () {
      expect(holdsOnlyRebuiltShaders(const <FolderEntry>[]), isFalse);
    });
  });

  // 3373795844: 8.7GB in one nested folder and nothing WPE reads.
  test('content with nothing recognisable is media only', () {
    expect(
      verdict(const <String>[], dirs: <String>['1110-5奶咪'], project: false),
      IntegrityVerdict.mediaOnly,
    );
  });

  // 3679588148 in the myprojects backup: the 5GB payload with no metadata.
  test('a payload alone is media only, not sound', () {
    expect(
      verdict(<String>['STARS-141.mp4'], project: false),
      IntegrityVerdict.mediaOnly,
    );
  });

  test('an empty folder is empty rather than media only', () {
    expect(verdict(const <String>[], project: false), IntegrityVerdict.empty);
  });

  group('the order the concerns are shown in', () {
    // A verdict left out of the order gets no pill and no list. Sound is fine;
    // empty and shader-cache-only leftovers belong to Backup's Empty/Junk view.
    test('covers every verdict but the three the tab does not list', () {
      expect(<IntegrityVerdict>{
        ...integrityVerdictOrder,
        IntegrityVerdict.sound,
        IntegrityVerdict.empty,
        IntegrityVerdict.shaderCacheOnly,
      }, IntegrityVerdict.values.toSet());
    });

    test('counts every concern, including the ones with nothing in them', () {
      final Map<IntegrityVerdict, int> counts =
          verdictCounts(<IntegrityVerdict>[
            IntegrityVerdict.mediaOnly,
            IntegrityVerdict.mediaOnly,
            IntegrityVerdict.shaderCacheOnly,
          ]);

      expect(counts[IntegrityVerdict.mediaOnly], 2);
      expect(counts[IntegrityVerdict.payloadMissing], 0);
      expect(counts.containsKey(IntegrityVerdict.shaderCacheOnly), isFalse);
      expect(counts.keys, hasLength(integrityVerdictOrder.length));
    });

    // A recheck can empty the concern being read, and an empty list under a
    // lit pill reads as the check having lost the folders.
    test('a pick that still holds something is kept, and one that does not is '
        'swapped for the worst left', () {
      final Map<IntegrityVerdict, int> counts = verdictCounts(
        <IntegrityVerdict>[
          IntegrityVerdict.mediaOnly,
          IntegrityVerdict.payloadMissing,
        ],
      );

      expect(
        shownVerdict(IntegrityVerdict.mediaOnly, counts),
        IntegrityVerdict.mediaOnly,
      );
      expect(
        shownVerdict(IntegrityVerdict.projectUnreadable, counts),
        IntegrityVerdict.payloadMissing,
      );
      expect(shownVerdict(null, counts), IntegrityVerdict.payloadMissing);
    });

    test('the worst one found is where the tab opens', () {
      expect(
        worstFound(
          verdictCounts(<IntegrityVerdict>[
            IntegrityVerdict.empty,
            IntegrityVerdict.projectUnreadable,
          ]),
        ),
        IntegrityVerdict.projectUnreadable,
      );
    });

    test('nothing found falls back rather than throwing', () {
      expect(
        worstFound(verdictCounts(const <IntegrityVerdict>[])),
        integrityVerdictOrder.first,
      );
    });
  });

  test('a project file that will not parse is called out on its own', () {
    expect(
      verdict(<String>['project.json', 'scene.pkg'], readable: false),
      IntegrityVerdict.projectUnreadable,
    );
  });

  test('no file field falls back to a custom directory', () {
    expect(
      verdict(
        <String>['project.json'],
        dirs: <String>['directories'],
        customDirectory: true,
      ),
      IntegrityVerdict.sound,
    );
    expect(
      verdict(<String>['project.json'], dirs: <String>['directories']),
      IntegrityVerdict.payloadMissing,
    );
  });

  test('names match whatever their case, since Windows sees one folder', () {
    expect(
      verdict(<String>['project.json', 'Scene.PKG'], file: 'scene.json'),
      IntegrityVerdict.sound,
    );
  });
}
