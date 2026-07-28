import 'dart:io';

/// Streams [source] into [destination], reporting progress at most once per
/// [throttle], and always once at the end.
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
}) async {
  final int total = await source.length();
  await destination.parent.create(recursive: true);

  int copied = 0;
  Stopwatch? sinceUpdate;

  final sink = destination.openWrite();
  try {
    await sink.addStream(
      source.openRead().map((chunk) {
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
  } finally {
    // Closed here and nowhere else.
    await sink.close();
  }
}
