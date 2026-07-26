import 'package:flutter/material.dart';
import 'package:we_repkg/config/custom_theme.dart';

class CustomBtn extends StatelessWidget {
  const CustomBtn({super.key, required this.label, this.onPressed})
    : _variant = _CustomBtnVariant.primary;

  const CustomBtn.destructive({super.key, required this.label, this.onPressed})
    : _variant = _CustomBtnVariant.destructive;

  final String label;
  final VoidCallback? onPressed;
  final _CustomBtnVariant _variant;

  @override
  Widget build(BuildContext context) {
    final ActionButtonTheme colors = Theme.of(context).actionButtons;
    final (
      Color background,
      Color foreground,
      Color border,
    ) = switch (_variant) {
      _CustomBtnVariant.primary => (
        colors.primaryBackground,
        colors.primaryForeground,
        colors.primaryBorder,
      ),
      _CustomBtnVariant.destructive => (
        colors.destructiveBackground,
        colors.destructiveForeground,
        colors.destructiveBorder,
      ),
    };

    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: background,
        foregroundColor: foreground,
        disabledBackgroundColor: background.withValues(alpha: .5),
        disabledForegroundColor: foreground.withValues(alpha: .5),
        elevation: 0,
        side: BorderSide(color: border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        enabledMouseCursor: SystemMouseCursors.click,
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 14, fontFamily: 'Microsoft YaHei'),
      ),
    );
  }
}

enum _CustomBtnVariant { primary, destructive }
