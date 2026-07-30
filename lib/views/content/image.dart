import 'package:flutter/material.dart';
import 'package:we_repkg/models/wallpaper.dart';
import 'package:we_repkg/utils/preview_image.dart';

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
      // Decode at the tile's real pixel size. Height rather than width, so a
      // preview that is not square still reaches the tile edge on its shorter
      // side rather than being upscaled by cover.
      image: previewImage(
        wallpaper.previews,
        cacheHeight: (size * MediaQuery.devicePixelRatioOf(context)).round(),
      ),
      width: size,
      height: size,
      fit: BoxFit.cover,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded) return child;
        // Nothing, rather than a spinner. Searching brings up wallpapers the
        // cache never reached, and a screenful of spinners appearing at once is
        // its own kind of flash.
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: frame != null ? child : const SizedBox.shrink(),
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
    // No fill while the preview loads: any colour reads as a flash against a
    // grid of photographs, and a light one especially so in light mode. The
    // tile's own shadow and title strip still show it is there. The tile's
    // ClipRRect already takes the corners, so nothing clips here either.
    return SizedBox(
      width: size,
      height: size,
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
