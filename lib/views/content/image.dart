import 'dart:io';

import 'package:flutter/material.dart';
import 'package:we_repkg/models/wallpaper.dart';
import 'package:we_repkg/widgets/circular_progress.dart';

class ImageView extends StatelessWidget {
  const ImageView({
    super.key,
    required this.size,
    required this.wallpaper,
    this.scale,
  });

  final double size;
  final WallpaperInfo wallpaper;
  final Animation<double>? scale;

  @override
  Widget build(BuildContext context) {
    final Image preview = Image.file(
      File(wallpaper.previews),
      width: size,
      height: size,
      // Decode at the tile's real on-screen pixel size (logical size ×
      // display density) rather than full resolution.
      //
      // Constrain the HEIGHT, not the width. The tile is square and the fit
      // is cover, so the image's shorter side is what has to reach the tile
      // edge. Wallpaper previews are almost always landscape, which makes
      // height the shorter side: capping width instead decoded a 16:9
      // preview to 270x152 for a 270x270 tile, and cover then upscaled it
      // 1.8x. Every landscape preview in the grid was soft.
      cacheHeight: (size * MediaQuery.devicePixelRatioOf(context)).round(),
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
    );
    final Animation<double>? scaleAnimation = scale;
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(color: Colors.white),
      clipBehavior: Clip.hardEdge,
      child: scaleAnimation == null
          ? preview
          : ScaleTransition(
              scale: scaleAnimation,
              alignment: Alignment.center,
              child: preview,
            ),
    );
  }
}
