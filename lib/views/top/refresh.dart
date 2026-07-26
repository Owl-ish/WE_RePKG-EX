import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:we_repkg/constants/nums.dart';
import 'package:we_repkg/cores/wallpaper.dart';
import 'package:we_repkg/widgets/app_icon_button.dart';

class Refresh extends ConsumerWidget {
  const Refresh({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppIconButton(
      onPressed: () => refreshWallpaper(ref),
      icon: Icons.refresh_rounded,
      width: TopBarNums.buttonSize,
      height: TopBarNums.buttonSize,
      iconSize: TopBarNums.iconSize,
    );
  }
}
