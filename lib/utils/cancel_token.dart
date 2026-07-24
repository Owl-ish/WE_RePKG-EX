import 'dart:io';

/// Cooperative cancellation for a batch of work.
///
/// Two halves. Workers check [isCancelled] between items, so a cancelled batch
/// stops picking up new wallpapers. Long-running child processes register
/// themselves, so cancelling also kills the RePKG instance currently running
/// rather than waiting for it to finish on its own.
class CancelToken {
  bool _cancelled = false;
  final Set<Process> _processes = {};

  bool get isCancelled => _cancelled;

  /// Stops further work and kills anything already running.
  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    for (final process in _processes.toList()) {
      // The process may have exited between the snapshot and here; kill returns
      // false rather than throwing, so there is nothing to guard against.
      process.kill();
    }
    _processes.clear();
  }

  /// Tracks [process] so [cancel] can kill it. Registering after cancellation
  /// kills it immediately, which closes the gap where a worker spawns a process
  /// just as the user cancels.
  void register(Process process) {
    if (_cancelled) {
      process.kill();
      return;
    }
    _processes.add(process);
  }

  void unregister(Process process) => _processes.remove(process);
}
