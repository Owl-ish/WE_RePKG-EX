import 'package:flutter/foundation.dart';
import 'package:we_repkg/cores/backup.dart';

/// Owns the per-file choices for one open Update detail view.
///
/// Every change starts selected, matching the existing full Update. Only the
/// user's opt-outs are stored and later passed to the backup core.
class BackupUpdateSelection extends ChangeNotifier {
  BackupUpdateSelection(this.changes);

  final Future<BackupFileChanges?> changes;
  final Set<String> _skippedCopies = <String>{};
  final Set<String> _keptBackupFiles = <String>{};

  String _key(String value) => value.toLowerCase().replaceAll('/', r'\');

  bool copySelected(String filePath) =>
      !_skippedCopies.contains(_key(filePath));

  void setCopySelected(String filePath, bool selected) {
    final String key = _key(filePath);
    final bool changed = selected
        ? _skippedCopies.remove(key)
        : _skippedCopies.add(key);
    if (changed) notifyListeners();
  }

  bool? copyGroupSelected(Iterable<String> filePaths) =>
      _groupState(filePaths.map(copySelected));

  void setCopyGroupSelected(Iterable<String> filePaths, bool selected) {
    bool changed = false;
    for (final String filePath in filePaths) {
      final String key = _key(filePath);
      changed |= selected
          ? _skippedCopies.remove(key)
          : _skippedCopies.add(key);
    }
    if (changed) notifyListeners();
  }

  bool deletionSelected(String filePath) =>
      !_keptBackupFiles.contains(_key(filePath));

  void setDeletionSelected(String filePath, bool selected) {
    final String key = _key(filePath);
    final bool changed = selected
        ? _keptBackupFiles.remove(key)
        : _keptBackupFiles.add(key);
    if (changed) notifyListeners();
  }

  bool? deletionGroupSelected(Iterable<String> filePaths) =>
      _groupState(filePaths.map(deletionSelected));

  void setDeletionGroupSelected(Iterable<String> filePaths, bool selected) {
    bool changed = false;
    for (final String filePath in filePaths) {
      final String key = _key(filePath);
      changed |= selected
          ? _keptBackupFiles.remove(key)
          : _keptBackupFiles.add(key);
    }
    if (changed) notifyListeners();
  }

  bool? _groupState(Iterable<bool> values) {
    bool? state;
    for (final bool value in values) {
      state ??= value;
      if (state != value) return null;
    }
    return state;
  }

  Future<BackupSelectiveUpdatePlan?> buildPlan() async {
    final BackupFileChanges? expected = await changes;
    if (expected == null) return null;
    return BackupSelectiveUpdatePlan(
      expectedChanges: expected,
      skippedCopies: Set<String>.unmodifiable(_skippedCopies),
      keptBackupFiles: Set<String>.unmodifiable(_keptBackupFiles),
    );
  }
}
