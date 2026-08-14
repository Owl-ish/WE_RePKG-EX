import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

/// Moves a fully written sibling to its final path without replacing anything
/// that appeared there in the meantime.
void publishWithoutReplacing(FileSystemEntity staged, String destination) {
  if (!Platform.isWindows) {
    throw UnsupportedError('Atomic repair publishing requires Windows.');
  }
  final Pointer<Utf16> from = staged.path.toNativeUtf16();
  final Pointer<Utf16> to = destination.toNativeUtf16();
  try {
    if (MoveFile(from, to) == 0) {
      throw FileSystemException(
        'Could not publish without replacing an existing path',
        destination,
        OSError('Windows error', GetLastError()),
      );
    }
  } finally {
    calloc.free(from);
    calloc.free(to);
  }
}
