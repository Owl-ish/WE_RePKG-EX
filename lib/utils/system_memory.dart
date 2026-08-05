import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

typedef _InstalledMemoryC = Int32 Function(Pointer<Uint64>);
typedef _InstalledMemoryDart = int Function(Pointer<Uint64>);

typedef _MemoryStatusC = Int32 Function(Pointer<_MemoryStatusEx>);
typedef _MemoryStatusDart = int Function(Pointer<_MemoryStatusEx>);

/// Field order and widths are the API's. The unused ones still have to be
/// declared for `dwLength` to describe the struct being passed.
final class _MemoryStatusEx extends Struct {
  @Uint32()
  external int dwLength;
  @Uint32()
  external int dwMemoryLoad;
  @Uint64()
  external int ullTotalPhys;
  @Uint64()
  external int ullAvailPhys;
  @Uint64()
  external int ullTotalPageFile;
  @Uint64()
  external int ullAvailPageFile;
  @Uint64()
  external int ullTotalVirtual;
  @Uint64()
  external int ullAvailVirtual;
  @Uint64()
  external int ullAvailExtendedVirtual;
}

/// Installed RAM in bytes, or null when it could not be read.
///
/// Read once and cached: it cannot change while the app runs, and every caller
/// wants the same answer. Null means callers should fall back to bounding by
/// core count alone rather than guessing at a size.
int? installedMemoryBytes() => _installed ??= _read();

int? _installed;

int? _read() {
  if (!Platform.isWindows) return null;
  final Pointer<Uint64> out = calloc<Uint64>();
  try {
    final int ok = DynamicLibrary.open('kernel32.dll')
        .lookupFunction<_InstalledMemoryC, _InstalledMemoryDart>(
          'GetPhysicallyInstalledSystemMemory',
        )(out);
    // The API reports kilobytes.
    return ok == 0 ? null : out.value * 1024;
  } catch (e) {
    debugPrint('Installed memory unavailable: $e');
    return null;
  } finally {
    calloc.free(out);
  }
}

/// Physical memory not currently in use, in bytes, or null when it could not be
/// read.
///
/// Deliberately not cached, unlike the installed figure: this is the number that
/// moves while the app is open, and a reading taken at startup would describe a
/// machine the user has since opened a browser on.
int? availableMemoryBytes() {
  if (!Platform.isWindows) return null;
  final Pointer<_MemoryStatusEx> status = calloc<_MemoryStatusEx>();
  try {
    status.ref.dwLength = sizeOf<_MemoryStatusEx>();
    final int ok = DynamicLibrary.open('kernel32.dll')
        .lookupFunction<_MemoryStatusC, _MemoryStatusDart>(
          'GlobalMemoryStatusEx',
        )(status);
    return ok == 0 ? null : status.ref.ullAvailPhys;
  } catch (e) {
    debugPrint('Available memory unavailable: $e');
    return null;
  } finally {
    calloc.free(status);
  }
}

@visibleForTesting
void resetInstalledMemoryCache() => _installed = null;
