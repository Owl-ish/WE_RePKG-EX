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
