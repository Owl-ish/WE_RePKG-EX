import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:we_repkg/models/wallpaper.dart';
import 'package:we_repkg/provider/wallpaper.dart';
import 'package:we_repkg/widgets/circular_progress.dart';

class ImageView extends StatelessWidget {
  const ImageView({super.key, required this.size, required this.wallpaper});

  final double size;
  final WallpaperInfo wallpaper;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: Colors.white),
      clipBehavior: Clip.hardEdge,
      child: Consumer(
        builder: (_, ref, child) {
          return AnimatedScale(
            // Only rebuild this tile when ITS OWN hover state flips, not on
            // every hover change across the grid.
            scale:
                ref.watch(
                  hoverWallpaperProvider.select((h) => h == wallpaper),
                )
                ? 1.2
                : 1,
            duration: const Duration(milliseconds: 250), // 动画时长300ms
            curve: Curves.easeInOut,
            alignment: Alignment.center, // 缩放中心
            child: child!,
          );
        },
        child: Image.file(
          File(wallpaper.previews),
          width: size,
          height: size,
          // Decode the preview at the tile's real on-screen pixel size
          // (logical size × display density) instead of full resolution: big
          // memory/decode win that also stays crisp on high-DPI displays.
          cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).round(),
          fit: BoxFit.cover,
          frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
            if (wasSynchronouslyLoaded) return child;
            return AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: frame != null
                  ? child
                  : const Center(child: EasyCircularProgress()),
            );
          },
          errorBuilder: (context, error, stackTrace) {
            return Container(
              color: Colors.grey[300],
              child: const Icon(Icons.broken_image, size: 48),
            );
          },
        ),
      ),
    );
  }
}
