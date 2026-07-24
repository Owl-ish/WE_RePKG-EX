import 'dart:io';

/// Streams [source] into [destination], reporting progress at most once per
/// [throttle].
///
/// Two things this fixes over a hand-rolled `listen` + `sink.add` loop:
///
/// Backpressure. `IOSink.add` never blocks, so a fast read into a slower write
/// target buffers the difference in memory. Copying a multi-gigabyte wallpaper
/// video to a network drive or a slow USB stick could grow the heap by the
/// whole backlog. `addStream` pauses the read when the sink cannot keep up.
///
/// Progress cost. The read stream delivers roughly 64KB per chunk, so a 3GB
/// video fires about 50,000 progress events. Driving a provider write and a
/// widget rebuild from each one is most of the jank during a video export.
/// Throttling to ten updates a second keeps the counter smooth and costs
/// nothing.
///
/// [onProgress] always fires once for the final chunk, so callers never end on
/// a stale count.
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
    // Exactly one close, in one place. The previous version closed the sink in
    // both the stream's onDone and an enclosing finally.
    await sink.close();
  }
}
