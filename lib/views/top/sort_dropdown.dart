import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:we_repkg/models/enums.dart';
import 'package:we_repkg/provider/setting.dart';
import 'package:we_repkg/widgets/pill_dropdown.dart';

class SortDropdown extends ConsumerWidget {
  const SortDropdown({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Sorting by update time needs the ACF's timestamps, so the option goes
    // when the setting that reads them is off. WallpaperSortType holds the
    // value in step, so the list always contains it.
    final bool useAcfFile = ref.watch(useAcfInfoProvider);
    return PillDropdown<SortType>(
      value: ref.watch(wallpaperSortTypeProvider),
      items: <SortType>[
        for (final SortType type in SortType.values)
          if (useAcfFile || type != SortType.update) type,
      ],
      labelOf: (SortType type) => type.label,
      onChanged: (SortType type) =>
          ref.read(wallpaperSortTypeProvider.notifier).update(type),
    );
  }
}
