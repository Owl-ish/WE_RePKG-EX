// Shared editable and read-only input-shaped controls.
//
// Provides the app's common input surface plus compact path displays. Path
// actions are opt-in so ordinary read-only fields do not gain filesystem
// behavior simply by reusing the same visual treatment.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:we_repkg/constants/nums.dart';

/// Standard editable/read-only text input built on the shared pill surface.
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
    this.border,
  });

  final Widget child;
  final double? width;
  final double? height;
  final EdgeInsets? padding;
  final BorderSide? border;

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
        border: border == null ? null : Border.fromBorderSide(border!),
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

/// Read-only path surface with opt-in actions.
///
/// Callers choose the capabilities they need. Plain path displays elsewhere
/// remain lightweight, while temporary/work folders can expose copy/open.
class PathActionBox extends StatelessWidget {
  const PathActionBox({
    super.key,
    required this.path,
    required this.copyTooltip,
    this.openTooltip,
    this.onOpen,
    this.foreground,
    this.compact = false,
  });

  final String path;
  final String copyTooltip;
  final String? openTooltip;
  final FutureOr<void> Function()? onOpen;
  final Color? foreground;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color resolvedForeground = foreground ?? theme.colorScheme.onSurface;
    final bool tooltipsAvailable =
        TooltipVisibility.of(context) && Overlay.maybeOf(context) != null;
    final double minHeight = compact ? 32 : 42;
    final double actionSize = compact ? 24 : 30;
    final double iconSize = compact ? 14 : 17;
    final double actionIconSize = compact ? 14 : 16;
    final double fontSize = compact ? 11 : 12;
    final EdgeInsets padding = compact
        ? const EdgeInsets.only(left: 8, right: 2, top: 2, bottom: 2)
        : const EdgeInsets.only(left: 10, right: 3, top: 3, bottom: 3);
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool bounded = constraints.hasBoundedWidth;
        final Widget pathText = SelectableText(
          path,
          maxLines: 1,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: resolvedForeground,
            fontFamily: 'Consolas',
            fontSize: fontSize,
          ),
        );
        return Container(
          width: bounded ? double.infinity : null,
          constraints: BoxConstraints(minHeight: minHeight),
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: theme.dividerColor.withValues(alpha: .48),
            ),
            color: theme.colorScheme.surfaceContainerHighest.withValues(
              alpha: .58,
            ),
          ),
          child: Row(
            mainAxisSize: bounded ? MainAxisSize.max : MainAxisSize.min,
            children: <Widget>[
              Icon(
                Icons.folder_outlined,
                size: iconSize,
                color: resolvedForeground.withValues(alpha: .62),
              ),
              SizedBox(width: compact ? 6 : 7),
              if (bounded)
                Expanded(child: pathText)
              else
                Flexible(fit: FlexFit.loose, child: pathText),
              IconButton(
                tooltip: tooltipsAvailable ? copyTooltip : null,
                onPressed: () => Clipboard.setData(ClipboardData(text: path)),
                icon: Icon(
                  Icons.copy_rounded,
                  semanticLabel: tooltipsAvailable ? null : copyTooltip,
                  size: actionIconSize,
                  color: resolvedForeground.withValues(alpha: .72),
                ),
                visualDensity: VisualDensity.compact,
                constraints: BoxConstraints.tightFor(
                  width: actionSize,
                  height: actionSize,
                ),
                padding: EdgeInsets.zero,
              ),
              if (onOpen != null)
                IconButton(
                  tooltip: tooltipsAvailable ? openTooltip : null,
                  onPressed: () => onOpen!(),
                  icon: Icon(
                    Icons.folder_open_rounded,
                    semanticLabel: tooltipsAvailable ? null : openTooltip,
                    size: actionIconSize,
                    color: resolvedForeground.withValues(alpha: .72),
                  ),
                  visualDensity: VisualDensity.compact,
                  constraints: BoxConstraints.tightFor(
                    width: actionSize,
                    height: actionSize,
                  ),
                  padding: EdgeInsets.zero,
                ),
            ],
          ),
        );
      },
    );
  }
}
