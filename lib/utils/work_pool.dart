import 'package:we_repkg/utils/cancel_token.dart';

/// Runs [work] over [items] with at most [concurrency] in flight, returning
/// results in input order.
///
/// Completions arrive out of order, so [onComplete] is a count, not a cursor
/// into [items]. A throw propagates once the other workers settle; callers that
/// must finish the batch return errors instead of throwing.
///
/// Cancelling stops workers claiming new items. Whatever is in flight finishes,
/// and entries never reached come back null.
Future<List<R?>> runBounded<T, R>(
  List<T> items,
  Future<R> Function(T item) work, {
  int concurrency = 4,
  void Function(T item)? onStart,
  void Function(T item)? onComplete,
  CancelToken? cancelToken,
}) async {
  if (items.isEmpty) return <R?>[];

  int workers = concurrency < 1 ? 1 : concurrency;
  if (workers > items.length) workers = items.length;

  final List<R?> results = List<R?>.filled(items.length, null);
  int next = 0;

  Future<void> runWorker() async {
    while (true) {
      if (cancelToken?.isCancelled ?? false) return;
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
  return results;
}
