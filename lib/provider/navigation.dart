import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:we_repkg/models/enums.dart';

part 'navigation.g.dart';

/// Which area the window is showing. Not persisted: a launch should land on the
/// wallpaper grid, not wherever the last session closed.
@Riverpod(keepAlive: true)
class CurrentSection extends _$CurrentSection {
  bool _extractEntrancePending = false;

  @override
  NavSection build() => NavSection.extract;

  void update(NavSection value) => state = value;

  /// The next Extract view to mount should replay its grid entrance. Separate
  /// from [state], since asking for a replay must not navigate anywhere.
  void requestExtractEntrance() => _extractEntrancePending = true;

  /// Read once, so an ordinary switch back does not replay it again.
  bool consumeExtractEntrance() {
    final bool pending = _extractEntrancePending;
    _extractEntrancePending = false;
    return pending;
  }
}
