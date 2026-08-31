import 'package:flutter/foundation.dart';
import 'package:we_repkg/cores/backup.dart';

/// Tracks the user's per-file choices for one detailed Update.
///
/// The full mirror plan is the default. Only opt-outs are stored, so a partial
/// Update can preserve selected backup files without changing bulk Update.
/// Package-child overrides are also tracked so unsupported repacking can block
/// whole-package replacement instead of silently discarding those choices.
class BackupUpdateSelection extends ChangeNotifier {
  BackupUpdateSelection(this.changes);

  final Future<BackupFileChanges?> changes;
  final Set<String> _skippedCopies = <String>{};
  final Set<String> _keptBackupFiles = <String>{};
  final Map<String, Set<String>> _packageOverrides = <String, Set<String>>{};

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

  bool packageChangeSelected(
    String packagePath,
    String filePath, {
    required bool deletion,
  }) {
    final String choice = '${deletion ? 'delete' : 'copy'}:${_key(filePath)}';
    final Set<String>? overrides = _packageOverrides[_key(packagePath)];
    return overrides == null || !overrides.contains(choice);
  }

  void setPackageChangeSelected(
    String packagePath,
    String filePath,
    bool selected, {
    required bool deletion,
  }) {
    final String packageKey = _key(packagePath);
    final Set<String> overrides = _packageOverrides.putIfAbsent(
      packageKey,
      () => <String>{},
    );
    final String choice = '${deletion ? 'delete' : 'copy'}:${_key(filePath)}';
    final bool changed = selected
        ? overrides.remove(choice)
        : overrides.add(choice);
    if (changed) notifyListeners();
  }

  bool? packageGroupSelected(
    String packagePath,
    Iterable<String> filePaths, {
    required bool deletion,
  }) => _groupState(
    filePaths.map(
      (String filePath) =>
          packageChangeSelected(packagePath, filePath, deletion: deletion),
    ),
  );

  void setPackageGroupSelected(
    String packagePath,
    Iterable<String> filePaths,
    bool selected, {
    required bool deletion,
  }) {
    final String packageKey = _key(packagePath);
    final Set<String> overrides = _packageOverrides.putIfAbsent(
      packageKey,
      () => <String>{},
    );
    bool changed = false;
    for (final String filePath in filePaths) {
      final String choice = '${deletion ? 'delete' : 'copy'}:${_key(filePath)}';
      changed |= selected ? overrides.remove(choice) : overrides.add(choice);
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
    final Set<String> blockedPackages = <String>{
      for (final MapEntry<String, Set<String>> entry
          in _packageOverrides.entries)
        if (entry.value.isNotEmpty && copySelected(entry.key)) entry.key,
    };
    return BackupSelectiveUpdatePlan(
      expectedChanges: expected,
      skippedCopies: Set<String>.unmodifiable(_skippedCopies),
      keptBackupFiles: Set<String>.unmodifiable(_keptBackupFiles),
      blockedPackages: blockedPackages,
    );
  }
}
