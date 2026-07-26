import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

enum ScrollEdge { top, bottom }

/// One endpoint control for a long scrollable.
///
/// This widget alone listens to [controller], so changing scroll position does
/// not rebuild the grid or list that the controller belongs to.
class ScrollEdgeButton extends StatefulWidget {
  const ScrollEdgeButton({
    super.key,
    required this.controller,
    required this.active,
    required this.edge,
    required this.tooltip,
  });

  static const Key topButtonKey = ValueKey<String>('scroll-to-top');
  static const Key bottomButtonKey = ValueKey<String>('scroll-to-bottom');

  final ScrollController controller;
  final ValueListenable<bool> active;
  final ScrollEdge edge;
  final String tooltip;

  @override
  State<ScrollEdgeButton> createState() => _ScrollEdgeButtonState();
}

class _ScrollEdgeButtonState extends State<ScrollEdgeButton> {
  static const double _edgeTolerance = .5;
  static const Duration _fadeDuration = Duration(milliseconds: 180);

  bool _visible = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_sync);
    _syncAfterLayout();
  }

  @override
  void didUpdateWidget(ScrollEdgeButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      oldWidget.controller.removeListener(_sync);
      widget.controller.addListener(_sync);
    }
    _syncAfterLayout();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_sync);
    super.dispose();
  }

  void _syncAfterLayout() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _sync();
    });
  }

  void _sync() {
    bool visible = false;
    if (widget.controller.hasClients) {
      final ScrollPosition position = widget.controller.position;
      if (position.hasContentDimensions) {
        visible = switch (widget.edge) {
          ScrollEdge.top =>
            position.pixels > position.minScrollExtent + _edgeTolerance,
          ScrollEdge.bottom =>
            position.pixels < position.maxScrollExtent - _edgeTolerance,
        };
      }
    }
    if (visible == _visible) return;
    setState(() => _visible = visible);
  }

  void _jumpToEdge() {
    if (!widget.controller.hasClients) return;
    final ScrollPosition position = widget.controller.position;
    widget.controller.jumpTo(
      widget.edge == ScrollEdge.top
          ? position.minScrollExtent
          : position.maxScrollExtent,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: widget.active,
      builder: (context, active, _) {
        final bool showButton = active && _visible;

        final ThemeData theme = Theme.of(context);
        final Color foreground = theme.colorScheme.onSurface.withValues(
          alpha: .68,
        );
        return IgnorePointer(
          ignoring: !showButton,
          child: ExcludeSemantics(
            excluding: !showButton,
            child: AnimatedSwitcher(
              duration: _fadeDuration,
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeOut,
              child: showButton
                  ? Material(
                      key: const ValueKey<String>('scroll-edge-visible'),
                      elevation: 1,
                      color: theme.colorScheme.surface.withValues(alpha: .64),
                      shape: CircleBorder(
                        side: BorderSide(
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: .10,
                          ),
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: IconButton(
                        key: widget.edge == ScrollEdge.top
                            ? ScrollEdgeButton.topButtonKey
                            : ScrollEdgeButton.bottomButtonKey,
                        onPressed: _jumpToEdge,
                        icon: Icon(
                          widget.edge == ScrollEdge.top
                              ? Icons.keyboard_arrow_up_rounded
                              : Icons.keyboard_arrow_down_rounded,
                          size: 26,
                        ),
                        tooltip: widget.tooltip,
                        style: IconButton.styleFrom(
                          foregroundColor: foreground,
                          hoverColor: theme.colorScheme.primary.withValues(
                            alpha: .10,
                          ),
                          highlightColor: theme.colorScheme.primary.withValues(
                            alpha: .14,
                          ),
                        ),
                        constraints: const BoxConstraints.tightFor(
                          width: 44,
                          height: 44,
                        ),
                        padding: EdgeInsets.zero,
                      ),
                    )
                  : const SizedBox.shrink(
                      key: ValueKey<String>('scroll-edge-hidden'),
                    ),
            ),
          ),
        );
      },
    );
  }
}
