import 'package:flutter/material.dart';
import 'package:we_repkg/constants/nums.dart';

class CustomInput extends StatelessWidget {
  const CustomInput({
    super.key,
    this.width,
    this.height,
    required this.controller,
    this.padding,
    this.fontSize,
    required this.hintText,
    this.leading,
    this.suffix,
    this.readOnly = false,
    this.extraIcon,
  });

  final double? width;
  final double? height;
  final TextEditingController controller;
  final EdgeInsets? padding;
  final double? fontSize;
  final String hintText;
  final Widget? leading;
  final Widget? suffix;
  final bool readOnly;
  final Widget? extraIcon;

  @override
  Widget build(BuildContext context) {
    ThemeData theme = Theme.of(context);
    return Container(
      width: width,
      height: height ?? LayoutNums.controlHeight,
      padding: padding ?? EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        borderRadius: LayoutNums.pill,
        color: theme.inputDecorationTheme.fillColor,
      ),
      alignment: Alignment.center,
      child: Row(
        spacing: 4,
        children: [
          ?leading,
          Expanded(
            child: TextField(
              controller: controller,
              readOnly: readOnly,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontSize: fontSize ?? 14,
              ),
              decoration: InputDecoration(
                hintText: hintText,
                hintStyle: theme.inputDecorationTheme.hintStyle,
                border: const OutlineInputBorder(
                  borderRadius: LayoutNums.pill,
                  borderSide: BorderSide.none,
                ),
                isCollapsed: true,
              ),
            ),
          ),
          ?extraIcon,
          if (suffix != null) ...[suffix!, SizedBox.shrink()],
        ],
      ),
    );
  }
}
