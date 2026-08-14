import 'package:clock/clock.dart';
import 'package:flutter/gestures.dart';

/// Tells the second click of a double click from two separate clicks on a tile.
///
/// Both clicks reach a `Listener`, which never loses to the double tap
/// recogniser, so acting on both selects on the way down and deselects on the
/// way back up. `clock`, not `DateTime.now`, or no test could tell the two
/// apart.
class DoubleClickGuard {
  String? _id;
  DateTime? _at;

  bool isSecondClick(String id) {
    final DateTime now = clock.now();
    final bool second =
        _id == id && _at != null && now.difference(_at!) < kDoubleTapTimeout;
    _id = id;
    _at = now;
    return second;
  }
}
