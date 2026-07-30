import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:we_repkg/constants/i10n.dart';
import 'package:we_repkg/provider/setting.dart';

/// Caps what extraction may hold at once, shared between the wallpapers running
/// side by side.
///
/// A ceiling rather than a prediction: nothing can say in advance what a
/// wallpaper costs, since that follows the size of its largest texture. Setting
/// this low only makes extraction slower.
class MemoryLimitSlider extends ConsumerWidget {
  const MemoryLimitSlider({super.key});

  /// Whole gigabytes read better on a slider than 1536MB does.
  static const int step = 256;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final int value = ref.watch(extractMemoryLimitProvider);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  tr(AppI10n.settingConfigMemoryLimit),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              Text('$value MB', style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
          Text(
            tr(AppI10n.settingConfigMemoryLimitTip),
            style: const TextStyle(fontSize: 13, color: Colors.grey),
          ),
          Slider(
            value: value.toDouble().clamp(
              ExtractMemoryLimit.min.toDouble(),
              ExtractMemoryLimit.max.toDouble(),
            ),
            min: ExtractMemoryLimit.min.toDouble(),
            max: ExtractMemoryLimit.max.toDouble(),
            divisions:
                (ExtractMemoryLimit.max - ExtractMemoryLimit.min) ~/ step,
            label: '$value MB',
            onChanged: (v) => ref
                .read(extractMemoryLimitProvider.notifier)
                .update((v / step).round() * step),
          ),
        ],
      ),
    );
  }
}
