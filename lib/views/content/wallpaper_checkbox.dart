import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:we_repkg/models/wallpaper.dart';
import 'package:we_repkg/provider/wallpaper.dart';

class WallpaperCheckbox extends ConsumerWidget {
  const WallpaperCheckbox({
    super.key,
    required this.wallpaper,
    required this.hoverOpacity,
  });

  final WallpaperInfo wallpaper;
  final Animation<double> hoverOpacity;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Color primaryColor = Theme.of(context).primaryColor;
    return Align(
      alignment: Alignment.topRight,
      child: FadeTransition(
        // A checked wallpaper stays visible after the pointer leaves. Otherwise
        // this shares the tile's one hover controller with the zoom and hint.
        opacity: wallpaper.checked
            ? const AlwaysStoppedAnimation<double>(1)
            : hoverOpacity,
        child: Checkbox(
          value: wallpaper.checked,
          mouseCursor: SystemMouseCursors.click,
          fillColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return primaryColor;
            }
            return Colors.white;
          }),
          checkColor: Colors.white,
          side: BorderSide(color: primaryColor),
          onChanged: (v) =>
              ref.read(wallpaperListProvider.notifier).toggleChecked(wallpaper),
        ),
      ),
    );
  }
}
