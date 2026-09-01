part of '../file_compare.dart';

const int _maxTextPreviewBytes = 1024 * 1024;
typedef _TextFileInfo = ({int bytes, String text, bool truncated});

Future<_TextFileInfo?> _readTextInfo(String filePath) async {
  final File file = File(filePath);
  if (!await file.exists()) return null;
  RandomAccessFile? handle;
  try {
    final FileStat stat = await file.stat();
    final int readableBytes = min(stat.size, _maxTextPreviewBytes);
    handle = await file.open();
    final List<int> bytes = await handle.read(readableBytes);
    return (
      bytes: stat.size,
      text: utf8.decode(bytes, allowMalformed: true),
      truncated: stat.size > readableBytes,
    );
  } on FileSystemException {
    return null;
  } catch (_) {
    return null;
  } finally {
    if (handle != null) await handle.close();
  }
}

class _JsonDifference {
  const _JsonDifference({
    required this.field,
    required this.before,
    required this.after,
    required this.beforePresent,
    required this.afterPresent,
  });

  final String field;
  final Object? before;
  final Object? after;
  final bool beforePresent;
  final bool afterPresent;
}

class _JsonComparison {
  const _JsonComparison(this.differences);

  final List<_JsonDifference> differences;
}

_JsonComparison? _tryJsonComparison(_TextFileInfo first, _TextFileInfo second) {
  if (first.truncated || second.truncated) return null;
  Object? left;
  Object? right;
  try {
    left = jsonDecode(first.text);
    right = jsonDecode(second.text);
  } on FormatException {
    return null;
  }

  final Map<String, Object?> before = <String, Object?>{};
  final Map<String, Object?> after = <String, Object?>{};
  _flattenJson(left, r'$', before);
  _flattenJson(right, r'$', after);
  final List<String> fields = <String>{...before.keys, ...after.keys}.toList()
    ..sort();

  final List<_JsonDifference> differences = <_JsonDifference>[];
  for (final String field in fields) {
    final bool beforePresent = before.containsKey(field);
    final bool afterPresent = after.containsKey(field);
    final Object? beforeValue = before[field];
    final Object? afterValue = after[field];
    if (beforePresent == afterPresent &&
        (!beforePresent || jsonEncode(beforeValue) == jsonEncode(afterValue))) {
      continue;
    }
    differences.add(
      _JsonDifference(
        field: field,
        before: beforeValue,
        after: afterValue,
        beforePresent: beforePresent,
        afterPresent: afterPresent,
      ),
    );
  }
  return _JsonComparison(differences);
}

void _flattenJson(Object? value, String field, Map<String, Object?> output) {
  if (value is Map) {
    if (value.isEmpty) {
      output[field] = const <String, Object?>{};
      return;
    }
    for (final Object? rawKey in value.keys) {
      final String key = rawKey.toString();
      _flattenJson(value[rawKey], '$field.$key', output);
    }
    return;
  }
  if (value is List) {
    if (value.isEmpty) {
      output[field] = const <Object?>[];
      return;
    }
    for (int index = 0; index < value.length; index++) {
      _flattenJson(value[index], '$field[$index]', output);
    }
    return;
  }
  output[field] = value;
}

Future<void> _showTextDialog(
  BuildContext context, {
  required FileComparisonSide first,
  required FileComparisonSide second,
  required String title,
  required String unavailableText,
  required String jsonModeLabel,
  required String textModeLabel,
  required String jsonNoDifferencesText,
  required String missingValueText,
  required String truncatedText,
}) => showDialog<void>(
  context: context,
  builder: (BuildContext context) {
    final Size screen = MediaQuery.sizeOf(context);
    return Dialog(
      key: const ValueKey<String>('file-text-compare-dialog'),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: min(1120.0, screen.width * .9),
        height: min(760.0, screen.height * .82),
        child: _TextComparisonBody(
          first: first,
          second: second,
          title: title,
          unavailableText: unavailableText,
          jsonModeLabel: jsonModeLabel,
          textModeLabel: textModeLabel,
          jsonNoDifferencesText: jsonNoDifferencesText,
          missingValueText: missingValueText,
          truncatedText: truncatedText,
        ),
      ),
    );
  },
);

class _TextComparisonBody extends StatefulWidget {
  const _TextComparisonBody({
    required this.first,
    required this.second,
    required this.title,
    required this.unavailableText,
    required this.jsonModeLabel,
    required this.textModeLabel,
    required this.jsonNoDifferencesText,
    required this.missingValueText,
    required this.truncatedText,
  });

  final FileComparisonSide first;
  final FileComparisonSide second;
  final String title;
  final String unavailableText;
  final String jsonModeLabel;
  final String textModeLabel;
  final String jsonNoDifferencesText;
  final String missingValueText;
  final String truncatedText;

  @override
  State<_TextComparisonBody> createState() => _TextComparisonBodyState();
}

class _TextComparisonBodyState extends State<_TextComparisonBody> {
  late Future<List<_TextFileInfo?>> _files;

  @override
  void initState() {
    super.initState();
    _files = _read();
  }

