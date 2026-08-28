part of 'file_tree_panel.dart';

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
  });

  final int depth;
  final IconData icon;
  final IconData? disclosure;
  final String label;
  final String? subtitle;
  final Widget? trailing;
  final Color foreground;
  final Color? iconColor;

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

    return Padding(
      padding: EdgeInsets.fromLTRB(8 + depth * 16.0, 3, 8, 3),
      child: Row(
        mainAxisSize: trailing == null ? MainAxisSize.min : MainAxisSize.max,
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
          if (trailing == null) labelWidget else Expanded(child: labelWidget),
          if (trailing != null) ...<Widget>[
            const SizedBox(width: 10),
            trailing!,
          ],
        ],
      ),
    );
  }
}
