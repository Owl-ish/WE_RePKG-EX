import 'package:clock/clock.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:we_repkg/utils/double_click.dart';

void main() {
  /// Runs [work] with the clock the guard reads under the test's control.
  T at<T>(DateTime now, T Function() work) => withClock(Clock.fixed(now), work);

  final DateTime start = DateTime(2026, 8, 11, 12);

  test('a lone click is not a second click', () {
    final DoubleClickGuard guard = DoubleClickGuard();

    expect(at(start, () => guard.isSecondClick('a')), isFalse);
  });

  // The one this exists for: acting on both clicks of a double click selects on
  // the way down and deselects on the way back up.
  test('the second click of a double click is caught', () {
    final DoubleClickGuard guard = DoubleClickGuard();

    at(start, () => guard.isSecondClick('a'));

    expect(
      at(start.add(kDoubleTapTimeout ~/ 2), () => guard.isSecondClick('a')),
      isTrue,
    );
  });

  test('two clicks far enough apart are two clicks', () {
    final DoubleClickGuard guard = DoubleClickGuard();

    at(start, () => guard.isSecondClick('a'));

    expect(
      at(start.add(kDoubleTapTimeout * 2), () => guard.isSecondClick('a')),
      isFalse,
    );
  });

  // Two tiles clicked in quick succession is an ordinary thing to do, and
  // neither click is part of a double click on the other.
  test('a quick click on another tile is its own click', () {
    final DoubleClickGuard guard = DoubleClickGuard();

    at(start, () => guard.isSecondClick('a'));

    expect(
      at(start.add(kDoubleTapTimeout ~/ 2), () => guard.isSecondClick('b')),
      isFalse,
    );
  });
}
