import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

typedef ScenePackageEntry = ({String path, int offset, int length});
typedef ScenePackageIndex = ({
  int headerBytes,
  Map<String, ScenePackageEntry> entries,
});

const int _maxPackageHeaderBytes = 32 * 1024 * 1024;
const int _maxPackageEntries = 100000;
const int _comparisonChunkBytes = 64 * 1024;

/// Reads only the package entry table. Offsets are relative to the end of the
/// table, as in RePKG's PackageReader; malformed or ambiguous tables fail closed.
Future<ScenePackageIndex?> readScenePackageIndex(File package) async {
  RandomAccessFile? input;
  try {
    input = await package.open();
    final int fileLength = await input.length();
    final int magicLength = await _readPackageInt(input);
    if (magicLength != 8) return null;
    final String magic = utf8.decode(
      await _readPackageBytes(input, magicLength),
    );
    if (!RegExp(r'^PKGV\d{4}$').hasMatch(magic)) return null;
    final int count = await _readPackageInt(input);
    if (count < 0 || count > _maxPackageEntries) return null;

    final Map<String, ScenePackageEntry> entries =
        <String, ScenePackageEntry>{};
    for (int index = 0; index < count; index++) {
      if (await input.position() > _maxPackageHeaderBytes - 12) return null;
      final int pathLength = await _readPackageInt(input);
      if (pathLength < 1 || pathLength > 255) return null;
      final String entryPath = utf8.decode(
        await _readPackageBytes(input, pathLength),
      );
      final List<String> segments = entryPath.split(RegExp(r'[/\\]'));
      if (segments.any(
            (String segment) =>
                segment.isEmpty || segment == '.' || segment == '..',
          ) ||
          entryPath.contains(':') ||
          entryPath.contains('\u0000')) {
        return null;
      }
      final int offset = await _readPackageInt(input);
      final int length = await _readPackageInt(input);
      if (offset < 0 || length < 0) return null;
      final String key = segments.join(r'\').toLowerCase();
      if (entries.containsKey(key)) return null;
      entries[key] = (path: entryPath, offset: offset, length: length);
    }

    final int headerBytes = await input.position();
    if (headerBytes > _maxPackageHeaderBytes) return null;
    final List<({int start, int end})> ranges = <({int start, int end})>[
      for (final ScenePackageEntry entry in entries.values)
        (start: entry.offset, end: entry.offset + entry.length),
    ]..sort((a, b) => a.start.compareTo(b.start));
    int previousEnd = 0;
    for (final range in ranges) {
      if (range.start < previousEnd || range.end > fileLength - headerBytes) {
        return null;
      }
      previousEnd = range.end;
    }
    return (headerBytes: headerBytes, entries: entries);
  } on FileSystemException {
    return null;
  } on FormatException {
    return null;
  } finally {
    await input?.close();
  }
}

Future<int> _readPackageInt(RandomAccessFile input) async {
  final List<int> bytes = await _readPackageBytes(input, 4);
  return ByteData.sublistView(
    Uint8List.fromList(bytes),
  ).getInt32(0, Endian.little);
}

Future<List<int>> _readPackageBytes(RandomAccessFile input, int count) async {
  final List<int> bytes = await input.read(count);
  if (bytes.length != count) throw const FormatException('Truncated package');
  return bytes;
}

/// Compares a raw package entry with an unpacked file without extraction.
/// A true result proves raw equality only; generated images and metadata need
/// separate semantic validation before the whole backup can be called identical.
Future<bool?> scenePackageEntryMatchesFile({
  required File package,
  required ScenePackageIndex index,
  required ScenePackageEntry entry,
  required File unpacked,
  bool Function()? isCancelled,
}) async {
  return fileSegmentMatchesFile(
    source: package,
    offset: index.headerBytes + entry.offset,
    length: entry.length,
    counterpart: unpacked,
    isCancelled: isCancelled,
  );
}

/// Compares a bounded file segment with a whole file, without copying either.
Future<bool?> fileSegmentMatchesFile({
  required File source,
  required int offset,
  required int length,
  required File counterpart,
  bool Function()? isCancelled,
}) async {
  RandomAccessFile? sourceInput;
  RandomAccessFile? counterpartInput;
  try {
    if (offset < 0 || length < 0) return null;
    sourceInput = await source.open();
    counterpartInput = await counterpart.open();
    final int sourceLength = await sourceInput.length();
    if (offset > sourceLength || length > sourceLength - offset) {
      return null;
    }
    if (await counterpartInput.length() != length) return false;
    await sourceInput.setPosition(offset);
    final Uint8List sourceChunk = Uint8List(_comparisonChunkBytes);
    final Uint8List counterpartChunk = Uint8List(_comparisonChunkBytes);
    int remaining = length;
    while (remaining > 0) {
      if (isCancelled?.call() == true) return null;
      final int size = remaining < _comparisonChunkBytes
          ? remaining
          : _comparisonChunkBytes;
      if (await sourceInput.readInto(sourceChunk, 0, size) != size ||
          await counterpartInput.readInto(counterpartChunk, 0, size) != size) {
        return null;
      }
      for (int index = 0; index < size; index++) {
        if (sourceChunk[index] != counterpartChunk[index]) return false;
      }
      remaining -= size;
    }
    return true;
  } on FileSystemException {
    return null;
  } finally {
    await sourceInput?.close();
    await counterpartInput?.close();
  }
}
