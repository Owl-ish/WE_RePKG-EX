import 'package:flutter/painting.dart';

/// Shared so the refresh, filter and sort buttons stay the same size as each
/// other.
class TopBarNums {
  static const double buttonSize = 40;
  static const double iconSize = 24;
}

class LayoutNums {
  /// Left and right inset shared by the top bar, the grid and the bottom bar,
  /// so the three line up down each side.
  static const double edgeInset = 24;

  /// Gap between the grid and the bars above and below it.
  static const double contentGap = 14;

  /// Corners of anything that reads as a surface of its own.
  static const double surfaceRadius = 8;

  /// Corners of the smaller controls sitting on those surfaces.
  static const double controlRadius = 4;

  /// Height of the search field, the path boxes and the dropdowns, so they
  /// line up wherever two of them sit side by side.
  static const double controlHeight = 36;

  /// Half that height, which is what makes a control read as a pill rather
  /// than as a rounded rectangle.
  static const double pillRadius = controlHeight / 2;

  /// The pill corner itself, so the controls sharing it cannot drift apart and
  /// so nothing allocates one per build.
  static const BorderRadius pill = BorderRadius.all(
    Radius.circular(pillRadius),
  );
}

class WindowNums {
  /// 16:9, used on first launch before a size has been saved.
  static const Size defaultSize = Size(1380, 800);

  /// The settings form's two columns stop fitting below this width.
  static const Size minimumSize = Size(1060, 720);
}
