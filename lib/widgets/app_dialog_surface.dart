import 'package:flutter/material.dart';
import 'package:we_repkg/constants/nums.dart';

/// Shared visual shell for the app's non-route modal surfaces.
///
/// Dialogs retain ownership of their width, padding, constraints, and content
/// layout; this widget owns only the common Material surface treatment.
class AppDialogSurface extends StatelessWidget {
  const AppDialogSurface({
    super.key,
    required this.width,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.maxHeight,
  });

  final double width;
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double? maxHeight;

  static const double elevation = 16;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return UnconstrainedBox(
      child: Material(
        elevation: elevation,
        borderRadius: BorderRadius.circular(LayoutNums.surfaceRadius),
        clipBehavior: Clip.antiAlias,
        color:
            theme.dialogTheme.backgroundColor ?? theme.scaffoldBackgroundColor,
        child: Container(
          width: width,
          constraints: BoxConstraints(maxHeight: maxHeight ?? double.infinity),
          padding: padding,
          child: child,
        ),
      ),
    );
  }
}

/// The icon and title shared by modal surfaces.
class AppDialogHeader extends StatelessWidget {
  const AppDialogHeader({
    super.key,
    required this.icon,
    required this.title,
    required this.foreground,
    required this.background,
  });

  final IconData icon;
  final String title;
  final Color foreground;
  final Color background;

  static const double _iconSize = 40;

  @override
  Widget build(BuildContext context) => Row(
    children: <Widget>[
      Container(
        width: _iconSize,
        height: _iconSize,
        decoration: BoxDecoration(color: background, shape: BoxShape.circle),
        child: Icon(icon, color: foreground, size: 21),
      ),
      const SizedBox(width: LayoutNums.mediumGap),
      Expanded(
        child: Text(title, style: Theme.of(context).textTheme.titleLarge),
      ),
    ],
  );
}
