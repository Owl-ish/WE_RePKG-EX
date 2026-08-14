import 'package:flutter/material.dart';

/// A rounded bar that eases to each new value.
///
/// Tweened rather than set: both callers move in steps, a batch of folders or a
/// finished wallpaper at a time, and the jump reads as a stutter.
class ProgressBar extends StatelessWidget {
  const ProgressBar({
    super.key,
    required this.value,
    this.colour,
    this.step = const Duration(milliseconds: 500),
  });

  /// How far along, from 0 to 1. Null draws the bar's own sweep instead.
  final double? value;

  final Color? colour;

  /// How long one move takes. A caller reporting many times a second wants this
  /// short, or the bar never catches up and trails the count it sits under.
  final Duration step;

  static const double _height = 8;

  @override
  Widget build(BuildContext context) {
    final double? end = value;
    return ClipRRect(
      borderRadius: BorderRadius.circular(_height / 2),
      child: end == null
          ? LinearProgressIndicator(minHeight: _height, color: colour)
          : TweenAnimationBuilder<double>(
              tween: Tween<double>(end: end),
              duration: step,
              curve: Curves.easeInOut,
              builder: (BuildContext context, double shown, _) =>
                  LinearProgressIndicator(
                    value: shown,
                    minHeight: _height,
                    color: colour,
                  ),
            ),
    );
  }
}
