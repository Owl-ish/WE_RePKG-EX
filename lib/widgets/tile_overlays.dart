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
/// Long badges are compressed toward a scrolling minimum. Overflowing text stays
/// still during ordinary grid movement and scrolls only while that badge is hovered.
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
        final measures = <({double width, double height})>[
          for (final TileBadgeData badge in badges)
            _TileBadge.measure(context, badge.text),
        ];
        final List<double> natural = <double>[
          for (final measure in measures) measure.width,
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
                child: _TileBadge(
                  data: badges[i],
                  naturalWidth: natural[i],
                  allocatedWidth: widths[i],
                  lineHeight: measures[i].height,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _TileBadge extends StatelessWidget {
  const _TileBadge({
    required this.data,
    required this.naturalWidth,
    required this.allocatedWidth,
    required this.lineHeight,
  });

  final TileBadgeData data;
  final double naturalWidth;
  final double allocatedWidth;
  final double lineHeight;

  static const double _backgroundMix = .60;
  static const TextStyle _style = TextStyle(
    color: Colors.white,
    fontSize: 11,
    fontFamily: 'Microsoft YaHei',
  );
  static final Map<
    (String, TextDirection, double, Locale?),
    ({double width, double height})
  >
  _measureCache =
      <
        (String, TextDirection, double, Locale?),
        ({double width, double height})
      >{};

  static ({double width, double height}) measure(
    BuildContext context,
    String text,
  ) {
    final TextDirection direction = Directionality.of(context);
    final TextScaler scaler = MediaQuery.textScalerOf(context);
    final Locale? locale = Localizations.maybeLocaleOf(context);
    final double scaledFontSize = scaler.scale(_style.fontSize!);
    return _measureCache.putIfAbsent(
      (text, direction, scaledFontSize, locale),
      () {
        final TextPainter painter = TextPainter(
          text: TextSpan(text: text, style: _style),
          maxLines: 1,
          textDirection: direction,
          textScaler: scaler,
          locale: locale,
        )..layout();
        return (width: painter.width + 12, height: painter.height);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final double viewport = math.max(0, allocatedWidth - 12);
    final double textWidth = math.max(0, naturalWidth - 12);
    final bool overflows = textWidth > viewport + .5;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          data.colour.withValues(alpha: _backgroundMix),
          Colors.black,
        ),
        borderRadius: BorderRadius.circular(4),
      ),
      child: overflows
          ? _HoverScrollText(
              text: data.text,
              style: _style,
              viewportWidth: viewport,
              textWidth: textWidth,
              lineHeight: lineHeight,
            )
          : Text(
              data.text,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.visible,
              style: _style,
            ),
    );
  }
}

/// Keeps an overflowing badge label still until the pointer asks to inspect it.
class _HoverScrollText extends StatefulWidget {
  const _HoverScrollText({
    required this.text,
    required this.style,
    required this.viewportWidth,
    required this.textWidth,
    required this.lineHeight,
  });

  final String text;
  final TextStyle style;
  final double viewportWidth;
  final double textWidth;
  final double lineHeight;

  @override
  State<_HoverScrollText> createState() => _HoverScrollTextState();
}

class _HoverScrollTextState extends State<_HoverScrollText>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;
  Animation<double>? _position;
  bool _hovered = false;

  void _start() {
    if (_hovered) return;
    _hovered = true;
    final double overflow = math.max(
      0,
      widget.textWidth - widget.viewportWidth,
    );
    if (overflow <= 0) return;

    final AnimationController controller = _controller ??= AnimationController(
      vsync: this,
    );
    _position ??= TweenSequence<double>(<TweenSequenceItem<double>>[
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
    ]).animate(controller);

    // More overflow gets more travel time so the label does not speed up.
    final int travel = math.max(2200, (overflow / 24 * 1000).round());
    controller
      ..duration = Duration(milliseconds: travel + 1600)
      ..repeat();
    setState(() {});
  }

  void _stop() {
    if (!_hovered) return;
    _hovered = false;
    _controller
      ?..stop()
      ..value = 0;
    setState(() {});
  }

  @override
  void didUpdateWidget(covariant _HoverScrollText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_hovered ||
        (oldWidget.viewportWidth - widget.viewportWidth).abs() < .5 &&
            (oldWidget.textWidth - widget.textWidth).abs() < .5) {
      return;
    }
    _controller
      ?..stop()
      ..value = 0;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _hovered = false;
      _start();
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Widget _label() => Text(
    widget.text,
    maxLines: 1,
    softWrap: false,
    overflow: TextOverflow.visible,
    style: widget.style,
  );

  Widget _positionedLabel(double left, Widget child) => Stack(
    clipBehavior: Clip.hardEdge,
    children: <Widget>[
      Positioned(
        left: left,
        top: 0,
        width: widget.textWidth,
        height: widget.lineHeight,
        child: Align(alignment: Alignment.centerLeft, child: child),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final double overflow = math.max(
      0,
      widget.textWidth - widget.viewportWidth,
    );
    final Animation<double>? position = _position;
    return Focus(
      onFocusChange: (bool focused) => focused ? _start() : _stop(),
      child: MouseRegion(
        onEnter: (_) => _start(),
        onExit: (_) => _stop(),
        child: SizedBox(
          width: widget.viewportWidth,
          height: widget.lineHeight,
          child: !_hovered || position == null
              ? _positionedLabel(0, _label())
              : AnimatedBuilder(
                  animation: position,
                  builder: (BuildContext context, Widget? child) =>
                      _positionedLabel(-overflow * position.value, child!),
                  child: _label(),
                ),
        ),
      ),
    );
  }
}
