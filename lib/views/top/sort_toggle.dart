import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:we_repkg/constants/nums.dart';
import 'package:we_repkg/provider/setting.dart';
import 'package:we_repkg/widgets/app_icon_button.dart';

class SortToggle extends ConsumerWidget {
  const SortToggle({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppIconButton(
      onPressed: ref.read(sortAscendingProvider.notifier).update,
      icon: ref.watch(sortAscendingProvider)
          ? Icons.arrow_upward_rounded
          : Icons.arrow_downward_rounded,
      width: TopBarNums.buttonSize,
      height: TopBarNums.buttonSize,
      iconSize: TopBarNums.iconSize,
    );
  }
}
