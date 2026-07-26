import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Adds a short ease-out only to mouse-wheel scrolling.
///
/// Flutter routes wheel input through [ScrollPosition.pointerScroll], while
/// drags, scrollbars, keyboard actions, and programmatic scrolling use separate
/// paths. Customizing the position therefore keeps those interactions native.
class SmoothWheelScrollController extends ScrollController {
  SmoothWheelScrollController({
    super.initialScrollOffset,
    super.keepScrollOffset,
    super.debugLabel,
  });

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) {
    return _SmoothWheelScrollPosition(
      physics: physics,
      context: context,
      initialPixels: initialScrollOffset,
      keepScrollOffset: keepScrollOffset,
      oldPosition: oldPosition,
      debugLabel: debugLabel,
    );
  }
}

class _SmoothWheelScrollPosition extends ScrollPositionWithSingleContext {
  _SmoothWheelScrollPosition({
    required super.physics,
    required super.context,
    super.initialPixels,
    super.keepScrollOffset,
    super.oldPosition,
    super.debugLabel,
  });

  static const Duration _wheelDuration = Duration(milliseconds: 70);
  static const double _immediateFraction = .55;

  double? _wheelTarget;
  int _animationGeneration = 0;

  @override
  void pointerScroll(double delta) {
    if (delta == 0) {
      _animationGeneration++;
      _wheelTarget = null;
      super.pointerScroll(delta);
      return;
    }

    final double target = ((_wheelTarget ?? pixels) + delta)
        .clamp(minScrollExtent, maxScrollExtent)
        .toDouble();
    if (target == pixels && _wheelTarget == null) return;

    _wheelTarget = target;
    updateUserScrollDirection(
      delta < 0 ? ScrollDirection.forward : ScrollDirection.reverse,
    );
    final int generation = ++_animationGeneration;

    // Move most of the distance on the input frame so the wheel never feels
    // queued behind an animation. Only the small remainder is eased, which
    // preserves a smooth finish without adding input latency.
    final double immediateTarget =
        pixels + ((target - pixels) * _immediateFraction);
    super.pointerScroll(immediateTarget - pixels);

    unawaited(
      animateTo(
        target,
        duration: _wheelDuration,
        curve: Curves.easeOutCubic,
      ).whenComplete(() {
        // Starting a new animation completes the previous activity's future.
        // Only the newest one owns the accumulated destination.
        if (generation == _animationGeneration) {
          _wheelTarget = null;
        }
      }),
    );
  }
}
