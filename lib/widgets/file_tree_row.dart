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

    if (effectiveTap != null || secondaryTap != null || selected) {
      surface = Material(
        color: selected
            ? foreground.withValues(alpha: .12)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(7),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          borderRadius: BorderRadius.circular(7),
          hoverColor: foreground.withValues(alpha: .065),
          onTap: effectiveTap,
          onSecondaryTapDown: secondaryTap,
          child: surface,
        ),
      );
    }

    Widget row = Padding(
      padding: EdgeInsets.only(left: 8 + depth * 16.0, right: 4),
      child: surface,
    );
    if (selectionTap != null) {
      row = Semantics(selected: selected, child: row);
    }
    return tooltip == null ? row : Tooltip(message: tooltip!, child: row);
  }
}
