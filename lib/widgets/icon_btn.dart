import 'package:flutter/material.dart';

class IconBtn extends StatelessWidget {
  const IconBtn({
    super.key,
    this.icon,
    this.onPressed,
    this.size = 36,
    this.iconSize = 20,
    this.color,
    this.tooltip,
  });

  final IconData? icon;
  final VoidCallback? onPressed;

  /// Tap target. Defaults to 36 so the button still fits inside a 36px input
  /// (see FolderInput); the top bar passes a larger one.
  final double size;
  final double iconSize;

  /// Grey unless a caller wants the icon to signal state.
  final Color? color;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      padding: EdgeInsets.all(4),
      constraints: BoxConstraints(maxWidth: size, maxHeight: size),
      icon: Icon(icon, color: color ?? Colors.grey, size: iconSize),
    );
  }
}
