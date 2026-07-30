import 'package:flutter_test/flutter_test.dart';
import 'package:we_repkg/cores/extract.dart';

List<String> argsFor({
  bool excludeTexture = false,
  bool onlySaveImage = false,
  bool overwrite = false,
  bool detailedProgress = false,
  bool newFlags = true,
  int? threads,
}) => wallpaperExtractArgs(
  target: r'C:\wallpapers\1\scene.pkg',
  outPath: r'C:\out',
  excludeTexture: excludeTexture,
  onlySaveImage: onlySaveImage,
  overwrite: overwrite,
  detailedProgress: detailedProgress,
  newFlags: newFlags,
  threads: threads,
);

void main() {
  test('always converts tex entries into the output directory', () {
    final args = argsFor();

    expect(args.first, 'extract');
    expect(args, containsAllInOrder(<String>['-e', 'tex']));
    expect(args, containsAllInOrder(<String>['-o', r'C:\out']));
    expect(args.last, r'C:\wallpapers\1\scene.pkg');
  });

  group('older tool', () {
    // Anything added since 0.5.3-ex makes it exit 0 having written nothing.
    test('gets none of the newer flags', () {
      final args = argsFor(
        newFlags: false,
        onlySaveImage: true,
        excludeTexture: true,
        detailedProgress: true,
      );

      expect(args, isNot(contains('-p')));
      expect(args, isNot(contains('--progress-json')));
      expect(args, isNot(contains('--ignore-dirs')));
    });

    test('still extracts, just without them', () {
      expect(
        argsFor(newFlags: false),
        containsAllInOrder(<String>['-e', 'tex']),
      );
    });
  });

  test('skips masks in both wallpaper layouts', () {
    for (final bool exclude in <bool>[false, true]) {
      expect(
        argsFor(excludeTexture: exclude),
        containsAllInOrder(<String>['--ignore-dirs', 'masks']),
        reason: 'excludeTexture=$exclude',
      );
    }
  });

  test('keeps the tree when the cleanup pass needs materials/', () {
    expect(argsFor(excludeTexture: true), isNot(contains('-s')));
    expect(argsFor(excludeTexture: false), contains('-s'));
  });

  test('writes only images when either cleanup would bin the raw tex', () {
    expect(argsFor(onlySaveImage: true), contains('-p'));
    expect(argsFor(excludeTexture: true), contains('-p'));
    expect(argsFor(), isNot(contains('-p')));
  });

  test('reports progress only when asked for it', () {
    expect(argsFor(detailedProgress: true), contains('--progress-json'));
    expect(argsFor(), isNot(contains('--progress-json')));
  });

  test('overwrite applies only to the flattened layout', () {
    expect(argsFor(overwrite: true), contains('--overwrite'));
    expect(
      argsFor(overwrite: true, excludeTexture: true),
      isNot(contains('--overwrite')),
    );
  });

  test('asks for a thread count only when one is given', () {
    final args = argsFor(threads: 4);
    expect(args.indexOf('--threads') + 1, args.indexOf('4'));
    expect(argsFor(), isNot(contains('--threads')));
  });

  group('splitting the machine between the two levels of concurrency', () {
    // 4 wallpapers at once, each converting 16 textures at once, would put 64
    // conversions on a 16 core machine and cost about 7GB.
    test('divides the cores by the wallpapers running side by side', () {
      expect(textureThreads(cores: 16, concurrency: 4), 4);
      expect(textureThreads(cores: 16, concurrency: 2), 8);
      expect(textureThreads(cores: 12, concurrency: 5), 2);
    });

    test('scales down to a small machine', () {
      expect(textureThreads(cores: 4, concurrency: 2), 2);
      expect(textureThreads(cores: 2, concurrency: 1), 2);
    });

    // Memory, not cores, is what runs out first: a thread costs roughly 100MB.
    test('stops asking for more once a package would eat the machine', () {
      expect(textureThreads(cores: 32, concurrency: 1), 8);
      expect(textureThreads(cores: 64, concurrency: 2), 8);
      expect(textureThreads(cores: 128, concurrency: 4), 8);
    });

    test('never asks for less than one', () {
      expect(textureThreads(cores: 4, concurrency: 8), 1);
      expect(textureThreads(cores: 1, concurrency: 1), 1);
      expect(textureThreads(cores: 8, concurrency: 0), 8);
    });
  });

  group('sizing extraction against the machine', () {
    const int gb = 1024 * 1024 * 1024;

    test('a roomy machine gets what it asked for', () {
      final plan = extractPlan(requested: 4, cores: 16, ramBytes: 32 * gb);
      expect(plan.concurrency, 4);
      expect(plan.threads, 4);
    });

    // 4 at once would be about 5GB against an 8GB budget of 4GB.
    test('a small machine runs fewer at once', () {
      final plan = extractPlan(requested: 4, cores: 16, ramBytes: 8 * gb);
      expect(plan.concurrency, lessThan(4));
      expect(plan.peakBytes, lessThanOrEqualTo(4 * gb));
    });

    test('one wallpaper is the floor, however little memory there is', () {
      final plan = extractPlan(requested: 4, cores: 16, ramBytes: 1 * gb);
      expect(plan.concurrency, 1);
    });

    test('an unreadable machine is bounded by cores alone', () {
      final plan = extractPlan(requested: 4, cores: 16);
      expect(plan.concurrency, 4);
      expect(plan.threads, 4);
    });

    // The pool and each worker call this separately rather than passing the
    // answer around, so the same inputs have to give the same plan.
    test('is deterministic', () {
      for (final int ram in <int>[4 * gb, 8 * gb, 16 * gb, 64 * gb]) {
        final a = extractPlan(requested: 6, cores: 12, ramBytes: ram);
        final b = extractPlan(requested: 6, cores: 12, ramBytes: ram);
        expect(a, b);
      }
    });

    test('the estimate rises with what is actually run', () {
      final small = extractPlan(requested: 1, cores: 16, ramBytes: 32 * gb);
      final large = extractPlan(requested: 4, cores: 16, ramBytes: 32 * gb);
      expect(large.peakBytes, greaterThan(small.peakBytes));
    });
  });
}
