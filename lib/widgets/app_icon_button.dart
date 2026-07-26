import 'package:flutter/material.dart';

/// The app's single accessible clickable-icon primitive.
///
/// Callers own geometry through [width] and [height]; this widget owns the
/// interaction, cursor, tooltip, padding, and themed icon color.
class AppIconButton extends StatelessWidget {
  const AppIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.width = 36,
    this.height = 36,
    this.iconSize = 20,
    this.color,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final double width;
  final double height;
  final double iconSize;
  final Color? color;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      padding: const EdgeInsets.all(4),
      constraints: BoxConstraints.tightFor(width: width, height: height),
      style: const ButtonStyle(tapTargetSize: MaterialTapTargetSize.shrinkWrap),
      icon: Icon(
        icon,
        color: color ?? Theme.of(context).iconTheme.color,
        size: iconSize,
      ),
    );
  }
}
