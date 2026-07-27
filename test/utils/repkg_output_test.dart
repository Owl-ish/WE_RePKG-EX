import 'package:flutter_test/flutter_test.dart';
import 'package:we_repkg/utils/repkg_output.dart';

void main() {
  test('counts extracted and skipped files across both output streams', () {
    final summary = summarizeRePKGOutput(
      '* Extracting: scene.json\n* Skipping, already exists: materials/a.tex',
      '* Extracting: materials/b.tex',
    );

    expect(summary.extractedFiles, 2);
    expect(summary.skippedFiles, 1);
    expect(summary.details, isEmpty);
  });

  test('keeps useful error details but drops verbose progress lines', () {
    final summary = summarizeRePKGOutput(
      '* Extracting: scene.json\nError: file is locked',
      'System.IO.IOException: collision\n   at RePKG.Extract()',
    );

    expect(summary.extractedFiles, 1);
    expect(summary.details, contains('Error: file is locked'));
    expect(summary.details, contains('System.IO.IOException: collision'));
    expect(summary.details, contains('at RePKG.Extract()'));
    expect(summary.details, isNot(contains('* Extracting:')));
  });

  test('empty output reports no work and no details', () {
    final summary = summarizeRePKGOutput('', '');

    expect(summary.extractedFiles, 0);
    expect(summary.skippedFiles, 0);
    expect(summary.details, isEmpty);
  });
}
