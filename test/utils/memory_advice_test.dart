import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:we_repkg/utils/memory_advice.dart';
import 'package:we_repkg/utils/system_memory.dart';

void main() {
  const int mb = 1024 * 1024;

  group('memoryAdvice', () {
    test('a setting under what is free is not a warning', () {
      final advice = memoryAdvice(settingMb: 1024, availableBytes: 4096 * mb);

      expect(advice.freeMb, 4096);
      expect(advice.exceedsFree, isFalse);
    });

    test('a setting above what is free is', () {
      final advice = memoryAdvice(settingMb: 8192, availableBytes: 2048 * mb);

      expect(advice.freeMb, 2048);
      expect(advice.exceedsFree, isTrue);
    });

    // The boundary is the whole point of the line, so it is worth pinning which
    // side of it counts.
    test('asking for exactly what is free is not a warning', () {
      expect(
        memoryAdvice(settingMb: 2048, availableBytes: 2048 * mb).exceedsFree,
        isFalse,
      );
      expect(
        memoryAdvice(settingMb: 2049, availableBytes: 2048 * mb).exceedsFree,
        isTrue,
      );
    });

    // Nothing to compare against, so there is nothing to warn about and nothing
    // to show. The caller drops the line entirely on a null.
    test('a machine that could not be read warns about nothing', () {
      final advice = memoryAdvice(settingMb: 16384, availableBytes: null);

      expect(advice.freeMb, isNull);
      expect(advice.exceedsFree, isFalse);
    });
  });

  group('formatGb', () {
    test('reads as gigabytes to one decimal', () {
      expect(formatGb(4096), '4.0 GB');
      expect(formatGb(6231), '6.1 GB');
      expect(formatGb(256), '0.3 GB');
    });
  });

  group('availableMemoryBytes', () {
    test('reports something a Windows machine could plausibly have', () {
      final int? available = availableMemoryBytes();
      final int? installed = installedMemoryBytes();

      if (!Platform.isWindows) {
        expect(available, isNull);
        return;
      }

      expect(available, isNotNull);
      expect(available, greaterThan(0));
      expect(
        available,
        lessThanOrEqualTo(installed!),
        reason: 'free memory cannot exceed what is installed',
      );
    });
  });
}
