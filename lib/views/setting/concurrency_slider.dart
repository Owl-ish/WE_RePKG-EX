import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:we_repkg/constants/i10n.dart';
import 'package:we_repkg/provider/setting.dart';

/// Picks how many wallpapers extract at once.
///
/// RePKG is partly disk-bound, so on a spinning disk a high value makes
/// a batch slower, while fast NVMe benefits from more.
class ConcurrencySlider extends ConsumerWidget {
  const ConcurrencySlider({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final int value = ref.watch(extractConcurrencyProvider);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  tr(AppI10n.settingConfigConcurrency),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              Text('$value', style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
          Text(
            tr(AppI10n.settingConfigConcurrencyTip),
            style: const TextStyle(fontSize: 13, color: Colors.grey),
          ),
          Slider(
            value: value.toDouble(),
            min: ExtractConcurrency.min.toDouble(),
            max: ExtractConcurrency.max.toDouble(),
            divisions: ExtractConcurrency.max - ExtractConcurrency.min,
            label: '$value',
            onChanged: (v) =>
                ref.read(extractConcurrencyProvider.notifier).update(v.round()),
          ),
        ],
      ),
    );
  }
}
