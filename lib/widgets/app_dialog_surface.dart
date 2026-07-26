import 'package:flutter/material.dart';

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

  static const double radius = 8;
  static const double elevation = 16;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return UnconstrainedBox(
      child: Material(
        elevation: elevation,
        borderRadius: BorderRadius.circular(radius),
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
