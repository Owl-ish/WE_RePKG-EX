import 'dart:io';

import 'package:we_repkg/utils/cancel_token.dart';

/// Thrown when a copy stops part way because [CancelToken.cancel] was called.
class CopyCancelled implements Exception {
  const CopyCancelled();

  @override
  String toString() => 'CopyCancelled';
}

/// Streams [source] into [destination], reporting progress at most once per
/// [throttle], and always once at the end.
///
/// Pass [cancelToken] to stop between chunks. Without one a cancelled batch
/// still has to copy the whole file before it can report itself cancelled,
/// which on a multi-gigabyte video is minutes of looking hung.
///
/// addStream rather than a listen loop, because IOSink.add never blocks: a fast
/// read into a slow USB stick would buffer the whole difference in memory.
/// Throttled because 64KB chunks mean a 3GB video fires ~50,000 events, and a
/// provider write on each is most of the jank during a video export.
Future<void> copyFileWithProgress(
  File source,
  File destination, {
  void Function(int copied, int total)? onProgress,
  Duration throttle = const Duration(milliseconds: 100),
  CancelToken? cancelToken,
}) async {
  final int total = await source.length();
  await destination.parent.create(recursive: true);

  int copied = 0;
  Stopwatch? sinceUpdate;

  final sink = destination.openWrite();
  bool cancelled = false;
  Object? failure;
  try {
    await sink.addStream(
      source.openRead().map((chunk) {
        if (cancelToken?.isCancelled ?? false) {
          // Aborts the read. addStream replaces the error with a
          // FileSystemException on close, so the throw below is what the caller
          // actually sees; this one only stops the stream.
          cancelled = true;
          throw const CopyCancelled();
        }
        copied += chunk.length;
        if (onProgress == null) return chunk;
        final bool isLast = copied >= total;
        if (sinceUpdate == null) {
          // First chunk: report immediately so the UI does not sit at zero.
          sinceUpdate = Stopwatch()..start();
          onProgress(copied, total);
        } else if (isLast || sinceUpdate!.elapsed >= throttle) {
          sinceUpdate!.reset();
          onProgress(copied, total);
        }
        return chunk;
      }),
    );
  } catch (e) {
    failure = e;
  }
  // Closed here and nowhere else, and before anything is thrown, or the handle
  // would keep the part-written file locked.
  try {
    await sink.close();
  } catch (e) {
    failure ??= e;
  }

  // The part-written file is left for the caller: it chose the name, and with
  // claimFilePath it created the file before this was called.
  if (failure == null) return;
  throw cancelled ? const CopyCancelled() : failure;
}
