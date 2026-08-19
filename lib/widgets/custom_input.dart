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
    final ThemeData theme = Theme.of(context);
    return InputSurface(
      width: width,
      height: height ?? LayoutNums.controlHeight,
      padding: padding ?? const EdgeInsets.symmetric(horizontal: 12),
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

/// Shared pill-shaped surface for input-like controls.
class InputSurface extends StatelessWidget {
  const InputSurface({
    super.key,
    required this.child,
    this.width,
    this.height,
    this.padding,
  });

  final Widget child;
  final double? width;
  final double? height;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      width: width,
      height: height,
      constraints: height == null
          ? const BoxConstraints(minHeight: LayoutNums.controlHeight)
          : null,
      padding: padding ?? const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        borderRadius: LayoutNums.pill,
        color: theme.inputDecorationTheme.fillColor,
      ),
      alignment: Alignment.center,
      child: child,
    );
  }
}

/// Compact selectable path field with an always-visible horizontal scrollbar.
class ReadOnlyPathBox extends StatefulWidget {
  const ReadOnlyPathBox({super.key, required this.path});

  final String path;

  @override
  State<ReadOnlyPathBox> createState() => _ReadOnlyPathBoxState();
}

class _ReadOnlyPathBoxState extends State<ReadOnlyPathBox> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return InputSurface(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 9),
      child: Scrollbar(
        controller: _scrollController,
        thumbVisibility: true,
        interactive: true,
        scrollbarOrientation: ScrollbarOrientation.bottom,
        thickness: 2,
        radius: const Radius.circular(1),
        child: SingleChildScrollView(
          controller: _scrollController,
          scrollDirection: Axis.horizontal,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: SelectableText(
              widget.path,
              maxLines: 1,
              style: theme.textTheme.bodyMedium?.copyWith(fontSize: 12),
            ),
          ),
        ),
      ),
    );
  }
}
