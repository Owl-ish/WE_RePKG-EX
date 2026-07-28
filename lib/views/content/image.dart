import 'package:flutter/material.dart';
import 'package:we_repkg/models/wallpaper.dart';
import 'package:we_repkg/utils/preview_image.dart';
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
    final Image preview = Image(
      // Decode at the tile's real pixel size, and constrain the height rather
      // than the width. The tile is square and the fit is cover, so the
      // image's shorter side has to reach the tile edge, and previews are
      // nearly always landscape. Capping width instead decoded a 16:9 preview
      // to 270x152 for a 270x270 tile and cover upscaled it 1.8x, which left
      // every landscape preview in the grid soft.
      image: previewImage(
        wallpaper.previews,
        cacheHeight: (size * MediaQuery.devicePixelRatioOf(context)).round(),
      ),
      width: size,
      height: size,
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
