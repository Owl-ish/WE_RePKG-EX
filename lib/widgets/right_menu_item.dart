import 'package:flutter/material.dart';
import 'package:flutter_context_menu/flutter_context_menu.dart';
import 'package:we_repkg/constants/nums.dart';

final class RightMenuItem extends ContextMenuItem {
  final String label;
  final Color? color;

  const RightMenuItem({
    required this.label,
    this.color,
    super.value,
    super.onSelected,
    super.enabled,
  });

  const RightMenuItem.submenu({
    required this.label,
    this.color,
    required List<ContextMenuEntry> items,
    super.onSelected,
    super.enabled,
  }) : super.submenu(items: items);

  @override
  Widget builder(
    BuildContext context,
    ContextMenuState menuState, [
    FocusNode? focusNode,
  ]) {
    final ThemeData theme = Theme.of(context);
    bool isFocused = menuState.focusedEntry == this;
    final Color focusedBackground = Colors.grey.withValues(alpha: 0.2);
    final TextStyle textStyle = TextStyle(
      color: color ?? theme.textTheme.labelMedium?.color,
      height: 1.0,
      fontSize: 14.0,
      fontFamily: 'Microsoft YaHei',
    );

    // The menu panel owns the visible surface. Rows stay transparent until
    // focused, avoiding a rounded control nested inside another rounded box.
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 36.0, minWidth: 120.0),
      child: Material(
        color: enabled && isFocused ? focusedBackground : Colors.transparent,
        borderRadius: BorderRadius.circular(LayoutNums.controlRadius),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          borderRadius: BorderRadius.circular(LayoutNums.controlRadius),
          onTap: !enabled ? null : () => handleItemSelection(context),
          mouseCursor: SystemMouseCursors.click,
          canRequestFocus: false,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            alignment: Alignment.center,
            child: Text(
              label,
              maxLines: 1,
              style: textStyle,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ),
    );
  }
}
