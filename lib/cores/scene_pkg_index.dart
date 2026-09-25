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
    final _PackageHeaderReader header = _PackageHeaderReader(
      input,
      fileLength < _maxPackageHeaderBytes ? fileLength : _maxPackageHeaderBytes,
    );
    final int magicLength = await header.readInt();
    if (magicLength != 8) return null;
    final String magic = await header.readString(magicLength);
    if (!RegExp(r'^PKGV\d{4}$').hasMatch(magic)) return null;
    final int count = await header.readInt();
    if (count < 0 || count > _maxPackageEntries) return null;

    final Map<String, ScenePackageEntry> entries =
        <String, ScenePackageEntry>{};
    for (int index = 0; index < count; index++) {
      if (header.position > _maxPackageHeaderBytes - 12) return null;
      final int pathLength = await header.readInt();
      if (pathLength < 1 || pathLength > 255) return null;
      final String entryPath = await header.readString(pathLength);
      final List<String> segments = entryPath.split(RegExp(r'[/\\]'));
      if (segments.any(
            (String segment) =>
                segment.isEmpty || segment == '.' || segment == '..',
          ) ||
          entryPath.contains(':') ||
          entryPath.contains('\u0000')) {
        return null;
      }
      final int offset = await header.readInt();
      final int length = await header.readInt();
      if (offset < 0 || length < 0) return null;
      final String key = segments.join(r'\').toLowerCase();
      if (entries.containsKey(key)) return null;
      entries[key] = (path: entryPath, offset: offset, length: length);
    }

    final int headerBytes = header.position;
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

class _PackageHeaderReader {
  _PackageHeaderReader(this.input, this.limit)
    : _buffer = Uint8List(limit < 16 * 1024 ? limit : 16 * 1024);

  final RandomAccessFile input;
  final int limit;
  Uint8List _buffer;
  int _loaded = 0;
  int position = 0;

  Future<int> readInt() async {
    await _ensure(4);
    final int value =
        _buffer[position] |
        (_buffer[position + 1] << 8) |
        (_buffer[position + 2] << 16) |
        (_buffer[position + 3] << 24);
    position += 4;
    return value.toSigned(32);
  }

  Future<String> readString(int length) async {
    await _ensure(length);
    final String value = utf8.decode(
      Uint8List.sublistView(_buffer, position, position + length),
    );
    position += length;
    return value;
  }

  Future<void> _ensure(int length) async {
    final int end = position + length;
    if (end > limit) throw const FormatException('Truncated package');
    if (end > _buffer.length) {
      final int doubled = _buffer.length * 2;
      final int capacity = doubled > end ? doubled : end;
      final Uint8List next = Uint8List(capacity < limit ? capacity : limit);
      next.setRange(0, _loaded, _buffer);
      _buffer = next;
    }
    while (_loaded < end) {
      final int count = await input.readInto(_buffer, _loaded, _buffer.length);
      if (count == 0) throw const FormatException('Truncated package');
      _loaded += count;
    }
  }
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
  Future<bool?> Function(File, int, int, File)? compareNative,
}) async {
  RandomAccessFile? sourceInput;
  RandomAccessFile? counterpartInput;
  try {
    if (offset < 0 || length < 0) return null;
    if (isCancelled?.call() == true) return null;
    if (compareNative != null) {
      try {
        final bool? native = await compareNative(
          source,
          offset,
          length,
          counterpart,
        );
        if (isCancelled?.call() == true) return null;
        if (native != null) return native;
      } catch (_) {
        if (isCancelled?.call() == true) return null;
      }
    }
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
