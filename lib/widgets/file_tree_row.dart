part of 'file_tree_panel.dart';

/// Selection click forwarded by a file-tree row after it reads desktop modifiers.
typedef FileTreeSelectionTap = void Function(bool control, bool shift);

/// One app-standard right-click action exposed by a file-tree row.
///
/// The generic tree owns menu presentation only. Callers decide which actions
/// make semantic sense for a concrete file, such as Compare.
class FileTreeContextAction {
  const FileTreeContextAction({
    required this.label,
    required this.onSelected,
    this.enabled = true,
    this.color,
  });

  final String label;
  final FutureOr<void> Function(BuildContext context) onSelected;
  final bool enabled;
  final Color? color;
}

/// Shared row styling for files and folders.
class FileTreeRow extends StatelessWidget {
  const FileTreeRow({
    super.key,
    required this.depth,
    required this.icon,
    required this.label,
    required this.foreground,
    this.disclosure,
    this.subtitle,
    this.trailing,
    this.iconColor,
    this.onTap,
    this.onSelectionTap,
    this.selected = false,
    this.tooltip,
    this.hoverHighlight = true,
    this.contextActions = const <FileTreeContextAction>[],
  }) : assert(onTap == null || onSelectionTap == null);

  final int depth;
  final IconData icon;
  final IconData? disclosure;
  final String label;
  final String? subtitle;
  final Widget? trailing;
  final Color foreground;
  final Color? iconColor;
  final VoidCallback? onTap;
  final FileTreeSelectionTap? onSelectionTap;
  final bool selected;
  final String? tooltip;
  final bool hoverHighlight;
  final List<FileTreeContextAction> contextActions;

  @override
  Widget build(BuildContext context) {
    final Color rowIcon = iconColor ?? foreground.withValues(alpha: .82);
    final Widget labelWidget = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          maxLines: 1,
          style: TextStyle(color: foreground, fontSize: 12),
        ),
        if (subtitle case final String text)
          Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: foreground.withValues(alpha: .65),
              fontSize: 11,
            ),
          ),
      ],
    );

    Widget surface = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SizedBox(
            width: 18,
            child: disclosure == null
                ? null
                : Icon(
                    disclosure,
                    size: 16,
                    color: foreground.withValues(alpha: .75),
                  ),
          ),
          Icon(icon, size: 16, color: rowIcon),
          const SizedBox(width: 6),
          if (trailing == null)
            labelWidget
          else
            Flexible(fit: FlexFit.loose, child: labelWidget),
          if (trailing != null) ...<Widget>[
            const SizedBox(width: 8),
            trailing!,
          ],
        ],
      ),
    );

    final FileTreeSelectionTap? selectionTap = onSelectionTap;
    final VoidCallback? effectiveTap = selectionTap == null
        ? onTap
        : () => selectionTap(isCtrlPressed, isShiftPressed);
    final GestureTapDownCallback? secondaryTap = contextActions.isEmpty
        ? null
        : (TapDownDetails details) {
            unawaited(
              showMenuAt(context, details, <RightMenuItem>[
                for (final FileTreeContextAction action in contextActions)
                  RightMenuItem(
                    label: action.label,
                    color: action.color,
                    enabled: action.enabled,
                    onSelected: (_) => action.onSelected(context),
                  ),
              ]),
            );
          };

    final bool showsHover =
        effectiveTap != null || secondaryTap != null || trailing != null;
    if (showsHover) {
      surface = _FileTreeRowInteractiveSurface(
        foreground: foreground,
        selected: selected,
        onTap: effectiveTap,
        onSecondaryTapDown: secondaryTap,
        hoverHighlight: hoverHighlight,
        child: surface,
      );
    } else if (selected) {
      surface = DecoratedBox(
        decoration: BoxDecoration(
          color: foreground.withValues(alpha: _fileTreeRowSelectedAlpha),
          borderRadius: BorderRadius.circular(_fileTreeRowInteractiveRadius),
        ),
        child: surface,
      );
    }

    Widget row = Padding(
      padding: EdgeInsets.only(left: 8 + depth * 16.0, right: 4),
      child: surface,
    );
    if (selectionTap != null) {
      row = Semantics(selected: selected, child: row);
    }
    return tooltip == null
        ? row
        : FileTreeTooltip(message: tooltip!, child: row);
  }
}

