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

/// Stable identity of one existing Windows file, even if another file later
/// takes the same path.
String windowsFileIdentity(String filePath) {
  if (!Platform.isWindows) {
    throw UnsupportedError('Repair file identity requires Windows.');
  }
  final Pointer<Utf16> name = filePath.toNativeUtf16();
  final Pointer<BY_HANDLE_FILE_INFORMATION> info =
      calloc<BY_HANDLE_FILE_INFORMATION>();
  final int handle = CreateFile(
    name,
    0,
    FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
    nullptr,
    OPEN_EXISTING,
    FILE_ATTRIBUTE_NORMAL,
    0,
  );
  try {
    if (handle == INVALID_HANDLE_VALUE ||
        GetFileInformationByHandle(handle, info) == 0) {
      throw FileSystemException(
        'Could not identify repair source',
        filePath,
        OSError('Windows error', GetLastError()),
      );
    }
    final BY_HANDLE_FILE_INFORMATION value = info.ref;
    return <int>[
      value.dwVolumeSerialNumber,
      value.nFileIndexHigh,
      value.nFileIndexLow,
      value.nFileSizeHigh,
      value.nFileSizeLow,
      value.ftCreationTime.dwHighDateTime,
      value.ftCreationTime.dwLowDateTime,
      value.ftLastWriteTime.dwHighDateTime,
      value.ftLastWriteTime.dwLowDateTime,
    ].join(':');
  } finally {
    if (handle != INVALID_HANDLE_VALUE) CloseHandle(handle);
    calloc.free(name);
    calloc.free(info);
  }
}

/// False only when Windows confirms that [processId] is no longer running.
bool windowsProcessIsRunning(int processId) {
  final int handle = OpenProcess(SYNCHRONIZE, 0, processId);
  if (handle == 0) return GetLastError() != ERROR_INVALID_PARAMETER;
  try {
    // Only a signalled process handle proves the owner exited. Access and wait
    // errors are treated as live so another operation's stage is never swept.
    return WaitForSingleObject(handle, 0) != WAIT_OBJECT_0;
  } finally {
    CloseHandle(handle);
  }
}