  @override
  void didUpdateWidget(covariant _TextComparisonBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.first.path != widget.first.path ||
        oldWidget.second.path != widget.second.path) {
      _files = _read();
    }
  }

  Future<List<_TextFileInfo?>> _read() => Future.wait(<Future<_TextFileInfo?>>[
    _readTextInfo(widget.first.path),
    _readTextInfo(widget.second.path),
  ]);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                widget.title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            IconButton(
              key: const ValueKey<String>('file-text-dialog-close'),
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close_rounded),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Expanded(
          child: FutureBuilder<List<_TextFileInfo?>>(
            future: _files,
            builder:
                (
                  BuildContext context,
                  AsyncSnapshot<List<_TextFileInfo?>> snapshot,
                ) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final List<_TextFileInfo?>? files = snapshot.data;
                  if (snapshot.hasError ||
                      files == null ||
                      files.length != 2 ||
                      files[0] == null ||
                      files[1] == null) {
                    return Center(child: Text(widget.unavailableText));
                  }
                  final _TextFileInfo first = files[0]!;
                  final _TextFileInfo second = files[1]!;
                  final _JsonComparison? json = _tryJsonComparison(
                    first,
                    second,
                  );
                  if (json != null) {
                    return _StructuredJsonComparison(
                      key: const ValueKey<String>('file-json-compare-content'),
                      firstSide: widget.first,
                      secondSide: widget.second,
                      comparison: json,
                      modeLabel: widget.jsonModeLabel,
                      noDifferencesText: widget.jsonNoDifferencesText,
                      missingValueText: widget.missingValueText,
                    );
                  }
                  return _PlainTextComparison(
                    key: const ValueKey<String>(
                      'file-plain-text-compare-content',
                    ),
                    firstSide: widget.first,
                    secondSide: widget.second,
                    first: first,
                    second: second,
                    modeLabel: widget.textModeLabel,
                    truncatedText: widget.truncatedText,
                  );
                },
          ),
        ),
      ],
    ),
  );
}

class _StructuredJsonComparison extends StatelessWidget {
  const _StructuredJsonComparison({
    super.key,
    required this.firstSide,
    required this.secondSide,
    required this.comparison,
    required this.modeLabel,
    required this.noDifferencesText,
    required this.missingValueText,
  });

  final FileComparisonSide firstSide;
  final FileComparisonSide secondSide;
  final _JsonComparison comparison;
  final String modeLabel;
  final String noDifferencesText;
  final String missingValueText;

  String _value(Object? value, bool present) =>
      present ? jsonEncode(value) : missingValueText;

  @override
  Widget build(BuildContext context) {
    final Color outline = Theme.of(context).colorScheme.outlineVariant;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _ComparisonModeHeader(
          modeLabel: modeLabel,
          first: firstSide,
          second: secondSide,
        ),
        const SizedBox(height: 8),
        Expanded(
          child: comparison.differences.isEmpty
              ? Center(child: Text(noDifferencesText))
              : ListView.separated(
                  itemCount: comparison.differences.length,
                  separatorBuilder: (_, _) =>
                      Divider(height: 1, color: outline.withValues(alpha: .65)),
                  itemBuilder: (BuildContext context, int index) {
                    final _JsonDifference difference =
                        comparison.differences[index];
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 8,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          Text(
                            formatJsonFieldPath(difference.field),
                            style: const TextStyle(
                              fontFamily: 'Consolas',
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Expanded(
                                child: SelectableText(
                                  _value(
                                    difference.before,
                                    difference.beforePresent,
                                  ),
                                  key: ValueKey<String>(
                                    'file-json-before-${difference.field}',
                                  ),
                                  style: const TextStyle(
                                    fontFamily: 'Consolas',
                                  ),
                                ),
                              ),
                              const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 10),
                                child: Icon(
                                  Icons.compare_arrows_rounded,
                                  size: 16,
                                ),
                              ),
                              Expanded(
                                child: SelectableText(
                                  _value(
                                    difference.after,
                                    difference.afterPresent,
                                  ),
                                  key: ValueKey<String>(
                                    'file-json-after-${difference.field}',
                                  ),
                                  style: const TextStyle(
                                    fontFamily: 'Consolas',
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _PlainTextComparison extends StatelessWidget {
  const _PlainTextComparison({
    super.key,
    required this.firstSide,
    required this.secondSide,
    required this.first,
    required this.second,
    required this.modeLabel,
    required this.truncatedText,
  });

  final FileComparisonSide firstSide;
  final FileComparisonSide secondSide;
  final _TextFileInfo first;
  final _TextFileInfo second;
  final String modeLabel;
  final String truncatedText;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      _ComparisonModeHeader(
        modeLabel: modeLabel,
        first: firstSide,
        second: secondSide,
      ),
      const SizedBox(height: 8),
      Expanded(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Expanded(
              child: _TextPane(
                side: firstSide,
                info: first,
                truncatedText: truncatedText,
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 10),
              child: Icon(Icons.compare_arrows_rounded),
            ),
            Expanded(
              child: _TextPane(
                side: secondSide,
                info: second,
                truncatedText: truncatedText,
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

class _TextPane extends StatelessWidget {
  const _TextPane({
    required this.side,
    required this.info,
    required this.truncatedText,
  });

  final FileComparisonSide side;
  final _TextFileInfo info;
  final String truncatedText;

  @override
  Widget build(BuildContext context) {
    final Color outline = Theme.of(context).colorScheme.outlineVariant;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: outline),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              _formatBytes(info.bytes),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (info.truncated)
              Text(
                truncatedText,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            const SizedBox(height: 6),
            Expanded(
              child: SingleChildScrollView(
                child: SelectableText(
                  info.text,
                  key: ValueKey<String>('file-text-${side.path}'),
                  style: const TextStyle(fontFamily: 'Consolas', fontSize: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
