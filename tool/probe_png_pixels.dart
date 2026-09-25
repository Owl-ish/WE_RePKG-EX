// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as image;

// Read-only diagnostic for byte-different PNG pairs listed in a TSV manifest.
void main() {
  final String manifest = Platform.environment['PNG_PROBE_MANIFEST']!;
  final List<String> lines = File(manifest).readAsLinesSync();
  for (int index = 0; index < lines.length; index++) {
    final List<String> paths = lines[index].split('\t');
    final Stopwatch timer = Stopwatch()..start();
    final bool same = _samePixels(paths[0], paths[1]);
    print('DART_PAIR ${index + 1} $same ${timer.elapsedMilliseconds}ms');
  }
}

bool _samePixels(String firstPath, String secondPath) {
  try {
    final image.Image? first = image.decodeImage(
      File(firstPath).readAsBytesSync(),
    );
    final image.Image? second = image.decodeImage(
      File(secondPath).readAsBytesSync(),
    );
    if (first == null || second == null) return false;
    if (first.width != second.width ||
        first.height != second.height ||
        first.numFrames != second.numFrames) {
      return false;
    }
    for (int frame = 0; frame < first.numFrames; frame++) {
      final image.Image a = first.frames[frame];
      final image.Image b = second.frames[frame];
      if (a.frameDuration != b.frameDuration ||
          !_equalBytes(
            a.getBytes(order: image.ChannelOrder.rgba),
            b.getBytes(order: image.ChannelOrder.rgba),
          )) {
        return false;
      }
    }
    return true;
  } catch (_) {
    return false;
  }
}

bool _equalBytes(Uint8List first, Uint8List second) {
  if (first.length != second.length) return false;
  for (int index = 0; index < first.length; index++) {
    if (first[index] != second[index]) return false;
  }
  return true;
}
