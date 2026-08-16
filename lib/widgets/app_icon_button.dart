import 'package:flutter/material.dart';
import 'package:we_repkg/config/theme_extensions.dart';

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

/// Circular action surface using the app-wide action palette.
///
/// Use [AppActionIconButton.destructive] for deletion, recycling, or any other
/// operation the app already treats as destructive.
class AppActionIconButton extends StatelessWidget {
  const AppActionIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.width = 36,
    this.height = 36,
    this.iconSize = 20,
    this.tooltip,
  }) : destructive = false;

  const AppActionIconButton.destructive({
    super.key,
    required this.icon,
    this.onPressed,
    this.width = 36,
    this.height = 36,
    this.iconSize = 20,
    this.tooltip,
  }) : destructive = true;

  final IconData icon;
  final VoidCallback? onPressed;
  final double width;
  final double height;
  final double iconSize;
  final String? tooltip;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final ActionButtonTheme colors = Theme.of(context).actionButtons;
    final Color background = destructive
        ? colors.destructiveBackground
        : colors.primaryBackground;
    final Color foreground = destructive
        ? colors.destructiveForeground
        : colors.primaryForeground;
    final Color border = destructive
        ? colors.destructiveBorder
        : colors.primaryBorder;
    return Material(
      color: background,
      shape: CircleBorder(side: BorderSide(color: border)),
      child: AppIconButton(
        icon: icon,
        onPressed: onPressed,
        width: width,
        height: height,
        iconSize: iconSize,
        color: foreground,
        tooltip: tooltip,
      ),
    );
  }
}
