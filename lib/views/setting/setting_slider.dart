import 'package:flutter/material.dart';

/// A labelled slider over a whole-number setting, with its current value shown
/// beside the title and an explanatory line underneath.
class SettingSlider extends StatelessWidget {
  const SettingSlider({
    super.key,
    required this.label,
    required this.tip,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.step = 1,
    this.unit = '',
  });

  final String label;
  final String tip;
  final int value;
  final int min;
  final int max;
  final int step;
  final String unit;
  final void Function(int value) onChanged;

  @override
  Widget build(BuildContext context) {
    final TextStyle? bodyMedium = Theme.of(context).textTheme.bodyMedium;
    final String display = '$value$unit';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(label, style: bodyMedium)),
              Text(display, style: bodyMedium),
            ],
          ),
          Text(tip, style: const TextStyle(fontSize: 13, color: Colors.grey)),
          Slider(
            value: value.toDouble(),
            min: min.toDouble(),
            max: max.toDouble(),
            divisions: (max - min) ~/ step,
            label: display,
            onChanged: (v) => onChanged((v / step).round() * step),
          ),
        ],
      ),
    );
  }
}
