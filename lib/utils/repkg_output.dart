class RePKGOutputSummary {
  const RePKGOutputSummary({
    required this.extractedFiles,
    required this.skippedFiles,
    required this.details,
  });

  final int extractedFiles;
  final int skippedFiles;
  final String details;
}

final RegExp _progressPattern = RegExp(
  r'^\s*\{"pos":(\d+),"total":(\d+)\}\s*$',
);

/// Reads one of RePKG's `--progress-json` lines, or null for anything else.
///
/// A regex rather than a JSON decode: this runs on every line RePKG prints, and
/// all but a handful of them are ordinary log text.
({int position, int total})? parseRePKGProgress(String line) {
  final match = _progressPattern.firstMatch(line);
  if (match == null) return null;
  final int total = int.parse(match.group(2)!);
  if (total <= 0) return null;
  return (position: int.parse(match.group(1)!), total: total);
}

/// Reduces RePKG's verbose output to the facts useful in an error dialog.
RePKGOutputSummary summarizeRePKGOutput(String stdout, String stderr) {
  final lines = '$stdout\n$stderr'
      .split(RegExp(r'\r?\n'))
      .map(_stripAnsi)
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();

  int extractedFiles = 0;
  int skippedFiles = 0;
  final details = <String>[];
  for (final line in lines) {
    final lower = line.toLowerCase();
    if (RegExp(r'^\*\s*extracting:', caseSensitive: false).hasMatch(line)) {
      extractedFiles++;
      continue;
    }
    if (RegExp(
      r'^\*\s*skipping,\s*already exists:',
      caseSensitive: false,
    ).hasMatch(line)) {
      skippedFiles++;
      continue;
    }
    if (lower.contains('exception') ||
        lower.contains('error') ||
        lower.contains('failed') ||
        lower.contains('fatal') ||
        lower.startsWith('at ')) {
      if (!details.contains(line)) details.add(line);
    }
  }

  return RePKGOutputSummary(
    extractedFiles: extractedFiles,
    skippedFiles: skippedFiles,
    details: details.take(8).join('\n'),
  );
}

String _stripAnsi(String value) {
  return value.replaceAll(RegExp(r'\x1B\[[0-?]*[ -/]*[@-~]'), '');
}
