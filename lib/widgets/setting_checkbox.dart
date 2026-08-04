import 'package:flutter/material.dart';
import 'package:we_repkg/config/custom_theme.dart';
import 'package:we_repkg/constants/nums.dart';

class SettingCheckbox extends StatelessWidget {
  const SettingCheckbox.text({
    super.key,
    required String label,
    required this.value,
    required this.onChanged,
  }) : _label = label,
       _subTitle = null;

  /// A label with an explanatory line under it, for a setting whose effect the
  /// name alone does not give away.
  const SettingCheckbox.twoLine({
    super.key,
    required String label,
    required String subTitle,
    required this.value,
    required this.onChanged,
  }) : _label = label,
       _subTitle = subTitle;

  final String _label;
  final String? _subTitle;
  final bool value;
  final void Function(bool?) onChanged;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Text label = Text(_label, style: theme.textTheme.bodyMedium);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // Wraps instead of overflowing. Several subtitles do not fit half a
        // two-column card.
        Flexible(
          child: _subTitle == null
              ? label
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    label,
                    Text(_subTitle, style: theme.meta.captionStyle),
                  ],
                ),
        ),
        Checkbox(
          value: value,
          onChanged: onChanged,
          mouseCursor: SystemMouseCursors.click,
          side: BorderSide(width: 2, color: Colors.grey),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(LayoutNums.controlRadius),
          ),
          fillColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? theme.primaryColor
                : Colors.transparent,
          ),
        ),
      ],
    );
  }
}
