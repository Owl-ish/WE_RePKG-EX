import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

typedef _InstalledMemoryC = Int32 Function(Pointer<Uint64>);
typedef _InstalledMemoryDart = int Function(Pointer<Uint64>);

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

@visibleForTesting
void resetInstalledMemoryCache() => _installed = null;
