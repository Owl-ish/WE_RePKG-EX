import 'package:flutter/material.dart';
import 'package:we_repkg/widgets/sliding_switch.dart';

/// A labelled segmented control over a fixed set of values.
///
/// SlidingSwitch keys its segments from 1, so the index maths lives here
/// instead of being spelled out again at every call site.
class SettingSegmented<T> extends StatelessWidget {
  const SettingSegmented({
    super.key,
    required this.label,
    required this.values,
    required this.current,
    required this.labelOf,
    required this.onChanged,
  });

  final String label;
  final List<T> values;
  final T current;
  final String Function(T value) labelOf;
  final void Function(T value) onChanged;

  @override
  Widget build(BuildContext context) {
    final TextStyle? style = Theme.of(context).textTheme.bodySmall;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(label),
        SlidingSwitch(
          initialValue: values.indexOf(current),
          children: <int, Widget>{
            for (int i = 0; i < values.length; i++)
              i + 1: Text(labelOf(values[i]), style: style),
          },
          onValueChanged: (v) => onChanged(values[v - 1]),
        ),
      ],
    );
  }
}
