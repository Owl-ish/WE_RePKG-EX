import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:we_repkg/cores/wallpaper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('getWindowsDisks', () {
    test('returns present drives in alphabetical order', () async {
      final present = {'C:\\', 'D:\\', 'Z:\\'};
      final disks = await getWindowsDisks(
        probe: (path) async => present.contains(path),
      );
      expect(disks, ['C:', 'D:', 'Z:']);
    });

    test(
      'the system drive lands first, which path generation relies on',
      () async {
        final disks = await getWindowsDisks(
          probe: (path) async => {'C:\\', 'A:\\'}.contains(path),
        );
        expect(disks.first, 'A:');
      },
    );

    test('probes every letter exactly once', () async {
      final probed = <String>[];
      await getWindowsDisks(
        probe: (path) async {
          probed.add(path);
          return false;
        },
      );
      expect(probed.length, 26);
      expect(probed.first, 'A:\\');
      expect(probed.last, 'Z:\\');
      expect(probed.toSet().length, 26);
    });

    test('issues the probes concurrently rather than one at a time', () async {
      // A serial implementation waits out each probe in turn, so a 20ms delay
      // per letter costs 520ms. Concurrently it costs about one delay.
      int inFlight = 0;
      int peakInFlight = 0;
      final stopwatch = Stopwatch()..start();
      await getWindowsDisks(
        probe: (path) async {
          inFlight++;
          peakInFlight = peakInFlight > inFlight ? peakInFlight : inFlight;
          await Future<void>.delayed(const Duration(milliseconds: 20));
          inFlight--;
          return false;
        },
      );
      stopwatch.stop();
      expect(peakInFlight, 26, reason: 'all 26 probes should overlap');
      expect(stopwatch.elapsedMilliseconds, lessThan(300));
    });

    test('returns an empty list when no drive exists', () async {
      final disks = await getWindowsDisks(probe: (_) async => false);
      expect(disks, isEmpty);
    });

    test('swallows a probe failure instead of breaking the scan', () async {
      final disks = await getWindowsDisks(
        probe: (path) async => throw const FileSystemException('nope'),
      );
      expect(disks, isEmpty);
    });
  });
}
