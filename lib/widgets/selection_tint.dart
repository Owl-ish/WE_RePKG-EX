import 'package:flutter/material.dart';
import 'package:we_repkg/constants/nums.dart';

/// How both grids mark a selected tile: the whole tile tinted and outlined,
/// with a tick in the corner.
///
/// The tick is a mark, not a control. The checkbox it replaces was the only
/// reason a tile needed a hover-aware overlay, and it could be clicked to mean
/// something the tile itself did not.
///
/// Goes straight into a tile's [Stack], and takes no pointer: the tile under it
/// owns every click.
class SelectionTint extends StatelessWidget {
  const SelectionTint({super.key});

  /// Marks the tint for a test, which has no text to find it by.
  static const Key tintKey = ValueKey<String>('tile-selected');

  static const double _tick = 20;

  @override
  Widget build(BuildContext context) {
    final Color colour = Theme.of(context).primaryColor;
    return Positioned.fill(
      key: tintKey,
      child: IgnorePointer(
        child: Stack(
          children: <Widget>[
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colour.withValues(alpha: .28),
                  border: Border.all(color: colour, width: 2),
                  borderRadius: BorderRadius.circular(LayoutNums.surfaceRadius),
                ),
              ),
            ),
            Positioned(
              top: 6,
              right: 6,
              child: Container(
                width: _tick,
                height: _tick,
                decoration: BoxDecoration(
                  color: colour,
                  shape: BoxShape.circle,
                  // Against a pale preview the disc alone can vanish.
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: Colors.black.withValues(alpha: .25),
                      blurRadius: 4,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.check_rounded,
                  size: 14,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
