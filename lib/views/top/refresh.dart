import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:we_repkg/constants/nums.dart';
import 'package:we_repkg/cores/wallpaper.dart';
import 'package:we_repkg/widgets/icon_btn.dart';

class Refresh extends ConsumerWidget {
  const Refresh({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return IconBtn(
      onPressed: () => refreshWallpaper(ref),
      icon: Icons.refresh_rounded,
      size: TopBarNums.buttonSize,
      iconSize: TopBarNums.iconSize,
    );
  }
}
