import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:we_repkg/models/enums.dart';

part 'navigation.g.dart';

/// Which top level area the window is showing.
///
/// Deliberately not persisted: a launch should land on the wallpaper grid,
/// which is what the app is for, rather than reopening on whatever page the
/// last session happened to close on.
@Riverpod(keepAlive: true)
class CurrentSection extends _$CurrentSection {
  bool _extractEntrancePending = false;

  @override
  NavSection build() => NavSection.extract;

  void update(NavSection value) => state = value;

  /// Remembers that the next mounted Extract view should replay its grid
  /// entrance. This is deliberately separate from [state]: requesting a visual
  /// replay must not navigate away from Settings while a new library is being
  /// scanned.
  void requestExtractEntrance() => _extractEntrancePending = true;

  /// Returns and clears the pending request so ordinary tab switches do not
  /// replay the animation repeatedly.
  bool consumeExtractEntrance() {
    final bool pending = _extractEntrancePending;
    _extractEntrancePending = false;
    return pending;
  }
}
