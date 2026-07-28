import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:we_repkg/utils/info.dart';

void main() {
  test('parses stdout and removes build metadata', () {
    expect(
      parseRepkgVersionOutput(
        'RePKG 0.4.0+e69a76dcdb461f5bdeba01a8a7fa5131a09bcefe',
        '',
      ),
      '0.4.0',
    );
  });

  test('preserves an EX semantic-version suffix from stderr', () {
    expect(parseRepkgVersionOutput('', 'RePKG 0.5.0-ex+abc123'), '0.5.0-ex');
  });

  test('returns null for unrelated or empty output', () {
    expect(parseRepkgVersionOutput('hello', ''), isNull);
    expect(parseRepkgVersionOutput('', ''), isNull);
  });

  group('extract flag support', () {
    test('accepts the version that introduced the flags, and later', () {
      expect(repkgSupportsExtractFlags('0.5.1-ex'), isTrue);
      expect(repkgSupportsExtractFlags('0.6.0-ex'), isTrue);
      expect(repkgSupportsExtractFlags('1.0.0-ex'), isTrue);
    });

    test('rejects earlier versions of this fork', () {
      expect(repkgSupportsExtractFlags('0.5.0-ex'), isFalse);
      expect(repkgSupportsExtractFlags('0.4.9-ex'), isFalse);
    });

    // addallno's fork numbers itself 0.5.1 and has neither flag, so matching on
    // the numbers alone would send them to a tool that answers by writing
    // nothing and exiting 0.
    test('rejects a same-numbered fork without the ex suffix', () {
      expect(repkgSupportsExtractFlags('0.5.1'), isFalse);
      expect(repkgSupportsExtractFlags('0.6.0'), isFalse);
    });

    test('rejects unreadable and absent versions', () {
      expect(repkgSupportsExtractFlags(null), isFalse);
      expect(repkgSupportsExtractFlags(''), isFalse);
      expect(repkgSupportsExtractFlags('nonsense'), isFalse);
    });
  });

  final File localRepkgFixture = File(r'test\scene\RePKG.exe');
  test(
    'reads the version directly from RePKG.exe',
    () async {
      expect(await readRepkgVersion(localRepkgFixture.path), '0.4.0');
    },
    skip: localRepkgFixture.existsSync()
        ? false
        : 'Local RePKG fixture is not committed.',
  );
}
