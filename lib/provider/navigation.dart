import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:we_repkg/models/enums.dart';

part 'navigation.g.dart';

/// Which area the window is showing. Not persisted: a launch should land on the
/// wallpaper grid, not wherever the last session closed.
@Riverpod(keepAlive: true)
class CurrentSection extends _$CurrentSection {
  final Set<NavSection> _entrancePending = <NavSection>{};

  @override
  NavSection build() => NavSection.extract;

  void update(NavSection value) {
    if (value != state) requestEntrance(value);
    state = value;
  }

  /// Marks a section so the next grid it shows replays its entrance. Kept
  /// separate from [state], since asking for a replay must not navigate.
  void requestEntrance(NavSection section) => _entrancePending.add(section);

  /// Read once by the section that is about to show its grid.
  bool consumeEntrance(NavSection section) => _entrancePending.remove(section);
}

/// Which tab the backup area is showing. Not persisted, for the same reason as
/// [CurrentSection].
@Riverpod(keepAlive: true)
class CurrentBackupTab extends _$CurrentBackupTab {
  final Set<BackupTab> _entrancePending = <BackupTab>{};

  @override
  BackupTab build() => BackupTab.backup;

  void update(BackupTab value) {
    if (value != state && value == BackupTab.backup) {
      _entrancePending.add(value);
    }
    state = value;
  }

  /// Read once when the Backup tab mounts after being selected from Integrity.
  bool consumeEntrance(BackupTab tab) => _entrancePending.remove(tab);
}
