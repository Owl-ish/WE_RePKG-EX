import 'dart:io';

/// Cooperative cancellation for a batch of work.
///
/// Workers check [isCancelled] between items, and child processes register
/// themselves so cancelling also kills the RePKG instance already running.
class CancelToken {
  bool _cancelled = false;
  final Set<Process> _processes = {};

  bool get isCancelled => _cancelled;

  /// Stops further work and kills anything already running.
  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    for (final process in _processes.toList()) {
      // Already exited is fine: kill returns false rather than throwing.
      process.kill();
    }
    _processes.clear();
  }

  /// Tracks [process] so [cancel] can kill it. Registering after cancellation
  /// kills it at once, closing the gap where a worker spawns just as the user
  /// cancels.
  void register(Process process) {
    if (_cancelled) {
      process.kill();
      return;
    }
    _processes.add(process);
  }

  void unregister(Process process) => _processes.remove(process);
}
