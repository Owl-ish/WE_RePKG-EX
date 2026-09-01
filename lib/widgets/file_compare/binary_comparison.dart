part of '../file_compare.dart';

typedef _BinaryFileInfo = ({
  int bytes,
  DateTime modified,
  String extension,
  String sha256,
});

Future<_BinaryFileInfo?> _readBinaryInfo(String filePath) async {
  final File file = File(filePath);
  if (!await file.exists()) return null;
  try {
    final FileStat before = await file.stat();
    if (before.type != FileSystemEntityType.file) return null;

    final Digest digest = await sha256.bind(file.openRead()).first;
    final FileStat after = await file.stat();

    // Do not present a hash as authoritative if the file changed while it was
    // being read. A retry from the Compare action will produce a fresh result.
    if (after.type != FileSystemEntityType.file ||
        before.size != after.size ||
        before.modified != after.modified) {
      return null;
    }

    return (
      bytes: after.size,
      modified: after.modified,
      extension: path.extension(filePath).toLowerCase(),
      sha256: digest.toString(),
    );
  } on FileSystemException {
    return null;
  } catch (_) {
    return null;
  }
}

Future<void> _showBinaryDialog(
  BuildContext context, {
  required FileComparisonSide first,
  required FileComparisonSide second,
  required String title,
  required String unavailableText,
  required String modeLabel,
  required String fileTypeLabel,
  required String fileSizeLabel,
  required String fileModifiedLabel,
  required String hashLabel,
  required String sameText,
  required String differentText,
  required String noExtensionText,
}) => showDialog<void>(
  context: context,
  builder: (BuildContext context) {
    final Size screen = MediaQuery.sizeOf(context);
    return Dialog(
      key: const ValueKey<String>('file-binary-compare-dialog'),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: min(980.0, screen.width * .88),
        height: min(620.0, screen.height * .76),
        child: _BinaryComparisonBody(
          first: first,
          second: second,
          title: title,
          unavailableText: unavailableText,
          modeLabel: modeLabel,
          fileTypeLabel: fileTypeLabel,
          fileSizeLabel: fileSizeLabel,
          fileModifiedLabel: fileModifiedLabel,
          hashLabel: hashLabel,
          sameText: sameText,
          differentText: differentText,
          noExtensionText: noExtensionText,
        ),
      ),
    );
  },
);

class _BinaryComparisonBody extends StatefulWidget {
  const _BinaryComparisonBody({
    required this.first,
    required this.second,
    required this.title,
    required this.unavailableText,
    required this.modeLabel,
    required this.fileTypeLabel,
    required this.fileSizeLabel,
    required this.fileModifiedLabel,
    required this.hashLabel,
    required this.sameText,
    required this.differentText,
    required this.noExtensionText,
  });

  final FileComparisonSide first;
  final FileComparisonSide second;
  final String title;
  final String unavailableText;
  final String modeLabel;
  final String fileTypeLabel;
  final String fileSizeLabel;
  final String fileModifiedLabel;
  final String hashLabel;
  final String sameText;
  final String differentText;
  final String noExtensionText;

  @override
  State<_BinaryComparisonBody> createState() => _BinaryComparisonBodyState();
}

class _BinaryComparisonBodyState extends State<_BinaryComparisonBody> {
  late Future<List<_BinaryFileInfo?>> _files;

  @override
  void initState() {
    super.initState();
    _files = _read();
  }

  @override
  void didUpdateWidget(covariant _BinaryComparisonBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.first.path != widget.first.path ||
        oldWidget.second.path != widget.second.path) {
      _files = _read();
    }
  }

  Future<List<_BinaryFileInfo?>> _read() =>
      Future.wait(<Future<_BinaryFileInfo?>>[
        _readBinaryInfo(widget.first.path),
        _readBinaryInfo(widget.second.path),
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
              key: const ValueKey<String>('file-binary-dialog-close'),
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close_rounded),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Expanded(
          child: FutureBuilder<List<_BinaryFileInfo?>>(
            future: _files,
            builder:
                (
                  BuildContext context,
                  AsyncSnapshot<List<_BinaryFileInfo?>> snapshot,
                ) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final List<_BinaryFileInfo?>? files = snapshot.data;
                  if (snapshot.hasError ||
                      files == null ||
                      files.length != 2 ||
                      files[0] == null ||
                      files[1] == null) {
                    return Center(child: Text(widget.unavailableText));
                  }
                  return _BinaryComparisonContent(
                    key: const ValueKey<String>('file-binary-compare-content'),
                    firstSide: widget.first,
                    secondSide: widget.second,
                    first: files[0]!,
                    second: files[1]!,
                    modeLabel: widget.modeLabel,
                    fileTypeLabel: widget.fileTypeLabel,
                    fileSizeLabel: widget.fileSizeLabel,
                    fileModifiedLabel: widget.fileModifiedLabel,
                    hashLabel: widget.hashLabel,
                    sameText: widget.sameText,
                    differentText: widget.differentText,
                    noExtensionText: widget.noExtensionText,
                  );
                },
          ),
        ),
      ],
    ),
  );
}