class _FileTreeRowInteractiveSurface extends StatefulWidget {
  const _FileTreeRowInteractiveSurface({
    required this.foreground,
    required this.selected,
    required this.onTap,
    required this.onSecondaryTapDown,
    required this.hoverHighlight,
    required this.child,
  });

  final Color foreground;
  final bool selected;
  final VoidCallback? onTap;
  final GestureTapDownCallback? onSecondaryTapDown;
  final bool hoverHighlight;
  final Widget child;

  @override
  State<_FileTreeRowInteractiveSurface> createState() =>
      _FileTreeRowInteractiveSurfaceState();
}

class _FileTreeRowInteractiveSurfaceState
    extends State<_FileTreeRowInteractiveSurface>
    with SingleTickerProviderStateMixin {
  final FocusNode _focusNode = FocusNode(debugLabel: 'File tree row');
  late final AnimationController _hover = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 80),
    reverseDuration: const Duration(milliseconds: 80),
  );
  bool _hovered = false;
  bool _focused = false;

  void _updateHighlight() {
    if (_hovered || _focused) {
      _hover.forward();
    } else {
      _hover.reverse();
    }
  }

  void _handleHover(bool hovered) {
    _hovered = hovered;
    _updateHighlight();
  }

  void _handleFocus(bool focused) {
    _focused = focused;
    _updateHighlight();
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _hover.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final VoidCallback? onTap = widget.onTap;
    final GestureTapDownCallback? onSecondaryTapDown =
        widget.onSecondaryTapDown;

    // Pointer movement is paint-only. Keep Material's hover-aware controls out
    // of this wrapper: even a transparent InkWell updates its internal hover
    // state and can make Windows publish a new AX relationship for the row.
    // GestureDetector retains pointer and semantics actions without reacting to
    // hover, while the controller only asks the background painter for a frame.
    Widget child = widget.child;
    if (onTap != null || onSecondaryTapDown != null) {
      final VoidCallback? activate = onTap == null
          ? null
          : () {
              _focusNode.requestFocus();
              onTap();
            };
      child = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: activate,
        onSecondaryTapDown: onSecondaryTapDown,
        excludeFromSemantics: onTap == null,
        child: child,
      );
      if (activate != null) {
        child = Shortcuts(
          shortcuts: const <ShortcutActivator, Intent>{
            SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
            SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
          },
          child: Actions(
            actions: <Type, Action<Intent>>{
              ActivateIntent: CallbackAction<ActivateIntent>(
                onInvoke: (_) {
                  activate();
                  return null;
                },
              ),
            },
            child: Focus(
              focusNode: _focusNode,
              onFocusChange: _handleFocus,
              child: child,
            ),
          ),
        );
      }
    }

    final Widget painted = CustomPaint(
      painter: _FileTreeRowBackgroundPainter(
        foreground: widget.foreground,
        selected: widget.selected,
        hover: _hover,
      ),
      child: child,
    );
    if (!widget.hoverHighlight) {
      // Inspected package trees are inserted into an already-live Windows AX
      // subtree. Avoid publishing another frame merely because the pointer
      // crossed a filename; focus and selection painting still work normally.
      return onTap == null
          ? painted
          : MouseRegion(cursor: SystemMouseCursors.click, child: painted);
    }
    return MouseRegion(
      cursor: onTap == null ? MouseCursor.defer : SystemMouseCursors.click,
      onEnter: (_) => _handleHover(true),
      onExit: (_) => _handleHover(false),
      child: painted,
    );
  }
}

class _FileTreeRowBackgroundPainter extends CustomPainter {
  _FileTreeRowBackgroundPainter({
    required this.foreground,
    required this.selected,
    required this.hover,
  }) : super(repaint: hover);

  final Color foreground;
  final bool selected;
  final Animation<double> hover;

  @override
  void paint(Canvas canvas, Size size) {
    final double alpha = selected
        ? _fileTreeRowSelectedAlpha
        : _fileTreeRowHoverAlpha * Curves.easeOut.transform(hover.value);
    if (alpha <= 0 || size.isEmpty) return;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Offset.zero & size,
        const Radius.circular(_fileTreeRowInteractiveRadius),
      ),
      Paint()..color = foreground.withValues(alpha: alpha),
    );
  }

  @override
  bool shouldRepaint(covariant _FileTreeRowBackgroundPainter oldDelegate) =>
      oldDelegate.foreground != foreground || oldDelegate.selected != selected;
}
