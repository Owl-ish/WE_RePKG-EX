import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:we_repkg/constants/i10n.dart';

/// Darkens the tile on hover and says double-click opens the details.
class HoverHint extends StatelessWidget {
  const HoverHint({super.key, required this.opacity});

  final Animation<double> opacity;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      // The hint sits over the image
      child: IgnorePointer(
        child: FadeTransition(
          opacity: opacity,
          child: Container(
            color: Colors.black.withValues(alpha: .18),
            // Sits clear of the title bar along the bottom edge.
            padding: const EdgeInsets.only(bottom: 24, left: 6, right: 6),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.open_in_full_rounded,
                  size: 20,
                  color: Colors.white,
                ),
                const SizedBox(height: 6),
                Text(
                  tr(AppI10n.homeDoubleClickDetails),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    height: 1.3,
                    fontFamily: 'Microsoft YaHei',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
