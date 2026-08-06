import 'package:flutter/material.dart';
import 'package:we_repkg/constants/nums.dart';

/// The app's dropdown: a filled pill whose menu is the same width and whose
/// rows are the same height and shape, so opening it does not appear to resize
/// it and nothing inside it goes square.
///
/// Built on [MenuAnchor], like the filter panel, because the ink has to be
/// shaped twice over and neither of the simpler widgets lets it. `DropdownButton`
/// floors every row at the 48px touch target inside `DropdownMenuItem` itself,
/// and `PopupMenuButton` wraps the trigger in an `InkWell` whose radius it never
/// exposes, so both press and hover flashed a rectangle over the pill.
class PillDropdown<T> extends StatelessWidget {
  const PillDropdown({
    super.key,
    required this.value,
    required this.items,
    required this.labelOf,
    required this.onChanged,
  });

  final T value;
  final List<T> items;
  final String Function(T value) labelOf;
  final ValueChanged<T> onChanged;

  /// Wide enough for the longest label either dropdown carries in either
  /// language.
  static const double _width = 150;

  /// Inset of the rows from the panel's edge, so a pill row does not touch a
  /// rounded corner of the panel behind it.
  static const double _menuInset = 4;

  static const double _rowWidth = _width - _menuInset * 2;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final TextStyle? style = theme.textTheme.bodyMedium?.copyWith(fontSize: 13);

    return MenuAnchor(
      alignmentOffset: const Offset(0, 4),
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll<Color?>(
          theme.dropdownMenuTheme.inputDecorationTheme?.fillColor,
        ),
        padding: const WidgetStatePropertyAll<EdgeInsets>(
          EdgeInsets.all(_menuInset),
        ),
        minimumSize: const WidgetStatePropertyAll<Size>(Size(_width, 0)),
        maximumSize: const WidgetStatePropertyAll<Size>(
          Size(_width, double.infinity),
        ),
        shape: WidgetStatePropertyAll<OutlinedBorder>(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(LayoutNums.surfaceRadius),
          ),
        ),
      ),
      builder: (BuildContext context, MenuController controller, Widget? _) =>
          Material(
            color: theme.inputDecorationTheme.fillColor,
            borderRadius: LayoutNums.pill,
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              borderRadius: LayoutNums.pill,
              mouseCursor: SystemMouseCursors.click,
              onTap: () =>
                  controller.isOpen ? controller.close() : controller.open(),
              child: SizedBox(
                width: _width,
                height: LayoutNums.controlHeight,
                child: Padding(
                  padding: const EdgeInsets.only(left: 14, right: 8),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Center(
                          child: Text(
                            labelOf(value),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: style,
                          ),
                        ),
                      ),
                      Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 18,
                        color: style?.color,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      menuChildren: <Widget>[
        for (final T item in items)
          MenuItemButton(
            // Picking the current value would rescan the library already on
            // screen, so it does nothing instead.
            onPressed: () {
              if (item != value) onChanged(item);
            },
            style: const ButtonStyle(
              padding: WidgetStatePropertyAll<EdgeInsets>(EdgeInsets.zero),
              minimumSize: WidgetStatePropertyAll<Size>(
                Size(_rowWidth, LayoutNums.controlHeight),
              ),
              maximumSize: WidgetStatePropertyAll<Size>(
                Size(_rowWidth, LayoutNums.controlHeight),
              ),
              shape: WidgetStatePropertyAll<OutlinedBorder>(
                RoundedRectangleBorder(borderRadius: LayoutNums.pill),
              ),
            ),
            // Sized rather than centred by the button, whose label sits in a
            // row built for leading and trailing icons this has neither of.
            child: SizedBox(
              width: _rowWidth,
              height: LayoutNums.controlHeight,
              child: Center(
                child: Text(
                  labelOf(item),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  // Colour rather than a tick, so the row stays centred. A menu
                  // panel has no selected state of its own.
                  style: item == value
                      ? style?.copyWith(color: theme.colorScheme.primary)
                      : style,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
