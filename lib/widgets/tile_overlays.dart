import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:we_repkg/constants/nums.dart';

/// How both grids mark a selected tile: the whole tile tinted and outlined,
/// with a decorative tick in the corner.
///
/// Goes straight into a tile's [Stack] and ignores pointers so the tile beneath
/// it owns every selection interaction.
class SelectionTint extends StatelessWidget {
  const SelectionTint({super.key});

  /// Marks the tint for a test, which has no text to find it by.
  static const Key tintKey = ValueKey<String>('tile-selected');

  static const double _tick = 20;

  @override
  Widget build(BuildContext context) {
    final Color colour = Theme.of(context).primaryColor;
    return Positioned.fill(
      key: tintKey,
      child: IgnorePointer(
        child: Stack(
          children: <Widget>[
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colour.withValues(alpha: .28),
                  border: Border.all(color: colour, width: 2),
                  borderRadius: BorderRadius.circular(LayoutNums.surfaceRadius),
                ),
              ),
            ),
            Positioned(
              top: 6,
              right: 6,
              child: Container(
                width: _tick,
                height: _tick,
                decoration: BoxDecoration(
                  color: colour,
                  shape: BoxShape.circle,
                  // Against a pale preview the disc alone can vanish.
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: Colors.black.withValues(alpha: .25),
                      blurRadius: 4,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.check_rounded,
                  size: 14,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class TileBadgeData {
  const TileBadgeData({required this.text, required this.colour});

  final String text;
  final Color colour;
}

/// Fits multiple tile badges into one row without sacrificing short labels first.
///
/// Long badges are compressed toward a scrolling minimum; text only auto-scrolls
/// when its badge still cannot show the full label.
class TileBadgeStrip extends StatelessWidget {
  const TileBadgeStrip({super.key, required this.badges});

  final List<TileBadgeData> badges;

  static const double _spacing = 4;
  static const double _staticWidthLimit = 76;
  static const double _scrollingMinWidth = 44;

  @override
  Widget build(BuildContext context) {
    if (badges.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final List<double> natural = <double>[
          for (final TileBadgeData badge in badges)
            _TileBadge.measureWidth(context, badge.text),
        ];
        final List<double> widths = List<double>.from(natural);
        if (constraints.maxWidth.isFinite) {
          final double available = math.max(
            0,
            constraints.maxWidth - _spacing * (badges.length - 1),
          );
          double excess = widths.fold<double>(0, (a, b) => a + b) - available;
          if (excess > 0) {
            // Preserve short badges at natural width; compress labels with room
            // to scroll before taking space from compact badges.
            final List<double> minimums = <double>[
              for (final double width in natural)
                width <= _staticWidthLimit
                    ? width
                    : math.min(width, _scrollingMinWidth),
            ];
            final List<int> order = List<int>.generate(widths.length, (i) => i)
              ..sort(
                (int a, int b) => (widths[b] - minimums[b]).compareTo(
                  widths[a] - minimums[a],
                ),
              );
            for (final int i in order) {
              if (excess <= 0) break;
              final double capacity = widths[i] - minimums[i];
              final double take = math.min(capacity, excess);
              widths[i] -= take;
              excess -= take;
            }
            // If the preferred minimums still do not fit, share the remaining
            // width proportionally rather than overflowing the tile.
            if (excess > .5 && widths.isNotEmpty) {
              final double total = widths.fold<double>(0, (a, b) => a + b);
              if (total > 0) {
                final double scale = math.max(0, available / total);
                for (int i = 0; i < widths.length; i++) {
                  widths[i] *= scale;
                }
              }
            }
          }
        }
        return Row(
          spacing: _spacing,
          children: <Widget>[
            for (int i = 0; i < badges.length; i++)
              SizedBox(
                width: widths[i],
                child: _TileBadge(data: badges[i], naturalWidth: natural[i]),
              ),
          ],
        );
      },
    );
  }
}

class _TileBadge extends StatelessWidget {
  const _TileBadge({required this.data, required this.naturalWidth});

  final TileBadgeData data;
  final double naturalWidth;

  static const TextStyle _style = TextStyle(
    color: Colors.white,
    fontSize: 11,
    fontFamily: 'Microsoft YaHei',
  );

  static double measureWidth(BuildContext context, String text) {
    final TextPainter painter = TextPainter(
      text: TextSpan(text: text, style: _style),
      maxLines: 1,
      textDirection: Directionality.of(context),
    )..layout();
    return painter.width + 12;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: data.colour,
        borderRadius: BorderRadius.circular(4),
      ),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final double viewport = math.max(0, constraints.maxWidth);
          final double textWidth = math.max(0, naturalWidth - 12);
          if (textWidth <= viewport + .5) {
            return Text(
              data.text,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.visible,
              style: _style,
            );
          }
          return _AutoScrollText(
            text: data.text,
            style: _style,
            viewportWidth: viewport,
            textWidth: textWidth,
          );
        },
      ),
    );
  }
}

/// Scrolls an overlong badge label back and forth with pauses at both edges.
class _AutoScrollText extends StatefulWidget {
  const _AutoScrollText({
    required this.text,
    required this.style,
    required this.viewportWidth,
    required this.textWidth,
  });

  final String text;
  final TextStyle style;
  final double viewportWidth;
  final double textWidth;

  @override
  State<_AutoScrollText> createState() => _AutoScrollTextState();
}

class _AutoScrollTextState extends State<_AutoScrollText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 5),
  );
  late final Animation<double> _position =
      TweenSequence<double>(<TweenSequenceItem<double>>[
        TweenSequenceItem<double>(tween: ConstantTween<double>(0), weight: 18),
        TweenSequenceItem<double>(
          tween: Tween<double>(begin: 0, end: 1),
          weight: 32,
        ),
        TweenSequenceItem<double>(tween: ConstantTween<double>(1), weight: 18),
        TweenSequenceItem<double>(
          tween: Tween<double>(begin: 1, end: 0),
          weight: 32,
        ),
      ]).animate(_controller);
  double _configuredOverflow = -1;

  void _configure(double overflow) {
    if ((_configuredOverflow - overflow).abs() < .5) return;
    _configuredOverflow = overflow;
    // Configure after layout so a width change does not mutate the animation
    // controller while this widget is building.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (overflow <= 0) {
        _controller
          ..stop()
          ..value = 0;
        return;
      }
      // More overflow gets more travel time so the label does not speed up.
      final int travel = math.max(2200, (overflow / 24 * 1000).round());
      _controller
        ..duration = Duration(milliseconds: travel + 1600)
        ..repeat();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double overflow = math.max(
      0,
      widget.textWidth - widget.viewportWidth,
    );
    final TextPainter painter = TextPainter(
      text: TextSpan(text: widget.text, style: widget.style),
      maxLines: 1,
      textDirection: Directionality.of(context),
    )..layout();
    final double lineHeight = painter.height;
    _configure(overflow);
    return ClipRect(
      child: SizedBox(
        width: widget.viewportWidth,
        height: lineHeight,
        child: AnimatedBuilder(
          animation: _position,
          builder: (BuildContext context, Widget? child) => OverflowBox(
            alignment: Alignment.centerLeft,
            minWidth: widget.textWidth,
            maxWidth: widget.textWidth,
            minHeight: lineHeight,
            maxHeight: lineHeight,
            child: Transform.translate(
              offset: Offset(-overflow * _position.value, 0),
              child: child,
            ),
          ),
          child: SizedBox(
            width: widget.textWidth,
            height: lineHeight,
            child: Text(
              widget.text,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.visible,
              style: widget.style,
            ),
          ),
        ),
      ),
    );
  }
}
