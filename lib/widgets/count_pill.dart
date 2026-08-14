import 'dart:math';

import 'package:flutter/material.dart';
import 'package:we_repkg/constants/nums.dart';

/// The row of pills across the top of a tab, wrapping in a narrow window.
class PillRow extends StatelessWidget {
  const PillRow({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: LayoutNums.smallGap,
    runSpacing: LayoutNums.compactGap,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: children,
  );
}

/// A count that shows what it holds when picked, and hides it when another pill
/// is.
///
/// Glows in its own colour while it holds something and is switched off: what
/// nobody is looking at is what to come back to. Dimmed and unclickable at zero,
/// including while it is the one picked, so a pill that would show an empty grid
/// cannot be mistaken for a live control.
class CountPill extends StatefulWidget {
  const CountPill({
    super.key,
    required this.colour,
    required this.label,
    required this.count,
    required this.on,
    required this.onPressed,
    this.nags = true,
  });

  final Color colour;
  final String label;
  final int count;
  final bool on;
  final VoidCallback onPressed;

  /// Whether this pill is worth coming back to at all.
  final bool nags;

  @override
  State<CountPill> createState() => _CountPillState();
}

class _CountPillState extends State<CountPill>
    with SingleTickerProviderStateMixin {
  /// A visible but unhurried pulse: inactive work should attract attention
  /// without making the label harder to read.
  static const Duration _period = Duration(milliseconds: 2200);
  static const double _idleFill = .07;
  static const double _selectedFill = .14;
  static const double _disabledFill = .05;
  static const double _pulse = .08;
  static const double _glowAlpha = .14;
  static const double _glowBlur = 8;
  static const double _glowSpread = .5;
  static const double _selectedBorder = .55;
  static const double _idleBorder = .2;

  late final AnimationController _glow = AnimationController(
    vsync: this,
    duration: _period,
  );

  bool get _wanted => widget.nags && widget.count > 0 && !widget.on;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(CountPill old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    if (_wanted) {
      if (!_glow.isAnimating) _glow.repeat();
    } else if (_glow.isAnimating) {
      _glow.stop();
      _glow.value = 0;
    }
  }

  @override
  void dispose() {
    _glow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool live = widget.count > 0;
    final ThemeData theme = Theme.of(context);
    final Color tint = live ? widget.colour : theme.disabledColor;
    final double baseFill = !live
        ? _disabledFill
        : widget.on
        ? _selectedFill
        : _idleFill;
    return AnimatedBuilder(
      animation: _glow,
      builder: (BuildContext context, Widget? child) {
        // Cosine, so it swells and fades rather than snapping at either end.
        final double pulse = (1 - cos(_glow.value * 2 * pi)) / 2;
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: LayoutNums.pill,
            boxShadow: _wanted
                ? <BoxShadow>[
                    BoxShadow(
                      color: tint.withValues(alpha: _glowAlpha * pulse),
                      blurRadius: _glowBlur * pulse,
                      spreadRadius: _glowSpread * pulse,
                    ),
                  ]
                : const <BoxShadow>[],
          ),
          child: Material(
            color: tint.withValues(alpha: baseFill + _pulse * pulse),
            borderRadius: LayoutNums.pill,
            child: child,
          ),
        );
      },
      child: InkWell(
        borderRadius: LayoutNums.pill,
        mouseCursor: live ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onTap: live ? widget.onPressed : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            borderRadius: LayoutNums.pill,
            border: Border.all(
              color: tint.withValues(
                alpha: widget.on && live ? _selectedBorder : _idleBorder,
              ),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 6,
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: widget.on ? tint : Colors.transparent,
                  border: Border.all(color: tint, width: 1.5),
                  shape: BoxShape.circle,
                ),
              ),
              // Flexible, or a long label in a narrow window overflows its own
              // row rather than being cut short.
              Flexible(
                child: Text(
                  '${widget.label} ${widget.count}',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: live && widget.on ? null : tint),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
