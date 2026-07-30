import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:we_repkg/utils/cancel_token.dart';
import 'package:we_repkg/utils/file_copy.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('we_repkg_copy'));
  tearDown(() => tmp.deleteSync(recursive: true));

  File writeRandom(String name, int bytes) {
    final rng = Random(7);
    final data = Uint8List.fromList(
      List<int>.generate(bytes, (_) => rng.nextInt(256)),
    );
    return File(p.join(tmp.path, name))..writeAsBytesSync(data);
  }

  group('replacing a file that is already there', () {
    // Writing straight to the destination truncates it when the sink opens, so
    // cancelling used to destroy an export from an earlier run.
    test('a cancelled replace leaves the original intact', () async {
      final src = writeRandom('clip.mp4', 5 * 1024 * 1024);
      final dest = File(p.join(tmp.path, 'out', 'clip.mp4'))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('the previous export');
      final token = CancelToken();

      await expectLater(
        copyFileReplacing(
          src,
          dest,
          onProgress: (_, _) => token.cancel(),
          cancelToken: token,
        ),
        throwsA(isA<CopyCancelled>()),
      );

      expect(dest.readAsStringSync(), 'the previous export');
      expect(File('${dest.path}.part').existsSync(), isFalse);
    });

    test('a finished replace swaps the new file in', () async {
      final src = writeRandom('clip.mp4', 2 * 1024 * 1024);
      final dest = File(p.join(tmp.path, 'out', 'clip.mp4'))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('the previous export');

      await copyFileReplacing(src, dest);

      expect(dest.lengthSync(), src.lengthSync());
      expect(File('${dest.path}.part').existsSync(), isFalse);
    });

    test('works when nothing is there yet', () async {
      final src = writeRandom('clip.mp4', 1024 * 1024);
      final dest = File(p.join(tmp.path, 'fresh', 'clip.mp4'));

      await copyFileReplacing(src, dest);

      expect(dest.lengthSync(), src.lengthSync());
    });
  });

  // Without this the pool still has to copy the whole file before the batch can
  // report itself cancelled, so cancel does nothing visible on a large video.
  test('stops part way when the token is cancelled', () async {
    final src = writeRandom('clip.mp4', 5 * 1024 * 1024);
    final dest = File(p.join(tmp.path, 'out', 'clip.mp4'));
    final token = CancelToken();

    await expectLater(
      copyFileWithProgress(
        src,
        dest,
        // Cancels on the first progress report, so the copy is mid-stream.
        onProgress: (_, _) => token.cancel(),
        cancelToken: token,
      ),
      // A stable type, not the FileSystemException addStream turns the aborting
      // throw into, or the caller cannot tell cancelling from a disk failure.
      throwsA(isA<CopyCancelled>()),
    );

    expect(
      dest.lengthSync(),
      lessThan(src.lengthSync()),
      reason: 'the read must stop rather than finish the file',
    );
  });

  test('runs to the end when the token is never cancelled', () async {
    final src = writeRandom('clip.mp4', 2 * 1024 * 1024);
    final dest = File(p.join(tmp.path, 'out', 'clip.mp4'));

    await copyFileWithProgress(src, dest, cancelToken: CancelToken());

    expect(dest.lengthSync(), src.lengthSync());
  });

  test('copies bytes faithfully', () async {
    final src = writeRandom('clip.mp4', 5 * 1024 * 1024);
    final dest = File(p.join(tmp.path, 'out', 'clip.mp4'));

    await copyFileWithProgress(src, dest);

    expect(dest.lengthSync(), src.lengthSync());
    expect(dest.readAsBytesSync(), src.readAsBytesSync());
  });

  test('creates the destination directory', () async {
    final src = writeRandom('a.mp4', 1024);
    final dest = File(p.join(tmp.path, 'deep', 'deeper', 'a.mp4'));

    await copyFileWithProgress(src, dest);

    expect(dest.existsSync(), isTrue);
  });

  test('an empty file copies without reporting a bogus total', () async {
    final src = File(p.join(tmp.path, 'empty.mp4'))..writeAsBytesSync([]);
    final dest = File(p.join(tmp.path, 'out', 'empty.mp4'));
    final reports = <(int, int)>[];

    await copyFileWithProgress(
      src,
      dest,
      onProgress: (copied, total) => reports.add((copied, total)),
    );

    expect(dest.existsSync(), isTrue);
    expect(dest.lengthSync(), 0);
    expect(reports, isEmpty, reason: 'no chunks means no progress events');
  });

  test('throttles progress instead of firing per chunk', () async {
    // 5MB at the ~64KB default chunk size is roughly 80 stream events. The old
    // implementation drove a provider write and a widget rebuild from each.
    final src = writeRandom('big.mp4', 5 * 1024 * 1024);
    final dest = File(p.join(tmp.path, 'out', 'big.mp4'));
    int calls = 0;

    await copyFileWithProgress(
      src,
      dest,
      onProgress: (_, _) => calls++,
      throttle: const Duration(milliseconds: 100),
    );

    expect(calls, greaterThan(0));
    expect(
      calls,
      lessThan(20),
      reason: 'throttling should collapse ~80 chunk events into a handful',
    );
  });

  test('reports the final byte count exactly once at the end', () async {
    final src = writeRandom('big.mp4', 3 * 1024 * 1024);
    final dest = File(p.join(tmp.path, 'out', 'big.mp4'));
    final reports = <int>[];

    await copyFileWithProgress(
      src,
      dest,
      onProgress: (copied, _) => reports.add(copied),
      throttle: const Duration(seconds: 30), // suppress every mid-copy update
    );

    expect(
      reports.last,
      src.lengthSync(),
      reason: 'the last chunk must always report, whatever the throttle',
    );
    expect(reports.length, 2, reason: 'first chunk plus final chunk');
  });

  test('progress never exceeds the total and rises monotonically', () async {
    final src = writeRandom('big.mp4', 2 * 1024 * 1024);
    final dest = File(p.join(tmp.path, 'out', 'big.mp4'));
    final reports = <int>[];
    late int reportedTotal;

    await copyFileWithProgress(
      src,
      dest,
      onProgress: (copied, total) {
        reports.add(copied);
        reportedTotal = total;
      },
      throttle: Duration.zero,
    );

    expect(reportedTotal, src.lengthSync());
    for (int i = 1; i < reports.length; i++) {
      expect(reports[i], greaterThan(reports[i - 1]));
    }
    expect(reports.last, lessThanOrEqualTo(reportedTotal));
  });

  test(
    'a missing source throws and leaves no half-written sink open',
    () async {
      final src = File(p.join(tmp.path, 'nope.mp4'));
      final dest = File(p.join(tmp.path, 'out', 'nope.mp4'));

      await expectLater(
        copyFileWithProgress(src, dest),
        throwsA(isA<FileSystemException>()),
      );
    },
  );

  test('overwrites an existing destination rather than appending', () async {
    final src = writeRandom('a.mp4', 1024);
    final dest = File(p.join(tmp.path, 'out', 'a.mp4'))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(List<int>.filled(9999, 1));

    await copyFileWithProgress(src, dest);

    expect(dest.lengthSync(), 1024);
    expect(dest.readAsBytesSync(), src.readAsBytesSync());
  });
}
