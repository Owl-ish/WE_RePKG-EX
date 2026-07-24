/// Runs [work] over [items] with at most [concurrency] in flight, returning the
/// results in input order.
///
/// Extraction used to await one wallpaper at a time, so a batch used a single
/// core while the other seven idled. This keeps a fixed number of workers busy
/// instead.
///
/// [onStart] fires as a worker picks an item up, and [onComplete] as it finishes
/// one, which is what progress reporting hangs off. Because several items are in
/// flight, completions arrive out of order: count them, do not treat them as a
/// cursor into [items].
///
/// A throw from [work] propagates once the other in-flight workers settle, so
/// one bad item cannot leave orphaned futures running. Callers that must finish
/// the whole batch regardless should return errors rather than throwing, which
/// is what the extract functions do.
Future<List<R>> runBounded<T, R>(
  List<T> items,
  Future<R> Function(T item) work, {
  int concurrency = 4,
  void Function(T item)? onStart,
  void Function(T item)? onComplete,
}) async {
  if (items.isEmpty) return <R>[];

  int workers = concurrency < 1 ? 1 : concurrency;
  if (workers > items.length) workers = items.length;

  final List<R?> results = List<R?>.filled(items.length, null);
  int next = 0;

  Future<void> runWorker() async {
    while (true) {
      // Dart runs this synchronously between awaits, so the claim needs no lock.
      final int index = next;
      if (index >= items.length) return;
      next = index + 1;

      final T item = items[index];
      onStart?.call(item);
      results[index] = await work(item);
      onComplete?.call(item);
    }
  }

  await Future.wait([for (int i = 0; i < workers; i++) runWorker()]);
  return results.cast<R>();
}
