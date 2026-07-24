import 'package:flutter_test/flutter_test.dart';
import 'package:we_repkg/utils/work_pool.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'returns results in input order despite finishing out of order',
    () async {
      // Later items finish first, which is exactly what a cursor-based progress
      // model got wrong.
      final results = await runBounded<int, String>([0, 1, 2, 3, 4, 5], (
        i,
      ) async {
        await Future<void>.delayed(Duration(milliseconds: (6 - i) * 10));
        return 'item$i';
      }, concurrency: 6);
      expect(results, ['item0', 'item1', 'item2', 'item3', 'item4', 'item5']);
    },
  );

  test('processes every item exactly once', () async {
    final seen = <int>[];
    await runBounded<int, void>(
      List<int>.generate(100, (i) => i),
      (i) async => seen.add(i),
      concurrency: 7,
    );
    expect(seen.length, 100);
    expect(seen.toSet().length, 100);
  });

  test('never exceeds the concurrency limit', () async {
    int inFlight = 0;
    int peak = 0;
    await runBounded<int, void>(List<int>.generate(50, (i) => i), (_) async {
      inFlight++;
      peak = peak > inFlight ? peak : inFlight;
      await Future<void>.delayed(const Duration(milliseconds: 2));
      inFlight--;
    }, concurrency: 4);
    expect(peak, 4);
  });

  test('actually runs work in parallel', () async {
    // 12 items at 30ms each: serial is 360ms, four at a time is about 90ms.
    final stopwatch = Stopwatch()..start();
    await runBounded<int, void>(
      List<int>.generate(12, (i) => i),
      (_) => Future<void>.delayed(const Duration(milliseconds: 30)),
      concurrency: 4,
    );
    stopwatch.stop();
    expect(stopwatch.elapsedMilliseconds, lessThan(250));
  });

  test('an empty list does no work', () async {
    var called = false;
    final results = await runBounded<int, int>([], (i) async {
      called = true;
      return i;
    }, concurrency: 4);
    expect(results, isEmpty);
    expect(called, isFalse);
  });

  test('concurrency above the item count spawns no idle workers', () async {
    int peak = 0;
    int inFlight = 0;
    await runBounded<int, void>([1, 2], (_) async {
      inFlight++;
      peak = peak > inFlight ? peak : inFlight;
      await Future<void>.delayed(const Duration(milliseconds: 5));
      inFlight--;
    }, concurrency: 64);
    expect(peak, 2);
  });

  test('a concurrency below one still makes progress', () async {
    final results = await runBounded<int, int>(
      [1, 2, 3],
      (i) async => i * 2,
      concurrency: 0,
    );
    expect(results, [2, 4, 6]);
  });

  test('onStart and onComplete fire once per item', () async {
    final started = <int>[];
    final completed = <int>[];
    await runBounded<int, void>(
      List<int>.generate(20, (i) => i),
      (_) => Future<void>.delayed(const Duration(milliseconds: 1)),
      concurrency: 3,
      onStart: started.add,
      onComplete: completed.add,
    );
    expect(started.length, 20);
    expect(completed.length, 20);
    expect(started.toSet(), completed.toSet());
  });

  test('the completion count never exceeds the total', () async {
    // Premortem item 3: the loading view divides by this, and used to index a
    // list with it.
    const int total = 30;
    int completions = 0;
    await runBounded<int, void>(
      List<int>.generate(total, (i) => i),
      (_) => Future<void>.delayed(const Duration(milliseconds: 1)),
      concurrency: 5,
      onComplete: (_) {
        completions++;
        expect(completions, lessThanOrEqualTo(total));
      },
    );
    expect(completions, total);
  });

  test('a throw surfaces after in-flight work settles', () async {
    int finished = 0;
    await expectLater(
      runBounded<int, void>([0, 1, 2, 3], (i) async {
        await Future<void>.delayed(const Duration(milliseconds: 5));
        if (i == 1) throw StateError('boom');
        finished++;
      }, concurrency: 4),
      throwsA(isA<StateError>()),
    );
    expect(finished, 3, reason: 'the other three still completed');
  });

  test(
    'returning errors instead of throwing finishes the whole batch',
    () async {
      // How the extract functions use it: one bad wallpaper must not abandon the
      // rest of the run.
      final results = await runBounded<int, String?>(
        List<int>.generate(10, (i) => i),
        (i) async => i.isEven ? null : 'failed $i',
        concurrency: 3,
      );
      expect(results.length, 10);
      expect(results.whereType<String>().length, 5);
      expect(results[0], isNull);
      expect(results[1], 'failed 1');
    },
  );
}