class _BinaryComparisonContent extends StatelessWidget {
  const _BinaryComparisonContent({
    super.key,
    required this.firstSide,
    required this.secondSide,
    required this.first,
    required this.second,
    required this.modeLabel,
    required this.fileTypeLabel,
    required this.fileSizeLabel,
    required this.fileModifiedLabel,
    required this.hashLabel,
    required this.sameText,
    required this.differentText,
    required this.noExtensionText,
  });

  final FileComparisonSide firstSide;
  final FileComparisonSide secondSide;
  final _BinaryFileInfo first;
  final _BinaryFileInfo second;
  final String modeLabel;
  final String fileTypeLabel;
  final String fileSizeLabel;
  final String fileModifiedLabel;
  final String hashLabel;
  final String sameText;
  final String differentText;
  final String noExtensionText;

  String _type(_BinaryFileInfo info) {
    if (info.extension.isEmpty) return noExtensionText;
    return info.extension.substring(1).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final bool sameHash = first.sha256 == second.sha256;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _ComparisonModeHeader(
          modeLabel: modeLabel,
          first: firstSide,
          second: secondSide,
        ),
        const SizedBox(height: 10),
        Center(
          child: _ComparisonStateBadge(
            key: const ValueKey<String>('file-binary-content-result'),
            label: '$hashLabel: ${sameHash ? sameText : differentText}',
            same: sameHash,
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: ListView(
            children: <Widget>[
              _BinaryMetadataRow(
                rowKey: 'type',
                label: fileTypeLabel,
                firstValue: _type(first),
                secondValue: _type(second),
                sameText: sameText,
                differentText: differentText,
                sameOverride: first.extension == second.extension,
              ),
              _BinaryMetadataRow(
                rowKey: 'size',
                label: fileSizeLabel,
                firstValue: _formatBytes(first.bytes),
                secondValue: _formatBytes(second.bytes),
                sameText: sameText,
                differentText: differentText,
                sameOverride: first.bytes == second.bytes,
              ),
              _BinaryMetadataRow(
                rowKey: 'modified',
                label: fileModifiedLabel,
                firstValue: _formatModified(first.modified),
                secondValue: _formatModified(second.modified),
                sameText: sameText,
                differentText: differentText,
                sameOverride: first.modified == second.modified,
              ),
              _BinaryMetadataRow(
                rowKey: 'sha256',
                label: hashLabel,
                firstValue: first.sha256,
                secondValue: second.sha256,
                sameText: sameText,
                differentText: differentText,
                sameOverride: sameHash,
                monospace: true,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _BinaryMetadataRow extends StatelessWidget {
  const _BinaryMetadataRow({
    required this.rowKey,
    required this.label,
    required this.firstValue,
    required this.secondValue,
    required this.sameText,
    required this.differentText,
    this.sameOverride,
    this.monospace = false,
  });

  final String rowKey;
  final String label;
  final String firstValue;
  final String secondValue;
  final String sameText;
  final String differentText;
  final bool? sameOverride;
  final bool monospace;

  @override
  Widget build(BuildContext context) {
    final bool same = sameOverride ?? firstValue == secondValue;
    final Color outline = Theme.of(context).colorScheme.outlineVariant;
    final TextStyle? valueStyle = monospace
        ? const TextStyle(fontFamily: 'Consolas', fontSize: 12)
        : Theme.of(context).textTheme.bodyMedium;

    return Container(
      key: ValueKey<String>('file-binary-row-$rowKey'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: outline)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 92,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(
            child: SelectableText(
              firstValue,
              key: ValueKey<String>('file-binary-before-$rowKey'),
              style: valueStyle,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: _ComparisonStateBadge(
              key: ValueKey<String>('file-binary-status-$rowKey'),
              label: same ? sameText : differentText,
              same: same,
            ),
          ),
          Expanded(
            child: SelectableText(
              secondValue,
              key: ValueKey<String>('file-binary-after-$rowKey'),
              style: valueStyle,
            ),
          ),
        ],
      ),
    );
  }
}

class _ComparisonStateBadge extends StatelessWidget {
  const _ComparisonStateBadge({
    super.key,
    required this.label,
    required this.same,
  });

  final String label;
  final bool same;

  @override
  Widget build(BuildContext context) {
    final Color colour = same
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.error;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colour.withValues(alpha: .1),
        border: Border.all(color: colour.withValues(alpha: .35)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: colour,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

String _formatModified(DateTime value) {
  final String iso = value.toLocal().toIso8601String();
  final int decimal = iso.indexOf('.');
  final String precise = decimal < 0
      ? iso
      : iso.substring(0, min(iso.length, decimal + 4));
  return precise.replaceFirst('T', ' ');
}
